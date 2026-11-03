import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/question.dart';
import '../../shared/common_widgets.dart';

/// Cartão de questão usado na lista, na busca e no editor de listas.
class QuestionCard extends ConsumerWidget {
  const QuestionCard({
    super.key,
    required this.question,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Question question;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    final category = [
      question.subject,
      if (question.topic.trim().isNotEmpty) question.topic.trim(),
    ].join(' · ');
    final statement = question.statement.trim().isEmpty
        ? '(questão em imagem)'
        : question.statement.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Checkbox(value: selected, onChanged: (_) => onTap?.call())
              else
                AreaAvatar(question.area),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statement,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        InfoTag(
                          label: question.type.label,
                          icon: question.isObjective
                              ? Icons.radio_button_checked
                              : Icons.edit_note,
                        ),
                        InfoTag(
                          label: question.platform,
                          icon: Icons.source_outlined,
                        ),
                        if (question.hasImage)
                          const InfoTag(
                            label: 'imagem',
                            icon: Icons.image_outlined,
                          ),
                        InfoTag(
                          label: Formatters.relativeDay(
                            question.createdAt,
                            now,
                          ),
                          icon: Icons.schedule,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
