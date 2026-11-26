import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/direction_ai_policy.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';

final now = DateTime(2026, 11, 30, 12);

StudyGoal goal({DateTime? lastAiAt}) => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: 8,
  lastAiAt: lastAiAt,
  createdAt: now,
  updatedAt: now,
);

class _Proposer implements StepProposer {
  _Proposer({this.error, this.empty = false});
  final Object? error;
  final bool empty;
  int calls = 0;

  @override
  AiProviderInfo get provider => fakeAiProvider;

  @override
  Future<List<ProposedStep>> propose(DirectionContext context) async {
    calls++;
    if (error case final e?) throw e;
    if (empty) return const [];
    return FakeStepProposer().propose(context);
  }
}

class _EditingProposer extends _Proposer {
  _EditingProposer(this.onPropose);
  final Future<void> Function() onPropose;

  @override
  Future<List<ProposedStep>> propose(DirectionContext context) async {
    await onPropose();
    return super.propose(context);
  }
}

class _Setup {
  _Setup({required this.container, required this.repo, required this.metrics});
  final ProviderContainer container;
  final MemoryDirectionRepository repo;
  final MemoryMetricsRepository metrics;

  Future<List<StudyStep>> propose(StudyGoal g) =>
      container.read(directionActionsProvider).proposeWithRules(g);

  List<MetricEvent> events(MetricEventType t) => [
    for (final e in metrics.logged)
      if (e.type == t) e,
  ];
}

_Setup _setup({
  StepProposer? proposer,
  StudyGoal? savedGoal,
  bool member = true,
  bool aiEnabled = true,
  Object? owner = 'u1',
}) {
  final repo = MemoryDirectionRepository(goal: savedGoal ?? goal());
  final metrics = MemoryMetricsRepository(clock: () => now);
  final c = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      directionReadTimeoutProvider.overrideWithValue(
        const Duration(milliseconds: 50),
      ),
      dataOwnerProvider.overrideWithValue(owner),
      directionRepositoryProvider.overrideWithValue(repo),
      questionRepositoryProvider.overrideWithValue(
        MemoryQuestionRepository(clock: () => now),
      ),
      listRepositoryProvider.overrideWithValue(
        MemoryListRepository(clock: () => now),
      ),
      metricsRepositoryProvider.overrideWithValue(metrics),
      isMemberProvider.overrideWithValue(member),
      accessPolicyProvider.overrideWithValue(
        AccessPolicy(termsMinAge: 18, minAge: 18, aiEnabled: aiEnabled),
      ),
      aiAvailabilityProvider.overrideWith(
        (ref) async => AiAvailability.available,
      ),
      stepProposerProvider.overrideWithValue(proposer),
    ],
  );
  addTearDown(c.dispose);
  return _Setup(container: c, repo: repo, metrics: metrics);
}

String? _reason(MetricEvent e) => e.data['reason'] as String?;

