import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/features/direction/direction_pages.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// BUG: na demo (CA-BM19, spec 4.8), as etapas simuladas deveriam ganhar a
/// sugestão do acervo. `DirectionDemoData` usa `planDirection`, que grava
/// `bankAvailableAtProposal = 0` (não nulo); `attachBankToPendingSteps` só
/// processa etapas com `null` (direction_providers.dart:266) e nunca anexa.
/// Passa quando o bug for corrigido.
void main() {
  testWidgets('BUG: demo mostra "Montar lista com N do acervo" no Direciona', (
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
