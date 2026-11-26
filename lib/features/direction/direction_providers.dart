import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../data/bank_catalog.dart';
import '../../data/direction_repository.dart';
import '../../data/policy_providers.dart';
import '../../data/firebase/firestore_direction_repository.dart';
import '../../data/local/direction_demo_data.dart';
import '../../data/local/direction_memory_repository.dart';
import '../../data/providers.dart';
import '../../domain/ai_ports.dart';
import '../../domain/direction_ai_policy.dart';
import '../../domain/bank_summary.dart';
import '../../domain/direction_bank.dart';
import '../../domain/direction_models.dart';
import '../../domain/question.dart';
import '../../domain/question_filter.dart';
import '../../domain/direction_planner.dart';
import '../../domain/direction_progress.dart';
import '../../domain/session.dart';
import '../../domain/metric_event.dart';
import '../bank/bank_providers.dart';
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

/// Espera máxima pelo resumo do acervo (só o índice). Estourou: sem acervo.
const Duration bankSummaryTimeout = Duration(seconds: 2);

/// Espera máxima, no total, pelas sugestões de lista. Estourou: etapas sem
/// sugestão (a proposta nunca falha por causa do acervo).
const Duration bankSuggestionTimeout = Duration(seconds: 2);

/// Candidatas lidas do acervo por matéria (a maior tem menos de 300).
const int maxSuggestionPool = 500;

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

      final base = buildDirectionContext(
        goal: goal,
        questions: questions,
        lists: lists,
        steps: updated,
        now: now,
      );
      // Acervo: resumo com timeout; sem ele (ou com o interruptor desligado)
      // o contexto fica como no MVP.
      final summary = await _loadBankSummary();
      final context = summary == null
          ? base
          : _withBank(base, summary, questions);
      final today = DateTime(now.year, now.month, now.day);
      // IA se puder; qualquer falha, resposta inválida ou lista vazia cai nas
      // regras (CA-D4 e CA-D5): nunca vira erro para a tela.
      final byAi = await _proposeWithAi(goal, context, now);
      final source = byAi == null ? StepSource.rules : StepSource.ai;
      var created = [
        for (final p in byAi ?? planDirection(context))
          StudyStep.fromProposed(
            p,
            id: newId(),
            today: today,
            source: source,
            createdAt: now,
          ),
      ];
      if (summary != null) {
        created = await _attachBank(created, context, summary, questions);
      }
      // Uma escrita só: as vencidas como perdidas e as etapas novas.
      await _repo.updateSteps([...changed, ...created]);
      _logMissed(changed);
      if (created.isNotEmpty) {
        _ref.read(metricsLoggerProvider).log(
          MetricEventType.directionPlanCreated,
          {
            'source': source.name,
            if (summary != null) ...{
              'bankSuggestedSteps': created
                  .where((s) => s.bankIds.isNotEmpty)
                  .length,
              'catalogGeneratedAt': summary.generatedAt,
            },
          },
        );
        if (source == StepSource.ai) await _markAiProposal(now);
      }
      return created;
    } catch (_) {
      return const [];
    }
  }

  /// Etapas simuladas da demo nascem sem acervo (os dados são montados de
  /// forma síncrona). Esta chamada anexa a sugestão às pendentes que ainda não
  /// têm `bankAvailableAtProposal`, sem mudar matéria, ação nem prazo. Idempotente
  /// e nunca lança.
  Future<void> attachBankToPendingSteps() async {
    try {
      final timeout = _ref.read(directionReadTimeoutProvider);
      final goal = await _repo.watchGoal().first.timeout(timeout);
      if (goal == null) return;
      final steps = await _repo.watchSteps().first.timeout(timeout);
      final todo = [
        for (final s in steps)
          if (isPending(s) && s.bankAvailableAtProposal == null) s,
      ];
      if (todo.isEmpty) return;
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
      final summary = await _loadBankSummary();
      if (summary == null) return;
      final context = _withBank(
        buildDirectionContext(
          goal: goal,
          questions: questions,
          lists: lists,
          steps: steps,
          now: _now,
        ),
        summary,
        questions,
      );
      final enriched = await _attachBank(todo, context, summary, questions);
      await _repo.updateSteps(enriched);
    } catch (_) {
      // O acervo nunca atrapalha o Direciona.
    }
  }

  /// Resumo do acervo, ou `null` se o interruptor está desligado, o índice
  /// não carregou ou estourou [bankSummaryTimeout]. Nunca lança.
  Future<BankSummary?> _loadBankSummary() async {
    try {
      if (_ref.read(accessPolicyAsyncProvider).isLoading) {
        await _ref
            .read(accessPolicyAsyncProvider.future)
            .timeout(bankSummaryTimeout);
      }
    } catch (_) {
      // Sem a política, vale o padrão (ligado).
    }
    try {
      if (!_ref.read(accessPolicyProvider).directionBankEnabled) return null;
      return await _ref
          .read(bankCatalogProvider)
          .summary()
          .timeout(bankSummaryTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Cópias do acervo já salvas, por matéria.
  static Map<String, int> _savedBankCopies(Iterable<Question> questions) {
    final out = <String, int>{};
    for (final q in questions) {
      if (q.origin == QuestionOrigin.bank) {
        out[q.subject] = (out[q.subject] ?? 0) + 1;
      }
    }
    return out;
  }

  DirectionContext _withBank(
    DirectionContext base,
    BankSummary summary,
    Iterable<Question> questions,
  ) => DirectionContext(
    today: base.today,
    goal: base.goal,
    coverage: withBankAvailability(
      base.coverage,
      available: summary.available,
      savedBankCopies: _savedBankCopies(questions),
    ),
    history: base.history,
    limits: base.limits,
  );

  /// Anota `bankAvailableAtProposal` em todas as etapas e anexa a sugestão de
  /// lista às de `buildList` e `practice` com acervo disponível. Total limitado
  /// por [bankSuggestionTimeout]; qualquer falha deixa as etapas sem sugestão.
  Future<List<StudyStep>> _attachBank(
    List<StudyStep> steps,
    DirectionContext context,
    BankSummary summary,
    Iterable<Question> questions,
  ) async {
    int availableOf(StudyStep s) {
      for (final c in context.coverage) {
        if (c.area == s.area && c.subject == s.subject) return c.bankAvailable;
      }
      return 0;
    }

    final annotated = [
      for (final s in steps)
        s.withBank(bankAvailableAtProposal: availableOf(s)),
    ];
    try {
      final catalog = _ref.read(bankCatalogProvider);
      final excluded = {
        for (final q in questions)
          if (q.origin == QuestionOrigin.bank && q.bankId != null) q.bankId!,
      };
      final band = targetDifficulty(context.history);
      return await Future.wait([
        for (final s in annotated)
          _suggestFor(s, catalog, summary, excluded, band),
      ]).timeout(bankSuggestionTimeout);
    } catch (_) {
      return annotated;
    }
  }

  Future<StudyStep> _suggestFor(
    StudyStep step,
    BankCatalog catalog,
    BankSummary summary,
    Set<String> excluded,
    int band,
  ) async {
    final eligible =
        step.action == StepAction.buildList ||
        step.action == StepAction.practice;
    if (!eligible || (step.bankAvailableAtProposal ?? 0) <= 0) return step;
    final page = await catalog.search(
      QuestionFilter(subjects: {step.subject}),
      limit: maxSuggestionPool,
    );
    // Só usa a faixa se o acervo da matéria tem alguma questão com faixa.
    final hasBand =
        summary.available(step.subject) >
        summary.availableAt(step.subject, null);
    final count = step.targetCount < maxBankListQuestions
        ? step.targetCount
        : maxBankListQuestions;
    final ids = suggestBankQuestions(
      candidates: page.items,
      excludeBankIds: excluded,
      count: count,
      seed: step.id,
      targetBand: hasBand ? band : null,
      difficultyOf: (q) => q.bankDifficulty,
      topicOrder: summary.taxonomy[step.subject] ?? const [],
    );
    if (ids.isEmpty) return step;
    return step.withBank(bankIds: ids, difficultyTarget: hasBand ? band : null);
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
        'hadBankSuggestion': step.bankIds.isNotEmpty,
        'bankListCreated': step.bankListId != null,
      });
    }
    return ok;
  }

  void _logMissed(Iterable<StudyStep> missed) {
    for (final s in missed) {
      _ref.read(metricsLoggerProvider).log(
        MetricEventType.directionStepMissed,
        {
          'source': s.source.name,
          'action': s.action.name,
          'hadBankSuggestion': s.bankIds.isNotEmpty,
          'bankListCreated': s.bankListId != null,
        },
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
