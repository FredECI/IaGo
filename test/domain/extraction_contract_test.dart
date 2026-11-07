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
  group('salvageQuestions (CA-I7)', () {
    test('JSON cortado no meio do 3º item recupera os 2 completos', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três com } chave')]);
      final cut = full.substring(0, full.indexOf('Três') + 6);
      final r = salvageQuestions(cut);
      expect(r.map((e) => e['statement']), ['Um', 'Dois']);
    });

    test('chaves, colchetes e aspas dentro de strings não confundem', () {
      final full = _json([_q('a } ] { [ \\" fim'), _q('Segunda')]);
      final r = salvageQuestions(full.substring(0, full.length - 40));
      expect(r.first['statement'], 'a } ] { [ \\" fim');
    });

    test('cortado em qualquer posição nunca inventa objeto', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três')]);
      var previous = 0;
      for (var n = 0; n <= full.length; n++) {
        final r = salvageQuestions(full.substring(0, n));
        expect(r.length, greaterThanOrEqualTo(previous));
        previous = r.length;
        for (final item in r) {
          expect(['Um', 'Dois', 'Três'], contains(item['statement']));
          expect(item['alternatives'], hasLength(5));
        }
      }
      expect(previous, 3);
    });

    test('aceita cerca de código e texto sem questões', () {
      expect(salvageQuestions('sem json'), isEmpty);
      expect(salvageQuestions('{"schemaVersion":1,"quest'), isEmpty);
      final fenced = '```json\n${_json([_q('Um')])}\n```';
      expect(salvageQuestions(fenced), hasLength(1));
    });
  });

  group('parseExtraction', () {
    test('resposta íntegra, sem aviso de parcial', () {
      final r = parseExtraction(_json([_q('Um'), _q('Dois')]));
      expect(r.partial, isFalse);
      expect(r.questions, hasLength(2));
      expect(r.questions.first.suggestedArea, Area.mathematics);
      expect(r.questions.first.suggestedSubject, 'Matemática');
      expect(r.questions.first.selectedByDefault, isTrue);
      expect(r.warnings, isEmpty);
    });

    test('JSON cortado vira parcial com os objetos completos (CA-I7)', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três')]);
      final r = parseExtraction(full.substring(0, full.indexOf('Três') + 3));
      expect(r.partial, isTrue);
      expect(r.questions.map((e) => e.statement), ['Um', 'Dois']);
      expect(r.warnings.first, contains('Aproveitamos 2 questões'));
    });

    test('schemaVersion diferente de 1 ou resposta sem JSON é malformed', () {
      expect(
        () => parseExtraction(_json([_q('Um')], version: 2)),
        throwsA(isA<MalformedExtractionException>()),
      );
      expect(
        () => parseExtraction('{"questions": []}'),
        throwsA(isA<MalformedExtractionException>()),
      );
      expect(
        () => parseExtraction('nada de json'),
        throwsA(isA<MalformedExtractionException>()),
      );
    });

    test('statement vazio ou maior que 6.000 descarta o item', () {
      final r = parseExtraction(
        _json([_q('   '), _q('x' * 6001), _q('x' * 6000), _q('ok')]),
      );
      expect(r.questions, hasLength(2));
      expect(r.discardedCount, 2);
    });

    test('objetiva fora de 2 a 5 alternativas vira rascunho desmarcado', () {
      final r = parseExtraction(
        _json([
          _q(
            'Uma só',
            extra: {
              'alternatives': ['só'],
            },
          ),
          _q(
            'Seis',
            extra: {
              'alternatives': ['1', '2', '3', '4', '5', '6'],
            },
          ),
          _q(
            'Duas',
            extra: {
              'alternatives': ['1', '2'],
            },
          ),
        ]),
      );
      expect(r.questions, hasLength(3));
      expect(r.questions[0].selectedByDefault, isFalse);
      expect(r.questions[0].warnings, isNotEmpty);
      expect(r.questions[1].selectedByDefault, isFalse);
      expect(r.questions[2].selectedByDefault, isTrue);
    });

    test('discursiva limpa as alternativas', () {
      final r = parseExtraction(
        _json([
          _q('Explique', extra: {'type': 'discursive'}),
        ]),
      );
      expect(r.questions.single.type, QuestionType.discursive);
      expect(r.questions.single.alternatives, isEmpty);
    });

    test('remove a letra do começo da alternativa', () {
      final r = parseExtraction(
        _json([
          _q(
            'Q',
            extra: {
              'alternatives': [
                'A) um',
                '(B) dois',
                'c. três',
                'D - quatro',
                'E) cinco',
              ],
            },
          ),
          _q(
            'Q2',
            extra: {
              'alternatives': ['E. coli', 'B) bactéria'],
            },
          ),
        ]),
      );
      expect(r.questions[0].alternatives, [
        'um',
        'dois',
        'três',
        'quatro',
        'cinco',
      ]);
      expect(r.questions[1].alternatives, ['E. coli', 'bactéria']);
    });

    test('enunciado repetido mantém um e avisa', () {
      final r = parseExtraction(
        _json([_q('Mesma  Pergunta?'), _q('mesma pergunta?')]),
      );
      expect(r.questions, hasLength(1));
      expect(r.warnings.join(' '), contains('repetida'));
    });

    test('mais de 30 mantém 30 e avisa', () {
      final r = parseExtraction(
        _json([for (var i = 0; i < 35; i++) _q('Questão número $i')]),
      );
      expect(r.questions, hasLength(30));
      expect(r.warnings.join(' '), contains('30'));
    });

    test('matéria fora do catálogo da área vira null', () {
      final r = parseExtraction(
        _json([
          _q('A', extra: {'suggestedSubject': 'Física'}),
          _q(
            'B',
            extra: {
              'suggestedArea': 'naturalSciences',
              'suggestedSubject': 'fisica',
            },
          ),
          _q(
            'C',
            extra: {'suggestedArea': 'unknown', 'suggestedSubject': 'Física'},
          ),
        ]),
      );
      expect(r.questions[0].suggestedSubject, isNull);
      expect(r.questions[1].suggestedArea, Area.naturalSciences);
      expect(r.questions[1].suggestedSubject, 'Física');
      expect(r.questions[2].suggestedArea, isNull);
      expect(r.questions[2].suggestedSubject, isNull);
    });

    test('campo de gabarito nunca é guardado (CA-I8)', () {
      final raw = jsonEncode({
        'schemaVersion': 1,
        'gabarito': ['B'],
        'questions': [
          _q(
            'Com gabarito',
            extra: {
              'correctAlternative': 'SEGREDO-GAB',
              'answer': 'SEGREDO-GAB',
              'gabarito': 'SEGREDO-GAB',
            },
          ),
        ],
        'containsPersonalData': false,
      });
      final r = parseExtraction(raw);
      final q = r.questions.single;
      final dump = [
        q.statement,
        q.type.name,
        ...q.alternatives,
        q.sourceHint,
        q.suggestedSubject,
        ...q.warnings,
        r.notes,
        ...r.warnings,
      ].join('|');
      expect(dump, isNot(contains('SEGREDO-GAB')));
      final cut = parseExtraction(raw.substring(0, raw.length - 30));
      expect(cut.questions.single.statement, 'Com gabarito');
    });

    test('hasFigure e isComplete=false vêm desmarcadas (CA-I9)', () {
      final r = parseExtraction(
        _json([
          _q('Com figura', extra: {'hasFigure': true}),
          _q('Cortada', extra: {'isComplete': false}),
          _q('Normal'),
        ]),
      );
      expect(r.questions[0].hasFigure, isTrue);
      expect(r.questions[0].selectedByDefault, isFalse);
      expect(r.questions[1].isComplete, isFalse);
      expect(r.questions[1].selectedByDefault, isFalse);
      expect(r.questions[2].selectedByDefault, isTrue);
    });

    test('containsPersonalData gera aviso', () {
      final r = parseExtraction(_json([_q('Um')], pii: true));
      expect(r.containsPersonalData, isTrue);
      expect(r.warnings.join(' '), contains('dados pessoais'));
    });
  });

  group('ajustes do ciclo 2', () {
    test('alternativa de mais de 1.000 caracteres ou mais de 10 descarta', () {
      final r = parseExtraction(
        _json([
          _q(
            'Longa',
            extra: {
              'alternatives': ['a', 'x' * 1001],
            },
          ),
          _q(
            'Muitas',
            extra: {
              'alternatives': [for (var i = 0; i < 11; i++) 'a$i'],
            },
          ),
          _q(
            'No limite',
            extra: {
              'alternatives': ['a', 'x' * 1000],
            },
          ),
        ]),
      );
      expect(r.questions.map((q) => q.statement), ['No limite']);
      expect(r.discardedCount, 2);
    });

    test('"Gabarito: C" no texto avisa e desmarca', () {
      final r = parseExtraction(
        _json([
          _q('Quanto é 2+2?\nGabarito: C'),
          _q(
            'Normal',
            extra: {
              'alternatives': ['a', 'Resposta: b'],
            },
          ),
          _q('Dica', extra: {'sourceHint': 'gabarito oficial'}),
          _q('Limpa'),
        ]),
      );
      expect(r.questions[0].selectedByDefault, isFalse);
      expect(r.questions[0].warnings.join(' '), contains('gabarito'));
      expect(r.questions[1].selectedByDefault, isFalse);
      expect(r.questions[2].selectedByDefault, isFalse);
      expect(r.questions[3].selectedByDefault, isTrue);
    });

    test('frase de abertura com chaves não desvia a varredura', () {
      final full = _json([_q('Um'), _q('Dois'), _q('Três')]);
      final cut =
          'Aqui vai {o JSON}: ${full.substring(0, full.indexOf('Três') + 3)}';
      expect(salvageQuestions(cut).map((e) => e['statement']), ['Um', 'Dois']);
      final r = parseExtraction(cut);
      expect(r.questions, hasLength(2));
    });

    test('JSON válido fora do formato lança malformed, sem varrer', () {
      for (final bad in [
        '[1, 2]',
        '{"schemaVersion": 1}',
        '{"questions": 3}',
        '"texto"',
        '42',
      ]) {
        expect(
          () => parseExtraction(bad),
          throwsA(isA<MalformedExtractionException>()),
          reason: bad,
        );
      }
    });
  });
}
