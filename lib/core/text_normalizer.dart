/// Normalização de texto para busca e para comparar tags livres.
///
/// - minúsculas e sem acentos ("Função" → "funcao");
/// - plural em "-ões" vira "-ão" ("funções" → "funcao"), para que a busca por
///   "função" encontre também o assunto "Funções".
library;

const Map<String, String> _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
};

/// Diacríticos combinantes (texto colado de PDF costuma vir decomposto).
final RegExp _combiningMarks = RegExp('[̀-ͯ]');
final RegExp _nonWord = RegExp('[^a-z0-9]+');

/// Passa para minúsculas e remove acentos, preservando os demais caracteres.
String foldAccents(String input) {
  final lower = input.toLowerCase().replaceAll(_combiningMarks, '');
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

String _stem(String word) {
  if (word.length > 4 && word.endsWith('oes')) {
    return '${word.substring(0, word.length - 3)}ao';
  }
  return word;
}

/// Quebra o texto em termos de busca normalizados.
List<String> searchTerms(String input) =>
    foldAccents(input)
        .split(_nonWord)
        .where((w) => w.isNotEmpty)
        .map(_stem)
        .toList();

/// Texto indexável: termos normalizados separados por espaço.
String buildSearchText(Iterable<String> parts) =>
    searchTerms(parts.join(' ')).join(' ');

/// Chave para comparar tags livres (assunto, plataforma) sem ligar para
/// maiúsculas, acentos ou espaços extras.
String tagKey(String tag) => searchTerms(tag).join(' ');
