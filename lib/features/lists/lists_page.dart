import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/question_list.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import 'lists_providers.dart';

/// Listas montadas: para estudar ou levar à aula de reforço.
class ListsPage extends ConsumerWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsProvider);
    return Scaffold(
      appBar: AppBar(title: const PageTitle('Listas')),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Não foi possível carregar as listas',
          message: '$error',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.list_alt_outlined,
              title: 'Nenhuma lista ainda',
              message:
                  'Selecione questões ou use o filtro atual para montar '
                  'uma lista.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ListCard(list: items[index]),
          );
        },
      ),
    );
  }
}

class _ListCard extends ConsumerWidget {
  const _ListCard({required this.list});

  final QuestionList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final exported = list.lastExportedAt;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.list_alt,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          list.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            Formatters.questions(list.length),
            if (exported != null)
              'exportada ${Formatters.relativeDay(exported, now)}'
            else
              'ainda não exportada',
          ].join(' · '),
        ),
      ),
    );
  }
}
