import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/features/import/import_models.dart';
import 'package:iago/features/import/import_providers.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/data/repositories.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

/// Extrator de teste: cada chamada consome o próximo item do roteiro, que é
/// uma falha ([AiFailure]) ou um resultado.
class _ScriptedExtractor implements QuestionExtractor {
  _ScriptedExtractor(this.script);

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

ExtractedQuestion _extracted(
  String statement, {
  bool hasFigure = false,
  bool isComplete = true,
}) => ExtractedQuestion(
  statement: statement,
  type: QuestionType.objective,
  alternatives: const ['1', '2', '3', '4', '5'],
  hasFigure: hasFigure,
  isComplete: isComplete,
  suggestedArea: Area.mathematics,
  suggestedSubject: 'Matemática',
);

ExtractionResult _result(List<ExtractedQuestion> q) =>
    ExtractionResult(questions: q);

ImportFile _file(String name) => ImportFile(
  name: name,
  mimeType: 'image/png',
  bytes: Uint8List.fromList(List.filled(10, 1)),
);

String _pasted(int count) => [
  for (var n = 1; n <= count; n++)
    'Questão $n\nQual o valor de $n + $n?\nA) 1\nB) 2\nC) 3\nD) 4\nE) 5\n',
].join('\n');

class _FailingRepo implements QuestionRepository {
  @override
  Stream<List<Question>> watchAll() => Stream.value(const []);

