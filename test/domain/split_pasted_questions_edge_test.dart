import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/paste_parser.dart';

const _alts = 'A) a\nB) b\nC) c\nD) d';

void main() {
  group('splitPastedQuestions: casos-limite (CA-I1)', () {
    test('cadeia de apenas 2 já separa', () {
      final r = splitPastedQuestions('1. Um?\n$_alts\n2. Dois?\n$_alts');
      expect(r.map((q) => q.statement), ['Um?', 'Dois?']);
      expect(r.every((q) => q.alternatives.length == 4), isTrue);
    });

    test('um único "1." não parte nada e fica no enunciado', () {
      final r = splitPastedQuestions('1. Pergunta?\n$_alts');
      expect(r, hasLength(1));
      expect(r.single.alternatives, hasLength(4));
    });

    test('numeração que salta não perde texto', () {
      final r = splitPastedQuestions(
        '1. Um?\n$_alts\n2. Dois?\n$_alts\n4. Quatro?\n$_alts\n5. Cinco?\n$_alts',
      );
      final all = r.map((q) => '${q.statement} ${q.alternatives.join(' ')}');
      final joined = all.join(' ');
      for (final word in ['Um?', 'Dois?', 'Quatro?', 'Cinco?']) {
        expect(joined, contains(word));
      }
    });

    test('cabeçalho sem acento e em minúsculas', () {
      final r = splitPastedQuestions(
        'questão 1\nX?\n$_alts\nQUESTAO 2\nY?\n$_alts\nQuestao 3\nZ?\n$_alts',
      );
      expect(r.map((q) => q.statement), ['X?', 'Y?', 'Z?']);
    });

    test('"Q1" e "Q2" sem ponto', () {
      final r = splitPastedQuestions('Q1 Alfa?\n$_alts\nQ2 Beta?\n$_alts');
      expect(r.map((q) => q.statement), ['Alfa?', 'Beta?']);
    });

    test('só o cabeçalho, sem conteúdo, devolve lista vazia', () {
      expect(splitPastedQuestions('Questão 1'), isEmpty);
      expect(splitPastedQuestions('Questão 1\n\nQuestão 2\n  '), isEmpty);
    });

    test('cabeçalho vazio no meio é descartado, sem quebrar as vizinhas', () {
      final r = splitPastedQuestions('Questão 1\nA?\nQuestão 2\nQuestão 3\nB?');
      expect(r.map((q) => q.statement), ['A?', 'B?']);
    });

    test('rodapés em todas as formas somem e não entram na alternativa', () {
      final r = splitPastedQuestions(
        'Questão 1\nX?\nA) a\nB) b\nC) c\nD) d\n'
        'Página 3\n- 3 -\n  PÁG. 4/9  \nPágina 2 de 10\n'
        'CN - 2º dia | Caderno 7 - AMARELO - Página 12\n*010175AZ2*\n'
        'Questão 2\nY?\nA) a\nB) b\nC) c\nD) d',
      );
      expect(r, hasLength(2));
      expect(r[0].alternatives.last, 'd');
      expect(r[0].statement, 'X?');
    });

    test('rodapé com CRLF', () {
      final r = splitPastedQuestions(
        'Questão 1\r\nX?\r\n$_alts\r\nPágina 1 de 2\r\n'
        'Questão 2\r\nY?\r\n$_alts\r\nPágina 2 de 2\r\n',
      );
      expect(r, hasLength(2));
      expect(r[0].alternatives.last, 'd');
      expect(r[1].alternatives.last, 'd');
    });

    test('"(A)" e "A)" misturados entre as questões', () {
      final r = splitPastedQuestions(
        'Questão 1\nX?\n(A) a\n(B) b\n(C) c\n(D) d\n(E) e\n'
        'Questão 2\nY?\nA) a\nB) b\nC) c\nD) d\nE) e',
      );
      expect(r.map((q) => q.alternatives.length), [5, 5]);
    });

    test('texto antes da 1ª questão (instruções) é descartado', () {
      final r = splitPastedQuestions(
        'INSTRUÇÕES: A) leia. B) marque. C) assine. D) entregue.\n'
        'Questão 1\nX?\n$_alts\nQuestão 2\nY?\n$_alts',
      );
      expect(r, hasLength(2));
      expect(r[0].statement, 'X?');
    });

    test('40 questões: nenhum limite no domínio', () {
      final r = splitPastedQuestions(
        [for (var i = 1; i <= 40; i++) 'Questão $i\nEnunciado $i\n$_alts']
            .join('\n'),
      );
      expect(r, hasLength(40));
    });

    test('só rodapés e espaços devolve lista vazia', () {
      expect(splitPastedQuestions('Página 1\n- 2 -\n\n'), isEmpty);
    });

    test('números do enunciado que não formam cadeia não partem a questão', () {
      final r = splitPastedQuestions(
        'Questão 1\nEm 1964. O que houve?\n2 - 1 = 1\n$_alts\n'
        'Questão 2\nOutra?\n$_alts',
      );
      expect(r, hasLength(2));
      expect(r[0].statement, contains('2 - 1 = 1'));
    });

    test('regressão: cabeçalho "Questão nº 1" separa as questões', () {
      final r = splitPastedQuestions(
        'Questão nº 1\nX?\n$_alts\nQuestão nº 2\nY?\n$_alts',
      );
      expect(r, hasLength(2));
      expect(r[0].alternatives.last, 'd');
    });

    test(
      'regressão: lista numerada dentro do enunciado não rouba o lugar da Q2',
      () {
        final r = splitPastedQuestions(
          '1. Leia:\n1. A Terra.\n2. O Sol.\n$_alts\n'
          '2. Outra?\n$_alts\n3. Terceira?\n$_alts',
        );
        expect(r, hasLength(3));
        expect(r[1].statement, 'Outra?');
        expect(r[0].statement, contains('O Sol.'));
      },
    );
  });
}
