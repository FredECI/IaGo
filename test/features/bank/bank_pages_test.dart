import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/lists/lists_providers.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_bank_catalog.dart';
import '../../helpers/test_app.dart';

/// A4 e A5: lista do acervo, detalhe, salvar, montar lista e fontes, tudo a
/// 360 px (o `pumpIagoApp` já fixa a tela) com um catálogo falso e lento.
void main() {
  setUpAll(initTestLocale);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  Future<FakeBankCatalog> openBank(
    WidgetTester tester, {
    String path = '/questoes/acervo',
    FakeBankCatalog? catalog,
  }) async {
    final fake = catalog ?? FakeBankCatalog();
    await pumpIagoApp(
      tester,
      overrides: [bankCatalogProvider.overrideWithValue(fake)],
    );
    await enterDemo(tester);
    containerOf(tester).read(routerProvider).go(path);
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> typeQuery(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('bank-search-field')), text);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  int savedCount(WidgetTester tester) =>
      containerOf(tester)
          .read(questionsProvider)
          .value!
          .where((q) => q.origin == QuestionOrigin.bank)
          .length;

  group('lista do acervo', () {
    testWidgets('mostra carregando, depois a contagem com contexto', (
      tester,
    ) async {
      final fake = FakeBankCatalog();
      await pumpIagoApp(
        tester,
        overrides: [bankCatalogProvider.overrideWithValue(fake)],
      );
      await enterDemo(tester);
      containerOf(tester).read(routerProvider).go('/questoes/acervo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel('Carregando o acervo'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('1.250 questões'), findsOneWidget);
      expect(find.byKey(const Key('bank-card-enem-2022-0')), findsOneWidget);
      // Matéria vazia: aviso discreto.
      expect(find.byKey(const Key('bank-unclassified-note')), findsOneWidget);
      expect(find.textContaining('ainda sem matéria'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('bank-load-more')));
      expect(find.text('Mostrando 40 de 1.250'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('buscar com debounce e filtrar não mexe em Minhas questões', (
      tester,
    ) async {
      final fake = await openBank(tester);
      final before = fake.cursors.length;

      await tester.enterText(
        find.byKey(const Key('bank-search-field')),
        'função',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // Ainda dentro da pausa de 300 ms: nenhuma busca nova.
      expect(fake.cursors.length, before);
      await tester.pumpAndSettle();
      expect(find.text('50 de 1.250 questões'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bank-filter-area-mathematics')));
      await tester.pumpAndSettle();
      expect(find.text('50 de 1.250 questões'), findsOneWidget);

      // E com a busca: nenhuma outra área tem "função", então o chip dela
      // fica desligado (contador 0).
      final languages = tester.widget<FilterChip>(
        find.descendant(
          of: find.byKey(const Key('bank-filter-area-languages')),
          matching: find.byType(FilterChip),
        ),
      );
      expect(languages.onSelected, isNull);

      // Minhas questões não foi tocada (CA-B3).
      final c = containerOf(tester);
      expect(c.read(questionFilterProvider), const QuestionFilter());
      expect(c.read(questionsProvider).value, hasLength(40));
      expect(c.read(bankFilterProvider).areas, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('filtro por área e tipo muda a contagem', (tester) async {
      await openBank(tester);
      await tester.tap(find.byKey(const Key('bank-filter-area-mathematics')));
      await tester.pumpAndSettle();
      expect(find.textContaining(' de 1.250 questões'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bank-clear-filters')));
      await tester.pumpAndSettle();
      expect(find.text('1.250 questões'), findsOneWidget);
    });

    testWidgets('busca sem resultado mostra o estado vazio e limpa', (
      tester,
    ) async {
      await openBank(tester);
      await typeQuery(tester, 'zzzxqwyk');
      expect(find.text('Nenhuma questão com esses filtros'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('bank-empty-clear')));
      await tester.pumpAndSettle();
      expect(find.text('1.250 questões'), findsOneWidget);
    });

    testWidgets('Carregar mais usa o cursor; falha tem nova tentativa', (
      tester,
    ) async {
      final fake = await openBank(tester);
      final more = find.byKey(const Key('bank-load-more'));
      fake.failSearches = 1;
      await tapVisible(tester, more);
      expect(
        find.text('Não foi possível carregar mais questões.'),
        findsOneWidget,
      );
      expect(find.text('Mostrando 40 de 1.250'), findsOneWidget);

      await tapVisible(tester, find.text('Tentar de novo'));
      await reveal(tester, find.byKey(const Key('bank-load-more')));
      expect(find.text('Mostrando 80 de 1.250'), findsOneWidget);
      expect(fake.cursors.last, '40');
      expect(tester.takeException(), isNull);
    });

    testWidgets('erro ao abrir mostra "Tentar de novo"', (tester) async {
      final fake = FakeBankCatalog()..failSearches = 1;
      await openBank(tester, catalog: fake);
      expect(find.text('Não foi possível abrir o acervo'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('bank-retry')));
      await tester.pumpAndSettle();
      expect(find.text('1.250 questões'), findsOneWidget);
    });
  });

  group('detalhe e salvar', () {
    testWidgets('abre pelo cartão: sem gabarito e com crédito', (tester) async {
      await openBank(tester);
      await tapVisible(tester, find.byKey(const Key('bank-card-enem-2022-3')));

      expect(find.textContaining('Questão 3.'), findsOneWidget);
      for (final letter in Question.letters) {
        expect(find.text('Alternativa $letter do 3'), findsOneWidget);
      }
      expect(find.textContaining('abarito'), findsNothing);
      // Crédito: attribution e notice do asset, sem afirmar licença.
      expect(find.text('Provas do ENEM, INEP.'), findsOneWidget);
      expect(find.byKey(const Key('bank-notice')), findsOneWidget);
      expect(
        find.textContaining('Reproduzido para uso educacional'),
        findsOneWidget,
      );
      expect(find.textContaining('licenciad'), findsNothing);
      expect(find.textContaining('sem alteração'), findsNothing);
      expect(find.byKey(const Key('bank-official-link')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('salva uma vez; depois mostra "Já salva" e não regrava', (
      tester,
    ) async {
      await openBank(tester, path: '/questoes/acervo/enem-2022-3');
      expect(savedCount(tester), 0);

      await tapVisible(tester, find.byKey(const Key('bank-save')));
      expect(savedCount(tester), 1);
      expect(find.byKey(const Key('bank-already-saved')), findsOneWidget);
      expect(find.text('Já salva'), findsOneWidget);
      expect(find.byKey(const Key('bank-save')), findsNothing);

      // O aluno edita a cópia; salvar de novo não pode apagar a edição.
      final c = containerOf(tester);
      final repo = c.read(questionRepositoryProvider);
      final copy = c
          .read(questionsProvider)
          .value!
          .firstWhere((q) => q.id == 'bank_enem-2022-3');
      expect(copy.platform, 'ENEM 2023');
      await repo.update(copy.copyWith(statement: 'Editada pelo aluno'));

      final original = fakeBankData().questions.firstWhere(
        (q) => q.bankId == 'enem-2022-3',
      );
      expect(await c.read(bankActionsProvider).save(original), isFalse);
      final after = c
          .read(questionsProvider)
          .value!
          .where((q) => q.id == 'bank_enem-2022-3');
      expect(after, hasLength(1));
      expect(after.single.statement, 'Editada pelo aluno');
      expect(savedCount(tester), 1);

      // Na lista, o cartão mostra "Já salva".
      c.read(routerProvider).go('/questoes/acervo');
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('bank-card-enem-2022-3')));
      expect(find.text('Já salva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('id inexistente mostra o estado vazio', (tester) async {
      await openBank(tester, path: '/questoes/acervo/nao-existe');
      expect(find.text('Questão não encontrada no acervo'), findsOneWidget);
    });
  });

  group('montar lista com estas N', () {
    testWidgets('cria as cópias e a lista com as N questões', (tester) async {
      await openBank(tester);
      await typeQuery(tester, 'reforço');
      expect(find.text('12 de 1.250 questões'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('bank-build-list')));
      expect(find.text('Nova lista com 12 questões'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('list-name-field')),
        'Reforço do acervo',
      );
      await tester.tap(find.byKey(const Key('list-name-confirm')));
      await tester.pumpAndSettle();

      final c = containerOf(tester);
      expect(savedCount(tester), 12);
      final lists = c.read(listsProvider).value!;
      final list = lists.firstWhere((l) => l.name == 'Reforço do acervo');
      expect(list.questionIds, hasLength(12));
      expect(list.questionIds.every((id) => id.startsWith('bank_')), isTrue);
      expect(c.read(routerProvider).state.uri.toString(), '/listas/${list.id}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('não regrava cópia já salva ao montar a lista', (tester) async {
      await openBank(tester, path: '/questoes/acervo/enem-2022-100');
      await tapVisible(tester, find.byKey(const Key('bank-save')));
      final c = containerOf(tester);
      final repo = c.read(questionRepositoryProvider);
      final copy = c
          .read(questionsProvider)
          .value!
          .firstWhere((q) => q.id == 'bank_enem-2022-100');
      await repo.update(copy.copyWith(statement: 'Minha versão'));

      c.read(routerProvider).go('/questoes/acervo');
      await tester.pumpAndSettle();
      await typeQuery(tester, 'reforço');
      await tapVisible(tester, find.byKey(const Key('bank-build-list')));
      await tester.tap(find.byKey(const Key('list-name-confirm')));
      await tester.pumpAndSettle();

      expect(savedCount(tester), 12);
      final mine = c
          .read(questionsProvider)
          .value!
          .firstWhere((q) => q.id == 'bank_enem-2022-100');
      expect(mine.statement, 'Minha versão');
    });

    testWidgets('mais de 30 resultados: botão desligado e aviso', (
      tester,
    ) async {
      await openBank(tester);
      await typeQuery(tester, 'função');
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('bank-build-list')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('bank-list-limit-note')), findsOneWidget);
      expect(find.textContaining('até 30 questões'), findsOneWidget);
    });
  });

  group('fontes e licenças', () {
    testWidgets('traz link oficial, remoção e avisos, sem afirmar licença', (
      tester,
    ) async {
      await openBank(tester, path: '/questoes/acervo/fontes');
      expect(find.text('ENEM (INEP)'), findsOneWidget);
      expect(find.text('Provas do ENEM, INEP.'), findsOneWidget);
      expect(find.byKey(const Key('source-link-enem')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('sources-removal')));
      expect(find.textContaining('<e-mail do projeto>'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('sources-unclassified')));
      expect(find.text('Questões com imagem'), findsOneWidget);
      expect(find.text('Matérias ainda sem classificação'), findsOneWidget);
      expect(find.textContaining('ainda estão sem matéria'), findsOneWidget);
      expect(find.textContaining('licenciad'), findsNothing);
      expect(find.textContaining('sem alteração'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('abre pelo botão Fontes da lista', (tester) async {
      await openBank(tester);
      await tapVisible(tester, find.byKey(const Key('open-bank-sources')));
      expect(find.byKey(const Key('source-link-enem')), findsOneWidget);
      expect(
        containerOf(tester).read(routerProvider).state.uri.toString(),
        '/questoes/acervo/fontes',
      );
    });
  });
}
