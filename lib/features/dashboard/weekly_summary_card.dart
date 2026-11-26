import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/dashboard_summary.dart';
import '../lists/lists_providers.dart';
import '../questions/questions_providers.dart';

/// Resumo da semana: sempre comparado com os 7 dias anteriores.
final dashboardSummaryProvider = Provider<DashboardSummary?>((ref) {
  final questions = ref.watch(questionsProvider).value;
  final lists = ref.watch(listsProvider).value;
  if (questions == null || lists == null) return null;
  return buildDashboardSummary(
    questions: questions,
    lists: lists,
    now: ref.watch(clockProvider)(),
  );
});

class WeeklySummaryCard extends ConsumerWidget {
  const WeeklySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final theme = Theme.of(context);
    if (summary == null) {
      return const Card(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (summary.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Comece salvando a primeira questão. O resumo da semana '
                  'aparece aqui, sempre comparado com a semana anterior.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final saved = summary.questionsSaved;
    final lists = summary.listsCreated;
    final top = summary.topArea;
    return Card(
      key: const Key('weekly-summary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta semana',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${saved.current}',
                  key: const Key('saved-this-week'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${saved.current == 1 ? 'questão salva' : 'questões salvas'} '
                    'nos últimos 7 dias',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DeltaChip(comparison: saved),
            const SizedBox(height: 12),
            _ComparisonBars(comparison: saved),
            const Divider(height: 28),
            _Line(
              icon: Icons.list_alt,
              text:
                  '${Formatters.count(lists.current, 'lista montada', 'listas montadas')} '
                  'nos últimos 7 dias, ${lists.describe()}.',
            ),
            if (top != null) ...[
              const SizedBox(height: 10),
              _Line(
                icon: AppIcons.area(top.area),
                text:
                    '${top.area.label} concentra ${top.percent}% das suas questões '
                    '(${top.count} de ${Formatters.questions(top.total)}), em '
                    '${summary.areasCovered} de 4 áreas.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.comparison});

  final PeriodComparison comparison;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = comparison.delta;
    final (icon, background, foreground) = switch (delta) {
      > 0 => (
        Icons.trending_up,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      < 0 => (
        Icons.trending_down,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (
        Icons.trending_flat,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      key: const Key('saved-delta'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              comparison.describe(),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Duas barras: últimos 7 dias × 7 dias anteriores (comparação, não nota).
class _ComparisonBars extends StatelessWidget {
  const _ComparisonBars({required this.comparison});

  final PeriodComparison comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = [
      comparison.current,
      comparison.previous,
      1,
    ].reduce((a, b) => a > b ? a : b);
    Widget bar(String label, int value, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 10,
                  width: constraints.maxWidth * value / maxValue,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label:
          '${comparison.current} nos últimos 7 dias contra '
          '${comparison.previous} nos 7 anteriores',
      excludeSemantics: true,
      child: Column(
        children: [
          bar('Últimos 7 dias', comparison.current, theme.colorScheme.primary),
          bar(
            '7 dias antes',
            comparison.previous,
            theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
