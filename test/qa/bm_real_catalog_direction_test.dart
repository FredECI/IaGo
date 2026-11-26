import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';

/// Probe de QA: Direciona com o acervo REAL (asset), como na demo do build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('etapa simulada ganha sugestão com o acervo real', () async {
    final now = DateTime(2026, 11, 30, 12);
    final step = StudyStep(
      id: 'demo-pending-0',
      action: StepAction.buildList,
      area: Area.mathematics,
      subject: 'Matemática',
      targetCount: 10,
      dueAt: now.add(const Duration(days: 3)),
      source: StepSource.rules,
      rationale: 'x',
      createdAt: now,
    );
    final repo = MemoryDirectionRepository(
      goal: StudyGoal(
        exam: ExamTarget.enem,
        weeklyHours: 8,
        focusAreas: const [Area.mathematics],
        createdAt: now,
        updatedAt: now,
      ),
      steps: [step],
    );
    final c = ProviderContainer(
      overrides: <Override>[
        clockProvider.overrideWithValue(() => now),
        directionRepositoryProvider.overrideWithValue(repo),
        metricsRepositoryProvider.overrideWithValue(
          MemoryMetricsRepository(clock: () => now),
        ),
        questionRepositoryProvider.overrideWithValue(
          MemoryQuestionRepository(clock: () => now),
        ),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(repo.dispose);
    final sw = Stopwatch()..start();
    await c.read(directionActionsProvider).attachBankToPendingSteps();
    final s = (await repo.watchSteps().first).single;
    // ignore: avoid_print
    print(
      'ms=${sw.elapsedMilliseconds} avail=${s.bankAvailableAtProposal} ids=${s.bankIds.length}',
    );
    expect(s.bankAvailableAtProposal, greaterThan(0));
    expect(s.bankIds, isNotEmpty);
  });
}
