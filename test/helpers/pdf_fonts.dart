import 'dart:io';
import 'dart:typed_data';

import 'package:iago/features/export/list_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Fontes do PDF lidas direto do disco (fora do relógio falso dos testes).
PdfFonts loadTestPdfFonts() {
  pw.Font font(String file) => pw.Font.ttf(
    ByteData.view(File('assets/fonts/$file').readAsBytesSync().buffer),
  );
  return PdfFonts(
    regular: font('Inter-Regular.ttf'),
    bold: font('Inter-Bold.ttf'),
  );
}
