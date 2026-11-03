import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/bootstrap.dart';
import 'package:iago/core/clock.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// "Agora" fixo dos testes: sexta da apresentação, 14h.
final DateTime testNow = DateTime(2026, 11, 6, 14);

Future<void> initTestLocale() async {
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';
}

/// Monta o app inteiro numa tela de celular barato (360 x 780 dp).
Future<void> pumpIagoApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => testNow),
        sharedPreferencesProvider.overrideWithValue(null),
      ],
      child: const IagoApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Entra no modo demonstração a partir da tela inicial.
Future<void> enterDemo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('enter-demo')));
  await tester.pumpAndSettle();
}
