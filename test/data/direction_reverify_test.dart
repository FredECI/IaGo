import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/direction_repository.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_planner.dart';
import 'package:iago/domain/direction_progress.dart';
import 'package:iago/domain/direction_tuning.dart';
import 'package:iago/domain/direction_validation.dart';
import 'package:iago/features/direction/direction_providers.dart';

final now = DateTime(2026, 11, 30, 12);

StudyGoal goal({List<Area> focus = const [], int hours = 6}) => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: hours,
  focusAreas: focus,
  createdAt: now,
  updatedAt: now,
);

StudyStep step(
  String id,
  DateTime due,
  StepStatus status, {
  DateTime? doneAt,
}) => StudyStep(
  id: id,
  action: StepAction.collect,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: due,
  status: status,
  doneAt: doneAt,
  source: StepSource.rules,
  rationale: 'x',
  createdAt: now,
);

DirectionContext ctx({
  List<SubjectCoverage> coverage = const [],
  int hours = 6,
  List<Area> focus = const [],
  DirectionLimits limits = const DirectionLimits(),
}) => DirectionContext(
  today: now,
  goal: GoalSummary(
    exam: ExamTarget.enem,
    weeklyHours: hours,
    focusAreas: focus,
  ),
  coverage: coverage,
  limits: limits,
);

/// Repositório que falha em toda escrita.
class _Failing implements DirectionRepository {
  _Failing(this.inner);
  final MemoryDirectionRepository inner;
  @override
  Stream<StudyGoal?> watchGoal() => inner.watchGoal();
  @override
  Stream<List<StudyStep>> watchSteps() => inner.watchSteps();
  @override
  Future<void> saveGoal(StudyGoal goal) => Future.error(StateError('rede'));
  @override
  Future<void> addSteps(List<StudyStep> steps) =>
      Future.error(StateError('rede'));
  @override
  Future<void> updateStep(StudyStep step) => Future.error(StateError('rede'));
  @override
  Future<void> updateSteps(List<StudyStep> steps) =>
      Future.error(StateError('rede'));
}

(ProviderContainer, MemoryDirectionRepository) env([
  Iterable<StudyStep> steps = const [],
]) {
  final repo = MemoryDirectionRepository(steps: steps);
  final c = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      directionRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return (c, repo);
}

