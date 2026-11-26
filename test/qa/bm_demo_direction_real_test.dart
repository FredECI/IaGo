import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/features/direction/direction_pages.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Demo do Direciona com o acervo real (CA-BM19, spec 4.8): as etapas
/// simuladas ganham a sugestão.
void main() {
  testWidgets('demo mostra "Montar lista com N do acervo" no Direciona', (
    tester,
  ) async {
    await initTestLocale();
    await pumpIagoApp(tester);
    await enterDemo(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go(Routes.direction);
    await tester.pumpAndSettle();
    expect(find.byType(DirectionPage), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('do acervo'), findsWidgets);
  });
}