  @override
  Future<List<Question>> createMany(List<Question> questions) =>
      throw StateError('segredo-interno');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(initTestLocale);

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

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('import-paste-field')), text);
    await tapVisible(tester, find.byKey(const Key('import-split')));
  }

  Future<List<Question>> allQuestions(WidgetTester tester) => tester
      .runAsync(
        () =>
            containerOf(tester)
                .read(questionRepositoryProvider)
                .watchAll()
                .first,
      )
      .then((v) => v!);

  Future<int> totalQuestions(WidgetTester tester) async =>
      (await allQuestions(tester)).length;

  Future<void> expectCount(WidgetTester tester, String text) async {
    // A lista é preguiçosa: volta ao topo e desce até o contador.
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('import-count')));
    expect(find.text(text), findsOneWidget);
  }

  bool checked(WidgetTester tester, int id) =>
      tester.widget<Checkbox>(find.byKey(Key('draft-check-$id'))).value!;

  group('colagem', () {
    testWidgets('5 questões: revisar e salvar só as marcadas', (tester) async {
      await openImport(tester);
      final before = await totalQuestions(tester);

      await paste(tester, _pasted(5));
      expect(find.byKey(const Key('import-count')), findsOneWidget);
      await expectCount(
        tester,
        '5 de 5 marcadas para salvar (limite de 30 por lote).',
      );
      // Nada gravado antes de "Salvar" (CA-I4).
      expect(await totalQuestions(tester), before);
      // Sem aviso de privacidade na colagem (CA-I12).
      expect(find.byKey(const Key('ai-notice')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('draft-check-2')));
      expect(checked(tester, 2), isFalse);
      await expectCount(
        tester,
        '4 de 5 marcadas para salvar (limite de 30 por lote).',
      );

      // Sem categoria nem plataforma: não salva e mostra o que falta.
      await tapVisible(tester, find.byKey(const Key('import-save')));
      expect(find.text('Escolha a área.'), findsWidgets);
      expect(await totalQuestions(tester), before);

      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('bulk-area-mathematics')));
      await tester.enterText(
        find.byKey(const Key('bulk-platform')),
        'Apostila',
      );
      await tapVisible(tester, find.byKey(const Key('import-apply-all')));
      await tapVisible(tester, find.byKey(const Key('import-save')));

      await tester.pumpAndSettle();
      expect(await totalQuestions(tester), before + 4);
      final imported = (await allQuestions(tester))
          .where((q) => q.origin == QuestionOrigin.import);
      expect(imported.length, 4);
      expect(imported.every((q) => q.platform == 'Apostila'), isTrue);
      expect(find.byKey(const Key('import-summary')), findsOneWidget);
      expect(find.text('4 questões salvas'), findsOneWidget);
      expect(
        find.text('Minhas questões: de $before para ${before + 4}.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mais de 30 questões: mantém as primeiras 30', (tester) async {
      await openImport(tester);
      await paste(tester, _pasted(35));
      // O excedente continua no campo de colagem, a partir da questão 31.
      final field = tester.widget<TextField>(
        find.byKey(const Key('import-paste-field')),
      );
      expect(field.controller!.text, startsWith('Questão 31'));
      expect(field.controller!.text, contains('Questão 35'));
      expect(field.controller!.text, isNot(contains('Questão 30')));
      // Esvazia o campo para a rolagem de teste não cair dentro dele.
      field.controller!.clear();
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('import-count')));
      expect(
        find.text('30 de 30 marcadas para salvar (limite de 30 por lote).'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-cap-notice')), findsOneWidget);
      expect(find.byKey(const Key('draft-31')), findsNothing);
    });

    testWidgets('lote cheio: colar de novo não registra import_run vazio', (
      tester,
    ) async {
      await openImport(tester);
      await paste(tester, _pasted(30));
      await paste(tester, _pasted(3));
      final repo = containerOf(
        tester,
      ).read(metricsRepositoryProvider) as MemoryMetricsRepository;
      final runs = repo.logged
          .where((e) => e.type == MetricEventType.importRun)
          .toList();
      expect(runs.length, 1);
      expect(runs.single.intData('extracted'), 30);
    });

    testWidgets('Ver minhas questões limpa busca e filtros', (tester) async {
      await openImport(tester);
      final notifier = containerOf(tester)
          .read(questionFilterProvider.notifier);
      notifier.setQuery('xyz');
      notifier.toggleArea(Area.humanities);
      await paste(tester, _pasted(1));
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('bulk-area-mathematics')));
      await tester.enterText(find.byKey(const Key('bulk-platform')), 'Site');
      await tapVisible(tester, find.byKey(const Key('import-apply-all')));
      await tapVisible(tester, find.byKey(const Key('import-save')));
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(questionFilterProvider).isEmpty, isFalse);

      await tester.tap(find.byKey(const Key('import-see-questions')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(questionFilterProvider).isEmpty, isTrue);
    });

    testWidgets('erro ao salvar mostra mensagem fixa, sem a exceção', (
      tester,
    ) async {
      await openImport(
        tester,
        overrides: [
          questionRepositoryProvider.overrideWithValue(_FailingRepo()),
        ],
      );
      await paste(tester, _pasted(1));
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('bulk-area-mathematics')));
      await tester.enterText(find.byKey(const Key('bulk-platform')), 'Site');
      await tapVisible(tester, find.byKey(const Key('import-apply-all')));
      await tapVisible(tester, find.byKey(const Key('import-save')));
      expect(
        find.text('Não foi possível salvar. Tente de novo.'),
        findsOneWidget,
      );
      expect(find.textContaining('segredo-interno'), findsNothing);
      expect(find.byKey(const Key('import-summary')), findsNothing);
    });

    testWidgets('trocar de sessão zera o aceite do aviso', (tester) async {
      await openImport(
        tester,
        overrides: [pickFilesProvider.overrideWithValue(() async => const [])],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      expect(container.read(aiNoticeAcceptedProvider), aiNoticeVersion);
      await container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(container.read(aiNoticeAcceptedProvider), isNull);
    });

    testWidgets('texto sem questão avisa e não cria rascunho', (tester) async {
      await openImport(tester);
      await tester.enterText(find.byKey(const Key('import-paste-field')), '  ');
      await tapVisible(tester, find.byKey(const Key('import-split')));
      expect(find.byKey(const Key('import-count')), findsNothing);
    });
  });

  group('arquivos', () {
    testWidgets('aviso de privacidade só no caminho de arquivos', (
      tester,
    ) async {
      var picks = 0;
      await openImport(
        tester,
        overrides: [
          pickFilesProvider.overrideWithValue(() async {
            picks++;
            return [_file('prova.png')];
          }),
        ],
      );
      expect(find.byKey(const Key('import-simulated-note')), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(find.byKey(const Key('ai-notice')), findsOneWidget);
      expect(find.textContaining('vai para o Google'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-notice-cancel')));
      await tester.pumpAndSettle();
      expect(picks, 0);

      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(
        containerOf(tester).read(aiNoticeAcceptedProvider),
        aiNoticeVersion,
      );

      // Depois de aceito, não pergunta de novo.
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(find.byKey(const Key('ai-notice')), findsNothing);
      expect(picks, 2);
    });

    testWidgets('demo: 1 falha, tentar de novo só este', (tester) async {
      final extractor = _ScriptedExtractor([
        AiFailure.blocked,
        _result([_extracted('Quanto é 2 + 3?'), _extracted('Quanto é 4 + 4?')]),
      ]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(extractor),
          pickFilesProvider.overrideWithValue(() async => [_file('prova.png')]),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();

      expect(find.text('A IA não processou este arquivo.'), findsOneWidget);
      expect(find.byKey(const Key('import-count')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('job-retry-prova.png')));
      expect(extractor.calls, 2);
      expect(find.text('2 questões encontradas'), findsOneWidget);
      await expectCount(
        tester,
        '2 de 2 marcadas para salvar (limite de 30 por lote).',
      );
    });

    testWidgets('figura ou cortada vem desmarcada e com aviso', (tester) async {
      final extractor = _ScriptedExtractor([
        _result([
          _extracted('Questão com gráfico', hasFigure: true),
          _extracted('Questão cortada', isComplete: false),
          _extracted('Questão boa'),
        ]),
      ]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(extractor),
          pickFilesProvider.overrideWithValue(() async => [_file('prova.png')]),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();

      await expectCount(
        tester,
        '1 de 3 marcadas para salvar (limite de 30 por lote).',
      );
      await reveal(tester, find.byKey(const Key('draft-1')));
      expect(checked(tester, 1), isFalse);
      expect(
        find.textContaining('Depende de figura, gráfico ou tabela'),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(const Key('draft-3')));
      expect(checked(tester, 3), isTrue);
      expect(find.textContaining('pode estar cortada'), findsOneWidget);
    });

    testWidgets('cota (429): mantém o que veio e mostra o horário', (
      tester,
    ) async {
      final extractor = _ScriptedExtractor([
        _result([_extracted('Quanto é 1 + 1?')]),
        AiFailure.quotaExhausted,
        _result([_extracted('Quanto é 2 + 2?')]),
      ]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(extractor),
          pickFilesProvider.overrideWithValue(
            () async => [_file('a.png'), _file('b.png'), _file('c.png')],
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-quota')), findsOneWidget);
      expect(find.textContaining('por volta das 5h'), findsWidgets);
      expect(find.textContaining('A colagem funciona agora'), findsWidgets);
      // A primeira ficou na revisão; as outras, pendentes.
      await expectCount(
        tester,
        '1 de 1 marcadas para salvar (limite de 30 por lote).',
      );
      expect(extractor.calls, 2);
      expect(find.text('Pendente'), findsNWidgets(2));

      await tapVisible(tester, find.byKey(const Key('import-resume')));
      expect(extractor.calls, 4);
    });

    testWidgets('mais de 5 arquivos: recusa os extras antes de enviar', (
      tester,
    ) async {
      final extractor = _ScriptedExtractor([
        _result([_extracted('Quanto é 1 + 1?')]),
      ]);
      await openImport(
        tester,
        overrides: [
          questionExtractorProvider.overrideWithValue(extractor),
          pickFilesProvider.overrideWithValue(
            () async => [for (var i = 0; i < 7; i++) _file('p$i.png')],
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tester.tap(find.byKey(const Key('ai-notice-accept')));
      await tester.pumpAndSettle();
      expect(extractor.calls, 5);
      expect(find.byKey(const Key('import-refusal')), findsNWidgets(2));
    });

    testWidgets('sem extrator: esconde os arquivos e explica', (tester) async {
      await openImport(
        tester,
        overrides: [questionExtractorProvider.overrideWithValue(null)],
      );
      expect(find.byKey(const Key('import-files-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('import-pick')), findsNothing);
      // A colagem segue funcionando.
      await paste(tester, _pasted(2));
      expect(find.byKey(const Key('import-count')), findsOneWidget);
    });
  });

  group('regras puras', () {
    final scripted = _ScriptedExtractor([_result(const [])]);

    test('modo da IA: demo, indisponível e conta real', () {
      const off = AccessPolicy.safeDefault(termsMinAge: 18);
      const on = AccessPolicy(termsMinAge: 18, minAge: 18, aiEnabled: true);
      ImportAiMode mode({
        bool isDemo = false,
        QuestionExtractor? extractor,
        AccessPolicy policy = off,
        bool isMember = false,
      }) => resolveImportAiMode(
        isDemo: isDemo,
        extractor: extractor,
        policy: policy,
        isMember: isMember,
      );
      expect(mode(isDemo: true, extractor: scripted), ImportAiMode.simulated);
      expect(mode(isDemo: true), ImportAiMode.unavailable);
      expect(mode(extractor: scripted), ImportAiMode.unavailable);
      expect(mode(extractor: scripted, policy: on), ImportAiMode.unavailable);
      expect(
        mode(extractor: scripted, policy: on, isMember: true),
        ImportAiMode.real,
      );
    });

    test('limites de arquivo: tipo, tamanho e quantidade', () {
      final big = ImportFile(
        name: 'g.png',
        mimeType: 'image/png',
        bytes: Uint8List(maxImportFileBytes + 1),
      );
      final doc = ImportFile(
        name: 'a.docx',
        mimeType: 'application/msword',
        bytes: Uint8List(5),
      );
      final check = checkImportFiles([big, doc, _file('ok.png')]);
      expect(check.accepted.map((f) => f.name), ['ok.png']);
      expect(check.refusals.length, 2);

      final many = checkImportFiles([
        for (var i = 0; i < 6; i++) _file('$i.png'),
      ]);
      expect(many.accepted.length, maxImportFiles);
      expect(many.refusals.length, 1);
    });
  });
}
