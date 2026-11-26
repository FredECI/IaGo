import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/direction_repository.dart';
import '../../data/policy_providers.dart';
import '../../data/firebase/firestore_direction_repository.dart';
import '../../data/local/direction_demo_data.dart';
import '../../data/local/direction_memory_repository.dart';
import '../../data/providers.dart';
import '../../domain/ai_ports.dart';
import '../../domain/direction_ai_policy.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_planner.dart';
import '../../domain/direction_progress.dart';
import '../../domain/session.dart';
import '../../domain/metric_event.dart';
import '../community/community_access.dart';
import '../lists/lists_providers.dart';
import '../metrics/metrics_providers.dart';
import '../questions/questions_providers.dart';

/// Direciona do usuário atual: demo → memória com dados simulados (recriados a
/// cada entrada, sem rede); conta → Firestore.
final directionRepositoryProvider = Provider<DirectionRepository>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner case final String uid) {
    return FirestoreDirectionRepository(
      db: FirebaseFirestore.instance,
      uid: uid,
    );
  }
  final MemoryDirectionRepository repo;
  if (owner case DemoSession(:final startedAt)) {
    final data = DirectionDemoData.build(startedAt);
    repo = MemoryDirectionRepository(goal: data.goal, steps: data.steps);
  } else {
    repo = MemoryDirectionRepository();
  }
  ref.onDispose(repo.dispose);
  return repo;
});

/// `true` quando as etapas da sessão são simuladas (rótulo da CA-D10).
final directionSimulatedProvider = Provider<bool>(
  (ref) => ref.watch(dataOwnerProvider) is DemoSession,
);

final studyGoalProvider = StreamProvider<StudyGoal?>(
  (ref) => ref.watch(directionRepositoryProvider).watchGoal(),
);

final studyStepsProvider = StreamProvider<List<StudyStep>>(
  (ref) => ref.watch(directionRepositoryProvider).watchSteps(),
);

/// Etapas ainda por fazer, da mais próxima do prazo para a mais distante.
final pendingStepsProvider = Provider<List<StudyStep>>(
  (ref) => [
    for (final s in ref.watch(studyStepsProvider).value ?? const <StudyStep>[])
      if (isPending(s)) s,
  ],
);

/// Próxima etapa do card do Painel (`null` se não houver).
final nextStepProvider = Provider<StudyStep?>(
  (ref) => ref.watch(pendingStepsProvider).firstOrNull,
);

/// Comparação relativa dos últimos 14 dias contra os 14 anteriores (CA-D7).
final stepProgressProvider = Provider<StepProgress>((ref) {
  final steps = ref.watch(studyStepsProvider).value ?? const <StudyStep>[];
  return computeStepProgress(steps, ref.watch(clockProvider)());
});

/// Entrada do planejador, só com contagens por matéria do catálogo. `null`
/// sem objetivo.
final directionContextProvider = Provider<DirectionContext?>((ref) {
  final goal = ref.watch(studyGoalProvider).value;
  if (goal == null) return null;
  return buildDirectionContext(
    goal: goal,
    questions: ref.watch(questionsProvider).value ?? const [],
    lists: ref.watch(listsProvider).value ?? const [],
    steps: ref.watch(studyStepsProvider).value ?? const [],
    now: ref.watch(clockProvider)(),
  );
});

/// Espera máxima pelas leituras antes de propor (sem rede, nada trava).
final directionReadTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

final directionActionsProvider = Provider<DirectionActions>(
  DirectionActions.new,
);

/// Operações da trilha. A proposta tenta a IA (DI3) e cai nas regras.
/// Nenhuma operação lança para a tela: falha vira `false` ou lista vazia.
class DirectionActions {
  DirectionActions(this._ref);

  final Ref _ref;

  DirectionRepository get _repo => _ref.read(directionRepositoryProvider);
  DateTime get _now => _ref.read(clockProvider)();

  /// Grava o objetivo e propõe (se não houver etapa pendente em dia). `false`
  /// se a gravação do objetivo falhou.
  Future<bool> setGoal(StudyGoal goal) async {
    try {
      await _repo.saveGoal(goal);
    } catch (_) {
      return false;
    }
    await proposeWithRules(goal);
    return true;
  }

