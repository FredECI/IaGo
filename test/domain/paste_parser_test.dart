import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/paste_parser.dart';

void main() {
  test('separa alternativas "A)" a "E)" em linhas próprias', () {
    final result = parsePastedQuestion(
      'Considere a função f(x) = 3x - 4. O valor de f(5) é:\n'
      'A) 5\nB) 7\nC) 9\nD) 11\nE) 13',
    );
    expect(
      result.statement,
      'Considere a função f(x) = 3x - 4. O valor de f(5) é:',
    );
    expect(result.alternatives, ['5', '7', '9', '11', '13']);
  });

  test('aceita "(a)", "a." e "a -" e quebras de linha do Windows', () {
    expect(
      parsePastedQuestion(
        'Pergunta?\r\n(a) um\r\n(b) dois\r\n(c) três\r\n(d) quatro',
      ).alternatives,
      ['um', 'dois', 'três', 'quatro'],
    );
    expect(
      parsePastedQuestion(
        'Pergunta?\nA. um\nB. dois\nC. três\nD. quatro\nE. cinco',
      ).alternatives,
      hasLength(5),
    );
    expect(
      parsePastedQuestion('Pergunta?\nA - um\nB - dois\nC - três\nD - quatro')
          .alternatives,
      ['um', 'dois', 'três', 'quatro'],
    );
  });

  test('separa alternativas na mesma linha', () {
    final result = parsePastedQuestion(
      'Quanto é 2 + 2? a) 1 b) 2 c) 3 d) 4 e) 5',
    );
    expect(result.statement, 'Quanto é 2 + 2?');
    expect(result.alternatives, ['1', '2', '3', '4', '5']);
  });

  test('junta alternativas que ocupam várias linhas', () {
    final result = parsePastedQuestion(
      'Enunciado\nA) primeira parte\ncontinua aqui\nB) b\nC) c\nD) d',
    );
    expect(result.alternatives.first, 'primeira parte continua aqui');
  });

  test('entende letras soltas de prova em PDF, sem confundir o artigo "A"', () {
    final result = parsePastedQuestion(
      'A população de uma cidade dobra a cada década.\n'
      'Em 30 anos, ela será multiplicada por:\n'
      'A 2\nB 4\nC 6\nD 8\nE 16',
    );
    expect(result.statement, startsWith('A população'));
    expect(result.alternatives, ['2', '4', '6', '8', '16']);
  });

  test('não trata itens a) e b) de discursiva como alternativas', () {
    const text =
        'Uma bola é lançada.\na) Calcule a altura máxima.\nb) Explique.';
    final result = parsePastedQuestion(text);
    expect(result.hasAlternatives, isFalse);
    expect(result.statement, text);
  });

  test('texto sem alternativas vira só enunciado', () {
    final result = parsePastedQuestion('  Explique a fotossíntese.  ');
    expect(result.statement, 'Explique a fotossíntese.');
    expect(result.alternatives, isEmpty);
  });
}
