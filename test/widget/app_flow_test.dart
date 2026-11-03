import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('entra como Pedro em 1 toque e navega pelas abas', (
    tester,
  ) async {
    await pumpIagoApp(tester);

    // Tela inicial com selo Beta.
    expect(find.text('Beta 0.1'), findsOneWidget);
    await enterDemo(tester);

    // Painel: saudação, resumo relativo, atalhos e o roteiro "Em breve".
    expect(find.text('Olá, Pedro'), findsOneWidget);
    expect(find.byKey(const Key('saved-this-week')), findsOneWidget);
    expect(find.text('3 a mais que nos 7 dias anteriores'), findsOneWidget);
    await reveal(tester, find.text('Em breve: Conecta'));
    expect(find.text('Salvar questão'), findsOneWidget);
    expect(find.text('Em breve: Direciona'), findsOneWidget);
    expect(find.text('Em breve: Conecta'), findsOneWidget);

    // Questões: as 40 de exemplo.
    await tester.tap(find.text('Questões').last);
    await tester.pumpAndSettle();
    expect(find.text('40 questões'), findsOneWidget);

    // Listas: as 2 prontas.
    await tester.tap(find.text('Listas').last);
    await tester.pumpAndSettle();
    expect(find.text('Revisão — Ciências da Natureza'), findsOneWidget);
    expect(find.text('Aula de reforço — Matemática básica'), findsOneWidget);

    // Conta: sair volta para a tela inicial.
    await tester.tap(find.text('Conta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enter-demo')), findsOneWidget);
  });

  testWidgets('tema escuro pode ser escolhido na conta', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tester.tap(find.text('Conta').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Aparência'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
