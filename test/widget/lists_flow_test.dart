import 'package:flutter_test/flutter_test.dart';
import 'package:iago/features/questions/question_card.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> tapKey(WidgetTester tester, String key) =>
    tapVisible(tester, find.byKey(Key(key)));

Future<void> nameList(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('list-name-field')), name);
  await tester.tap(find.byKey(const Key('list-name-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('roteiro: filtro → montar lista → exportar e abrir o PDF', (
    tester,
  ) async {
    final exporter = FakePdfExporter();
    await pumpIagoApp(tester, exporter: exporter);
    await enterDemo(tester);
    await tester.tap(find.text('Questões').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('search-field')), 'função');
    await tester.pumpAndSettle();
    await tapKey(tester, 'filter-area-mathematics');
    await tapKey(tester, 'filter-type-objective');
    expect(find.text('Montar lista com estas 9 questões'), findsOneWidget);

    await tapKey(tester, 'build-list-from-filter');
    expect(find.text('Nova lista com 9 questões'), findsOneWidget);
    await nameList(tester, 'Reforço — Funções');

    // Editor da lista.
    expect(find.text('Reforço — Funções'), findsOneWidget);
    expect(find.text('9 questões · todas objetivas'), findsOneWidget);
    expect(find.text('Ainda não exportada'), findsOneWidget);

    await tapKey(tester, 'export-pdf');
    expect(find.byKey(const Key('pdf-ready')), findsOneWidget);
    await tapKey(tester, 'pdf-open');
    expect(exporter.calls, ['abrir:Reforço - Funções.pdf']);
    expect(exporter.lastBytes, greaterThan(1000));

    // A exportação foi contada (o PDF em si não fica guardado).
    await tester.tapAt(const Offset(180, 60));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exportada 1 vez'), findsOneWidget);
  });

  testWidgets('montar lista selecionando questões e editar', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);

    // Atalho do painel entra direto no modo seleção.
    await tapKey(tester, 'shortcut-build-list');
    expect(find.text('0 selecionadas'), findsOneWidget);
    final cards = find.byType(QuestionCard);
    for (var i = 0; i < 2; i++) {
      // A 360 px os filtros ocupam o topo: rola até o cartão antes de tocar.
      await tester.scrollUntilVisible(
        cards.at(i),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(cards.at(i));
      await tester.pumpAndSettle();
    }
    expect(find.text('2 selecionadas'), findsOneWidget);

    await tapKey(tester, 'create-list-from-selection');
    await nameList(tester, 'Revisão rápida');
    expect(find.text('2 questões · todas objetivas'), findsOneWidget);

    // Tirar uma questão da lista.
    await tester.tap(find.byTooltip('Tirar da lista').first);
    await tester.pumpAndSettle();
    expect(find.text('1 questão · todas objetivas'), findsOneWidget);

    // Renomear.
    await tapKey(tester, 'rename-list');
    await nameList(tester, 'Revisão de sexta');
    expect(find.text('Revisão de sexta'), findsOneWidget);
  });

  testWidgets('lista pronta da seed abre no editor', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tester.tap(find.text('Listas').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisão — Ciências da Natureza'));
    await tester.pumpAndSettle();
    expect(
      find.text('8 questões · 5 objetivas e 3 discursivas'),
      findsOneWidget,
    );
    expect(find.textContaining('Exportada 1 vez'), findsOneWidget);
  });
}
