import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/list_builder.dart';
import '../../domain/question.dart';
import '../../domain/question_list.dart';
import '../../shared/common_widgets.dart';
import '../export/export_sheet.dart';
import '../questions/questions_providers.dart';
import 'list_name_dialog.dart';
import 'lists_providers.dart';
import 'question_picker_sheet.dart';

/// Editor de lista: nome, ordem (arrastar), remover, adicionar e exportar.
class ListEditorPage extends ConsumerWidget {
  const ListEditorPage({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(listByIdProvider(listId));
    if (list == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lista')),
        body: ref.watch(listsProvider).isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.search_off,
                title: 'Lista não encontrada',
              ),
      );
    }
    final questions = resolveQuestions(
      list.questionIds,
      ref.watch(questionsProvider).value ?? const [],
    );
    final actions = ref.read(listActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(list.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('rename-list'),
            tooltip: 'Renomear',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(context, ref, list),
          ),
          IconButton(
            key: const Key('delete-list'),
            tooltip: 'Excluir lista',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref, list),
          ),
        ],
      ),
      floatingActionButton: questions.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              key: const Key('export-pdf'),
              onPressed: () => showExportSheet(context, listId: list.id),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar PDF'),
            ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        buildDefaultDragHandles: false,
        header: _Summary(list: list, questions: questions),
        footer: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            key: const Key('add-questions'),
            onPressed: () async {
              final ids = await showQuestionPicker(
                context,
                alreadyInList: list.questionIds.toSet(),
              );
              if (ids != null && ids.isNotEmpty) await actions.add(list, ids);
            },
            icon: const Icon(Icons.add),
            label: const Text('Adicionar questões'),
          ),
        ),
        itemCount: questions.length,
        onReorderItem: (oldIndex, newIndex) =>
            actions.reorder(list, oldIndex, newIndex),
        itemBuilder: (context, index) {
          final question = questions[index];
          return _ListItem(
            key: ValueKey(question.id),
            index: index,
            question: question,
            onRemove: () => actions.remove(list, question.id),
          );
        },
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    QuestionList list,
  ) async {
    final actions = ref.read(listActionsProvider);
    final name = await showListNameDialog(
      context,
      title: 'Renomear lista',
      initial: list.name,
      confirmLabel: 'Salvar',
    );
    if (name != null) await actions.rename(list, name);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    QuestionList list,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir lista?'),
        content: const Text('As questões continuam salvas; só a lista some.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-delete-list'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final actions = ref.read(listActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    await actions.delete(list);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Lista excluída.')));
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.list, required this.questions});

  final QuestionList list;
  final List<Question> questions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final exported = list.lastExportedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            describeComposition(questions),
            key: const Key('list-composition'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            exported == null
                ? 'Ainda não exportada'
                : 'Exportada ${Formatters.count(list.exportCount, 'vez', 'vezes')}'
                      ' · última ${Formatters.relativeDay(exported, now)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (questions.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Arraste pela alça para mudar a ordem.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    super.key,
    required this.index,
    required this.question,
    required this.onRemove,
  });

  final int index;
  final Question question;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = [
      question.subject,
      if (question.topic.trim().isNotEmpty) question.topic.trim(),
      question.type.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      question.statement.trim().isEmpty
                          ? '(questão em imagem)'
                          : question.statement.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tirar da lista',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: onRemove,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, semanticLabel: 'Arrastar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