void main() {
  test('IA propõe: etapas com origem "ai" e lastAiAt gravado', () async {
    final p = _Proposer();
    final s = _setup(proposer: p);
    final steps = await s.propose(goal());
    expect(steps, hasLength(3));
    expect(steps.every((e) => e.source == StepSource.ai), isTrue);
    expect(p.calls, 1);
    expect(s.repo.currentGoal!.lastAiAt, now);
    expect(
      s.events(MetricEventType.directionPlanCreated).single.data['source'],
      'ai',
    );
    expect(s.events(MetricEventType.aiFallback), isEmpty);
  });

  test(
    'lastAiAt não sobrescreve edição do objetivo feita durante a IA',
    () async {
      late MemoryDirectionRepository repo;
      final p = _EditingProposer(() async {
        await repo.saveGoal(
          StudyGoal(
            exam: ExamTarget.enem,
            weeklyHours: 20,
            createdAt: now,
            updatedAt: now,
          ),
        );
      });
      final s = _setup(proposer: p);
      repo = s.repo;
      await s.propose(goal());
      expect(s.repo.currentGoal!.weeklyHours, 20);
      expect(s.repo.currentGoal!.lastAiAt, now);
    },
  );

  test('uma proposta por semana: dentro da janela, só regras', () async {
    final p = _Proposer();
    final last = now.subtract(const Duration(days: 2));
    final s = _setup(
      proposer: p,
      savedGoal: goal(lastAiAt: last),
    );
    final steps = await s.propose(goal(lastAiAt: last));
    expect(steps.every((e) => e.source == StepSource.rules), isTrue);
    expect(p.calls, 0);
    // Não é falha: nada de ai_fallback.
    expect(s.events(MetricEventType.aiFallback), isEmpty);
    expect(s.repo.currentGoal!.lastAiAt, last);
  });

  test('passada a janela, a IA volta a propor', () async {
    final p = _Proposer();
    final last = now.subtract(aiProposalWindow + const Duration(minutes: 1));
    final s = _setup(
      proposer: p,
      savedGoal: goal(lastAiAt: last),
    );
    final steps = await s.propose(goal(lastAiAt: last));
    expect(steps.first.source, StepSource.ai);
    expect(p.calls, 1);
  });

  group('queda para as regras, sem tela de erro (CA-D5)', () {
    for (final failure in [
      AiFailure.offline,
      AiFailure.quotaExhausted,
      AiFailure.appCheckDenied,
      AiFailure.malformed,
      AiFailure.unavailable,
      AiFailure.dailyLimit,
    ]) {
      test(failure.name, () async {
        final s = _setup(proposer: _Proposer(error: AiException(failure)));
        final steps = await s.propose(goal());
        expect(steps, hasLength(3));
        expect(steps.every((e) => e.source == StepSource.rules), isTrue);
        expect(
          _reason(s.events(MetricEventType.aiFallback).single),
          failure.name,
        );
        // Falhou: o limite semanal não é gasto.
        expect(s.repo.currentGoal!.lastAiAt, isNull);
      });
    }

    test('tempo esgotado', () async {
      final s = _setup(proposer: _Proposer(error: TimeoutException('x')));
      final steps = await s.propose(goal());
      expect(steps.first.source, StepSource.rules);
      expect(_reason(s.events(MetricEventType.aiFallback).single), 'timeout');
    });

    test('erro inesperado', () async {
      final s = _setup(proposer: _Proposer(error: StateError('segredo')));
      final steps = await s.propose(goal());
      expect(steps.first.source, StepSource.rules);
      expect(_reason(s.events(MetricEventType.aiFallback).single), 'unknown');
    });

    test('proposta vazia', () async {
      final s = _setup(proposer: _Proposer(empty: true));
      final steps = await s.propose(goal());
      expect(steps, hasLength(3));
      expect(steps.first.source, StepSource.rules);
      expect(_reason(s.events(MetricEventType.aiFallback).single), 'malformed');
    });

    test(
      'IA desligada (aiEnabled=false) para membro: regras e motivo',
      () async {
        final s = _setup(proposer: null, aiEnabled: false);
        final steps = await s.propose(goal());
        expect(steps.first.source, StepSource.rules);
        expect(
          _reason(s.events(MetricEventType.aiFallback).single),
          'disabled',
        );
      },
    );
  });

  test('não membro: regras, sem chamar a IA nem registrar falha', () async {
    final p = _Proposer();
    final s = _setup(proposer: p, member: false);
    final steps = await s.propose(goal());
    expect(steps.first.source, StepSource.rules);
    expect(p.calls, 0);
    expect(s.events(MetricEventType.aiFallback), isEmpty);
  });

  test('demo: sempre regras, a IA nunca é chamada', () async {
    final p = _Proposer();
    final s = _setup(
      proposer: p,
      owner: DemoSession(startedAt: now),
    );
    final steps = await s.propose(goal());
    expect(steps.first.source, StepSource.rules);
    expect(p.calls, 0);
  });

  test('janela semanal: regra pura', () {
    expect(aiProposalAllowed(null, now), isTrue);
    expect(
      aiProposalAllowed(now.subtract(const Duration(days: 6)), now),
      isFalse,
    );
    expect(
      aiProposalAllowed(now.subtract(const Duration(days: 7)), now),
      isTrue,
    );
    // Relógio que voltou no tempo não bloqueia.
    expect(aiProposalAllowed(now.add(const Duration(days: 3)), now), isTrue);
    expect(maxAiProposalsPerWindow, 1);
  });
}
