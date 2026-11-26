import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/features/import/import_models.dart';
import 'package:iago/features/import/import_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../helpers/test_app.dart';

class _Extractor implements QuestionExtractor {
  _Extractor(this.script);

  /// Cada item: [AiFailure], [ExtractionResult] ou [Completer] (trava até o
  /// teste completar).
  final List<Object> script;
  int calls = 0;

  @override
  AiProviderInfo get provider =>
      const AiProviderInfo(name: 'IA simulada', minUserAge: 0);

  @override
  Future<ExtractionResult> extract(ImportFile file) async {
    final step = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (step is AiFailure) throw AiException(step);
    if (step is Completer<ExtractionResult>) return step.future;
    return step as ExtractionResult;
  }
}

class _CountingGateway implements AiGateway {
  int availabilityCalls = 0;

  @override
  Future<AiAvailability> availability() async {
    availabilityCalls++;
    return AiAvailability.available;
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
  }) => throw UnimplementedError();
}

ExtractionResult _result(String statement) => ExtractionResult(
  questions: [
    ExtractedQuestion(
      statement: statement,
      type: QuestionType.objective,
      alternatives: const ['1', '2', '3', '4', '5'],
      hasFigure: false,
      isComplete: true,
      suggestedArea: Area.mathematics,
      suggestedSubject: 'Matemática',
    ),
  ],
);

ImportFile _png(String name) => ImportFile(
  name: name,
  mimeType: 'image/png',
  bytes: Uint8List.fromList(List.filled(10, 1)),
);

Future<ImportFile> _pdf(String name, int pages) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Text('p$i')));
  }
  return ImportFile(
    name: name,
    mimeType: 'application/pdf',
    bytes: await doc.save(),
  );
}

