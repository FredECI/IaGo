// QA de I3 e DI3: casos de borda além dos testes do especialista.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/core/pdf_page_count.dart';
import 'package:iago/data/ai/ai_daily_limit.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/local/memory_runtime_config.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/import/import_models.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _ascii(String s) => Uint8List.fromList(latin1.encode(s));

Uint8List _objStmPdf(List<int> pagesPerStream, {String eol = '\n'}) {
  final b = BytesBuilder()..add(_ascii('%PDF-1.5$eol'));
  var n = 5;
  for (final count in pagesPerStream) {
    final inner = [
      for (var i = 0; i < count; i++) '<< /Type /Page /Parent 2 0 R >>',
      '<< /Type /Pages /Count $count >>',
    ].join(' ');
    b
      ..add(
        _ascii(
          '$n 0 obj$eol<< /Type /ObjStm /N 3 /Filter /FlateDecode >>'
          '${eol}stream$eol',
        ),
      )
      ..add(const ZLibEncoder().encodeBytes(utf8.encode(inner)))
      ..add(_ascii('${eol}endstream${eol}endobj$eol'));
    n++;
  }
  b.add(_ascii('%%EOF'));
  return b.toBytes();
}

class _Account extends SessionController {
  @override
  Session? build() => const AccountSession(uid: 'u1', email: 'a@b.c');
}

class _Gw implements AiGateway {
  _Gw({required this.availabilities, required this.response});
  final List<AiAvailability> availabilities;
  final String response;
  int availabilityCalls = 0;
  int generateCalls = 0;

  @override
  Future<AiAvailability> availability() async {
    final i = availabilityCalls++;
    return availabilities[i < availabilities.length
        ? i
        : availabilities.length - 1];
  }

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
    generateCalls++;
    return response;
  }
}