  Future<List<StudyStep>>? _inFlight;

  /// Regra "no máximo 3 pendentes por vez": marca as pendentes vencidas como
  /// perdidas; se ainda restar pendente em dia, não propõe e devolve essas
  /// etapas; senão grava as etapas propostas e devolve as criadas. Propõe pela
  /// IA quando a política, a conta e o limite semanal deixam; em qualquer
  /// outro caso, ou se a IA falhar, pelo planejador por regras (que são
  /// sempre a rede de segurança). Em qualquer caso, o resultado são as etapas pendentes agora.
  ///
  /// Chamadas simultâneas (toque duplo) compartilham a mesma execução. Se as
  /// etapas, as questões ou as listas não chegarem a tempo, não propõe e
  /// devolve vazio. Todas as escritas vão numa só operação.
  Future<List<StudyStep>> proposeWithRules(StudyGoal goal) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _propose(goal).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<List<StudyStep>> _propose(StudyGoal goal) async {
    try {
      final timeout = _ref.read(directionReadTimeoutProvider);
      final now = _now;
      // Tudo é lido antes de qualquer escrita: "carregando" nunca vira "vazio".
      final current = await _repo.watchSteps().first.timeout(timeout);
      final questions = await _ref
          .read(questionRepositoryProvider)
          .watchAll()
          .first
          .timeout(timeout);
      final lists = await _ref
          .read(listRepositoryProvider)
          .watchAll()
          .first
          .timeout(timeout);

      final updated = <StudyStep>[];
      final changed = <StudyStep>[];
      for (final s in current) {
        if (isOverdue(s, now)) {
          final missed = markMissed(s);
          changed.add(missed);
          updated.add(missed);
        } else {
          updated.add(s);
        }
      }
      final pending = updated.where(isPending).toList();
      if (pending.isNotEmpty) {
        if (changed.isNotEmpty) {
          await _repo.updateSteps(changed);
          _logMissed(changed);
        }
        return pending;
      }

      final context = buildDirectionContext(
        goal: goal,
        questions: questions,
        lists: lists,
        steps: updated,
        now: now,
      );
      final today = DateTime(now.year, now.month, now.day);
      // IA se puder; qualquer falha, resposta inválida ou lista vazia cai nas
      // regras (CA-D4 e CA-D5): nunca vira erro para a tela.
      final byAi = await _proposeWithAi(goal, context, now);
      final source = byAi == null ? StepSource.rules : StepSource.ai;
      final created = [
        for (final p in byAi ?? planDirection(context))
          StudyStep.fromProposed(
            p,
            id: newId(),
            today: today,
            source: source,
            createdAt: now,
          ),
      ];
      // Uma escrita só: as vencidas como perdidas e as etapas novas.
      await _repo.updateSteps([...changed, ...created]);
      _logMissed(changed);
      if (created.isNotEmpty) {
        _ref.read(metricsLoggerProvider).log(
          MetricEventType.directionPlanCreated,
          {'source': source.name},
        );
        if (source == StepSource.ai) await _markAiProposal(now);
      }
      return created;
    } catch (_) {
      return const [];
    }
  }

  /// Tenta a proposta pela IA. `null` = usar as regras. Só conta real, membro,
  /// com a IA disponível pela `AccessPolicy` e sem proposta da IA dentro da
  /// janela de [aiProposalWindow]. A demo vai sempre pelas regras (spec,
  /// "Modo demo"). Nunca lança.
  ///
  /// A checagem da IA e a proposta dividem o mesmo limite de
  /// [aiProposalTimeout]. Falha ou tempo esgotado consomem a cota diária
  /// (`aiDailyPerUser`), mas não a semanal: `lastAiAt` só grava com sucesso.
  Future<List<ProposedStep>?> _proposeWithAi(
    StudyGoal studyGoal,
    DirectionContext context,
    DateTime now,
  ) async {
    try {
      if (_ref.read(dataOwnerProvider) is! String) return null;
      if (!aiProposalAllowed(studyGoal.lastAiAt, now)) return null;
      if (!_ref.read(isMemberProvider)) return null;
      return await _attemptAi(context).timeout(aiProposalTimeout);
    } on TimeoutException {
      _logFallback(AiFailure.timeout);
    } catch (_) {
      _logFallback(AiFailure.unknown);
    }
    return null;
  }

