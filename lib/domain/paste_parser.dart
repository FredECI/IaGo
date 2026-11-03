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
