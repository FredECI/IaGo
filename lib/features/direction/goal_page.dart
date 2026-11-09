import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/area.dart';
import '../../domain/direction_models.dart';
import '../../shared/common_widgets.dart';
import 'direction_providers.dart';

/// Objetivo de estudo: prova-alvo, data opcional, horas por semana e áreas de
/// foco. Ao salvar, as regras já propõem as primeiras etapas.
class GoalPage extends ConsumerStatefulWidget {
  const GoalPage({super.key});

  @override
  ConsumerState<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends ConsumerState<GoalPage> {
  ExamTarget _exam = ExamTarget.enem;
  DateTime? _targetDate;
  double _hours = 8;
  final Set<Area> _areas = {};
  bool _saving = false;
  bool _prefilled = false;

  void _prefill(StudyGoal goal) {
    _prefilled = true;
    _exam = goal.exam;
    _targetDate = goal.targetDate;
    _hours = goal.weeklyHours.clamp(1, 40).toDouble();
    _areas
      ..clear()
      ..addAll(goal.focusAreas);
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate != null && !_targetDate!.isBefore(today)
          ? _targetDate!
          : today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
      helpText: 'Data da prova',
    );
    if (picked != null && mounted) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    final existing = ref.read(studyGoalProvider).value;
    final goal = StudyGoal(
      exam: _exam,
      targetDate: _targetDate,
      weeklyHours: _hours.round(),
      focusAreas: [
        for (final a in Area.values)
          if (_areas.contains(a)) a,
      ],
      lastAiAt: existing?.lastAiAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final ok = await ref.read(directionActionsProvider).setGoal(goal);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showMessage(
        context,
        'Não foi possível salvar o objetivo. Tente de novo.',
      );
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.direction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = ref.watch(studyGoalProvider).value;
    if (!_prefilled && existing != null) _prefill(existing);
    final hours = _hours.round();

    return Scaffold(
      appBar: AppBar(title: const Text('Objetivo de estudo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Qual é a sua prova?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in ExamTarget.values)
                  ChoiceChip(
                    key: Key('goal-exam-${e.wireName}'),
                    label: Text(e.label),
                    selected: _exam == e,
                    onSelected: (_) => setState(() => _exam = e),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Data da prova (opcional)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('goal-date'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _targetDate == null
                        ? 'Escolher data'
                        : Formatters.date(_targetDate!),
                  ),
                ),
                if (_targetDate != null)
                  TextButton(
                    key: const Key('goal-date-clear'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => setState(() => _targetDate = null),
                    child: const Text('Remover data'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Horas de estudo por semana',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '$hours ${hours == 1 ? 'hora' : 'horas'} por semana',
              key: const Key('goal-hours-label'),
              style: theme.textTheme.bodyLarge,
            ),
            Slider(
              key: const Key('goal-hours'),
              min: 1,
              max: 40,
              divisions: 39,
              value: _hours,
              label: '$hours h',
              semanticFormatterCallback: (v) => '${v.round()} horas por semana',
              onChanged: (v) => setState(() => _hours = v),
            ),
            const SizedBox(height: 16),
            Text(
              'Áreas de foco (opcional)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'As etapas dão prioridade a estas áreas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in Area.values)
                  FilterChip(
                    key: Key('goal-area-${a.name}'),
                    label: Text(a.shortLabel),
                    selected: _areas.contains(a),
                    onSelected: (on) => setState(() {
                      on ? _areas.add(a) : _areas.remove(a);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('goal-save'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar e receber etapas'),
            ),
          ],
        ),
      ),
    );
  }
}
