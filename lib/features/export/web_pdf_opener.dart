/// Abertura do PDF no navegador: implementação real só na web.
library;

export 'web_pdf_opener_stub.dart'
    if (dart.library.js_interop) 'web_pdf_opener_web.dart';
