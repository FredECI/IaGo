import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/features/import/import_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

class _Extractor implements QuestionExtractor {
  _Extractor(this.script);
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
    return step as ExtractionResult;
  }
}

ExtractedQuestion _q(String s) => ExtractedQuestion(
  statement: s,
  type: QuestionType.objective,
  alternatives: const ['1', '2', '3', '4', '5'],
  hasFigure: false,
  isComplete: true,
  suggestedArea: Area.mathematics,
  suggestedSubject: 'Matemática',
);

ImportFile _f(String name, {String mime = 'image/png', int size = 10}) =>
    ImportFile(name: name, mimeType: mime, bytes: Uint8List(size));

const _secret = 'ENUNCIADO-SECRETO-XYZ';

void main() {
  setUpAll(initTestLocale);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  late MemoryMetricsRepository metrics;

  Future<void> openImport(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    metrics = MemoryMetricsRepository(clock: () => testNow);
    await pumpIagoApp(
      tester,
      overrides: [
        metricsRepositoryProvider.overrideWithValue(metrics),
        ...overrides,
      ],
    );
    await enterDemo(tester);
    containerOf(tester).read(routerProvider).go(Routes.import);
    await tester.pumpAndSettle();
  }

  Future<int> total(WidgetTester tester) async => (await tester.runAsync(
    () => containerOf(tester).read(questionRepositoryProvider).watchAll().first,
  ))!.length;

  Future<void> acceptNotice(WidgetTester tester) async {
    await tapVisible(tester, find.byKey(const Key('import-pick')));
    await tester.tap(find.byKey(const Key('ai-notice-accept')));
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('import-paste-field')), text);
    await tapVisible(tester, find.byKey(const Key('import-split')));
  }

  /// Os mapas devem ter só tipos escalares curtos e nunca o texto da questão.
  void expectNoContent(Map<String, Object?> map) {
    for (final e in map.entries) {
      expect(e.value is num || e.value is bool || e.value is String, isTrue);
      expect('${e.value}'.length < 24, isTrue, reason: '${e.key}=${e.value}');
      expect('${e.value}'.contains(_secret), isFalse);
    }
  }

  for (final entry in <String, String>{
    'Questão N': 'Questão ##\nEnunciado ## aqui\nA) um\nB) dois\nC) três\nD) quatro\nE) cinco\n',
    'N.': '##. Enunciado ## aqui\n(A) um\n(B) dois\n(C) três\n(D) quatro\n(E) cinco\n',
    'N)':
        '##) Enunciado ## aqui\na) um\nb) dois\nc) três\nd) quatro\ne) cinco\n',
    'QUESTÃO 0N': 'QUESTÃO 0##\nEnunciado ## aqui\nA. um\nB. dois\nC. três\nD. quatro\nE. cinco\n',
  }.entries) {
    testWidgets('CA-I1: 5 questões no formato ${entry.key}', (tester) async {
      await openImport(tester);
      await paste(
        tester,
        [for (var n = 1; n <= 5; n++) entry.value.replaceAll('##', '$n')]
            .join('\n'),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('import-count')));
      expect(find.textContaining('5 de 5 marcadas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('CA-I4: sair sem salvar não grava nada', (tester) async {
    await openImport(tester);
    final before = await total(tester);
    await paste(
      tester,
      [
        for (var n = 1; n <= 5; n++)
          'Questão $n\nQuanto é $n + $n?\nA) 1\nB) 2\nC) 3\nD) 4\nE) 5\n',
      ].join('\n'),
    );
    containerOf(tester).read(routerProvider).go(Routes.questions);
    await tester.pumpAndSettle();
    expect(await total(tester), before);
    expect(
      metrics.logged.where((e) => e.type == MetricEventType.questionsBulkSaved),
      isEmpty,
    );
  });

  testWidgets('CA-I5: 3 arquivos, 1 falha: 2 ficam e só o falho repete', (
    tester,
  ) async {
    final ex = _Extractor([
      ExtractionResult(questions: [_q('Quanto é 1 + 1?')]),
      AiFailure.malformed,
      ExtractionResult(questions: [_q('Quanto é 3 + 3?')]),
      ExtractionResult(questions: [_q('Quanto é 2 + 2?')]),
    ]);
    await openImport(
      tester,
      overrides: [
        questionExtractorProvider.overrideWithValue(ex),
        pickFilesProvider.overrideWithValue(
          () async => [_f('a.png'), _f('b.png'), _f('c.png')],
        ),
      ],
    );
    await acceptNotice(tester);
    expect(ex.calls, 3);
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('import-count')));
    expect(find.textContaining('2 de 2 marcadas'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('job-retry-b.png')));
    expect(ex.calls, 4, reason: 'só o arquivo que falhou');
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('import-count')));
    expect(find.textContaining('3 de 3 marcadas'), findsOneWidget);
  });

  testWidgets('CA-I13: tipo errado e arquivo grande: recusa sem chamar a IA', (
    tester,
  ) async {
    final ex = _Extractor([
      ExtractionResult(questions: [_q('x')]),
    ]);
    await openImport(
      tester,
      overrides: [
        questionExtractorProvider.overrideWithValue(ex),
        pickFilesProvider.overrideWithValue(
          () async => [
            _f('doc.docx', mime: 'application/msword'),
            _f('grande.png', size: 10 * 1024 * 1024 + 1),
          ],
        ),
      ],
    );
    await acceptNotice(tester);
    expect(ex.calls, 0);
    expect(find.byKey(const Key('import-refusal')), findsNWidgets(2));
    expect(find.byKey(const Key('import-count')), findsNothing);
  });

  testWidgets('CA-I13: exatamente 10 MB é aceito (limite)', (tester) async {
    final ex = _Extractor([
      ExtractionResult(questions: [_q('Quanto é 1 + 1?')]),
    ]);
    await openImport(
      tester,
      overrides: [
        questionExtractorProvider.overrideWithValue(ex),
        pickFilesProvider.overrideWithValue(
          () async => [_f('limite.png', size: 10 * 1024 * 1024)],
        ),
      ],
    );
    await acceptNotice(tester);
    expect(ex.calls, 1);
    expect(find.byKey(const Key('import-refusal')), findsNothing);
  });

  testWidgets('CA-I14 + CA-I11: eventos sem conteúdo e origin=import', (
    tester,
  ) async {
    await openImport(tester);
    await paste(
      tester,
      [
        for (var n = 1; n <= 3; n++)
          'Questão $n\n$_secret $n?\nA) um\nB) dois\nC) três\nD) quatro\nE) cinco\n',
      ].join('\n'),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('bulk-area-mathematics')));
    await tester.enterText(find.byKey(const Key('bulk-platform')), 'Apostila');
    await tapVisible(tester, find.byKey(const Key('import-apply-all')));
    await tapVisible(tester, find.byKey(const Key('draft-check-3')));
    await tapVisible(tester, find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    final run = metrics.logged
        .singleWhere((e) => e.type == MetricEventType.importRun)
        .toMap();
    expect(run, {
      'source': 'paste',
      'files': 0,
      'extracted': 3,
      'failedFiles': 0,
      'partial': false,
      'type': 'import_run',
      'at': testNow,
    });
    final bulk = metrics.logged
        .singleWhere((e) => e.type == MetricEventType.questionsBulkSaved)
        .toMap();
    expect(bulk['origin'], 'import');
    expect(bulk['count'], 2);
    expect(bulk['discardedCount'], 1);
    expect(bulk.keys.toSet(), {
      'origin',
      'count',
      'seconds',
      'discardedCount',
      'type',
      'at',
    });
    expectNoContent({
      for (final e in [...run.entries, ...bulk.entries])
        if (e.key != 'at') e.key: e.value,
    });

    final imported = (await tester.runAsync(
      () =>
          containerOf(tester).read(questionRepositoryProvider).watchAll().first,
    ))!.where((q) => q.origin == QuestionOrigin.import);
    expect(imported.length, 2);
  });

  testWidgets('CA-I14: evento de arquivos também não leva conteúdo', (
    tester,
  ) async {
    final ex = _Extractor([
      ExtractionResult(questions: [_q('$_secret 1')]),
      AiFailure.blocked,
    ]);
    await openImport(
      tester,
      overrides: [
        questionExtractorProvider.overrideWithValue(ex),
        pickFilesProvider.overrideWithValue(
          () async => [_f('a.png'), _f('b.png')],
        ),
      ],
    );
    await acceptNotice(tester);
    final run = metrics.logged
        .singleWhere((e) => e.type == MetricEventType.importRun)
        .toMap();
    expect(run['source'], 'files');
    expect(run['files'], 2);
    expect(run['extracted'], 1);
    expect(run['failedFiles'], 1);
    expect('$run'.contains(_secret), isFalse);
    expect('$run'.contains('a.png'), isFalse, reason: 'nome do arquivo vaza');
  });

  testWidgets('CA-I9: figura marcada manualmente salva; sem marcar, não', (
    tester,
  ) async {
    final ex = _Extractor([
      ExtractionResult(
        questions: [
          ExtractedQuestion(
            statement: 'Veja o gráfico',
            type: QuestionType.objective,
            alternatives: const ['1', '2', '3', '4', '5'],
            hasFigure: true,
            isComplete: true,
            suggestedArea: Area.mathematics,
            suggestedSubject: 'Matemática',
          ),
        ],
      ),
    ]);
    await openImport(
      tester,
      overrides: [
        questionExtractorProvider.overrideWithValue(ex),
        pickFilesProvider.overrideWithValue(() async => [_f('a.png')]),
      ],
    );
    await acceptNotice(tester);
    final before = await total(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('bulk-platform')));
    await tester.enterText(find.byKey(const Key('bulk-platform')), 'Site');
    await tapVisible(tester, find.byKey(const Key('import-apply-all')));
    // Desmarcada: salvar não grava.
    await tapVisible(tester, find.byKey(const Key('import-save')));
    expect(await total(tester), before);
  });
}
