import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/theme.dart';
import 'package:iago/data/firebase/firestore_direction_repository.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/bank_source.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/features/bank/bank_pages.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_bank_catalog.dart';
import '../../helpers/test_app.dart';

/// BM9: detalhe com dificuldade relativa e "Classificação automática", Fontes e
/// licenças com várias fontes e a data, mapeamento dos campos novos da etapa e
/// o interruptor na política.
Question bankQuestion({int? band, bool auto = false}) => Question(
  id: 'bank_enem-2022-1',
  statement: 'Enunciado da questão.',
  type: QuestionType.objective,
  alternatives: const ['a', 'b', 'c', 'd', 'e'],
  area: Area.mathematics,
  subject: 'Matemática',
  platform: 'ENEM 2022',
  createdAt: DateTime(2026, 11, 7),
  updatedAt: DateTime(2026, 11, 7),
  origin: QuestionOrigin.bank,
  bankId: 'enem-2022-1',
  bankDifficulty: band,
  autoClassified: auto,
);

Future<void> pumpPage(
  WidgetTester tester,
  Widget page,
  FakeBankCatalog catalog,
) async {
  await initTestLocale();
  tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[bankCatalogProvider.overrideWithValue(catalog)],
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: const Locale('pt', 'BR'),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakeBankCatalog catalogOf(
  Question q, {
  List<BankSource> sources = const [fakeBankSource],
}) => FakeBankCatalog(
  delay: Duration.zero,
  data: BankData(sources: sources, questions: [q], generatedAt: '2026-11-07'),
);

void main() {
  group('detalhe da questão', () {
    testWidgets('dificuldade sempre comparada e Classificação automática', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const BankQuestionPage(questionId: 'enem-2022-1'),
        catalogOf(bankQuestion(band: 3, auto: true)),
      );
      expect(
        find.text(
          'Dificuldade estimada pelo INEP: Difícil '
          '(entre as mais difíceis de Matemática no acervo)',
        ),
        findsOneWidget,
      );
      expect(find.text('Classificação automática'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem faixa e classificação manual: nada disso aparece', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const BankQuestionPage(questionId: 'enem-2022-1'),
        catalogOf(bankQuestion()),
      );
      expect(find.byKey(const Key('bank-difficulty')), findsNothing);
      expect(find.text('Classificação automática'), findsNothing);
    });
  });

  testWidgets('Fontes e licenças: várias fontes, dados de dificuldade e data', (
    tester,
  ) async {
    const difficulty = BankSource(
      id: 'inepdados',
      name: 'Microdados do ENEM (INEP)',
      officialUrl: 'https://exemplo.gov.br/microdados',
      attribution: 'Microdados, INEP.',
      notice: '',
      kind: 'difficulty',
    );
    await pumpPage(
      tester,
      const BankSourcesPage(),
      catalogOf(bankQuestion(), sources: const [fakeBankSource, difficulty]),
    );
    expect(find.text('ENEM (INEP)'), findsOneWidget);
    expect(find.text('Microdados do ENEM (INEP)'), findsOneWidget);
    expect(find.text('Dados de dificuldade'), findsOneWidget);
    expect(find.text('Acervo gerado em 07/11/2026.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('etapa no Firestore', () {
    final base = StudyStep(
      id: 's1',
      action: StepAction.buildList,
      area: Area.mathematics,
      subject: 'Matemática',
      targetCount: 10,
      dueAt: DateTime(2026, 12, 1),
      source: StepSource.rules,
      rationale: 'x',
      createdAt: DateTime(2026, 11, 20),
    );

    test('ida e volta dos campos do acervo', () {
      final step = base.withBank(
        bankIds: ['enem-2022-1', 'enem-2023-45'],
        difficultyTarget: 2,
        bankListId: 'L1',
        bankAvailableAtProposal: 40,
      );
      final back = stepFromMap('s1', stepToMap(step))!;
      expect(back.bankIds, step.bankIds);
      expect(back.difficultyTarget, 2);
      expect(back.bankListId, 'L1');
      expect(back.bankAvailableAtProposal, 40);
    });

    test('documento antigo continua válido e sem os campos', () {
      final map = stepToMap(base);
      expect(map.keys, isNot(contains('bankIds')));
      final back = stepFromMap('s1', map)!;
      expect(back.bankIds, isEmpty);
      expect(back.difficultyTarget, isNull);
      expect(back.bankListId, isNull);
    });

    test('campo de tipo errado ou id fora do formato é ignorado', () {
      final map = {
        ...stepToMap(base),
        'bankIds': ['enem-2022-1', 'Inválido!', 7, 'x'],
        'difficultyTarget': 9,
        'bankListId': 5,
        'bankAvailableAtProposal': 'muitas',
      };
      final back = stepFromMap('s1', map)!;
      expect(back.bankIds, ['enem-2022-1']);
      expect(back.difficultyTarget, isNull);
      expect(back.bankListId, isNull);
      expect(back.bankAvailableAtProposal, isNull);
    });

    test('limpar o vínculo da lista apaga o campo', () {
      final linked = base.withBank(bankListId: 'L1');
      final cleared = linked.withBank(bankListId: null);
      expect(stepToMap(cleared).keys, isNot(contains('bankListId')));
    });
  });

  group('directionBankEnabled na política', () {
    test('padrão ligado; false desliga; tipo errado vale o padrão', () {
      AccessPolicy of(Map<String, Object?>? d) =>
          AccessPolicy.fromRuntime(d, termsMinAge: 18);
      expect(of(null).directionBankEnabled, isTrue);
      expect(of(const {}).directionBankEnabled, isTrue);
      expect(of({'directionBankEnabled': false}).directionBankEnabled, isFalse);
      expect(of({'directionBankEnabled': 'não'}).directionBankEnabled, isTrue);
      expect(
        const AccessPolicy.safeDefault(termsMinAge: 18).directionBankEnabled,
        isTrue,
      );
    });
  });
}
