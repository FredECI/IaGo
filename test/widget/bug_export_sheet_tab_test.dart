import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// QA (A4/A5, 08/11): a folha "Exportar PDF" fica presa à aba Listas. Trocar de
/// aba com ela aberta e voltar mostra a folha da lista antiga por cima de
/// qualquer outra lista (visto no build web, com a lista do acervo).
void main() {
  setUpAll(initTestLocale);

  testWidgets(
    'regressão: a folha de exportar PDF não deve sobreviver à troca de aba',
    (tester) async {
      await pumpIagoApp(tester);
      await enterDemo(tester);
      final nav = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: nav, matching: find.text('Listas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-pdf')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdf-ready')), findsOneWidget);

      await tester.tap(find.descendant(of: nav, matching: find.text('Painel')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: nav, matching: find.text('Listas')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pdf-ready')),
        findsNothing,
        reason:
            'regressão: a folha de exportação da lista anterior continua aberta '
            'ao voltar à aba Listas (export_sheet.dart:16, showModalBottomSheet '
            'sem useRootNavigator)',
      );
    },
  );
}
