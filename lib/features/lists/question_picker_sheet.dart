import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/question_filter.dart';
import '../questions/question_card.dart';
import '../questions/questions_providers.dart';

/// Escolhe questões para acrescentar a uma lista (com busca).
Future<List<String>?> showQuestionPicker(
  BuildContext context, {
  required Set<String> alreadyInList,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _QuestionPicker(alreadyInList: alreadyInList),
    ),
  );
}

class _QuestionPicker extends ConsumerStatefulWidget {
  const _QuestionPicker({required this.alreadyInList});

  final Set<String> alreadyInList;

  @override
  ConsumerState<_QuestionPicker> createState() => _QuestionPickerState();
}

class _QuestionPickerState extends ConsumerState<_QuestionPicker> {
  String _query = '';
  final List<String> _selected = [];

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(questionsProvider).value ?? const [];
    final candidates = QuestionFilter(query: _query)
        .apply(all)
        .where((q) => !widget.alreadyInList.contains(q.id))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Adicionar questões',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton(
                key: const Key('picker-confirm'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(List.of(_selected)),
                child: Text('Adicionar (${_selected.length})'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('picker-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Buscar questões',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: candidates.isEmpty
              ? const Center(child: Text('Nenhuma questão para adicionar.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final question = candidates[index];
                    final selected = _selected.contains(question.id);
                    return QuestionCard(
                      question: question,
                      selectionMode: true,
                      selected: selected,
                      onTap: () => setState(
                        () => selected
                            ? _selected.remove(question.id)
                            : _selected.add(question.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
