/// Conta as páginas de um PDF sem renderizá-lo (CA-I13, CA-R7).
///
/// Procura os objetos `/Type /Page` no texto do arquivo e, nos PDFs que
/// guardam objetos comprimidos (`/Type /ObjStm`, comum desde o PDF 1.5), nos
/// fluxos descomprimidos. Devolve `null` se não conseguir contar com
/// segurança (arquivo cifrado, fluxo ilegível, nenhuma página achada): a
/// importação trata isso como "10 páginas não detectáveis" e recusa antes de
/// enviar. A contagem pode errar para mais (atualizações incrementais deixam
/// páginas antigas no arquivo); para menos só com PDF hostil (veja abaixo).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

final RegExp _pageObject = RegExp(r'/Type\s*/Page(?![A-Za-z])');
final RegExp _objStm = RegExp(r'/Type\s*/ObjStm');

/// Tetos contra "bombas" de compressão e custo quadrático. Estourar qualquer
/// um devolve `null` (o arquivo é recusado). A descompressão aborta assim que
/// passa do teto, sem alocar o resto.
const int _maxInflatedPerStream = 8 * 1024 * 1024;
const int _maxInflatedTotal = 32 * 1024 * 1024;
const int _maxObjectStreams = 50;

/// Limites desta contagem, que roda no isolate da interface: com os tetos
/// acima o pior caso fica em dezenas de milissegundos, por isso sem `compute`.
///
/// Limitações conhecidas: `/Encrypt` dentro de fluxo não é visto (só o
/// dicionário em texto); e um PDF hostil pode escrever `/Type /Pag#65` (nome
/// com `#`) e esconder páginas, ou seja, a contagem pode errar para MENOS.
/// Isso só poupa custo de IA do próprio usuário, e quem protege a cota é o
/// limite diário e o App Check, então não tratamos.
int? countPdfPages(Uint8List bytes) {
  try {
    final text = latin1.decode(bytes);
    if (!text.startsWith('%PDF-', _leadingJunk(text))) return null;
    // Cifrado: os fluxos não podem ser lidos, então a contagem não vale.
    if (text.contains('/Encrypt')) return null;

    var pages = _pageObject.allMatches(text).length;
    var cursor = 0;
    var streams = 0;
    var inflatedTotal = 0;
    for (final m in _objStm.allMatches(text)) {
      // Dicionário repetido dentro do fluxo já lido (ou lixo): não conta de
      // novo nem refaz a busca.
      if (m.start < cursor) continue;
      if (++streams > _maxObjectStreams) return null;
      final range = _streamAfter(bytes, text, m.end);
      if (range == null) return null;
      cursor = range.end;
      final data = Uint8List.sublistView(bytes, range.begin, range.end);
      final inflated = const ZLibDecoder().decodeBytes(
        data,
        maxOutputSize: _maxInflatedPerStream,
      );
      inflatedTotal += inflated.length;
      if (inflatedTotal > _maxInflatedTotal) return null;
      pages += _pageObject.allMatches(latin1.decode(inflated)).length;
    }
    return pages == 0 ? null : pages;
  } catch (_) {
    // Inclui ArchiveLimitException (teto estourado) e fluxo ilegível.
    return null;
  }
}

/// Alguns geradores põem lixo antes de `%PDF-` (o leitor aceita até 1024).
int _leadingJunk(String text) {
  final i = text.indexOf('%PDF-');
  return i < 0 || i > 1024 ? 0 : i;
}

/// Onde o fluxo cujo dicionário termina em [from] começa e termina: de depois
/// da palavra `stream` (e da quebra de linha) até `endstream`.
({int begin, int end})? _streamAfter(Uint8List bytes, String text, int from) {
  final start = text.indexOf('stream', from);
  if (start < 0) return null;
  var begin = start + 'stream'.length;
  if (begin < bytes.length && bytes[begin] == 0x0D) begin++;
  if (begin < bytes.length && bytes[begin] == 0x0A) begin++;
  final end = text.indexOf('endstream', begin);
  if (end < 0) return null;
  return (begin: begin, end: end);
}
