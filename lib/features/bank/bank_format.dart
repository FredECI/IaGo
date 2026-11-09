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