  Future<List<ProposedStep>?> _attemptAi(DirectionContext context) async {
    await _settleAvailability();
    final policy = _ref.read(accessPolicyProvider);
    final proposer = _ref.read(stepProposerProvider);
    if (proposer == null ||
        !policy.canUseAi(isMember: true, provider: proposer.provider)) {
      _logFallback(
        policy.aiEnabled
            ? aiUnavailableReason(_ref.read(aiAvailabilityProvider))
            : AiFailure.disabled,
      );
      return null;
    }
    try {
      final steps = await proposer.propose(context);
      if (steps.isEmpty) {
        _logFallback(AiFailure.malformed);
        return null;
      }
      return steps;
    } on AiException catch (e) {
      _logFallback(e.failure);
    }
    return null;
  }

  /// Espera a checagem da IA terminar. Carregando: só espera. Falha ou
  /// indisponível (pode ser passageiro, como o App Check): refaz uma vez.
  Future<void> _settleAvailability() async {
    final current = _ref.read(aiAvailabilityProvider);
    if (!current.isLoading && aiAvailabilityNeedsRetry(current)) {
      _ref.invalidate(aiAvailabilityProvider);
    }
    try {
      await _ref.read(aiAvailabilityProvider.future);
    } catch (_) {
      // O erro fica no provider: o proposer sai nulo e cai nas regras.
    }
  }

  void _logFallback(AiFailure reason) => _ref.read(metricsLoggerProvider).log(
    MetricEventType.aiFallback,
    {'feature': 'direction', 'reason': reason.name},
  );

  /// Guarda o dia da proposta pela IA no objetivo (limite semanal). Relê o
  /// objetivo atual, para não sobrescrever uma edição feita durante a espera
  /// pela IA. Falha aqui só deixa a IA propor de novo mais cedo; não desfaz as
  /// etapas, mas fica no log de depuração.
  Future<void> _markAiProposal(DateTime now) async {
    try {
      final current = await _repo.watchGoal().first.timeout(
        _ref.read(directionReadTimeoutProvider),
      );
      if (current == null) return;
      await _repo.saveGoal(
        StudyGoal(
          exam: current.exam,
          targetDate: current.targetDate,
          weeklyHours: current.weeklyHours,
          focusAreas: current.focusAreas,
          lastAiAt: now,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      );
    } catch (e) {
      debugPrint('Direciona: não gravou lastAiAt (${e.runtimeType})');
    }
  }

  /// `true` se gravou.
  Future<bool> accept(StudyStep step) => _write(acceptStep(step));

  /// Conclui a etapa. Registra se foi no prazo (H5), sem conteúdo.
  Future<bool> complete(StudyStep step) async {
    final now = _now;
    final wasDone = step.status == StepStatus.done;
    final ok = await _write(completeStep(step, now));
    if (ok && !wasDone) {
      _ref.read(metricsLoggerProvider).log(MetricEventType.directionStepDone, {
        'onTime': !now.isAfter(step.dueAt),
        'source': step.source.name,
        'action': step.action.name,
      });
    }
    return ok;
  }

  void _logMissed(Iterable<StudyStep> missed) {
    for (final s in missed) {
      _ref.read(metricsLoggerProvider).log(
        MetricEventType.directionStepMissed,
        {'source': s.source.name, 'action': s.action.name},
      );
    }
  }

  /// `false` se já foi adiada antes (CA-D8) ou se a gravação falhou.
  Future<bool> postpone(StudyStep step) async {
    final next = postponeStep(step, _now);
    return next != null && await _write(next);
  }

  Future<bool> _write(StudyStep step) async {
    try {
      await _repo.updateStep(step);
      return true;
    } catch (_) {
      return false;
    }
  }
}
