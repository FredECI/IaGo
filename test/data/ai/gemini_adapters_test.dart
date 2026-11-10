import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/ai/gemini/ai_schemas.dart';
import 'package:iago/data/ai/gemini/app_check_setup.dart';
import 'package:iago/data/ai/gemini/firebase_ai_gateway.dart';
import 'package:iago/data/ai/gemini/gemini_adapters.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';

class FakeGateway implements AiGateway {
  FakeGateway({this.response = '', this.error});
  String response;
  Object? error;
  final calls = <Map<String, Object?>>[];

  @override
  Future<AiAvailability> availability() async => AiAvailability.available;

  @override
  Future<String> generateJson({
    required AiCall call,
    required String model,
    required String systemInstruction,
    required String prompt,
    List<ImportFile> files = const [],
    required Map<String, Object?> responseSchema,
    required Duration timeout,
  }) async {
    calls.add({
      'call': call,
      'model': model,
      'prompt': prompt,
      'files': files,
      'timeout': timeout,
    });
    if (error case final e?) throw e;
    return response;
  }
}

final file = ImportFile(
  name: 'p.png',
  mimeType: 'image/png',
  bytes: Uint8List.fromList([1, 2, 3]),
);

DirectionContext ctx() => DirectionContext(
  today: DateTime(2026, 11, 30),
  goal: const GoalSummary(
    exam: ExamTarget.enem,
    weeklyHours: 6,
    focusAreas: [Area.mathematics],
  ),
  coverage: const [],
);

Matcher aiFailure(AiFailure f) =>
    isA<AiException>().having((e) => e.failure, 'failure', f);

void main() {
  group('GeminiQuestionExtractor', () {
    test('lê a resposta pelo contrato e manda o modelo e o arquivo', () async {
      final gw = FakeGateway(
        response: jsonEncode({
          'schemaVersion': 1,
          'questions': [
            {
              'statement': 'Quanto é 2 + 3?',
              'type': 'objective',
              'alternatives': ['A) 4', 'B) 5', 'C) 6'],
              'hasFigure': false,
              'isComplete': true,
              'suggestedArea': 'mathematics',
              'suggestedSubject': 'Matemática',
            },
          ],
          'containsPersonalData': false,
        }),
      );
      final ex = GeminiQuestionExtractor(gateway: gw, model: 'm-x');
      final r = await ex.extract(file);
      expect(r.questions, hasLength(1));
      expect(r.questions.first.alternatives, ['4', '5', '6']);
      expect(gw.calls.single['model'], 'm-x');
      expect(gw.calls.single['call'], AiCall.extraction);
      expect((gw.calls.single['files'] as List).single, same(file));
      expect(ex.provider.minUserAge, 18);
    });

    test('resposta ilegível vira malformed', () async {
      final ex = GeminiQuestionExtractor(gateway: FakeGateway(response: 'oi'));
      await expectLater(
        ex.extract(file),
        throwsA(aiFailure(AiFailure.malformed)),
      );
    });

    test('a falha do gateway passa sem mudar', () async {
      final ex = GeminiQuestionExtractor(
        gateway: FakeGateway(
          error: const AiException(AiFailure.quotaExhausted),
        ),
      );
      await expectLater(
        ex.extract(file),
        throwsA(aiFailure(AiFailure.quotaExhausted)),
      );
    });
  });

  group('GeminiStepProposer', () {
    final valid = jsonEncode({
      'schemaVersion': 1,
      'steps': [
        {
          'action': 'collect',
          'area': 'mathematics',
          'subject': 'Matemática',
          'targetCount': 10,
          'dueInDays': 3,
          'rationale': 'Matemática teve menos questões salvas.',
        },
      ],
    });

    test('devolve as etapas e o pedido só leva o contexto agregado', () async {
      final gw = FakeGateway(response: valid);
      final steps = await GeminiStepProposer(gateway: gw).propose(ctx());
      expect(steps.single.subject, 'Matemática');
      expect(gw.calls.single['call'], AiCall.proposal);
      final prompt = gw.calls.single['prompt'] as String;
      expect(prompt, contains('"today":"2026-11-30"'));
      expect(prompt, isNot(contains('uid')));
    });

    test('violação da C.2 descarta tudo (malformed)', () async {
      final bad = valid.replaceAll('"dueInDays":3', '"dueInDays":40');
      expect(bad, isNot(valid));
      await expectLater(
        GeminiStepProposer(gateway: FakeGateway(response: bad)).propose(ctx()),
        throwsA(aiFailure(AiFailure.malformed)),
      );
    });

    test('texto que não é JSON vira malformed', () async {
      await expectLater(
        GeminiStepProposer(gateway: FakeGateway(response: '{')).propose(ctx()),
        throwsA(aiFailure(AiFailure.malformed)),
      );
    });
  });

  test('esquemas são JSON puro e batem com o contrato', () {
    for (final s in [extractionResponseSchema, proposalResponseSchema]) {
      expect(() => jsonEncode(s), returnsNormally);
    }
    final props = extractionResponseSchema['properties']! as Map;
    expect(props.keys, containsAll(['schemaVersion', 'questions']));
  });

  group('FirebaseAiGateway.availability', () {
    test('Firebase fora do ar', () async {
      final g = FirebaseAiGateway(
        configured: () => false,
        ensureAppCheck: () async => AppCheckOutcome.active,
      );
      expect(await g.availability(), AiAvailability.firebaseUnavailable);
    });

    test('sem App Check ativo (APK sem chave)', () async {
      final g = FirebaseAiGateway(
        configured: () => true,
        ensureAppCheck: () async => AppCheckOutcome.noSiteKey,
      );
      expect(await g.availability(), AiAvailability.appCheckUnavailable);
    });

    test('com App Check ativo', () async {
      final g = FirebaseAiGateway(
        configured: () => true,
        ensureAppCheck: () async => AppCheckOutcome.activeDebug,
      );
      expect(await g.availability(), AiAvailability.available);
    });
  });
}
