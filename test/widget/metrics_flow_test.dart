import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> exportList(WidgetTester tester, String name) async {
  await tester.tap(find.text('Listas').last);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text(name));
  await tapVisible(tester, find.byKey(const Key('export-pdf')));
  await tester.tap(find.byKey(const Key('pdf-open')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('demo: Métricas do piloto com H1–H4 e "dados simulados"', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tester.tap(find.text('Conta').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('open-metrics')));
    expect(find.byKey(const Key('simulated-banner')), findsOneWidget);
    expect(find.textContaining('DADOS SIMULADOS'), findsOneWidget);
    for (final code in ['H1', 'H2', 'H3', 'H4']) {
      await reveal(tester, find.byKey(Key('hypothesis-$code')));
    }
    expect(find.text('Abaixo da meta'), findsWidgets);
    expect(find.text('Meta atingida'), findsWidgets);
  });

  testWidgets('a pesquisa de satisfação aparece só depois da 3ª exportação', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);

    // A seed já tem 1 exportação; a 2ª ainda não pergunta nada.
    await exportList(tester, 'Aula de reforço — Matemática básica');
    expect(find.text('Uma pergunta rápida'), findsNothing);
    // Fecha a folha; tocar de novo na aba Listas volta para a lista de listas.
    await tester.tapAt(const Offset(180, 60));
    await tester.pumpAndSettle();

    // A 3ª abre a pesquisa (0 a 10).
    await exportList(tester, 'Revisão — Ciências da Natureza');
    expect(find.text('Uma pergunta rápida'), findsOneWidget);
    await tester.tap(find.byKey(const Key('score-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('survey-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('Obrigado! Isso ajuda a melhorar o IaGo.'),
      findsOneWidget,
    );
  });
}
