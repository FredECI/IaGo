/// Leitura do texto de questão colado pelo usuário.
///
/// O IaGo não faz scraping: o estudante cola o texto que já tem, e este
/// leitor só separa o enunciado das alternativas (A a E) para poupar tempo.
library;

/// Resultado da leitura: enunciado e alternativas encontradas.
class PastedQuestion {
  const PastedQuestion({required this.statement, this.alternatives = const []});

  final String statement;
  final List<String> alternatives;

  bool get hasAlternatives => alternatives.isNotEmpty;
}

/// Mínimo de itens em sequência para tratar o texto como objetiva. Evita
/// confundir os itens "a)" e "b)" de uma discursiva com alternativas.
const int minDetectedAlternatives = 4;

class _Marker {
  const _Marker(this.letter, this.start, this.contentStart);

  /// 0 para A, 1 para B, ...
  final int letter;
  final int start;
  final int contentStart;
}

/// "A)", "(A)", "a)", "A.", "A -", "A:" no começo da linha.
final RegExp _lineMarker = RegExp(
  r'^[ \t]*(?:\(([A-Ea-e])\)|([A-Ea-e])[ \t]*[).:\-–—])[ \t]*',
  multiLine: true,
);

/// "a) ..." ou "(a) ..." no meio da linha, depois de um espaço.
final RegExp _inlineMarker = RegExp(r'(?<=\s)\(?([A-Ea-e])\)[ \t]+');

/// Letra maiúscula solta no começo da linha ("A 10"), comum ao copiar provas
/// em PDF. "A" e "E" também começam frases; a exigência de sequência protege.
final RegExp _bareMarker = RegExp(
  r'^[ \t]*([A-E])(?:[ \t]+|$)',
  multiLine: true,
);

final RegExp _spaces = RegExp(r'\s+');

int _letterIndex(String letter) =>
    letter.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);

List<_Marker> _collect(String text, List<RegExp> patterns) {
  final byStart = <int, _Marker>{};
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(text)) {
      final letter = match.group(1) ?? match.group(2);
      if (letter == null) continue;
      byStart.putIfAbsent(
        match.start,
        () => _Marker(_letterIndex(letter), match.start, match.end),
      );
    }
  }
  return byStart.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

/// Maior sequência A, B, C... de marcadores consecutivos (em empate, a última).
List<_Marker> _bestSequence(List<_Marker> markers) {
  var best = <_Marker>[];
  for (var i = 0; i < markers.length; i++) {
    if (markers[i].letter != 0) continue;
    final sequence = <_Marker>[markers[i]];
    for (var j = i + 1; j < markers.length && sequence.length < 5; j++) {
      if (markers[j].letter != sequence.length) break;
      sequence.add(markers[j]);
    }
    if (sequence.length >= best.length) best = sequence;
  }
  return best;
}

/// "Questão 1", "QUESTÃO 01", "Questão 136 (ENEM 2023)", "Q.3".
final RegExp _keywordHeader = RegExp(
  r'^[ \t]*(?:'
  // "Questão 1", "Questão nº 1"
  r'[Qq][Uu][Ee][Ss][Tt][ÃãAa][Oo][ \t]*(?:[Nn]\.?[º°oO]\.?[ \t]*)?(\d{1,4})(?!\d)'
  // "Q.1"
  r'|[Qq]\.[ \t]*(\d{1,4})(?!\d)'
  // "Q1." / "Q1)" (sem separador, "Q2 é..." é texto de enunciado)
  r'|[Qq][ \t]*(\d{1,4})(?!\d)(?=[ \t]*[.:)\-–—])'
  r')[ \t]*[.:)\-–—]?[ \t]*',
  multiLine: true,
);

/// "Q1 texto", sem separador. Só vale em cadeia (Q1, Q2...), porque "Q2 é..."
/// também pode ser o começo de um enunciado.
final RegExp _bareQHeader = RegExp(
  r'^[ \t]*[Qq][ \t]*(\d{1,4})(?!\d)[ \t]+(?=\S)',
  multiLine: true,
);

/// "1.", "1)", "01 -" no começo da linha, seguido de texto.
final RegExp _numberHeader = RegExp(
  r'^[ \t]*(\d{1,3})[ \t]*[.)\-–—][ \t]+(?=\S)',
  multiLine: true,
);

/// Linhas de rodapé ou cabeçalho de prova que não fazem parte da questão.
/// Testadas uma linha por vez; linhas longas nunca são rodapé (evita custo
/// alto de regex em linhas gigantes).
final List<RegExp> _noiseLines = [
  RegExp(
    r'^[ \t]*(?:p[áa]gina|p[áa]g\.?)[ \t]*\d+([ \t]*(?:de|/)[ \t]*\d+)?[ \t]*$',
    caseSensitive: false,
  ),
  RegExp(r'^[ \t]*[-–—]+[ \t]*\d+[ \t]*[-–—]+[ \t]*$'),
  RegExp(
    r'caderno[ \t]*\d*[ \t]*[-–—|].*p[áa]gina[ \t]*\d+',
    caseSensitive: false,
  ),
  RegExp(r'^[ \t]*\*[A-Z0-9]{6,}\*[ \t]*$'),
];

const int _maxNoiseLineLength = 200;

