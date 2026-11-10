import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/pdf_page_count.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List _ascii(String s) => Uint8List.fromList(latin1.encode(s));

Future<Uint8List> _realPdf(int pages) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Text('p$i')));
  }
  return doc.save();
}

Uint8List _objStm(Uint8List packed) {
  final b = BytesBuilder()
    ..add(_ascii('<< /Type /ObjStm /Filter /FlateDecode >>\nstream\n'))
    ..add(packed)
    ..add(_ascii('\nendstream\n'));
  return b.toBytes();
}

Uint8List _pdfOf(List<Uint8List> parts) {
  final b = BytesBuilder()..add(_ascii('%PDF-1.5\n'));
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

void main() {
  test('PDF de verdade (gerado pelo pacote pdf): 1, 10 e 11 páginas', () async {
    expect(countPdfPages(await _realPdf(1)), 1);
    expect(countPdfPages(await _realPdf(10)), 10);
    expect(countPdfPages(await _realPdf(11)), 11);
  });

  test('objetos de página dentro de fluxo comprimido (ObjStm)', () {
    const inner =
        '<< /Type /Page /Parent 2 0 R >> '
        '<< /Type/Page /Parent 2 0 R >> '
        '<< /Type /Pages /Count 2 >>';
    final packed = const ZLibEncoder().encodeBytes(utf8.encode(inner));
    expect(countPdfPages(_pdfOf([_objStm(packed)])), 2);
  });

  test('"Pages" não conta como página', () {
    final b = _ascii(
      '%PDF-1.4\n<< /Type /Pages /Count 3 >>\n<< /Type /Page >>',
    );
    expect(countPdfPages(b), 1);
  });

  test(
    'não detectável: lixo, vazio, cifrado, sem páginas, ObjStm ilegível',
    () {
      expect(countPdfPages(_ascii('isto não é um pdf')), isNull);
      expect(countPdfPages(Uint8List(0)), isNull);
      expect(
        countPdfPages(_ascii('%PDF-1.4\n/Encrypt 9 0 R\n<< /Type /Page >>')),
        isNull,
      );
      expect(countPdfPages(_ascii('%PDF-1.4\n<< /Type /Catalog >>')), isNull);
      expect(
        countPdfPages(
          _ascii(
            '%PDF-1.5\n<< /Type /ObjStm >>\nstream\nnão é zlib\nendstream',
          ),
        ),
        isNull,
      );
    },
  );

  group('tetos', () {
    final onePage = const ZLibEncoder().encodeBytes(
      utf8.encode('<< /Type /Page >>'),
    );

    test('bomba: fluxo acima do teto por fluxo vira null', () {
      // 9 MB de zeros comprimem para poucos KB; o teto é 8 MB.
      final bomb = const ZLibEncoder().encodeBytes(Uint8List(9 * 1024 * 1024));
      expect(bomb.length, lessThan(100 * 1024));
      expect(countPdfPages(_pdfOf([_objStm(bomb)])), isNull);
    });

    test('bomba: soma dos fluxos acima do teto total vira null', () {
      // 7 MB cada (abaixo do teto por fluxo); 5 passam dos 32 MB.
      final big = const ZLibEncoder().encodeBytes(Uint8List(7 * 1024 * 1024));
      expect(
        countPdfPages(_pdfOf([for (var i = 0; i < 5; i++) _objStm(big)])),
        isNull,
      );
    });

    test('vários ObjStm legítimos somam as páginas', () {
      expect(
        countPdfPages(_pdfOf([for (var i = 0; i < 10; i++) _objStm(onePage)])),
        10,
      );
    });

    test('mais de 50 ObjStm vira null', () {
      expect(
        countPdfPages(_pdfOf([for (var i = 0; i < 51; i++) _objStm(onePage)])),
        isNull,
      );
    });

    test('dicionários repetidos dentro de um mesmo fluxo não custam nada', () {
      final junk = BytesBuilder()..add(_ascii('<< /Type /ObjStm >>\nstream\n'));
      for (var i = 0; i < 20000; i++) {
        junk.add(_ascii('/Type /ObjStm '));
      }
      junk.add(_ascii('\nendstream\n'));
      final watch = Stopwatch()..start();
      expect(countPdfPages(_pdfOf([junk.toBytes()])), isNull);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });
}
