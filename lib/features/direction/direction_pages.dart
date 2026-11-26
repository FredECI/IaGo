import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../data/policy_providers.dart';
import '../../domain/direction_calendar.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_progress.dart';
import '../../domain/question_filter.dart';
import '../../shared/common_widgets.dart';
import '../bank/bank_format.dart';
import '../bank/bank_providers.dart';
import '../community/community_access.dart';
import '../lists/lists_providers.dart';
import '../questions/questions_providers.dart';
import 'direction_providers.dart';

export 'goal_page.dart';

/// Abre uma URL fora do app. Injetável para o teste não abrir nada.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Direciona: objetivo, até 3 etapas pendentes e a comparação com os 14 dias
/// anteriores.
class DirectionPage extends ConsumerStatefulWidget {
  const DirectionPage({super.key});

  @override
  ConsumerState<DirectionPage> createState() => _DirectionPageState();
}

class _DirectionPageState extends ConsumerState<DirectionPage> {
  bool _busy = false;
  bool _bankBusy = false;

  /// Etapas cujas questões sugeridas sumiram do acervo (versão nova).
  final Set<String> _gone = {};

  @override
  void initState() {
    super.initState();
    // As etapas simuladas da demo nascem sem acervo: anexa a sugestão.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(directionSimulatedProvider)) {
        ref.read(directionActionsProvider).attachBankToPendingSteps();
      }
    });
  }

  /// Roda uma gravação sem toque duplo e avisa se falhar.
  Future<void> _run(Future<bool> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) showMessage(context, failure);
  }

  Future<void> _propose(StudyGoal goal) async {
    if (_busy) return;
    setState(() => _busy = true);
    final steps = await ref
        .read(directionActionsProvider)
        .proposeWithRules(goal);
    if (!mounted) return;
    setState(() => _busy = false);
    if (steps.isEmpty) {
      showMessage(
        context,
        'Não foi possível montar a proposta agora. Tente de novo em instantes.',
      );
    }
  }

  Future<void> _addToCalendar(StudyStep step) async {
    final opened = await ref.read(urlOpenerProvider)(stepCalendarUri(step));
    if (!opened && mounted) {
      showMessage(context, 'Não foi possível abrir a agenda.');
    }
  }

  /// "Escolher no acervo" e "Ver o acervo": abre o acervo já filtrado pela área
  /// e pela matéria da etapa. Não mexe no filtro de "Minhas questões".
  void _openBank(StudyStep step) {
    ref
        .read(bankFilterProvider.notifier)
        .replace(QuestionFilter(areas: {step.area}, subjects: {step.subject}));
    // `go`, não `push`: o Direciona fica fora das abas, e empilhar uma rota
    // da aba Questões por cima dele deixava a tela em branco.
    context.go(Routes.bank);
  }

  /// "Ver minhas questões de {matéria}".
  void _openMine(StudyStep step) {
    ref
        .read(questionFilterProvider.notifier)
        .replace(QuestionFilter(areas: {step.area}, subjects: {step.subject}));
    context.go(Routes.questions);
  }

  /// "Montar lista com N do acervo": busca as questões pelos ids, cria a lista
  /// (as já salvas não duplicam), grava `bankListId` e abre o editor.
  Future<void> _buildBankList(StudyStep step) async {
    if (_bankBusy) return;
    setState(() => _bankBusy = true);
    try {
      final questions = await ref.read(bankCatalogProvider).byIds(step.bankIds);
      if (!mounted) return;
      if (questions.isEmpty) {
        setState(() => _gone.add(step.id));
        return;
      }
      final list = await ref
          .read(bankActionsProvider)
          .createList(
            name: 'Direciona: ${step.subject} até ${_shortDate(step.dueAt)}',
            questions: questions,
            fromStepId: step.id,
          );
      if (!mounted) return;
      context.go(Routes.list(list.id));
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Não foi possível montar a lista. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _bankBusy = false);
    }
  }

  /// Botões do acervo da etapa (vazio com o interruptor desligado).
  List<_BankButton> _bankButtons(StudyStep step, bool enabled) {
    if (!enabled) return const [];
    final available = (step.bankAvailableAtProposal ?? 0) > 0;
    switch (step.action) {
      case StepAction.review:
        return [
          _BankButton(
            key: Key('bank-mine-${step.id}'),
            label: 'Ver minhas questões de ${step.subject}',
            icon: Icons.folder_open_outlined,
            primary: true,
            onPressed: () => _openMine(step),
          ),
        ];
      case StepAction.collect:
        return [
          if (available)
            _BankButton(
              key: Key('bank-choose-${step.id}'),
              label: 'Escolher no acervo',
              icon: Icons.travel_explore_outlined,
              primary: true,
              onPressed: () => _openBank(step),
            ),
        ];
      case StepAction.buildList:
      case StepAction.practice:
        final lists = ref.read(listsProvider).value;
        final listExists =
            step.bankListId != null &&
            (lists == null || lists.any((l) => l.id == step.bankListId));
        return [
          if (step.bankIds.isNotEmpty && !_gone.contains(step.id))
            listExists
                ? _BankButton(
                    key: Key('bank-open-list-${step.id}'),
                    label: 'Abrir lista',
                    icon: Icons.list_alt_outlined,
                    primary: true,
                    onPressed: () => context.go(Routes.list(step.bankListId!)),
                  )
                : _BankButton(
                    key: Key('bank-build-${step.id}'),
                    label: 'Montar lista com ${step.bankIds.length} do acervo',
                    icon: Icons.playlist_add_outlined,
                    primary: true,
                    onPressed: _bankBusy ? null : () => _buildBankList(step),
                  ),
          if (available)
            _BankButton(
              key: Key('bank-open-${step.id}'),
              label: 'Ver o acervo de ${step.subject}',
              icon: Icons.travel_explore_outlined,
              onPressed: () => _openBank(step),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bankEnabled = ref.watch(accessPolicyProvider).directionBankEnabled;
    // Mantém as listas e as questões ouvidas: o botão vira "Abrir lista" (ou
    // volta a montar) e "Montar lista" confere as cópias já salvas.
    ref.watch(listsProvider);
    ref.watch(questionsProvider);
    final goalAsync = ref.watch(studyGoalProvider);
    final stepsAsync = ref.watch(studyStepsProvider);
    final pending = ref.watch(pendingStepsProvider);
    final progress = ref.watch(stepProgressProvider);
    final simulated = ref.watch(directionSimulatedProvider);
    final now = ref.watch(clockProvider)();
    final goal = goalAsync.value;

    Widget body;
    if (goalAsync.hasError && goal == null) {
      body = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar seu objetivo',
        message: 'Confira a conexão e tente de novo.',
        action: FilledButton(
          key: const Key('direction-reload'),
          onPressed: () {
            ref.invalidate(studyGoalProvider);
            ref.invalidate(studyStepsProvider);
          },
          child: const Text('Tentar de novo'),
        ),
      );
    } else if (goalAsync.isLoading && goal == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (goal == null) {
      body = EmptyState(
        icon: Icons.flag_outlined,
        title: 'Defina seu objetivo',
        message:
            'Diga a prova e quanto tempo você tem. As próximas etapas de '
            'estudo aparecem aqui.',
        action: FilledButton(
          key: const Key('direction-define-goal'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => context.push(Routes.directionGoal),
          child: const Text('Definir objetivo'),
        ),
      );
    } else {
      final inDate = [
        for (final s in pending)
          if (!isOverdue(s, now)) s,
      ];
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (simulated) const _SimulatedBanner(),
          _GoalSummary(goal: goal),
          const SizedBox(height: 16),
          _ProgressCard(progress: progress),
          const SizedBox(height: 16),
          Text(
            'Próximas etapas',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (stepsAsync.isLoading && pending.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pending.isEmpty)
            const _NoSteps()
          else
            for (final step in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StepCard(
                  step: step,
                  overdue: isOverdue(step, now),
                  busy: _busy,
                  onAccept: () => _run(
                    () => ref.read(directionActionsProvider).accept(step),
                    'Não foi possível aceitar o prazo. Tente de novo.',
                  ),
                  onComplete: () => _run(
                    () => ref.read(directionActionsProvider).complete(step),
                    'Não foi possível concluir a etapa. Tente de novo.',
                  ),
                  onPostpone: () => _run(
                    () => ref.read(directionActionsProvider).postpone(step),
                    'Não foi possível adiar a etapa.',
                  ),
                  onCalendar: () => _addToCalendar(step),
                  bankEnabled: bankEnabled,
                  bankGone: _gone.contains(step.id),
                  bankButtons: _bankButtons(step, bankEnabled),
                ),
              ),
          if (ref.watch(canOfferJoinProvider) &&
              ref.watch(accessPolicyProvider).aiEnabled) ...[
            const _JoinNote(),
            const SizedBox(height: 12),
          ],
          if (!stepsAsync.isLoading && inDate.isEmpty) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              key: const Key('direction-propose'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy ? null : () => _propose(goal),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Pedir nova proposta'),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Direciona'),
        actions: [
          if (goal != null)
            IconButton(
              key: const Key('direction-edit-goal'),
              tooltip: 'Editar objetivo',
              onPressed: () => context.push(Routes.directionGoal),
              icon: const Icon(Icons.tune),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Conta real fora do piloto: as etapas vêm das regras; a proposta pela IA é
/// para membros.
class _JoinNote extends StatelessWidget {
  const _JoinNote();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('direction-join-note'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'As etapas vêm das regras do app. A proposta pela IA é para '
              'quem entrou no piloto.',
            ),
            TextButton(
              key: const Key('direction-join'),
              onPressed: () => context.push(Routes.becomeMember),
              child: const Text('Entrar no piloto'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimulatedBanner extends StatelessWidget {
  const _SimulatedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('direction-simulated'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.science_outlined,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demonstração: proposta simulada',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.goal});

  final StudyGoal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [
      goal.exam.label,
      if (goal.targetDate != null)
        'prova em ${Formatters.date(goal.targetDate!)}',
      '${goal.weeklyHours} h por semana',
      if (goal.focusAreas.isNotEmpty)
        'foco: ${goal.focusAreas.map((a) => a.shortLabel).join(', ')}',
    ];
    return Row(
      children: [
        Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            parts.join(' · '),
            key: const Key('direction-goal-summary'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Comparação relativa (CA-D7): nunca um número solto.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final StepProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.trending_up, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                progress.isEmpty
                    ? 'Conclua a primeira etapa e a comparação com as '
                          'semanas anteriores aparece aqui.'
                    : progress.sentence,
                key: const Key('direction-progress'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSteps extends StatelessWidget {
  const _NoSteps();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      'Nenhuma etapa pendente. Peça uma nova proposta.',
      key: const Key('direction-empty'),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

/// Dia e mês, como em "Direciona: Matemática até 12/11".
String _shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

class _BankButton {
  const _BankButton({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final Key key;
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.overdue,
    required this.busy,
    required this.onAccept,
    required this.onComplete,
    required this.onPostpone,
    required this.onCalendar,
    required this.bankEnabled,
    required this.bankGone,
    required this.bankButtons,
  });

  final bool bankEnabled;
  final bool bankGone;
  final List<_BankButton> bankButtons;

  final StudyStep step;
  final bool overdue;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onComplete;
  final VoidCallback onPostpone;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minSize = const Size(48, 48);
    return Card(
      key: Key('step-${step.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${step.action.label}: ${step.targetCount} · ${step.subject}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              overdue
                  ? 'Prazo vencido em ${Formatters.date(step.dueAt)}'
                  : 'Até ${Formatters.date(step.dueAt)}'
                        '${step.postponedAt != null ? ' (adiada)' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(step.rationale, style: theme.textTheme.bodyMedium),
            if (bankEnabled && step.bankIds.isNotEmpty && !bankGone) ...[
              const SizedBox(height: 4),
              Text(
                _suggestionLine(step),
                key: Key('bank-line-${step.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (bankGone) ...[
              const SizedBox(height: 4),
              Text(
                'As questões sugeridas não estão mais no acervo.',
                key: Key('bank-gone-${step.id}'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            InfoTag(
              label: step.source.label,
              icon: Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 8),
            for (final b in bankButtons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: b.primary
                    ? FilledButton.tonalIcon(
                        key: b.key,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: b.onPressed,
                        icon: Icon(b.icon),
                        label: Text(b.label),
                      )
                    : OutlinedButton.icon(
                        key: b.key,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: b.onPressed,
                        icon: Icon(b.icon),
                        label: Text(b.label),
                      ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(
                  key: Key('complete-${step.id}'),
                  style: FilledButton.styleFrom(minimumSize: minSize),
                  onPressed: busy ? null : onComplete,
                  child: const Text('Concluir'),
                ),
                if (step.status == StepStatus.proposed && !overdue)
                  OutlinedButton(
                    key: Key('accept-${step.id}'),
                    style: OutlinedButton.styleFrom(minimumSize: minSize),
                    onPressed: busy ? null : onAccept,
                    child: const Text('Aceitar prazo'),
                  ),
                if (canPostpone(step))
                  OutlinedButton(
                    key: Key('postpone-${step.id}'),
                    style: OutlinedButton.styleFrom(minimumSize: minSize),
                    onPressed: busy ? null : onPostpone,
                    child: Text('Adiar $postponeDays dias'),
                  ),
                TextButton.icon(
                  key: Key('calendar-${step.id}'),
                  style: TextButton.styleFrom(minimumSize: minSize),
                  onPressed: onCalendar,
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Adicionar à agenda'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sugestão do acervo: 10 questões de Matemática, dificuldade Média". Sem
/// faixa, a linha omite a dificuldade.
String _suggestionLine(StudyStep step) {
  final band = difficultyLabel(step.difficultyTarget);
  return 'Sugestão do acervo: ${bankQuestions(step.bankIds.length)} de '
      '${step.subject}${band == null ? '' : ', dificuldade $band'}';
}
