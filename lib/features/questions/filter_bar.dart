import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/question_filter.dart';
import 'questions_providers.dart';

/// Filtros com contadores: áreas e tipos sempre à vista; matéria, assunto e
/// plataforma em folhas com a lista de opções.
class QuestionFilterBar extends ConsumerWidget {
  const QuestionFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facets = ref.watch(questionFacetsProvider);
    final filter = ref.watch(questionFilterProvider);
    final controller = ref.read(questionFilterProvider.notifier);
    if (facets == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in facets.areas)
              _CountChip(
                key: Key('filter-area-${option.value.name}'),
                label: option.label,
                count: option.count,
                selected: option.selected,
                icon: AppIcons.area(option.value),
                onTap: () => controller.toggleArea(option.value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Tudo à vista em 360 px: nada escondido em rolagem horizontal.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in facets.types)
              _CountChip(
                key: Key('filter-type-${option.value.name}'),
                label: option.label,
                count: option.count,
                selected: option.selected,
                onTap: () => controller.toggleType(option.value),
              ),
            _DimensionChip(
              key: const Key('filter-subject'),
              label: 'Matéria',
              selectedCount: filter.subjects.length,
              onTap: () => _openOptions(
                context,
                title: 'Matéria',
                dimension: FilterDimension.subject,
              ),
            ),
            _DimensionChip(
              key: const Key('filter-topic'),
              label: 'Assunto',
              selectedCount: filter.topicKeys.length,
              onTap: () => _openOptions(
                context,
                title: 'Assunto',
                dimension: FilterDimension.topic,
              ),
            ),
            _DimensionChip(
              key: const Key('filter-platform'),
              label: 'Plataforma',
              selectedCount: filter.platformKeys.length,
              onTap: () => _openOptions(
                context,
                title: 'Plataforma',
                dimension: FilterDimension.platform,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openOptions(
    BuildContext context, {
    required String title,
    required FilterDimension dimension,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OptionsSheet(title: title, dimension: dimension),
    );
  }
}

/// Folha com as opções de uma dimensão; os contadores mudam ao vivo.
class _OptionsSheet extends ConsumerWidget {
  const _OptionsSheet({required this.title, required this.dimension});

  final String title;
  final FilterDimension dimension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facets = ref.watch(questionFacetsProvider);
    final controller = ref.read(questionFilterProvider.notifier);
    final options = switch (dimension) {
      FilterDimension.subject => facets?.subjects,
      FilterDimension.topic => facets?.topics,
      FilterDimension.platform => facets?.platforms,
      _ => null,
    };
    void toggle(String value) => switch (dimension) {
      FilterDimension.subject => controller.toggleSubject(value),
      FilterDimension.topic => controller.toggleTopic(value),
      _ => controller.togglePlatform(value),
    };
    final theme = Theme.of(context);
    final items = options ?? const [];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                TextButton(
                  onPressed: () => controller.clearDimension(dimension),
                  child: const Text('Limpar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Pronto'),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma opção com a busca atual.'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in items)
                    CheckboxListTile(
                      value: option.selected,
                      onChanged: option.count == 0 && !option.selected
                          ? null
                          : (_) => toggle(option.value),
                      title: Text(option.label),
                      secondary: Text(
                        '${option.count}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = selected || count > 0;
    return FilterChip(
      visualDensity: VisualDensity.compact,
      avatar: icon == null ? null : Icon(icon, size: 18),
      showCheckmark: false,
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label),
            TextSpan(
              text: '  $count',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({
    super.key,
    required this.label,
    required this.selectedCount,
    required this.onTap,
  });

  final String label;
  final int selectedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selectedCount > 0;
    return FilterChip(
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
      selected: active,
      onSelected: (_) => onTap(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(active ? '$label · $selectedCount' : label),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