void main() {
  group('PlannerTuning', () {
    test('padrão explícito gera plano idêntico ao implícito', () {
      for (final hours in [1, 3, 6, 10, 40]) {
        final c = ctx(hours: hours, focus: [Area.naturalSciences]);
        expect(
          jsonEncode([
            for (final s in planDirection(c, tuning: const PlannerTuning()))
              s.toJson(),
          ]),
          jsonEncode([for (final s in planDirection(c)) s.toJson()]),
        );
      }
    });

    test('plano fixado: conta vazia, ENEM, 6 h, foco em Matemática', () {
      final plan = planDirection(ctx(focus: [Area.mathematics]));
      expect(plan, hasLength(3));
      expect(plan.first.subject, 'Matemática');
      expect(plan.first.action, StepAction.collect);
      expect(plan.first.targetCount, 10);
      expect(plan.every((s) => s.action == StepAction.collect), isTrue);
      expect(
        plan.map((s) => s.dueInDays).toList(),
        orderedEquals([...plan.map((s) => s.dueInDays)]..sort()),
      );
    });

    test('padrões documentados', () {
      const t = PlannerTuning();
      expect(
        (t.minQuestionsPerSubject, t.minCollectTarget, t.maxCollectTarget),
        (10, 5, 10),
      );
      expect((t.minDays, t.maxDays, t.dailyShareDivisor), (2, 7, 3));
      expect(directionWindowDays, 14);
    });

    test('valores extremos de tuning continuam gerando plano válido', () {
      final tunings = [
        const PlannerTuning(minDays: 1, maxDays: 1),
        const PlannerTuning(minDays: 10, maxDays: 14),
        const PlannerTuning(maxCollectTarget: 30, minCollectTarget: 30),
        const PlannerTuning(minQuestionsPerSubject: 0),
        const PlannerTuning(minQuestionsPerSubject: 1000),
        const PlannerTuning(practiceTarget: 30, buildListTarget: 1),
        const PlannerTuning(dailyShareDivisor: 1),
        const PlannerTuning(minutesPerCollect: 1, minutesPerPractice: 1),
        const PlannerTuning(minutesPerCollect: 60, minutesPerReview: 60),
      ];
      final coverages = [
        const <SubjectCoverage>[],
        [
          const SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 50,
            savedLast14d: 5,
            listsExportedLast14d: 1,
          ),
        ],
      ];
      for (final t in tunings) {
        for (final hours in [1, 6, 40]) {
          for (final cov in coverages) {
            final c = ctx(hours: hours, coverage: cov);
            final plan = planDirection(c, tuning: t);
            final v = validateProposalFor(c, plan);
            expect(v.isValid, isTrue, reason: '${v.violations} hours=$hours');
          }
        }
      }
    });

    test('limites apertados do contexto também são respeitados', () {
      final c = ctx(
        limits: const DirectionLimits(
          maxSteps: 2,
          maxDaysAhead: 5,
          minDaysBetweenDeadlines: 3,
        ),
      );
      final plan = planDirection(c);
      expect(plan.length, lessThanOrEqualTo(2));
      expect(validateProposalFor(c, plan).isValid, isTrue);
    });

    test('validateProposalFor usa os limites do contexto, não o padrão', () {
      final c = ctx(limits: const DirectionLimits(maxSteps: 1));
      final plan = [
        for (var i = 0; i < 2; i++)
          ProposedStep(
            action: StepAction.collect,
            area: Area.mathematics,
            subject: i == 0 ? 'Matemática' : 'Matemática',
            targetCount: 5,
            dueInDays: 2 + 3 * i,
            rationale: 'r',
          ),
      ];
      expect(validateProposalFor(c, plan).isValid, isFalse);
      expect(
        validateProposalJsonFor(c, [for (final p in plan) p.toJson()]).isValid,
        isFalse,
      );
    });
  });

  group('cobertura duplicada no DirectionContext', () {
    test('matéria repetida soma as contagens', () {
      final c = ctx(
        coverage: const [
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 3,
            savedLast14d: 1,
            listsExportedLast14d: 1,
          ),
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 4,
            savedLast14d: 2,
            listsExportedLast14d: 0,
          ),
        ],
      );
      final m = c.coverage.single;
      expect((m.saved, m.savedLast14d, m.listsExportedLast14d), (7, 3, 1));
    });

    test('duplicada misturada com fora do catálogo: só a do catálogo fica', () {
      final c = ctx(
        coverage: const [
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 1,
          ),
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Astrologia',
            saved: 99,
          ),
          SubjectCoverage(
            area: Area.naturalSciences,
            subject: 'Matemática',
            saved: 99,
          ),
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 2,
          ),
        ],
      );
      expect(c.coverage, hasLength(1));
      expect(c.coverage.single.saved, 3);
      expect(jsonEncode(c.toJson()).contains('Astrologia'), isFalse);
    });

    test('mesma matéria em áreas diferentes não se mistura', () {
      // Nomes iguais só em áreas distintas, se existirem; senão, controle.
      final c = ctx(
        coverage: [
          for (final a in Area.values)
            for (final s in a.subjects)
              SubjectCoverage(area: a, subject: s, saved: 1),
          for (final a in Area.values)
            for (final s in a.subjects)
              SubjectCoverage(area: a, subject: s, saved: 1),
        ],
      );
      expect(c.coverage.every((x) => x.saved == 2), isTrue);
      expect(
        c.coverage.length,
        Area.values.fold<int>(0, (n, a) => n + a.subjects.length),
      );
    });

    test('lista vazia de cobertura continua válida para o planejador', () {
      final c = ctx();
      expect(validateProposalFor(c, planDirection(c)).isValid, isTrue);
    });
  });

  group('proposeWithRules', () {
    test('vencida + em dia: marca a vencida e não propõe', () async {
      final (c, repo) = env([
        step(
          'vencida',
          now.subtract(const Duration(days: 1)),
          StepStatus.accepted,
        ),
        step('em-dia', now.add(const Duration(days: 1)), StepStatus.proposed),
      ]);
      final r = await c.read(directionActionsProvider).proposeWithRules(goal());
      expect([for (final s in r) s.id], ['em-dia']);
      expect(repo.currentSteps, hasLength(2));
      expect(
        repo.currentSteps.firstWhere((s) => s.id == 'vencida').status,
        StepStatus.missed,
      );
    });

    test('só concluída em dia não é pendente: propõe 3 novas', () async {
      final (c, repo) = env([
        step(
          'feita',
          now.add(const Duration(days: 2)),
          StepStatus.done,
          doneAt: now,
        ),
      ]);
      final r = await c.read(directionActionsProvider).proposeWithRules(goal());
      expect(r, hasLength(3));
      expect(repo.currentSteps.where(isPending), hasLength(3));
      expect(repo.currentSteps.where((s) => s.id == 'feita'), hasLength(1));
    });

    test('só vencida: vira missed e propõe 3 novas', () async {
      final (c, repo) = env([
        step('v', now.subtract(const Duration(days: 3)), StepStatus.proposed),
      ]);
      final r = await c.read(directionActionsProvider).proposeWithRules(goal());
      expect(r, hasLength(3));
      expect(
        repo.currentSteps.firstWhere((s) => s.id == 'v').status,
        StepStatus.missed,
      );
    });

    test(
      'etapa já perdida em dia (status incoerente) não segura a proposta',
      () async {
        final (c, _) = env([
          step('m', now.add(const Duration(days: 3)), StepStatus.missed),
        ]);
        expect(
          await c.read(directionActionsProvider).proposeWithRules(goal()),
          hasLength(3),
        );
      },
    );

    test('regressão: prazo exatamente agora é vencida em computeStepProgress mas não em isOverdue', () async {
      final (c, repo) = env([step('agora', now, StepStatus.accepted)]);
      await c.read(directionActionsProvider).proposeWithRules(goal());
      expect(
        repo.currentSteps.firstWhere((s) => s.id == 'agora').status,
        StepStatus.missed,
      );
    });

    test('proposta nova tem ids únicos e prazos válidos para a spec', () async {
      final (c, _) = env();
      final r = await c.read(directionActionsProvider).proposeWithRules(goal());
      expect({for (final s in r) s.id}, hasLength(3));
      final days = [
        for (final s in r)
          DateTime(
            s.dueAt.year,
            s.dueAt.month,
            s.dueAt.day,
          ).difference(DateTime(now.year, now.month, now.day)).inDays,
      ];
      final plan = [
        for (var i = 0; i < r.length; i++)
          ProposedStep(
            action: r[i].action,
            area: r[i].area,
            subject: r[i].subject,
            targetCount: r[i].targetCount,
            dueInDays: days[i],
            rationale: r[i].rationale,
          ),
      ];
      expect(validateProposalFor(ctx(), plan).isValid, isTrue);
    });

    test('falha de escrita devolve lista vazia sem lançar', () async {
      final inner = MemoryDirectionRepository();
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          directionRepositoryProvider.overrideWithValue(_Failing(inner)),
        ],
      );
      addTearDown(c.dispose);
      final actions = c.read(directionActionsProvider);
      expect(await actions.proposeWithRules(goal()), isEmpty);
    });

    test(
      'regressão: setGoal com gravação do objetivo falha lança para a tela',
      () async {
        // As demais ações capturam exceção; setGoal (saveGoal) não. Devia
        // completar sem lançar, como o restante de DirectionActions.
        final c = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            directionRepositoryProvider.overrideWithValue(
              _Failing(MemoryDirectionRepository()),
            ),
          ],
        );
        addTearDown(c.dispose);
        await expectLater(
          c.read(directionActionsProvider).setGoal(goal()),
          completes,
        );
      },
    );
  });

  group('ações com falha devolvem false', () {
    test('accept, complete e postpone', () async {
      final s = step(
        'a',
        now.add(const Duration(days: 2)),
        StepStatus.proposed,
      );
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          directionRepositoryProvider.overrideWithValue(
            _Failing(MemoryDirectionRepository(steps: [s])),
          ),
        ],
      );
      addTearDown(c.dispose);
      final a = c.read(directionActionsProvider);
      expect(await a.accept(s), isFalse);
      expect(await a.complete(s), isFalse);
      expect(await a.postpone(s), isFalse);
    });

    test(
      'sucesso devolve true e postpone da 2ª vez devolve false sem gravar',
      () async {
        final s = step(
          'a',
          now.add(const Duration(days: 2)),
          StepStatus.accepted,
        );
        final (c, repo) = env([s]);
        final a = c.read(directionActionsProvider);
        expect(await a.postpone(s), isTrue);
        final once = repo.currentSteps.single;
        expect(await a.postpone(once), isFalse);
        expect(repo.currentSteps.single.dueAt, once.dueAt);
        expect(await a.accept(once), isTrue);
        expect(await a.complete(once), isTrue);
      },
    );

    test('postpone de etapa concluída devolve false', () async {
      final s = step('a', now, StepStatus.done, doneAt: now);
      final (c, _) = env([s]);
      expect(await c.read(directionActionsProvider).postpone(s), isFalse);
    });
  });
}
