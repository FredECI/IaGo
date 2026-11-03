import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'list_pdf.dart';
import 'web_pdf_opener.dart';

/// Entrega do PDF já gerado. Trocável nos testes.
abstract interface class PdfExporter {
  String get openLabel;
  String get shareLabel;

  /// Web: abre numa nova aba. Android: tela de visualização/impressão.
  Future<bool> open(Uint8List bytes, String filename);

  /// Web: baixa o arquivo. Android: menu de compartilhar (WhatsApp, Drive...).
  Future<bool> share(Uint8List bytes, String filename);
}

/// Implementação real. Na web não usa `Printing.info()` nem a pré-visualização,
/// que buscariam o pdf.js num CDN (quebra offline).
class PlatformPdfExporter implements PdfExporter {
  const PlatformPdfExporter();

  @override
  String get openLabel => kIsWeb ? 'Abrir PDF' : 'Visualizar ou imprimir';

  @override
  String get shareLabel => kIsWeb ? 'Baixar PDF' : 'Compartilhar';

  @override
  Future<bool> open(Uint8List bytes, String filename) async {
    if (kIsWeb) return openPdfInNewTab(bytes, filename);
    return Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
  }

  @override
  Future<bool> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}

final pdfExporterProvider = Provider<PdfExporter>(
  (ref) => const PlatformPdfExporter(),
);

/// Fontes do PDF, carregadas uma vez.
final pdfFontsProvider = FutureProvider<PdfFonts>((ref) => PdfFonts.load());
