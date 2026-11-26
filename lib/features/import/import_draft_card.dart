import 'package:material_ui/material_ui.dart';

import '../../domain/area.dart';
import '../../domain/question.dart';
import 'import_models.dart';

/// Um rascunho na revisão: caixa de seleção, avisos e edição.
class ImportDraftCard extends StatefulWidget {
  const ImportDraftCard({
    super.key,
    required this.draft,
    required this.number,
    required this.showErrors,
    required this.onChanged,
  });

  final ImportDraft draft;

  /// Posição na lista (a partir de 1), para os rótulos.
  final int number;

  /// Depois de uma tentativa de salvar, mostra o que falta.
  final bool showErrors;

  /// Avisa a tela que algo mudou (contadores, botão Salvar).
  final VoidCallback onChanged;

  @override
  State<ImportDraftCard> createState() => _ImportDraftCardState();
}

class _ImportDraftCardState extends State<ImportDraftCard> {
  late final TextEditingController _statement;
  late final List<TextEditingController> _alternatives;
  late final TextEditingController _platform;

  ImportDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _statement = TextEditingController(text: draft.statement);
    _alternatives = [
      for (final a in draft.alternatives) TextEditingController(text: a),
    ];
    _platform = TextEditingController(text: draft.platform);
  }

  @override
  void didUpdateWidget(ImportDraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "Aplicar a todas" muda a plataforma por fora dos campos.
    if (_platform.text != draft.platform) _platform.text = draft.platform;
  }

  @override
  void dispose() {
    _statement.dispose();
    _platform.dispose();
    for (final c in _alternatives) {
      c.dispose();
    }
    super.dispose();
  }

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = draft.id;
    final problems = draft.problems;
    final showProblems = widget.showErrors && draft.selected;
    final preview = draft.statement.trim().isEmpty
        ? '(sem enunciado)'
        : draft.statement.trim();
    final categoryLabel = draft.subject ?? draft.area?.shortLabel;

    return Card(
      key: Key('draft-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Salvar a questão ${widget.number}',
                  child: Checkbox(
                    key: Key('draft-check-$id'),
                    value: draft.selected,
                    onChanged: (v) =>
                        _update(() => draft.selected = v ?? false),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Questão ${widget.number}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: draft.expanded ? 1 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            Text(
                              draft.type.label,
                              style: theme.textTheme.labelSmall,
                            ),
                            Text(
                              categoryLabel ?? 'Sem matéria',
                              style: theme.textTheme.labelSmall,
                            ),
                            if (draft.type == QuestionType.objective)
                              Text(
                                '${draft.filledAlternatives.length} alternativas',
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: Key('draft-edit-$id'),
                  tooltip: draft.expanded ? 'Fechar edição' : 'Editar',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () =>
                      _update(() => draft.expanded = !draft.expanded),
                  icon: Icon(
                    draft.expanded ? Icons.expand_less : Icons.edit_outlined,
                  ),
                ),
              ],
            ),
            for (final warning in draft.warnings)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(warning, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            if (showProblems && problems.isNotEmpty)
              Padding(
                key: Key('draft-problem-$id'),
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final problem in problems)
                      Text(
                        problem,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            if (draft.expanded) _editor(theme),
          ],
        ),
      ),
    );
  }

  Widget _editor(ThemeData theme) {
    final id = draft.id;
    final area = draft.area;
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: Key('draft-statement-$id'),
            controller: _statement,
            minLines: 3,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: 'Enunciado'),
            onChanged: (v) {
              draft.statement = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<QuestionType>(
            segments: const [
              ButtonSegment(
                value: QuestionType.objective,
                label: Text('Objetiva'),
              ),
              ButtonSegment(
                value: QuestionType.discursive,
                label: Text('Discursiva'),
              ),
            ],
            selected: {draft.type},
            onSelectionChanged: (s) => _update(() => draft.type = s.first),
          ),
          if (draft.type == QuestionType.objective) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _alternatives.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: Key('draft-alt-$id-$i'),
                  controller: _alternatives[i],
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Alternativa ${Question.letters[i]}',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    draft.alternatives[i] = v;
                    widget.onChanged();
                  },
                ),
              ),
          ],
          const SizedBox(height: 4),
          Text('Área', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in Area.values)
                ChoiceChip(
                  key: Key('draft-area-$id-${a.name}'),
                  label: Text(a.shortLabel),
                  selected: area == a,
                  onSelected: (_) => _update(() {
                    draft.area = a;
                    if (!a.subjects.contains(draft.subject)) {
                      draft.subject = a.defaultSubject;
                    }
                  }),
                ),
            ],
          ),
          if (area != null && area.subjects.length > 1) ...[
            const SizedBox(height: 12),
            Text('Matéria', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in area.subjects)
                  ChoiceChip(
                    key: Key('draft-subject-$id-$s'),
                    label: Text(s),
                    selected: draft.subject == s,
                    onSelected: (_) => _update(() => draft.subject = s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: Key('draft-platform-$id'),
            controller: _platform,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Plataforma de origem',
              hintText: 'Ex.: site, app, apostila, professor',
            ),
            onChanged: (v) {
              draft.platform = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}
