/// Número com ponto de milhar: 1687 vira "1.687".
String formatBankNumber(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// "1 questão" / "1.687 questões".
String bankQuestions(int n) =>
    '${formatBankNumber(n)} ${n == 1 ? 'questão' : 'questões'}';

/// "Fácil", "Média" ou "Difícil" para a faixa 1, 2 ou 3 (`null` fora delas).
String? difficultyLabel(int? band) => switch (band) {
  1 => 'Fácil',
  2 => 'Média',
  3 => 'Difícil',
  _ => null,
};

/// Dificuldade sempre comparada, nunca solta: a faixa é por tercil dentro da
/// área, então a frase diz com quem a questão é comparada.
String relativeDifficulty(int band, String areaLabel) => switch (band) {
  1 => 'entre as mais fáceis de $areaLabel no acervo',
  3 => 'entre as mais difíceis de $areaLabel no acervo',
  _ => 'no meio do caminho entre as de $areaLabel no acervo',
};