String _stripNoise(String text) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.length > _maxNoiseLineLength) continue;
    if (_noiseLines.any((r) => r.hasMatch(line))) lines[i] = '';
  }
  return lines.join('\n');
}

class _Header {
  const _Header(this.number, this.start, this.contentStart);
  final int number;
  final int start;
  final int contentStart;
}

List<_Header> _headers(String text, RegExp pattern) => [
  for (final m in pattern.allMatches(text))
    _Header(
      int.parse((m.group(1) ?? m.group(2) ?? m.group(3))!),
      m.start,
      m.end,
    ),
];

/// Acima disso, a escolha da cadeia cai no comportamento simples e linear.
const int _maxChainCandidates = 300;

/// Maior cadeia de numeração 1, 2, 3... (ou n, n+1, ...) entre os candidatos.
///
/// Entre candidatos com o mesmo número, prefere o que vem depois de um bloco de
/// alternativas (a lista "1. 2." dentro de um enunciado não tem alternativas
/// antes do próximo item). Sem alternativas em lugar nenhum, fica o primeiro.
///
/// Cada trecho entre candidatos é lido uma vez só (soma de prefixos). Acima de
/// [_maxChainCandidates] candidatos, usa só a cadeia gulosa a partir do 1º.
List<_Header> _longestChain(String text, List<_Header> candidates) {
  final n = candidates.length;
  if (n == 0) return const [];

  // prefix[k] = quantos trechos antes de k (entre candidatos) têm alternativas.
  final prefix = List<int>.filled(n + 1, 0);
  if (n <= _maxChainCandidates) {
    for (var k = 0; k < n; k++) {
      final end = k + 1 < n ? candidates[k + 1].start : text.length;
      final hasAlt = parsePastedQuestion(
        text.substring(candidates[k].contentStart, end),
      ).hasAlternatives;
      prefix[k + 1] = prefix[k] + (hasAlt ? 1 : 0);
    }
  }

  List<int> chainFrom(int start, {required bool preferAlternatives}) {
    final chain = <int>[start];
    var from = start + 1;
    while (from < n) {
      final wanted = candidates[chain.last].number + 1;
      int? firstMatch;
      int? afterAlternatives;
      for (var j = from; j < n; j++) {
        if (candidates[j].number != wanted) continue;
        firstMatch ??= j;
        if (!preferAlternatives) break;
        if (prefix[j] - prefix[chain.last] > 0) {
          afterAlternatives = j;
          break;
        }
      }
      final pick = afterAlternatives ?? firstMatch;
      if (pick == null) break;
      chain.add(pick);
      from = pick + 1;
    }
    return chain;
  }

  if (n > _maxChainCandidates) {
    final chain = chainFrom(0, preferAlternatives: false);
    return [for (final i in chain) candidates[i]];
  }

  var best = <int>[];
  for (var i = 0; i < n; i++) {
    final chain = chainFrom(i, preferAlternatives: true);
    if (chain.length > best.length) best = chain;
  }
  return [for (final i in best) candidates[i]];
}

/// Separa um texto com várias questões em rascunhos, um por questão.
///
/// Reconhece "Questão 1" / "QUESTÃO 136" (numeração qualquer, crescente) e
/// "1." / "1)" (cadeia consecutiva, para não confundir listas dentro do
/// enunciado). O que vem antes da primeira questão (cabeçalho de prova) é
/// descartado, assim como linhas de rodapé. Sem numeração, devolve uma só.
/// Cada rascunho passa por [parsePastedQuestion].
List<PastedQuestion> splitPastedQuestions(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = _stripNoise(text);

  var headers = _headers(text, _keywordHeader);
  if (headers.length < 2) {
    var chain = _longestChain(text, _headers(text, _bareQHeader));
    if (chain.length < 2) {
      chain = _longestChain(text, _headers(text, _numberHeader));
    }
    if (chain.length >= 2) headers = chain;
  }

  if (headers.isEmpty) {
    final single = parsePastedQuestion(text);
    return single.statement.isEmpty && !single.hasAlternatives
        ? const []
        : [single];
  }

  final drafts = <PastedQuestion>[];
  for (var i = 0; i < headers.length; i++) {
    final end = i + 1 < headers.length ? headers[i + 1].start : text.length;
    final parsed = parsePastedQuestion(
      text.substring(headers[i].contentStart, end),
    );
    if (parsed.statement.isEmpty && !parsed.hasAlternatives) continue;
    drafts.add(parsed);
  }
  return drafts;
}

/// Separa enunciado e alternativas de um texto colado.
PastedQuestion parsePastedQuestion(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  var sequence = _bestSequence(_collect(text, [_lineMarker, _inlineMarker]));
  if (sequence.length < minDetectedAlternatives) {
    sequence = _bestSequence(_collect(text, [_bareMarker]));
  }
  if (sequence.length < minDetectedAlternatives) {
    return PastedQuestion(statement: text.trim());
  }

  final alternatives = <String>[
    for (var i = 0; i < sequence.length; i++)
      text
          .substring(
            sequence[i].contentStart,
            i + 1 < sequence.length ? sequence[i + 1].start : text.length,
          )
          .replaceAll(_spaces, ' ')
          .trim(),
  ];
  return PastedQuestion(
    statement: text.substring(0, sequence.first.start).trim(),
    alternatives: alternatives,
  );
}
