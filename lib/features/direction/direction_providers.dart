import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/direction_repository.dart';
import '../../data/firebase/firestore_direction_repository.dart';
import '../../data/local/direction_demo_data.dart';
import '../../data/local/direction_memory_repository.dart';
import '../../data/providers.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_planner.dart';
import '../../domain/direction_progress.dart';
import '../../domain/session.dart';
import '../lists/lists_providers.dart';
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

/// Operações da trilha. A proposta pela IA entra na DI3; aqui só as regras.
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
  /// etapas; senão grava as etapas do planejador por regras e devolve as
  /// criadas. Em qualquer caso, o resultado são as etapas pendentes agora.
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
        if (changed.isNotEmpty) await _repo.updateSteps(changed);
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
      final created = [
        for (final p in planDirection(context))
          StudyStep.fromProposed(
            p,
            id: newId(),
            today: today,
            source: StepSource.rules,
            createdAt: now,
          ),
      ];
      // Uma escrita só: as vencidas como perdidas e as etapas novas.
      await _repo.updateSteps([...changed, ...created]);
      return created;
    } catch (_) {
      return const [];
    }
  }

  /// `true` se gravou.
  Future<bool> accept(StudyStep step) => _write(acceptStep(step));

  Future<bool> complete(StudyStep step) => _write(completeStep(step, _now));

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
