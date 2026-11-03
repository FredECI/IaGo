import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/bootstrap.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/features/export/pdf_exporter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'pdf_fonts.dart';

/// "Agora" fixo dos testes: sexta da apresentação, 14h.
final DateTime testNow = DateTime(2026, 11, 6, 14);

Future<void> initTestLocale() async {
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';
}

/// Exportador falso: registra o que seria aberto ou compartilhado.
class FakePdfExporter implements PdfExporter {
  final List<String> calls = [];
  int lastBytes = 0;

  @override
  String get openLabel => 'Abrir PDF';

  @override
  String get shareLabel => 'Baixar PDF';

  @override
  Future<bool> open(Uint8List bytes, String filename) async {
    calls.add('abrir:$filename');
    lastBytes = bytes.length;
    return true;
  }

  @override
  Future<bool> share(Uint8List bytes, String filename) async {
    calls.add('baixar:$filename');
    lastBytes = bytes.length;
    return true;
  }
}

/// Monta o app inteiro numa tela de celular barato (360 x 780 dp).
Future<void> pumpIagoApp(
  WidgetTester tester, {
  FakePdfExporter? exporter,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final fonts = loadTestPdfFonts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => testNow),
        sharedPreferencesProvider.overrideWithValue(null),
        pdfFontsProvider.overrideWith((ref) async => fonts),
        pdfExporterProvider.overrideWithValue(exporter ?? FakePdfExporter()),
        ...overrides,
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

/// Rola a tela atual até o widget existir e ficar visível (listas preguiçosas
/// e a fonte larga dos testes empurram itens para baixo).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Rola até o widget e toca nele.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