void main() {
  setUpAll(initTestLocale);

  group('limites de PDF (CA-I3, CA-I13, CA-R7)', () {
    test('a constante é 10', () => expect(maxImportPdfPages, 10));

    test('até 10 páginas passa; 11 é recusado antes de enviar', () async {
      final ok = await _pdf('ok.pdf', 10);
      final big = await _pdf('grande.pdf', 11);
      final check = checkImportFiles([ok, big]);
      expect(check.accepted.map((f) => f.name), ['ok.pdf']);
      expect(check.refusals.single, contains('grande.pdf'));
      expect(check.refusals.single, contains('11 páginas'));
    });

    test('páginas não detectáveis: recusa', () {
      final junk = ImportFile(
        name: 'estranho.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(List.filled(100, 7)),
      );
      final check = checkImportFiles([junk]);
      expect(check.accepted, isEmpty);
      expect(check.refusals.single, contains('contar as páginas'));
    });

    test('tipo pelo nome do arquivo quando o mime vem vazio', () async {
      final pdf = await _pdf('a.pdf', 2);
      final check = checkImportFiles([
        ImportFile(name: 'a.pdf', mimeType: '', bytes: pdf.bytes),
      ]);
      expect(check.accepted.single.mimeType, 'application/pdf');
    });

    test('arquivo vazio (ou excedente sem bytes) é recusado', () {
      final check = checkImportFiles([
        ImportFile(name: 'v.png', mimeType: 'image/png', bytes: Uint8List(0)),
        ImportFile(
          name: 'v.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List(0),
        ),
      ]);
      expect(check.accepted, isEmpty);
      expect(check.refusals, hasLength(2));
      expect(check.refusals.first, contains('vazio'));
    });

    test('imagem não passa pela contagem de páginas', () {
      expect(checkImportFiles([_png('a.png')]).accepted, hasLength(1));
    });
  });

  group('tela', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

    Future<void> openImport(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) async {
      await pumpIagoApp(tester, overrides: overrides);
      await enterDemo(tester);
      containerOf(tester).read(routerProvider).go(Routes.import);
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester) async {
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();
    }

    testWidgets('limite diário: mensagem própria, resto pendente, sem perder o '
        'que veio', (tester) async {
      final ex = _Extractor([
        _result('Quanto é 1 + 1?'),
        AiFailure.dailyLimit,
        _result('Quanto é 2 + 2?'),
      ]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(ex),
          pickFilesProvider.overrideWithValue(
            () async => [_png('a.png'), _png('b.png'), _png('c.png')],
          ),
        ],
      );
      await pick(tester);
      expect(find.byKey(const Key('import-quota')), findsOneWidget);
      expect(find.textContaining('limite de leituras de IA'), findsWidgets);
      // Não é a mensagem da cota do provedor.
      expect(find.textContaining('por volta das 5h'), findsNothing);
      expect(find.text('Pendente'), findsNWidgets(2));
      expect(ex.calls, 2);
    });

    testWidgets('PDF acima do limite: recusa sem chamar a IA', (tester) async {
      final ex = _Extractor([_result('x')]);
      final big = await tester.runAsync(() => _pdf('grande.pdf', 11));
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(ex),
          pickFilesProvider.overrideWithValue(() async => [big!]),
        ],
      );
      await pick(tester);
      expect(ex.calls, 0);
      expect(find.byKey(const Key('import-refusal')), findsOneWidget);
      expect(find.textContaining('11 páginas'), findsOneWidget);
    });

    testWidgets('cancelar ignora o resultado e deixa o arquivo pendente', (
      tester,
    ) async {
      final hang = Completer<ExtractionResult>();
      final ex = _Extractor([hang, _result('Quanto é 3 + 3?')]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(ex),
          pickFilesProvider.overrideWithValue(
            () async => [_png('a.png'), _png('b.png')],
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Lendo o arquivo…'), findsOneWidget);

      // O indicador de progresso gira: nada de pumpAndSettle enquanto lê.
      await tester.ensureVisible(find.byKey(const Key('import-cancel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('import-cancel')));
      await tester.pump();
      expect(find.byKey(const Key('import-cancel')), findsNothing);
      expect(find.text('Pendente'), findsNWidgets(2));

      // O resultado que chega depois é ignorado: nenhum rascunho.
      hang.complete(_result('Quanto é 1 + 1?'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-count')), findsNothing);
      expect(ex.calls, 1);

      // E dá para tentar de novo.
      await tapVisible(tester, find.byKey(const Key('import-resume')));
      expect(ex.calls, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('demo nunca toca no gateway nem no App Check', (tester) async {
      final gateway = _CountingGateway();
      await openImport(
        tester,
        overrides: [aiGatewayProvider.overrideWithValue(gateway)],
      );
      await tester.pump(const Duration(seconds: 1));
      expect(gateway.availabilityCalls, 0);
      expect(find.byKey(const Key('import-pick')), findsOneWidget);
    });

    testWidgets('toque duplo em "pendentes" e cancelar+retomar não extraem '
        'em dobro', (tester) async {
      final hang = Completer<ExtractionResult>();
      final ex = _Extractor([hang, _result('Quanto é 1 + 1?')]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(ex),
          pickFilesProvider.overrideWithValue(
            () async => [_png('a.png'), _png('b.png')],
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pump();
      await tester.pump();
      expect(ex.calls, 1);

      await tester.ensureVisible(find.byKey(const Key('import-cancel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('import-cancel')));
      await tester.pump();

      // Dois toques no mesmo quadro: só uma execução.
      final resume = find.byKey(const Key('import-resume'));
      await tester.ensureVisible(resume);
      await tester.pump();
      await tester.tap(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      // a (refeito) e b: 2 chamadas novas, e a antiga travada não conta.
      expect(ex.calls, 3);

      // A chamada antiga termina depois: ignorada, sem rascunho extra.
      hang.complete(_result('Velha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Velha'), findsNothing);
      expect(ex.calls, 3);
      expect(tester.takeException(), isNull);
    });
  });
}
