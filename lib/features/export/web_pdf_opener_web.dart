// Só é compilado na web (importação condicional em web_pdf_opener.dart).
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Abre o PDF numa nova aba, no visualizador do próprio navegador (funciona
/// offline). Se o navegador bloquear a aba, baixa o arquivo. O endereço
/// temporário é descartado depois de 2 minutos: nada fica guardado.
bool openPdfInNewTab(Uint8List bytes, String filename) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final tab = web.window.open(url, '_blank');
  if (tab == null) {
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.append(link);
    link.click();
    link.remove();
  }
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
  return true;
}