final _now = DateTime(2026, 11, 30, 12);
final _validJson = jsonEncode({
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

class _Env {
  _Env(this.c, this.gw, this.repo, this.metrics);
  final ProviderContainer c;
  final _Gw gw;
  final MemoryDirectionRepository repo;
  final MemoryMetricsRepository metrics;

  Future<List<StudyStep>> propose() =>
      c.read(directionActionsProvider).proposeWithRules(repo.currentGoal!);

  List<MetricEvent> fallbacks() => [
    for (final e in metrics.logged)
      if (e.type == MetricEventType.aiFallback) e,
  ];
}

Future<_Env> _env({
  required List<AiAvailability> availabilities,
  String? response,
  Map<String, Object?>? runtime,
  AiUsageStore? usage,
}) async {
  final gw = _Gw(
    availabilities: availabilities,
    response: response ?? _validJson,
  );
  final repo = MemoryDirectionRepository(
    goal: StudyGoal(
      exam: ExamTarget.enem,
      weeklyHours: 8,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  final metrics = MemoryMetricsRepository(clock: () => _now);
  final c = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => _now),
      firebaseStatusProvider.overrideWith((ref) async => FirebaseStatus.ready),
      sessionProvider.overrideWith(_Account.new),
      aiGatewayProvider.overrideWithValue(gw),
      runtimeConfigRepositoryProvider.overrideWithValue(
        MemoryRuntimeConfig(runtime ?? {'aiEnabled': true}),
      ),
      if (usage != null) aiUsageStoreProvider.overrideWithValue(usage),
      directionReadTimeoutProvider.overrideWithValue(
        const Duration(milliseconds: 50),
      ),
      directionRepositoryProvider.overrideWithValue(repo),
      questionRepositoryProvider.overrideWithValue(
        MemoryQuestionRepository(clock: () => _now),
      ),
      listRepositoryProvider.overrideWithValue(
        MemoryListRepository(clock: () => _now),
      ),
      metricsRepositoryProvider.overrideWithValue(metrics),
      isMemberProvider.overrideWithValue(true),
    ],
  );
  addTearDown(c.dispose);
  await c.read(accessPolicyAsyncProvider.future);
  return _Env(c, gw, repo, metrics);
}

void main() {
  group('contagem de páginas', () {
    test('ObjStm com 11 páginas: 11; com 10: 10', () {
      expect(countPdfPages(_objStmPdf([11])), 11);
      expect(countPdfPages(_objStmPdf([10])), 10);
    });
    test('vários ObjStm somam (6 + 5 = 11)', () {
      expect(countPdfPages(_objStmPdf([6, 5])), 11);
    });
    test('fim de linha CRLF depois de "stream"', () {
      expect(countPdfPages(_objStmPdf([3], eol: '\r\n')), 3);
    });
    test('lixo antes do %PDF- (até 1024 bytes) ainda conta', () {
      final b = BytesBuilder()
        ..add(Uint8List(500))
        ..add(_objStmPdf([4]));
      expect(countPdfPages(b.toBytes()), 4);
    });
    test('lixo além de 1024 bytes: não detectável', () {
      final b = BytesBuilder()
        ..add(Uint8List(2000))
        ..add(_objStmPdf([4]));
      expect(countPdfPages(b.toBytes()), isNull);
    });
    test('ObjStm truncado: sem exceção', () {
      final good = _objStmPdf([3]);
      final cut = Uint8List.sublistView(good, 0, good.length - 40);
      expect(() => countPdfPages(cut), returnsNormally);
    });
    test('checkImportFiles recusa PDF de 11 páginas em ObjStm', () {
      final r = checkImportFiles([
        ImportFile(
          name: 'x.pdf',
          mimeType: 'application/pdf',
          bytes: _objStmPdf([11]),
        ),
      ]);
      expect(r.accepted, isEmpty);
      expect(r.refusals.single, contains('11 páginas'));
    });
    test('PDF de 10 MB de zeros após o cabeçalho: recusa e não trava', () {
      final b = Uint8List(10 * 1024 * 1024)..setAll(0, _ascii('%PDF-1.4\n'));
      final sw = Stopwatch()..start();
      final r = checkImportFiles([
        ImportFile(name: 'x.pdf', mimeType: 'application/pdf', bytes: b),
      ]);
      expect(r.accepted, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('limite diário', () {
    test('virada exata da meia-noite', () {
      var t = DateTime(2026, 11, 10, 23, 59, 59);
      final l = AiDailyLimiter(
        store: MemoryAiUsageStore(),
        owner: 'u',
        limit: 1,
        now: () => t,
      );
      l.consume();
      expect(l.hasRoom, isFalse);
      t = DateTime(2026, 11, 11);
      expect(l.hasRoom, isTrue);
    });
    test('valor corrompido nas preferências conta como zero', () async {
      for (final raw in ['lixo', '2026-11-10:abc', '2026-11-10:1:1', '']) {
        SharedPreferences.setMockInitialValues({'ai_usage.u': raw});
        final s = PrefsAiUsageStore(await SharedPreferences.getInstance());
        expect(s.usedOn('u', '2026-11-10'), 0, reason: raw);
      }
    });
    test('contagem negativa nas preferências dá cota ilimitada', () async {
      SharedPreferences.setMockInitialValues({'ai_usage.u': '2026-11-10:-999'});
      final s = PrefsAiUsageStore(await SharedPreferences.getInstance());
      final l = AiDailyLimiter(
        store: s,
        owner: 'u',
        limit: 3,
        now: () => DateTime(2026, 11, 10),
      );
      for (var i = 0; i < 3; i++) {
        l.consume();
      }
      expect(l.hasRoom, isFalse);
    });
  });

  group('Direciona com providers reais e gateway falso', () {
    test('App Check falha na 1a checagem e passa na 2a: usa a IA', () async {
      final e = await _env(
        availabilities: [
          AiAvailability.appCheckUnavailable,
          AiAvailability.available,
        ],
      );
      await e.c.read(aiAvailabilityProvider.future);
      final steps = await e.propose();
      expect(e.gw.generateCalls, 1);
      expect(steps.every((s) => s.source == StepSource.ai), isTrue);
      expect(e.repo.currentGoal!.lastAiAt, _now);
    });

    test(
      'resposta inválida do modelo: regras, malformed, sem lastAiAt',
      () async {
        final e = await _env(
          availabilities: [AiAvailability.available],
          response: '{"schemaVersion":1,"steps":[{"action":"x"}]}',
        );
        await e.c.read(aiAvailabilityProvider.future);
        final steps = await e.propose();
        expect(steps, isNotEmpty);
        expect(steps.every((s) => s.source == StepSource.rules), isTrue);
        expect(e.repo.currentGoal!.lastAiAt, isNull);
        expect(e.fallbacks().single.data['reason'], 'malformed');
      },
    );

    test('texto que não é JSON: regras', () async {
      final e = await _env(
        availabilities: [AiAvailability.available],
        response: 'desculpe, nao posso',
      );
      await e.c.read(aiAvailabilityProvider.future);
      final steps = await e.propose();
      expect(steps.every((s) => s.source == StepSource.rules), isTrue);
    });

    test(
      'limite diário esgotado: regras, dailyLimit, gateway intacto',
      () async {
        final usage = MemoryAiUsageStore();
        for (var i = 0; i < 100; i++) {
          usage.record('u1', aiUsageDayKey(_now));
        }
        final e = await _env(
          availabilities: [AiAvailability.available],
          usage: usage,
          runtime: {'aiEnabled': true, 'aiDailyPerUser': 5},
        );
        await e.c.read(aiAvailabilityProvider.future);
        final steps = await e.propose();
        expect(e.gw.generateCalls, 0);
        expect(steps.every((s) => s.source == StepSource.rules), isTrue);
        expect(e.fallbacks().single.data['reason'], 'dailyLimit');
        expect(e.repo.currentGoal!.lastAiAt, isNull);
      },
    );

    test('aiEnabled desligado: o gateway não gera nada', () async {
      final e = await _env(
        availabilities: [AiAvailability.available],
        runtime: {'aiEnabled': false},
      );
      await e.propose();
      expect(e.gw.generateCalls, 0);
    });

    test('checagem de IA ainda carregando na 1a proposta: usa a IA', () async {
      final e = await _env(availabilities: [AiAvailability.available]);
      final steps = await e.propose();
      expect(
        steps.every((s) => s.source == StepSource.ai),
        isTrue,
        reason: 'caiu nas regras só porque a checagem não tinha terminado',
      );
    });
  });
}
