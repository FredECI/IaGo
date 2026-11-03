import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../domain/content_tree.dart';
import '../../domain/question_filter.dart';
import '../../shared/common_widgets.dart';
import 'questions_providers.dart';

/// Acervo por conteúdo (área → matéria → assunto). Tocar aplica o filtro.
class ContentTreePage extends ConsumerWidget {
  const ContentTreePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(questionsProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Por conteúdo')),
      body: questions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Toque num assunto para ver as questões dele.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final node in buildContentTree(questions)) ...[
                  _AreaCard(node: node),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

class _AreaCard extends ConsumerWidget {
  const _AreaCard({required this.node});

  final AreaNode node;

  void _apply(
    BuildContext context,
    WidgetRef ref, {
    String? subject,
    String? topicKey,
  }) {
    ref
        .read(questionFilterProvider.notifier)
        .replace(
          QuestionFilter(
            areas: {node.area},
            subjects: {?subject},
            topicKeys: {?topicKey},
          ),
        );
    context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final singleSubject = node.area.subjects.length == 1;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('tree-area-${node.area.name}'),
        shape: const Border(),
        leading: AreaAvatar(node.area, size: 36),
        title: Text(
          node.area.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          node.count == 0
              ? 'Nenhuma questão ainda'
              : Formatters.questions(node.count),
        ),
        children: [
          if (node.count == 0)
            const ListTile(
              title: Text(
                'Salve uma questão desta área para ela aparecer aqui.',
              ),
            ),
          for (final subject in node.subjects)
            if (singleSubject)
              ..._topicTiles(context, ref, subject)
            else
              ExpansionTile(
                key: Key('tree-subject-${subject.subject}'),
                shape: const Border(),
                tilePadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(subject.subject),
                subtitle: Text(Formatters.questions(subject.count)),
                children: _topicTiles(context, ref, subject),
              ),
        ],
      ),
    );
  }

  List<Widget> _topicTiles(
    BuildContext context,
    WidgetRef ref,
    SubjectNode subject,
  ) {
    final indent = node.area.subjects.length == 1 ? 32.0 : 48.0;
    return [
      for (final topic in subject.topics)
        ListTile(
          key: Key('tree-topic-${topic.label}'),
          contentPadding: EdgeInsets.only(left: indent, right: 16),
          leading: const Icon(Icons.sell_outlined, size: 20),
          title: Text(topic.label),
          trailing: _Count(topic.count),
          onTap: () => _apply(
            context,
            ref,
            subject: subject.subject,
            topicKey: topic.key,
          ),
        ),
      ListTile(
        contentPadding: EdgeInsets.only(left: indent, right: 16),
        leading: const Icon(Icons.list, size: 20),
        title: Text(
          subject.untagged > 0
              ? 'Todas de ${subject.subject} (${subject.untagged} sem assunto)'
              : 'Todas de ${subject.subject}',
        ),
        trailing: _Count(subject.count),
        onTap: () => _apply(context, ref, subject: subject.subject),
      ),
    ];
  }
}

class _Count extends StatelessWidget {
  const _Count(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
