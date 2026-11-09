import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/direction_calendar.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_progress.dart';
import '../../shared/common_widgets.dart';
import 'direction_providers.dart';

export 'goal_page.dart';

/// Abre uma URL fora do app. Injetável para o teste não abrir nada.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Ponto da proposta pela IA (DI3). Escondido até a DI3 ligar a política de
/// acesso e o `StepProposer`; nunca aparece nesta entrega.
const bool _aiProposalVisible = false;

/// Direciona: objetivo, até 3 etapas pendentes e a comparação com os 14 dias
/// anteriores.
class DirectionPage extends ConsumerStatefulWidget {
  const DirectionPage({super.key});

  @override
  ConsumerState<DirectionPage> createState() => _DirectionPageState();
}

class _DirectionPageState extends ConsumerState<DirectionPage> {
  bool _busy = false;

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

  @override
  Widget build(BuildContext context) {
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
                ),
              ),
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
          if (_aiProposalVisible) const SizedBox.shrink(),
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

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.overdue,
    required this.busy,
    required this.onAccept,
    required this.onComplete,
    required this.onPostpone,
    required this.onCalendar,
  });

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
            const SizedBox(height: 8),
            InfoTag(
              label: step.source.label,
              icon: Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 8),
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
