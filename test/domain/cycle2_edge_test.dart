import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/paste_parser.dart';

const _alts = 'A) a\nB) b\nC) c\nD) d';

String _json(List<Map<String, Object?>> qs) =>
    jsonEncode({'schemaVersion': 1, 'questions': qs});

Map<String, Object?> _q(
  String statement, {
  List<Object?>? alts,
  String? hint,
}) => {
  'statement': statement,
  'type': 'objective',
  'alternatives': alts ?? ['a', 'b', 'c', 'd'],
  'hasFigure': false,
  'isComplete': true,
  'sourceHint': hint,
};

void main() {
  group('desempenho de splitPastedQuestions (limite folgado de 5 s)', () {
    void timed(String name, String text, {int? expectAtLeast}) {
      test(name, () {
        final sw = Stopwatch()..start();
        final r = splitPastedQuestions(text);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(5000), reason: name);
        if (expectAtLeast != null) {
          expect(r.length, greaterThanOrEqualTo(expectAtLeast));
        }
      });
    }

    for (final n in [250, 300, 301, 1000, 2000]) {
      timed(
        '$n cabeçalhos numéricos alternando com e sem alternativas',
        [
          for (var i = 1; i <= n; i++)
            i.isEven ? '$i. Questão $i?\n$_alts' : '$i. Discursiva $i.',
        ].join('\n'),
        expectAtLeast: 2,
      );
      timed(
        '$n pares "1. a / 2. b" repetidos (muitos candidatos iguais)',
        [for (var i = 0; i < n; i++) '1. a$i\n2. b$i'].join('\n'),
      );
      timed(
        '$n linhas "1. item" todas iguais',
        List.filled(n, '1. item').join('\n'),
      );
    }

    timed(
      '2000 cabeçalhos "Questão N" com lista interna cada',
      [
        for (var i = 1; i <= 2000; i++)
          'Questão $i\nLeia:\n1. x\n2. y\n3. z\n$_alts',
      ].join('\n'),
      expectAtLeast: 2000,
    );

    timed(
      '1500 questões numeradas, cada uma com lista interna e alternativas',
      [for (var i = 1; i <= 1500; i++) '$i. Texto\n1. a\n2. b\n$_alts']
          .join('\n'),
    );

    timed(
      'uma linha enorme sem quebras (200 mil caracteres)',
      '1. ${'palavra ' * 25000}',
    );

    timed(
      'rodapés em excesso: 5000 linhas "Página N"',
      [for (var i = 0; i < 5000; i++) 'Página $i'].join('\n'),
    );

    test('300 e 301 candidatos limpos continuam separando tudo', () {
      for (final n in [300, 301, 400]) {
        final r = splitPastedQuestions(
          [for (var i = 1; i <= n; i++) '$i. Enunciado $i\n$_alts'].join('\n'),
        );
        expect(r, hasLength(n), reason: 'n=$n');
        expect(r.last.statement, 'Enunciado $n');
      }
    });
  });

  group('cabeçalhos Q', () {
    test('"Q1)" e "Q.1" separam em cadeia', () {
      final a = splitPastedQuestions('Q1) X?\n$_alts\nQ2) Y?\n$_alts');
      expect(a.map((q) => q.statement), ['X?', 'Y?']);
      final b = splitPastedQuestions('Q.1 X?\n$_alts\nQ.2 Y?\n$_alts');
      expect(b.map((q) => q.statement), ['X?', 'Y?']);
      final c = splitPastedQuestions('Q.1\nX?\n$_alts\nQ.2\nY?\n$_alts');
      expect(c, hasLength(2));
    });

    test('"Q2 é a segunda letra" no meio do enunciado não parte a questão', () {
      final r = splitPastedQuestions(
        'Questão 1\nO que é\nQ2 é uma sigla comum?\n$_alts\n'
        'Questão 2\nY?\n$_alts',
      );
      expect(r, hasLength(2));
      expect(r[0].statement, contains('Q2 é uma sigla'));
    });

    test('Q isolado sem cadeia não é cabeçalho, nada se perde', () {
      final r = splitPastedQuestions('Q1 vale quanto?\n$_alts');
      expect(r, hasLength(1));
      expect(r.single.alternatives, hasLength(4));
      expect(r.single.statement, contains('vale quanto'));
    });
  });

  group('rodapé: linha longa nunca é rodapé', () {
    test('linha de 201 caracteres com "Página 3" fica no enunciado', () {
      final long = 'Página 3 ${'x' * 200}';
      final r = splitPastedQuestions(
        'Questão 1\n$long\n$_alts\nQuestão 2\nY?\n$_alts',
      );
      expect(r[0].statement, contains('xxxx'));
    });
  });

  group('extração: gabarito em texto desmarca, não descarta', () {
    test('linha do enunciado começando com "Resposta"', () {
      final r = parseExtraction(
        _json([
          _q('Considere o caso.\nResposta ao problema anterior: 5\nCalcule.'),
        ]),
      );
      expect(r.questions, hasLength(1));
      expect(r.discardedCount, 0);
      expect(r.questions.single.selectedByDefault, isFalse);
      expect(r.questions.single.warnings, isNotEmpty);
    });

    test('"Gabarito: B" em linha própria, em alternativa e em sourceHint', () {
      final a = parseExtraction(_json([_q('Texto\nGabarito: B')]));
      final b = parseExtraction(
        _json([
          _q('Q', alts: ['a', 'Resposta correta', 'c', 'd']),
        ]),
      );
      final c = parseExtraction(_json([_q('Q', hint: 'Gabarito oficial')]));
      for (final r in [a, b, c]) {
        expect(r.questions, hasLength(1));
        expect(r.questions.single.selectedByDefault, isFalse);
        expect(r.questions.single.warnings, isNotEmpty);
      }
    });

    test('palavras parecidas ou no meio da linha não disparam', () {
      final r = parseExtraction(
        _json([
          _q('Responda: qual é a resposta certa?'),
          _q('Os gabaritos foram divulgados.'),
          _q('Respostas variadas são aceitas.'),
          _q('Qual é a resposta do problema?'),
        ]),
      );
      expect(r.questions, hasLength(4));
      for (final q in r.questions) {
        expect(q.selectedByDefault, isTrue, reason: q.statement);
      }
    });

    test('maiúsculas e recuo: "  RESPOSTA: x" também avisa', () {
      final r = parseExtraction(_json([_q('Texto\n   RESPOSTA: x')]));
      expect(r.questions.single.selectedByDefault, isFalse);
    });
  });

  group('extração: tetos de alternativas', () {
    test('1.000 caracteres vale; 1.001 descarta e conta', () {
      final ok = parseExtraction(
        _json([
          _q('Q', alts: ['x' * 1000, 'b', 'c', 'd']),
        ]),
      );
      expect(ok.questions, hasLength(1));
      expect(ok.discardedCount, 0);
      final bad = parseExtraction(
        _json([
          _q('Q', alts: ['x' * 1001, 'b', 'c', 'd']),
          _q('Boa'),
        ]),
      );
      expect(bad.questions.map((q) => q.statement), ['Boa']);
      expect(bad.discardedCount, 1);
    });

    test('1.000 com espaços ao redor vale (conta após trim)', () {
      final r = parseExtraction(
        _json([
          _q('Q', alts: [' ${'x' * 1000} ', 'b', 'c', 'd']),
        ]),
      );
      expect(r.questions, hasLength(1));
    });

    test('10 alternativas ficam (com aviso); 11 descartam', () {
      final ten = parseExtraction(
        _json([
          _q('Q', alts: [for (var i = 0; i < 10; i++) 'alt $i']),
        ]),
      );
      expect(ten.questions, hasLength(1));
      expect(ten.questions.single.selectedByDefault, isFalse);
      final eleven = parseExtraction(
        _json([
          _q('Q', alts: [for (var i = 0; i < 11; i++) 'alt $i']),
        ]),
      );
      expect(eleven.questions, isEmpty);
      expect(eleven.discardedCount, 1);
    });

    test('item descartado por teto não derruba os vizinhos', () {
      final r = parseExtraction(
        _json([
          _q('A'),
          _q('B', alts: [for (var i = 0; i < 50; i++) 'alt $i']),
          _q('C'),
        ]),
      );
      expect(r.questions.map((q) => q.statement), ['A', 'C']);
    });

    test('alternativa que não é texto não estoura o teto nem lança', () {
      final r = parseExtraction(
        _json([
          _q('Q', alts: ['a', 7, null, 'b', 'c']),
        ]),
      );
      expect(r.questions, hasLength(1));
    });

    test('limite vale também no JSON cortado', () {
      final full = _json([
        _q('Boa'),
        _q('Ruim', alts: ['x' * 1001, 'b', 'c', 'd']),
        _q('Cortada'),
      ]);
      final r = parseExtraction(full.substring(0, full.indexOf('Cortada') + 3));
      expect(r.partial, isTrue);
      expect(r.questions.map((q) => q.statement), ['Boa']);
      expect(r.discardedCount, 1);
    });
  });

  group('extração: _scan e JSON fora do formato', () {
    test('texto com "{" antes do JSON cortado não confunde o início', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três')]);
      final r = parseExtraction(
        'Segue {o resultado} abaixo:\n${full.substring(0, full.indexOf('Três') + 2)}',
      );
      expect(r.questions.map((q) => q.statement), ['Um', 'Dois']);
    });

    test('JSON válido fora do formato lança Malformed', () {
      for (final raw in [
        '{"foo": 1}',
        '{"schemaVersion":1,"questions":"x"}',
        '{"schemaVersion":1,"questions":{"a":1}}',
        '[{"statement":"x"}]',
        '{"schemaVersion":1}',
      ]) {
        expect(
          () => parseExtraction(raw),
          throwsA(isA<MalformedExtractionException>()),
          reason: raw,
        );
      }
    });

    test('questions antes de schemaVersion no JSON cortado', () {
      const raw =
          '{"questions":[{"statement":"Um","type":"discursive"}],"schemaVersion":1,"cont';
      final r = parseExtraction(raw);
      expect(r.questions, hasLength(1));
    });
  });
}
