import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_planner.dart';
import 'package:iago/domain/direction_validation.dart';
import 'package:iago/domain/extraction_contract.dart';
import 'package:iago/domain/paste_parser.dart';

const _alts = 'A) a\nB) b\nC) c\nD) d';

String _json(List<String> statements) => jsonEncode({
  'schemaVersion': 1,
  'questions': [
    for (final s in statements)
      {
        'statement': s,
        'type': 'discursive',
        'alternatives': <String>[],
        'hasFigure': false,
        'isComplete': true,
      },
  ],
});

DirectionContext _ctx({
  List<SubjectCoverage> coverage = const [],
  DirectionLimits limits = const DirectionLimits(),
  int hours = 6,
}) => DirectionContext(
  today: DateTime(2026, 11, 30),
  goal: GoalSummary(exam: ExamTarget.enem, weeklyHours: hours),
  coverage: coverage,
  limits: limits,
);

void main() {
  group('I1-b: preferência por bloco de alternativas', () {
    test('objetiva, discursiva, discursiva, objetiva: 4 rascunhos', () {
      final r = splitPastedQuestions(
        '1. Obj?\n$_alts\n2. Explique A.\n3. Explique B.\n4. Obj2?\n$_alts',
      );
      expect(r.map((q) => q.statement), [
        'Obj?',
        'Explique A.',
        'Explique B.',
        'Obj2?',
      ]);
    });

    test('só discursivas, numeração limpa: nada muda', () {
      final r = splitPastedQuestions('1. Um.\n2. Dois.\n3. Três.');
      expect(r.map((q) => q.statement), ['Um.', 'Dois.', 'Três.']);
    });

    test('discursiva com itens a) b) e lista interna não perde texto', () {
      const text =
          '1. Leia:\n1. A Terra.\n2. O Sol.\na) Explique.\nb) Compare.\n'
          '2. Outra.\n3. Terceira.';
      final joined = splitPastedQuestions(text)
          .map((q) => q.statement)
          .join(' ');
      for (final w in ['A Terra', 'O Sol', 'Explique', 'Outra', 'Terceira']) {
        expect(joined, contains(w));
      }
    });

    test('numeração que salta com alternativas não perde texto', () {
      final r = splitPastedQuestions(
        '1. Um?\n$_alts\n2. Dois?\n$_alts\n4. Quatro?\n$_alts\n5. Cinco?\n$_alts',
      );
      final joined = r.map((q) => '${q.statement} ${q.alternatives}').join();
      for (final w in ['Um?', 'Dois?', 'Quatro?', 'Cinco?']) {
        expect(joined, contains(w));
      }
    });

    test('palavra-chave com lista interna continua separando em 2', () {
      final r = splitPastedQuestions(
        'Questão 1\n1. item\n2. item\n$_alts\nQuestão 2\nY?\n$_alts',
      );
      expect(r, hasLength(2));
    });

    test('variações de nº: Nº, N.º, no, n°', () {
      final a = splitPastedQuestions(
        'QUESTÃO Nº 3\nX?\n$_alts\nQUESTÃO N.º 4\nY?\n$_alts',
      );
      expect(a.map((q) => q.statement), ['X?', 'Y?']);
      final b = splitPastedQuestions(
        'Questão no 1\nX?\n$_alts\nQuestão n° 2\nY?\n$_alts',
      );
      expect(b, hasLength(2));
    });
  });

  group('I2-a: chave de duplicata', () {
    test('maiúsculas, espaços e quebras colapsam; símbolos distintos não', () {
      final r = parseExtraction(
        _json(['Calcule  3 + 4', 'CALCULE\n3 + 4', 'Calcule 3 + 5']),
      );
      expect(r.questions, hasLength(2));
    });

    test('3 + 4 e 3+4 (informativo): não quebra, 1 ou 2 questões', () {
      final r = parseExtraction(_json(['Calcule 3 + 4', 'Calcule 3+4']));
      expect(r.questions.length, anyOf(1, 2));
    });
  });

  group('R1: filtro de cobertura no construtor', () {
    test('matéria fora do catálogo ou na área errada não chega ao JSON', () {
      final c = _ctx(
        coverage: const [
          SubjectCoverage(area: Area.mathematics, subject: 'Latim', saved: 5),
          SubjectCoverage(area: Area.mathematics, subject: 'Física', saved: 5),
          SubjectCoverage(
            area: Area.naturalSciences,
            subject: 'Física',
            saved: 7,
          ),
          SubjectCoverage(area: Area.humanities, subject: 'segredo@x.com'),
        ],
      );
      expect(c.coverage, hasLength(1));
      final text = jsonEncode(c.toJson());
      expect(text, isNot(contains('Latim')));
      expect(text, isNot(contains('segredo')));
      expect(text, contains('"saved":7'));
    });

    test('lista é cópia imutável', () {
      final src = [
        const SubjectCoverage(area: Area.mathematics, subject: 'Matemática'),
      ];
      final c = _ctx(coverage: src);
      src.clear();
      expect(c.coverage, hasLength(1));
      expect(() => c.coverage.add(c.coverage.first), throwsUnsupportedError);
    });

    test('capitalização diferente da matéria é filtrada', () {
      final c = _ctx(
        coverage: const [
          SubjectCoverage(area: Area.mathematics, subject: 'matemática'),
        ],
      );
      expect(c.coverage, isEmpty);
    });
  });

  group('R5: limites personalizados', () {
    test('varredura: plano não vazio, válido e dentro dos limites', () {
      for (final steps in [1, 2, 3]) {
        for (final gap in [1, 2, 3, 5]) {
          for (final ahead in [1, 2, 3, 5, 7, 14, 30]) {
            for (final hours in [1, 6, 40]) {
              final limits = DirectionLimits(
                maxSteps: steps,
                minDaysBetweenDeadlines: gap,
                maxDaysAhead: ahead,
              );
              final plan = planDirection(_ctx(limits: limits, hours: hours));
              final reason = '$steps/$gap/$ahead/$hours';
              expect(plan, isNotEmpty, reason: reason);
              expect(plan.length, lessThanOrEqualTo(steps), reason: reason);
              final v = validateProposal(plan, limits: limits);
              expect(v.isValid, isTrue, reason: '$reason ${v.violations}');
            }
          }
        }
      }
    });

    test('maxDaysAhead 1 devolve 1 etapa com prazo 1', () {
      final plan = planDirection(
        _ctx(limits: const DirectionLimits(maxDaysAhead: 1)),
      );
      expect(plan, hasLength(1));
      expect(plan.single.dueInDays, 1);
    });

    test('limites padrão continuam dando 3 etapas', () {
      expect(planDirection(_ctx()), hasLength(3));
    });
  });
}
