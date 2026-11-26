import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_planner.dart';
import 'package:iago/domain/direction_validation.dart';

DirectionContext ctx({
  List<Area> focus = const [],
  int hours = 6,
  List<SubjectCoverage> coverage = const [],
  DateTime? today,
  DirectionHistory history = const DirectionHistory(),
}) => DirectionContext(
  today: today ?? DateTime(2026, 11, 30, 15, 42),
  goal: GoalSummary(
    exam: ExamTarget.enem,
    daysToTarget: 340,
    weeklyHours: hours,
    focusAreas: focus,
  ),
  coverage: coverage,
  history: history,
);

SubjectCoverage cov(
  Area a,
  String s, {
  int saved = 0,
  int last14 = 0,
  int lists = 0,
}) => SubjectCoverage(
  area: a,
  subject: s,
  saved: saved,
  savedLast14d: last14,
  listsExportedLast14d: lists,
);

void main() {
  group('planDirection', () {
    test(
      'CA-D2: prazos entre amanhã e 14 dias, com intervalo, no catálogo',
      () {
        for (final hours in [1, 3, 6, 20, 40]) {
          for (final focus in [
            <Area>[],
            [Area.mathematics],
            [Area.languages, Area.humanities],
          ]) {
            final steps = planDirection(ctx(hours: hours, focus: focus));
            expect(steps, isNotEmpty);
            expect(steps.length, lessThanOrEqualTo(3));
            var prev = 0;
            for (final s in steps) {
              expect(s.dueInDays, inInclusiveRange(1, 14));
              if (prev > 0) expect(s.dueInDays - prev, greaterThanOrEqualTo(2));
              prev = s.dueInDays;
              expect(s.area.subjects, contains(s.subject));
              expect(s.rationale.length, lessThanOrEqualTo(140));
            }
            expect(validateProposal(steps).isValid, isTrue);
          }
        }
      },
    );

    test('CA-D3: mesma entrada, mesmo resultado, com relógio fixo', () {
      final input = ctx(
        focus: [Area.naturalSciences],
        coverage: [cov(Area.mathematics, 'Matemática', saved: 12, last14: 3)],
      );
      final a = planDirection(input).map((s) => s.toJson()).toList();
      final b = planDirection(input).map((s) => s.toJson()).toList();
      expect(jsonEncode(a), jsonEncode(b));
    });

    test('não repete matéria', () {
      final steps = planDirection(ctx());
      expect({for (final s in steps) s.subject}.length, steps.length);
    });

    test('áreas de foco vêm primeiro', () {
      final steps = planDirection(ctx(focus: [Area.humanities]));
      expect(steps.every((s) => s.area == Area.humanities), isTrue);
    });

    test('prioriza a matéria com menos questões nos últimos 14 dias', () {
      final coverage = [
        for (final s in Area.mathematics.subjects)
          cov(Area.mathematics, s, saved: 20, last14: 5),
        cov(Area.naturalSciences, 'Física', saved: 20, last14: 0, lists: 1),
        cov(Area.naturalSciences, 'Química', saved: 20, last14: 2, lists: 1),
        cov(Area.naturalSciences, 'Biologia', saved: 20, last14: 3, lists: 1),
      ];
      final steps = planDirection(
        ctx(focus: [Area.naturalSciences], coverage: coverage),
      );
      expect(steps.map((s) => s.subject), ['Física', 'Química', 'Biologia']);
    });

    test('escolha da ação', () {
      StepAction first(SubjectCoverage c) =>
          planDirection(ctx(focus: [c.area], coverage: [c]))
              .firstWhere((s) => s.subject == c.subject)
              .action;
      const m = 'Matemática';
      expect(first(cov(Area.mathematics, m, saved: 3)), StepAction.collect);
      expect(
        first(cov(Area.mathematics, m, saved: 15, last14: 2)),
        StepAction.buildList,
      );
      expect(
        first(cov(Area.mathematics, m, saved: 15, last14: 0, lists: 1)),
        StepAction.review,
      );
      expect(
        first(cov(Area.mathematics, m, saved: 15, last14: 4, lists: 1)),
        StepAction.practice,
      );
    });

    test('mais horas por semana encurtam os prazos', () {
      final few = planDirection(ctx(hours: 1)).first.dueInDays;
      final many = planDirection(ctx(hours: 40)).first.dueInDays;
      expect(many, lessThanOrEqualTo(few));
      expect(many, greaterThanOrEqualTo(2));
    });

    test('conta nova (sem cobertura) também gera 3 etapas válidas', () {
      expect(planDirection(ctx()).length, 3);
    });
  });

  group('DirectionContext (CA-D6)', () {
    test('serializa só os campos agregados da spec', () {
      final json = ctx(
        focus: [Area.mathematics],
        coverage: [cov(Area.mathematics, 'Matemática', saved: 12, last14: 3)],
      ).toJson();
      expect(json.keys.toSet(), {
        'today',
        'goal',
        'coverage',
        'history',
        'allowedSubjects',
        'limits',
      });
      expect(json['today'], '2026-11-30');
      expect((json['goal']! as Map).keys.toSet(), {
        'exam',
        'daysToTarget',
        'weeklyHours',
        'focusAreas',
      });
      expect(((json['coverage']! as List).single as Map).keys.toSet(), {
        'area',
        'subject',
        'saved',
        'savedLast14d',
        'listsExportedLast14d',
      });
      final text = jsonEncode(json).toLowerCase();
      for (final forbidden in ['uid', 'email', 'e-mail', 'name', 'stem']) {
        expect(text.contains('"$forbidden"'), isFalse);
      }
    });

    test('GoalSummary calcula os dias até a prova sem expor a data', () {
      final goal = StudyGoal(
        exam: ExamTarget.vestibular,
        targetDate: DateTime(2026, 12, 10, 8),
        weeklyHours: 5,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      final s = GoalSummary.fromGoal(goal, DateTime(2026, 11, 30, 23));
      expect(s.daysToTarget, 10);
      expect(s.toJson().containsKey('targetDate'), isFalse);
    });
  });

  group('validateProposal', () {
    ProposedStep step({
      Area area = Area.mathematics,
      String subject = 'Matemática',
      int count = 10,
      int due = 3,
      String rationale = 'ok',
    }) => ProposedStep(
      action: StepAction.collect,
      area: area,
      subject: subject,
      targetCount: count,
      dueInDays: due,
      rationale: rationale,
    );

    test('aceita uma proposta correta', () {
      expect(validateProposal([step()]).isValid, isTrue);
    });

    test('rejeita violações', () {
      expect(validateProposal([]).isValid, isFalse);
      expect(
        validateProposal([
          step(),
          step(subject: 'Física', area: Area.naturalSciences, due: 5),
          step(subject: 'Química', area: Area.naturalSciences, due: 7),
          step(subject: 'Biologia', area: Area.naturalSciences, due: 9),
        ]).isValid,
        isFalse,
      );
      expect(validateProposal([step(subject: 'Latim')]).isValid, isFalse);
      expect(validateProposal([step(count: 0)]).isValid, isFalse);
      expect(validateProposal([step(count: 31)]).isValid, isFalse);
      expect(validateProposal([step(due: 0)]).isValid, isFalse);
      expect(validateProposal([step(due: 15)]).isValid, isFalse);
      expect(validateProposal([step(rationale: 'x' * 141)]).isValid, isFalse);
      expect(
        validateProposal([
          step(),
          step(subject: 'Física', area: Area.naturalSciences, due: 4),
        ]).isValid,
        isFalse,
      );
      expect(validateProposal([step(), step(due: 8)]).isValid, isFalse);
    });

    test('JSON da C.2 válido passa; ignora campos extras', () {
      final r = validateProposalJson({
        'schemaVersion': 1,
        'steps': [
          {
            'action': 'collect',
            'area': 'mathematics',
            'subject': 'Matemática',
            'targetCount': 10,
            'dueInDays': 3,
            'rationale': 'Poucas questões.',
            'answerKey': 'C',
          },
        ],
      });
      expect(r.isValid, isTrue);
      expect(r.steps.single.subject, 'Matemática');
    });

    test('JSON malformado nunca lança e é inválido', () {
      Map<String, Object?> one(Map<String, Object?> patch) => {
        'schemaVersion': 1,
        'steps': [
          {
            'action': 'collect',
            'area': 'mathematics',
            'subject': 'Matemática',
            'targetCount': 10,
            'dueInDays': 3,
            'rationale': 'ok',
            ...patch,
          },
        ],
      };
      final bad = <Object?>[
        null,
        'texto',
        [],
        {'schemaVersion': 2, 'steps': []},
        {'schemaVersion': 1},
        {'schemaVersion': 1, 'steps': []},
        {
          'schemaVersion': 1,
          'steps': ['x'],
        },
        one({'action': 'ensinar'}),
        one({'area': 5}),
        one({'area': 'cooking'}),
        one({'subject': 'Latim'}),
        one({'targetCount': '10'}),
        one({'dueInDays': 3.5}),
        one({'dueInDays': 40}),
        one({'rationale': null}),
      ];
      for (final b in bad) {
        expect(validateProposalJson(b).isValid, isFalse, reason: '$b');
      }
    });
  });

  group('ajustes do ciclo 1', () {
    test('R1: matéria fora do catálogo não entra no contexto', () {
      final c = ctx(
        coverage: [
          cov(Area.mathematics, 'Matemática', saved: 2),
          cov(Area.mathematics, 'meu caderno secreto', saved: 9),
          cov(Area.naturalSciences, 'Matemática', saved: 1),
        ],
      );
      expect(c.coverage.length, 1);
      final text = jsonEncode(c.toJson());
      expect(text.contains('secreto'), isFalse);
    });

    test('R5: limites diferentes sempre dão plano válido e não vazio', () {
      for (final maxDays in [1, 2, 3, 5, 7, 14]) {
        for (final gap in [1, 2, 3]) {
          for (final maxSteps in [1, 2, 3]) {
            final limits = DirectionLimits(
              maxSteps: maxSteps,
              minDaysBetweenDeadlines: gap,
              maxDaysAhead: maxDays,
            );
            final steps = planDirection(
              DirectionContext(
                today: DateTime(2026, 11, 30),
                goal: const GoalSummary(exam: ExamTarget.enem, weeklyHours: 3),
                coverage: const [],
                limits: limits,
              ),
            );
            expect(steps, isNotEmpty, reason: '$maxDays/$gap/$maxSteps');
            expect(steps.length, lessThanOrEqualTo(maxSteps));
            expect(
              validateProposal(steps, limits: limits).isValid,
              isTrue,
              reason: '$maxDays/$gap/$maxSteps',
            );
          }
        }
      }
    });

    test(
      'R6: justificativa de practice nunca afirma ser a de menos questões',
      () {
        final coverage = [
          for (final s in Area.naturalSciences.subjects)
            cov(Area.naturalSciences, s, saved: 20, last14: 3, lists: 1),
        ];
        final steps = planDirection(
          ctx(coverage: coverage, focus: [Area.naturalSciences]),
        );
        final practice = steps.where((s) => s.action == StepAction.practice);
        expect(practice, isNotEmpty);
        for (final s in practice) {
          expect(s.rationale.contains('menos questões'), isFalse);
        }
      },
    );
  });

  group('StudyStep.fromProposed', () {
    test('prazo é o fim do dia de hoje + dias', () {
      final step = StudyStep.fromProposed(
        const ProposedStep(
          action: StepAction.collect,
          area: Area.mathematics,
          subject: 'Matemática',
          targetCount: 10,
          dueInDays: 3,
          rationale: 'x',
        ),
        id: 'a',
        today: DateTime(2026, 11, 30, 10),
        source: StepSource.rules,
        createdAt: DateTime(2026, 11, 30, 10),
      );
      expect(step.dueAt.year, 2026);
      expect(step.dueAt.month, 12);
      expect(step.dueAt.day, 3);
      expect(step.dueAt.hour, 23);
      expect(step.status, StepStatus.proposed);
      expect(StepSource.rules.label, 'Proposta automática');
    });
  });
}
