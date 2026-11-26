import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/direction_repository.dart';
import 'package:iago/data/firebase/firestore_direction_repository.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/data/repositories.dart';
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
  status: StepStatus.accepted,
  source: StepSource.rules,
  rationale: 'x',
  createdAt: now,
);

/// Conta as escritas e pode travar a leitura das etapas.
class _Spy implements DirectionRepository {
  _Spy(this.inner, {this.hangRead = false});
  final MemoryDirectionRepository inner;
  final bool hangRead;
  int updateStepCalls = 0, updateStepsCalls = 0, addStepsCalls = 0;

  @override
  Stream<StudyGoal?> watchGoal() => inner.watchGoal();
  @override
  Stream<List<StudyStep>> watchSteps() => hangRead
      ? StreamController<List<StudyStep>>().stream
      : inner.watchSteps();
  @override
  Future<void> saveGoal(StudyGoal goal) => inner.saveGoal(goal);
  @override
  Future<void> addSteps(List<StudyStep> steps) {
    addStepsCalls++;
    return inner.addSteps(steps);
  }

  @override
  Future<void> updateStep(StudyStep step) {
    updateStepCalls++;
    return inner.updateStep(step);
  }

  @override
  Future<void> updateSteps(List<StudyStep> steps) {
    updateStepsCalls++;
    return inner.updateSteps(steps);
  }
}

/// Questões que nunca terminam de carregar.
class _NeverQuestions implements QuestionRepository {
  @override
  Stream<List<Never>> watchAll() => StreamController<List<Never>>().stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer make(
  DirectionRepository repo, [
  List<Override> extra = const [],
]) {
  final c = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      directionReadTimeoutProvider.overrideWithValue(
        const Duration(milliseconds: 50),
      ),
      directionRepositoryProvider.overrideWithValue(repo),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Map<String, Object?> validStep() => {
  'action': 'collect',
  'area': 'mathematics',
  'subject': 'Matemática',
  'targetCount': 5,
  'dueAt': now,
  'status': 'accepted',
  'source': 'rules',
  'rationale': 'x',
  'createdAt': now,
};

void main() {
  test(
    '1. leitura das etapas sem resposta: não propõe e devolve vazio',
    () async {
      final repo = _Spy(MemoryDirectionRepository(), hangRead: true);
      final c = make(repo);
      final result = await c
          .read(directionActionsProvider)
          .proposeWithRules(goal());
      expect(result, isEmpty);
      expect(
        repo.addStepsCalls + repo.updateStepsCalls + repo.updateStepCalls,
        0,
      );
    },
  );

  test('2. vencidas e novas vão numa escrita só', () async {
    final repo = _Spy(
      MemoryDirectionRepository(
        steps: [
          step('v1', now.subtract(const Duration(days: 2))),
          step('v2', now.subtract(const Duration(days: 3))),
        ],
      ),
    );
    final c = make(repo);
    final result = await c
        .read(directionActionsProvider)
        .proposeWithRules(goal());
    expect(result, hasLength(3));
    expect(repo.updateStepsCalls, 1);
    expect(repo.updateStepCalls + repo.addStepsCalls, 0);
    final byId = {for (final s in repo.inner.currentSteps) s.id: s};
    expect(byId['v1']!.status, StepStatus.missed);
    expect(byId['v2']!.status, StepStatus.missed);
    expect(repo.inner.currentSteps.where(isPending), hasLength(3));
  });

  test(
    '3. questões ainda carregando: não grava etapas nem marca perdidas',
    () async {
      final repo = _Spy(
        MemoryDirectionRepository(
          steps: [step('v1', now.subtract(const Duration(days: 2)))],
        ),
      );
      final c = make(repo, [
        questionRepositoryProvider.overrideWithValue(_NeverQuestions()),
      ]);
      final result = await c
          .read(directionActionsProvider)
          .proposeWithRules(goal());
      expect(result, isEmpty);
      expect(
        repo.updateStepsCalls + repo.addStepsCalls + repo.updateStepCalls,
        0,
      );
      expect(repo.inner.currentSteps.single.status, StepStatus.accepted);
    },
  );

  test('4. toque duplo simultâneo grava um só conjunto de etapas', () async {
    final repo = _Spy(MemoryDirectionRepository());
    final c = make(repo);
    final actions = c.read(directionActionsProvider);
    final a = actions.proposeWithRules(goal());
    final b = actions.proposeWithRules(goal());
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    expect(repo.inner.currentSteps, hasLength(3));
    expect(repo.updateStepsCalls, 1);
    // Terminada a execução, uma nova chamada volta a funcionar (sem duplicar).
    final again = await actions.proposeWithRules(goal());
    expect(again, hasLength(3));
    expect(repo.inner.currentSteps, hasLength(3));
  });

  group('5. stepFromMap', () {
    test('aceita targetCount de 1 em diante', () {
      expect(stepFromMap('a', {...validStep(), 'targetCount': 31}), isNotNull);
      expect(stepFromMap('a', {...validStep(), 'targetCount': 1}), isNotNull);
      expect(stepFromMap('a', {...validStep(), 'targetCount': 0}), isNull);
    });

    test('descarta matéria que não pertence à área', () {
      expect(stepFromMap('a', {...validStep(), 'subject': 'Física'}), isNull);
      expect(
        stepFromMap('a', {...validStep(), 'subject': 'Astrologia'}),
        isNull,
      );
    });
  });
}
