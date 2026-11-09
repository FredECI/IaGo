import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/bank_asset_catalog.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:iago/features/bank/bank_format.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/lists/lists_providers.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

/// QA de A4/A5 com o asset REAL (`assets/acervo/acervo-v1.json`), sem catálogo
/// falso: abre as telas, busca, salva e monta lista, a 360 px.
void main() {
  setUpAll(initTestLocale);

  final raw = jsonDecode(
    File('assets/acervo/acervo-v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final total = (raw['questions'] as List).length;
  // Mesmos dados e mesma lógica do catálogo real; só o transporte (rootBundle +
  // isolate) fica de fora, porque um 2º `compute` trava no flutter_test. O
  // transporte é provado no navegador (build web).
  final realCatalog = MemoryBankCatalog(
    parseBankAsset(File('assets/acervo/acervo-v1.json').readAsStringSync()),
  );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  /// Deixa o isolate do parse e o `rootBundle` rodarem em tempo real.
  Future<void> settleReal(WidgetTester tester, {int ms = 1500}) async {
    // Espera em tempo real até os carregamentos acabarem (máx. 20 s).
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (i * 100 >= ms &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> openRealBank(
    WidgetTester tester, {
    String path = '/questoes/acervo',
  }) async {
    await pumpIagoApp(
      tester,
      overrides: [bankCatalogProvider.overrideWithValue(realCatalog)],
    );
    await enterDemo(tester);
    containerOf(tester).read(routerProvider).go(path);
    await tester.pump();
    await settleReal(tester);
  }

  Future<void> typeReal(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('bank-search-field')), text);
    await tester.pump(const Duration(milliseconds: 400));
    await settleReal(tester, ms: 400);
  }

  test('o asset real tem a contagem esperada', () {
    expect(total, 1687);
  });

  testWidgets('CA-B1: abre com o asset real e mostra a contagem com contexto', (
    tester,
  ) async {
    await openRealBank(tester);
    expect(find.text(bankQuestions(total)), findsOneWidget);
    expect(
      find.text('Mostrando 40 de ${formatBankNumber(total)}'),
      findsNothing,
    ); // ainda no topo; o rodapé vem depois de rolar
    await reveal(tester, find.byKey(const Key('bank-load-more')));
    expect(
      find.text('Mostrando 40 de ${formatBankNumber(total)}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CA-B3: buscar "função" no acervo real não mexe em Minhas questões',
    (tester) async {
      await openRealBank(tester);
      await typeReal(tester, 'função');
      final c = containerOf(tester);
      expect(c.read(bankFilterProvider).query, 'função');
      expect(c.read(questionFilterProvider), const QuestionFilter());
      final mine = c.read(questionsProvider).value!;
      expect(mine, hasLength(40));
      // O roteiro do beta continua: função + Matemática + Objetiva = 9.
      final roteiro = const QuestionFilter(
        query: 'função',
        areas: {Area.mathematics},
        type: QuestionType.objective,
      ).apply(mine);
      expect(roteiro, hasLength(9));
      // O acervo achou algo, e o texto na tela é "N de 1.687 questões".
      expect(
        find.textContaining('de ${formatBankNumber(total)} questões'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CA-B4 e CA-B8 no asset real: salvar, repetir e editar a cópia', (
    tester,
  ) async {
    final first = (raw['questions'] as List).first as Map<String, Object?>;
    final bankId = first['id'] as String;
    await openRealBank(tester, path: '/questoes/acervo/$bankId');
    await reveal(tester, find.byKey(const Key('bank-save')));
    expect(find.textContaining('Gabarito'), findsNothing);
    expect(find.textContaining('Resposta correta'), findsNothing);

    await tapVisible(tester, find.byKey(const Key('bank-save')));
    final c = containerOf(tester);
    final saved = c
        .read(questionsProvider)
        .value!
        .where((q) => q.origin == QuestionOrigin.bank)
        .toList();
    expect(saved, hasLength(1));
    expect(saved.single.id, 'bank_$bankId');
    expect(saved.single.platform, startsWith('ENEM '));
    expect(find.byKey(const Key('bank-already-saved')), findsOneWidget);

    // Salvar de novo pelo domínio: não duplica e não regrava.
    final original = (await c.read(bankCatalogProvider).byIds([bankId])).single;
    final repo = c.read(questionRepositoryProvider);
    await repo.update(saved.single.copyWith(statement: 'Meu ajuste'));
    expect(await c.read(bankActionsProvider).save(original), isFalse);
    final after = c
        .read(questionsProvider)
        .value!
        .where((q) => q.id == 'bank_$bankId')
        .toList();
    expect(after, hasLength(1));
    expect(after.single.statement, 'Meu ajuste');
    // "Editada" (updatedAt > createdAt) é coberta em question_bank_copy_test:
    // aqui o relógio dos testes de app é fixo.
    // O acervo não mudou (CA-B8).
    final again = (await c.read(bankCatalogProvider).byIds([bankId])).single;
    expect(again.statement, original.statement);
    expect(again.statement, isNot('Meu ajuste'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CA-B5: montar lista com N reais (até 30) cria cópias e a lista',
    (tester) async {
      await openRealBank(tester);
      // Acha uma busca real com 2 a 30 resultados.
      final catalog = containerOf(tester).read(bankCatalogProvider);
      String? query;
      int? n;
      await tester.runAsync(() async {
        for (final term in [
          'logaritmo',
          'fotossíntese',
          'Revolução Industrial',
          'mitocôndria',
          'termodinâmica',
          'soneto',
          'hidrólise',
        ]) {
          final p = await catalog.search(QuestionFilter(query: term), limit: 1);
          if (p.total >= 2 && p.total <= maxBankListQuestions) {
            query = term;
            n = p.total;
            break;
          }
        }
      });
      expect(
        query,
        isNotNull,
        reason: 'nenhum termo de teste dá 2 a 30 questões',
      );

      await typeReal(tester, query!);
      expect(
        find.text('$n de ${formatBankNumber(total)} questões'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('bank-build-list')));
      await tester.enterText(
        find.byKey(const Key('list-name-field')),
        'Do acervo',
      );
      await tester.tap(find.byKey(const Key('list-name-confirm')));
      await settleReal(tester, ms: 400);

      final c = containerOf(tester);
      final list = c
          .read(listsProvider)
          .value!
          .firstWhere((l) => l.name == 'Do acervo');
      expect(list.questionIds, hasLength(n!));
      final bankCopies = c
          .read(questionsProvider)
          .value!
          .where((q) => q.origin == QuestionOrigin.bank);
      expect(bankCopies, hasLength(n!));
      expect(bankCopies.every((q) => q.platform.startsWith('ENEM ')), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CA-B5: com mais de 30 resultados reais o botão fica desligado', (
    tester,
  ) async {
    await openRealBank(tester);
    await typeReal(tester, 'a');
    await reveal(tester, find.byKey(const Key('bank-build-list')));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('bank-build-list')),
    );
    expect(button.onPressed, isNull); // sem filtro: 1.687
    expect(find.byKey(const Key('bank-list-limit-note')), findsOneWidget);
  });

  testWidgets('CA-B7: fontes e licenças reais, sem afirmar licença', (
    tester,
  ) async {
    await openRealBank(tester, path: '/questoes/acervo/fontes');
    expect(find.byKey(const Key('source-link-enem')), findsOneWidget);
    expect(find.textContaining('licenciad'), findsNothing);
    expect(find.textContaining('sem alteração'), findsNothing);
    await reveal(tester, find.byKey(const Key('sources-removal')));
    expect(find.textContaining('Pedir a remoção'), findsOneWidget);
  });

  testWidgets(
    'BUG: CA-B7 o e-mail de remoção é só um marcador',
    // pendente: e-mail do projeto (D6/P4), obrigatório antes da publicação.
    // (testWidgets só aceita bool em `skip`, não texto.)
    skip: true,
    (tester) async {
      await openRealBank(tester, path: '/questoes/acervo/fontes');
      await reveal(tester, find.byKey(const Key('sources-removal')));
      // CA-B7 exige "o e-mail para pedir remoção"; hoje é o marcador do código
      // (bankRemovalContact em bank_sources_page.dart:12), à espera da D6/P4.
      expect(
        find.textContaining('<e-mail do projeto>'),
        findsNothing,
        reason:
            'BUG: o e-mail de remoção ainda é o marcador "<e-mail do projeto>"',
      );
    },
  );

  test(
    'CA-B9: busca e facetas no asset real em menos de 100 ms (após carregar)',
    () async {
      final catalog = AssetBankCatalog(bundle: _FileBundle());
      final sw = Stopwatch()..start();
      await catalog.search(const QuestionFilter(), limit: 40);
      final firstLoad = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('primeira abertura (VM): $firstLoad ms');
      for (final f in [
        const QuestionFilter(query: 'função'),
        const QuestionFilter(query: 'função', areas: {Area.mathematics}),
        const QuestionFilter(query: 'a'),
        const QuestionFilter(areas: {Area.naturalSciences}),
      ]) {
        sw
          ..reset()
          ..start();
        await catalog.search(f, limit: 40);
        await catalog.facets(f);
        final ms = sw.elapsedMilliseconds;
        // ignore: avoid_print
        print('busca+facetas ${f.query}/${f.areas}: $ms ms');
        expect(ms, lessThan(100), reason: '$f');
      }
    },
  );
}

/// Lê o asset direto do disco (a VM de teste não precisa do bundle).
class _FileBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}
