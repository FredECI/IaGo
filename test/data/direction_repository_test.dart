import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/local/direction_demo_data.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_progress.dart';
import 'package:iago/features/direction/direction_providers.dart';

final now = DateTime(2026, 11, 30, 12);

StudyGoal goal() => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: 8,
  createdAt: now,
  updatedAt: now,
);

StudyStep step(String id, DateTime due) => StudyStep(
  id: id,
  action: StepAction.collect,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: due,
  source: StepSource.rules,
  rationale: 'x',
  createdAt: now,
);

void main() {
  group('MemoryDirectionRepository', () {
    test('começa sem objetivo e grava o objetivo', () async {
      final repo = MemoryDirectionRepository();
      expect(await repo.watchGoal().first, isNull);
      await repo.saveGoal(goal());
      expect((await repo.watchGoal().first)!.weeklyHours, 8);
      await repo.dispose();
    });

    test('grava etapas ordenadas pelo prazo e concluir atualiza', () async {
      final repo = MemoryDirectionRepository();
      await repo.addSteps([
        step('b', DateTime(2026, 12, 5)),
        step('a', DateTime(2026, 12, 2)),
      ]);
      var steps = await repo.watchSteps().first;
      expect([for (final s in steps) s.id], ['a', 'b']);

      await repo.updateStep(completeStep(steps.first, now));
      steps = await repo.watchSteps().first;
      expect(steps.first.status, StepStatus.done);
      expect(steps.first.doneAt, now);
      await repo.dispose();
    });

    test('adiar uma vez funciona e a segunda é negada', () async {
      final repo = MemoryDirectionRepository(
        steps: [step('a', DateTime(2026, 12, 2, 23, 59, 59, 999))],
      );
      final s = repo.currentSteps.single;
      final once = postponeStep(s, now)!;
      await repo.updateStep(once);
      expect(repo.currentSteps.single.dueAt.day, 4);
      expect(postponeStep(repo.currentSteps.single, now), isNull);
      await repo.dispose();
    });

    test(
      'atualizar etapa inexistente cria a etapa (upsert, como o Firestore)',
      () async {
        final repo = MemoryDirectionRepository();
        await repo.updateStep(step('x', now));
        expect(repo.currentSteps.single.id, 'x');
        await repo.dispose();
      },
    );
  });

  group('demo', () {
    test('dados simulados: 3 de 4 e 1 de 3, mais 3 etapas pendentes', () {
      final data = DirectionDemoData.build(now);
      final p = computeStepProgress(data.steps, now);
      expect(
        (p.doneRecent, p.totalRecent, p.donePrevious, p.totalPrevious),
        (3, 4, 1, 3),
      );
      final pending = data.steps.where(isPending).toList();
      expect(pending, hasLength(3));
      for (final s in pending) {
        expect(s.area.subjects, contains(s.subject));
        expect(s.dueAt.isAfter(now), isTrue);
      }
    });

    test('DemoSession traz objetivo e etapas sem rede, e é simulada', () async {
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).enterDemo();
      expect(container.read(directionSimulatedProvider), isTrue);
      final repo = container.read(directionRepositoryProvider);
      expect(await repo.watchGoal().first, isNotNull);
      expect(await repo.watchSteps().first, isNotEmpty);
    });

    test('ações: concluir e adiar pelo provider', () async {
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).enterDemo();
      final actions = container.read(directionActionsProvider);
      final repo = container.read(directionRepositoryProvider);
      final pending = (await repo.watchSteps().first).where(isPending).toList();

      expect(await actions.postpone(pending.first), isTrue);
      final postponed = (await repo.watchSteps().first).firstWhere(
        (s) => s.id == pending.first.id,
      );
      expect(await actions.postpone(postponed), isFalse);

      await actions.complete(postponed);
      final done = (await repo.watchSteps().first).firstWhere(
        (s) => s.id == pending.first.id,
      );
      expect(done.status, StepStatus.done);
    });

    test(
      'definir objetivo em conta nova propõe 3 etapas pelas regras',
      () async {
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            directionRepositoryProvider.overrideWithValue(
              MemoryDirectionRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(directionActionsProvider).setGoal(goal());
        final repo = container.read(directionRepositoryProvider);
        final steps = await repo.watchSteps().first;
        expect(steps, hasLength(3));
        expect(steps.every((s) => s.source == StepSource.rules), isTrue);
        // Com etapas pendentes em dia, definir de novo não duplica.
        await container.read(directionActionsProvider).setGoal(goal());
        expect(await repo.watchSteps().first, hasLength(3));
      },
    );
  });
}
