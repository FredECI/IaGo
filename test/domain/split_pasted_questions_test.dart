import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/paste_parser.dart';

String _alts(String style) => switch (style) {
  'line' => 'A) um\nB) dois\nC) três\nD) quatro\nE) cinco',
  'paren' => '(A) um\n(B) dois\n(C) três\n(D) quatro\n(E) cinco',
  'dot' => 'a. um\nb. dois\nc. três\nd. quatro\ne. cinco',
  _ => throw ArgumentError(style),
};

void main() {
  void expectFive(List<PastedQuestion> r) {
    expect(r, hasLength(5));
    for (final q in r) {
      expect(q.alternatives, ['um', 'dois', 'três', 'quatro', 'cinco']);
      expect(q.statement, isNotEmpty);
    }
  }

  test('formato 1: "1." com alternativas "A)" em linhas (CA-I1)', () {
    final text = [
      for (var i = 1; i <= 5; i++) '$i. Enunciado $i\n${_alts('line')}',
    ].join('\n\n');
    final r = splitPastedQuestions(text);
    expectFive(r);
    expect(r[2].statement, 'Enunciado 3');
  });

  test('formato 2: "1)"', () {
    expectFive(
      splitPastedQuestions(
        [for (var i = 1; i <= 5; i++) '$i) Enunciado $i\n${_alts('line')}']
            .join('\n'),
      ),
    );
  });

  test('formato 3: "Questão 1"', () {
    expectFive(
      splitPastedQuestions(
        [
          for (var i = 1; i <= 5; i++)
            'Questão $i\nEnunciado $i\n${_alts('line')}',
        ].join('\n\n'),
      ),
    );
  });

  test('formato 4: "QUESTÃO 01" em maiúsculas e com zero', () {
    final r = splitPastedQuestions(
      [
        for (var i = 1; i <= 5; i++)
          'QUESTÃO 0$i\nEnunciado $i\n${_alts('paren')}',
      ].join('\n\n'),
    );
    expectFive(r);
    expect(r.first.statement, 'Enunciado 1');
  });

  test('formato 5: numeração do ENEM, "QUESTÃO 136" em diante', () {
    final r = splitPastedQuestions(
      [
        for (var i = 136; i < 141; i++)
          'QUESTÃO $i\nTexto base $i. Qual é a resposta?\n${_alts('line')}',
      ].join('\n\n'),
    );
    expectFive(r);
    expect(r.first.statement, startsWith('Texto base 136'));
  });

  test('formato 6: cabeçalho com texto na mesma linha ("Questão 7 - ...")', () {
    final r = splitPastedQuestions(
      'Questão 7 - Quanto vale 2 + 2?\nA) 1\nB) 2\nC) 3\nD) 4\n'
      'Questão 8 - Quanto vale 3 + 3?\nA) 3\nB) 4\nC) 5\nD) 6',
    );
    expect(r, hasLength(2));
    expect(r[0].statement, 'Quanto vale 2 + 2?');
    expect(r[1].alternatives.last, '6');
  });

  test('formato 7: alternativas todas na mesma linha', () {
    final r = splitPastedQuestions(
      '1. Qual o valor de 2x se x = 3?\nA) 3 B) 6 C) 9 D) 12 E) 15\n'
      '2. Qual o valor de 3x se x = 3?\nA) 3 B) 6 C) 9 D) 12 E) 15',
    );
    expect(r, hasLength(2));
    expect(r[0].alternatives, ['3', '6', '9', '12', '15']);
    expect(r[1].statement, 'Qual o valor de 3x se x = 3?');
  });

  test('formato 8: discursiva com itens a) e b) não vira objetiva', () {
    final r = splitPastedQuestions(
      '1. Considere a função f(x) = 2x.\na) Calcule f(3).\nb) Esboce o gráfico.\n'
      '2. Explique a Revolução Francesa.\n'
      '3. Resolva:\na) x + 1 = 2\nb) x + 2 = 3',
    );
    expect(r, hasLength(3));
    expect(r.every((q) => !q.hasAlternatives), isTrue);
    expect(r[0].statement, contains('b) Esboce o gráfico.'));
  });

  test('formato 9: cabeçalho de prova e rodapé de página são descartados', () {
    final r = splitPastedQuestions(
      'UNIVERSIDADE EXEMPLO - VESTIBULAR 2026\n'
      'Leia com atenção as instruções.\n\n'
      '1. Qual é a capital do Brasil?\nA) Rio\nB) Brasília\nC) São Paulo\nD) Salvador\n'
      'Página 1 de 2\n\n'
      '2. Quem escreveu Dom Casmurro?\nA) Alencar\nB) Machado\nC) Assis\nD) Lima\n'
      'Página 2 de 2',
    );
    expect(r, hasLength(2));
    expect(r[0].statement, 'Qual é a capital do Brasil?');
    expect(r[0].alternatives.last, 'Salvador');
    expect(r[1].alternatives.last, 'Lima');
  });

  test('formato 10: rodapé de caderno do ENEM no meio do texto', () {
    final r = splitPastedQuestions(
      'QUESTÃO 91\nEnunciado A\nA) a1\nB) b1\nC) c1\nD) d1\nE) e1\n'
      'CN - 1º dia | Caderno 1 - AZUL - Página 5\n'
      'QUESTÃO 92\nEnunciado B\nA) a2\nB) b2\nC) c2\nD) d2\nE) e2\n'
      '*010175AZ2*',
    );
    expect(r, hasLength(2));
    expect(r[0].alternatives.last, 'e1');
    expect(r[1].alternatives.last, 'e2');
  });

  test('formato 11: quebras de linha do Windows', () {
    final r = splitPastedQuestions(
      '1. Primeira?\r\nA) a\r\nB) b\r\nC) c\r\nD) d\r\n\r\n'
      '2. Segunda?\r\nA) a\r\nB) b\r\nC) c\r\nD) d',
    );
    expect(r, hasLength(2));
    expect(r[1].statement, 'Segunda?');
  });

  test('formato 12: misto de objetiva e discursiva', () {
    final r = splitPastedQuestions(
      'Questão 1\nObjetiva?\nA) a\nB) b\nC) c\nD) d\nE) e\n'
      'Questão 2\nExplique o ciclo da água.',
    );
    expect(r, hasLength(2));
    expect(r[0].hasAlternatives, isTrue);
    expect(r[1].hasAlternatives, isFalse);
  });

  test('formato 13: "01 -" e "Q.2"', () {
    final r = splitPastedQuestions(
      '01 - Primeira pergunta?\nA) a\nB) b\nC) c\nD) d\n'
      '02 - Segunda pergunta?\nA) a\nB) b\nC) c\nD) d',
    );
    expect(r, hasLength(2));
    final q = splitPastedQuestions('Q.1 Alfa?\nQ.2 Beta?');
    expect(q.map((e) => e.statement), ['Alfa?', 'Beta?']);
  });

  test('lista numerada dentro do enunciado não parte a questão', () {
    final r = splitPastedQuestions(
      'Questão 1\nAnalise:\nI. afirmação\nII. outra\nA) a\nB) b\nC) c\nD) d\n'
      'Questão 2\nOutra?',
    );
    expect(r, hasLength(2));
  });

  test('sem numeração devolve uma só; vazio devolve nenhuma', () {
    final one = splitPastedQuestions('Pergunta?\nA) a\nB) b\nC) c\nD) d');
    expect(one, hasLength(1));
    expect(one.single.alternatives, hasLength(4));
    expect(splitPastedQuestions('   \n  '), isEmpty);
  });

  group('desempenho e robustez (ciclo 2)', () {
    String numbered(int lines) =>
        [for (var i = 0; i < lines; i++) '${i % 30 + 1}. item $i'].join('\n');

    test('250 linhas numeradas (dentro do teto de candidatos) são rápidas', () {
      final sw = Stopwatch()..start();
      splitPastedQuestions(numbered(250));
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('400 linhas numeradas (acima do teto) terminam com folga', () {
      final text = numbered(400);
      expect(text.length, greaterThan(4000));
      final sw = Stopwatch()..start();
      final r = splitPastedQuestions(text);
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(r, isNotEmpty);
    });

    test('linha única de 50 KB com "caderno" repetido termina rápido', () {
      final sw = Stopwatch()..start();
      final r = splitPastedQuestions('${'caderno ' * 8000}\nQuestão 1\nX?');
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(r, hasLength(1));
    });

    test('"Q2 é..." no começo de um enunciado não é cabeçalho', () {
      final r = splitPastedQuestions(
        'Questão 1\nQ2 é uma sigla comum?\nA) a\nB) b\nC) c\nD) d\n'
        'Questão 2\nOutra?',
      );
      expect(r, hasLength(2));
      expect(r[0].statement, 'Q2 é uma sigla comum?');
    });
  });
}
