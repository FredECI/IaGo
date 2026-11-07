import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/question.dart';

Map<String, Object?> _q(String statement, {Map<String, Object?>? extra}) => {
  'statement': statement,
  'type': 'objective',
  'alternatives': ['a', 'b', 'c', 'd', 'e'],
  'hasFigure': false,
  'isComplete': true,
  'page': 1,
  'sourceHint': null,
  'suggestedArea': 'mathematics',
  'suggestedSubject': 'Matemática',
  ...?extra,
};

String _json(
  List<Map<String, Object?>> qs, {
  Object? version = 1,
  bool pii = false,
}) => jsonEncode({
  'schemaVersion': version,
  'questions': qs,
  'containsPersonalData': pii,
  'notes': null,
});

void main() {
  group('JSON cortado: casos-limite (CA-I7)', () {
    test('escapes, \\u00e9 e aspas escapadas sobrevivem', () {
      const raw =
          r'{"schemaVersion":1,"questions":[{"statement":"Café \"quente\" \\ fim","type":"discursive","isComplete":true},{"statement":"Segun';
      final r = parseExtraction(raw);
      expect(r.partial, isTrue);
      expect(r.questions, hasLength(1));
      expect(r.questions.single.statement, 'Café "quente" \\ fim');
    });

    test('corte no meio de um escape ou de um \\uXXXX não inventa nada', () {
      const head =
          r'{"schemaVersion":1,"questions":[{"statement":"Um","type":"discursive","isComplete":true},{"statement":"Dois ';
      for (final tail in [r'\', r'\u', r'\u00', r'\u00e', r'\"', r'é']) {
        final r = salvageQuestions('$head$tail');
        expect(r, hasLength(1), reason: tail);
        expect(r.single['statement'], 'Um');
      }
    });

    test('objeto completo seguido de outro cortado em cada posição', () {
      final full = _json([
        _q('Primeira } ] { [ "x"'),
        _q('Segunda \\ \\" fim'),
      ]);
      final firstEnd = full.indexOf('"Segunda');
      for (var n = firstEnd; n <= full.length; n++) {
        final r = salvageQuestions(full.substring(0, n));
        expect(r, isNotEmpty, reason: 'corte em $n');
        expect(r.first['statement'], 'Primeira } ] { [ "x"');
        for (final item in r) {
          expect([
            'Primeira } ] { [ "x"',
            'Segunda \\ \\" fim',
          ], contains(item['statement']));
        }
      }
    });

    test('nenhuma questão completa: parcial, vazio e sem exceção', () {
      final r = parseExtraction(
        '{"schemaVersion":1,"questions":[{"statement":"Um","type"',
      );
      expect(r.partial, isTrue);
      expect(r.questions, isEmpty);
    });

    test('cerca ```json sem fechar (resposta cortada) ainda recupera', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três')]);
      final r = parseExtraction(
        '```json\n${full.substring(0, full.indexOf('Três') + 2)}',
      );
      expect(r.questions.map((e) => e.statement), ['Um', 'Dois']);
    });

    test('texto antes do JSON cortado também recupera', () {
      final full = _json([_q('Um'), _q('Dois')]);
      final r = parseExtraction(
        'Aqui está:\n${full.substring(0, full.indexOf('Dois') + 2)}',
      );
      expect(r.partial, isTrue);
      expect(r.questions.map((e) => e.statement), ['Um']);
    });

    test('schemaVersion ausente ou errado também lança no caminho cortado', () {
      expect(
        () => parseExtraction(
          '{"questions":[{"statement":"Um","type":"discursive"},{"statem',
        ),
        throwsA(isA<MalformedExtractionException>()),
      );
      expect(
        () => parseExtraction(
          '{"schemaVersion":2,"questions":[{"statement":"Um"},{"statem',
        ),
        throwsA(isA<MalformedExtractionException>()),
      );
    });

    test('entradas inúteis lançam Malformed, nunca outro erro', () {
      for (final raw in ['', '   ', '[]', '{}', 'null', '42', '"texto"', '{']) {
        expect(
          () => parseExtraction(raw),
          throwsA(isA<MalformedExtractionException>()),
          reason: '"$raw"',
        );
      }
    });

    test('schemaVersion como texto não vale', () {
      expect(
        () => parseExtraction('{"schemaVersion":"1","questions":[]}'),
        throwsA(isA<MalformedExtractionException>()),
      );
    });

    test('resposta vazia e íntegra não é parcial', () {
      final r = parseExtraction(_json([]));
      expect(r.partial, isFalse);
      expect(r.questions, isEmpty);
    });
  });

  group('gabarito nunca é guardado (CA-I8)', () {
    String dumpOf(ExtractionResult r) => [
      for (final q in r.questions) ...[
        q.statement,
        q.type.name,
        ...q.alternatives,
        q.sourceHint,
        q.suggestedSubject,
        q.page,
        ...q.warnings,
      ],
      r.notes,
      ...r.warnings,
    ].join('|');

    test('campos de gabarito no item e na raiz', () {
      final raw = jsonEncode({
        'schemaVersion': 1,
        'answerKey': 'SEGREDO',
        'questions': [
          _q(
            'Q',
            extra: {
              'answer': 'SEGREDO',
              'correctAlternative': 'SEGREDO',
              'gabarito': {'letter': 'SEGREDO'},
              'isCorrect': true,
              'correctIndex': 2,
              'resolution': 'SEGREDO',
            },
          ),
        ],
        'containsPersonalData': false,
      });
      expect(dumpOf(parseExtraction(raw)), isNot(contains('SEGREDO')));
      final cut = parseExtraction(raw.substring(0, raw.length - 20));
      expect(cut.questions, hasLength(1));
      expect(dumpOf(cut), isNot(contains('SEGREDO')));
    });

    test('alternativas como objeto com isCorrect não vazam o gabarito', () {
      final r = parseExtraction(
        _json([
          _q(
            'Q',
            extra: {
              'alternatives': [
                {'text': 'SEGREDO-a', 'isCorrect': true},
                {'text': 'SEGREDO-b', 'isCorrect': false},
              ],
            },
          ),
        ]),
      );
      expect(dumpOf(r), isNot(contains('SEGREDO')));
      expect(r.questions.single.selectedByDefault, isFalse);
    });

    test('alternativas como texto continuam só com o texto', () {
      final r = parseExtraction(
        _json([
          _q(
            'Q',
            extra: {
              'alternatives': ['um', 'dois'],
              'isCorrect': [false, true],
            },
          ),
        ]),
      );
      expect(r.questions.single.alternatives, ['um', 'dois']);
    });
  });

  group('regras do contrato: limites', () {
    test('6.000 com espaços ao redor vale; 6.001 após trim não', () {
      final r = parseExtraction(
        _json([_q('  ${'x' * 6000}  '), _q('y' * 6001), _q(' ${'z' * 6001}')]),
      );
      expect(r.questions, hasLength(1));
      expect(r.questions.single.statement.length, 6000);
      expect(r.discardedCount, 2);
    });

    test('statement que não é texto descarta o item', () {
      final r = parseExtraction(
        jsonEncode({
          'schemaVersion': 1,
          'questions': [
            {'statement': 42},
            {'statement': null},
            'texto',
            null,
            _q('ok'),
          ],
        }),
      );
      expect(r.questions, hasLength(1));
      expect(r.discardedCount, 4);
    });

    test(
      'type inválido: objetiva com alternativas, desmarcada e com aviso',
      () {
        final r = parseExtraction(
          _json([
            _q('A', extra: {'type': 'multiple'}),
            _q('B', extra: {'type': null, 'alternatives': <String>[]}),
            _q('C', extra: {'type': 7}),
          ]),
        );
        expect(r.questions[0].type, QuestionType.objective);
        expect(r.questions[1].type, QuestionType.discursive);
        expect(r.questions[2].type, QuestionType.objective);
        for (final q in r.questions) {
          expect(q.warnings, isNotEmpty);
          expect(q.selectedByDefault, isFalse);
        }
      },
    );

    test('isComplete ausente ou não booleano conta como falso', () {
      final base = _q('A')..remove('isComplete');
      final r = parseExtraction(
        _json([
          base,
          _q('B', extra: {'isComplete': 'true'}),
        ]),
      );
      for (final q in r.questions) {
        expect(q.isComplete, isFalse);
        expect(q.selectedByDefault, isFalse);
      }
    });

    test('hasFigure ausente conta como falso; "true" em texto também', () {
      final base = _q('A')..remove('hasFigure');
      final r = parseExtraction(
        _json([
          base,
          _q('B', extra: {'hasFigure': 'true'}),
        ]),
      );
      expect(r.questions[0].hasFigure, isFalse);
      expect(r.questions[1].hasFigure, isFalse);
    });

    test('objetiva sem alternativas fica desmarcada com aviso', () {
      final r = parseExtraction(
        _json([
          _q('A', extra: {'alternatives': <String>[]}),
        ]),
      );
      expect(r.questions.single.warnings, isNotEmpty);
      expect(r.questions.single.selectedByDefault, isFalse);
    });

    test('letra só sai quando é a esperada para a posição', () {
      final r = parseExtraction(
        _json([
          _q(
            'A',
            extra: {
              'alternatives': ['B) um', 'A) dois', 'C. três', 'E - quatro'],
            },
          ),
        ]),
      );
      expect(r.questions.single.alternatives, [
        'B) um',
        'A) dois',
        'três',
        'E - quatro',
      ]);
    });

    test('matéria é reconhecida sem acento e sem caixa', () {
      final r = parseExtraction(
        _json([
          _q('A', extra: {'suggestedSubject': 'matematica'}),
          _q(
            'B',
            extra: {
              'suggestedArea': 'languages',
              'suggestedSubject': 'EDUCACAO FISICA',
            },
          ),
        ]),
      );
      expect(r.questions[0].suggestedSubject, 'Matemática');
      expect(r.questions[1].suggestedArea, Area.languages);
      expect(r.questions[1].suggestedSubject, 'Educação Física');
    });

    test('page inválida e sourceHint longo', () {
      final r = parseExtraction(
        _json([
          _q('A', extra: {'page': 0, 'sourceHint': '   '}),
          _q('B', extra: {'page': -3, 'sourceHint': 'h' * 500}),
          _q('C', extra: {'page': '2'}),
          _q('D', extra: {'page': 4}),
        ]),
      );
      expect(r.questions[0].page, isNull);
      expect(r.questions[0].sourceHint, isNull);
      expect(r.questions[1].page, isNull);
      expect(r.questions[1].sourceHint, hasLength(200));
      expect(r.questions[2].page, isNull);
      expect(r.questions[3].page, 4);
    });

    test('duplicatas saem antes do corte em 30', () {
      final qs = [
        for (var i = 0; i < 30; i++) _q('Enunciado número $i'),
        for (var i = 0; i < 5; i++) _q('Enunciado número 0'),
      ];
      final r = parseExtraction(_json(qs));
      expect(r.questions, hasLength(30));
      final text = r.warnings.join(' ');
      expect(text, contains('repetida'));
      expect(text, isNot(contains('primeiras')));
    });

    test('28 distintas + 5 repetidas + 5 distintas: 30 e aviso de excesso', () {
      final qs = [
        for (var i = 0; i < 28; i++) _q('Enunciado número $i'),
        for (var i = 0; i < 5; i++) _q('Enunciado número 1'),
        for (var i = 28; i < 33; i++) _q('Enunciado número $i'),
      ];
      final r = parseExtraction(_json(qs));
      expect(r.questions, hasLength(30));
      expect(r.questions.last.statement, 'Enunciado número 29');
      expect(r.warnings.join(' '), contains('primeiras 30'));
    });

    test('dados pessoais e parcial somam avisos sem se atrapalhar', () {
      final full = _json([_q('Um'), _q('Dois')], pii: true);
      final r = parseExtraction(full.substring(0, full.length - 5));
      expect(r.partial, isTrue);
      expect(r.containsPersonalData, isTrue);
      expect(r.warnings.join(' '), contains('dados pessoais'));
    });

    test(
      'regressão: enunciados que só diferem por símbolo não são duplicata',
      () {
        final r = parseExtraction(
          _json([
            _q('Calcule 3 + 4'),
            _q('Calcule 3 - 4'),
            _q('Calcule 3 × 4'),
          ]),
        );
        expect(r.questions, hasLength(3));
      },
    );

    test('regressão: desigualdade oposta não é duplicata', () {
      final r = parseExtraction(
        _json([_q('Resolva x > 3'), _q('Resolva x < 3')]),
      );
      expect(r.questions, hasLength(2));
    });
  });
}
