import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../domain/list_builder.dart';
import '../questions/selection.dart';
import 'lists_providers.dart';

/// Pede o nome da lista. O texto sugerido vem selecionado: é só digitar.
Future<String?> showListNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String confirmLabel = 'Criar lista',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ListNameDialog(title: title, initial: initial, confirm: confirmLabel),
  );
}

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({
    required this.title,
    required this.initial,
    required this.confirm,
  });

  final String title;
  final String initial;
  final String confirm;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('list-name-field'),
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nome da lista',
          hintText: 'Ex.: Reforço — Funções',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('list-name-confirm'),
          onPressed: _submit,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Cria a lista com as questões dadas e abre o editor dela.
Future<void> createListAndOpen(
  BuildContext context,
  WidgetRef ref,
  List<String> questionIds,
) async {
  if (questionIds.isEmpty) return;
  final name = await showListNameDialog(
    context,
    title:
        'Nova lista com ${questionIds.length} '
        '${questionIds.length == 1 ? 'questão' : 'questões'}',
    initial: suggestListName(ref.read(clockProvider)()),
  );
  if (name == null || !context.mounted) return;
  final list = await ref
      .read(listActionsProvider)
      .create(name: name, questionIds: questionIds);
  ref.read(questionSelectionProvider.notifier).exit();
  if (!context.mounted) return;
  context.go(Routes.list(list.id));
}
