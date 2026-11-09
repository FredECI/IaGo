import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../domain/question.dart';
import '../../shared/common_widgets.dart';
import '../rating/rating_panel.dart';
import 'question_image.dart';
import 'questions_providers.dart';

/// Detalhe da questão, com editar e excluir. Sem gabarito, de propósito.
class QuestionDetailPage extends ConsumerWidget {
  const QuestionDetailPage({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = ref.watch(questionByIdProvider(questionId));
    final loading = ref.watch(questionsProvider).isLoading;
    if (question == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Questão')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.search_off,
                title: 'Questão não encontrada',
                message: 'Ela pode ter sido excluída.',
              ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = [
      question.subject,
      if (question.topic.trim().isNotEmpty) question.topic.trim(),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Questão'),
        actions: [
          IconButton(
            key: const Key('edit-question'),
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(Routes.editQuestion(question.id)),
          ),
          IconButton(
            key: const Key('delete-question'),
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, question),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              AreaAvatar(question.area),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Em Matemática, área e matéria têm o mesmo nome.
                    if (question.area.label != question.subject)
                      Text(
                        question.area.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      category,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  question.isObjective
                      ? Icons.radio_button_checked
                      : Icons.edit_note,
                  size: 18,
                ),
                label: Text(question.type.label),
              ),
              Chip(
                avatar: const Icon(Icons.source_outlined, size: 18),
                label: Text(question.platform),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (question.statement.trim().isNotEmpty)
            SelectableText(
              question.statement,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          if (question.hasImage) ...[
            const SizedBox(height: 12),
            QuestionImage(questionId: question.id),
          ],
          if (question.isObjective && question.alternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < question.alternatives.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.secondaryContainer,
                      child: Text(
                        Question.letters[i],
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          question.alternatives[i],
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          const Divider(),
          if (question.sourceUrl != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: const Text('Link de origem'),
              subtitle: Text(
                question.sourceUrl!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openLink(context, question.sourceUrl!),
            ),
          if (question.notes != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Observações'),
              subtitle: Text(question.notes!),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text('Salva em ${Formatters.dateTime(question.createdAt)}'),
            subtitle: question.updatedAt != question.createdAt
                ? Text('Editada em ${Formatters.dateTime(question.updatedAt)}')
                : null,
          ),
          const Divider(),
          PrivateRatingPanel(question: question),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showMessage(context, 'Não foi possível abrir o link.');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Question question,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir questão?'),
        content: const Text(
          'Ela também sai das listas em que aparece. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Pega tudo antes de sair da tela: depois do pop, `ref` não vale mais.
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(questionActionsProvider);
    context.pop();
    await actions.delete(question.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Questão excluída.')));
  }
}
