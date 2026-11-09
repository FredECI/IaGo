import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../domain/question.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import '../lists/list_name_dialog.dart';
import 'filter_bar.dart';
import 'question_card.dart';
import 'questions_providers.dart';
import 'selection.dart';

/// Tela de questões: busca por texto, filtros com contadores e resultados.
/// Também é onde se monta uma lista: pelo filtro atual ou selecionando.
class QuestionsPage extends ConsumerStatefulWidget {
  const QuestionsPage({super.key});

  @override
  ConsumerState<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends ConsumerState<QuestionsPage> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(questionFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    ref.read(questionFilterProvider.notifier).setQuery(value);
    setState(() {});
  }

  void _clearAll() {
    _search.clear();
    ref.read(questionFilterProvider.notifier).clearAll();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(questionFilterProvider);
    final filtered = ref.watch(filteredQuestionsProvider);
    final total = ref.watch(questionsProvider).value?.length;
    final selection = ref.watch(questionSelectionProvider);
    final selecting = ref.read(questionSelectionProvider.notifier);
    final items = filtered.value ?? const <Question>[];
    final theme = Theme.of(context);
    // Se o filtro mudar por fora (tela "Por conteúdo"), o campo acompanha.
    ref.listen(questionFilterProvider, (_, next) {
      if (next.query != _search.text) _search.text = next.query;
    });

    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) selecting.exit();
      },
      child: Scaffold(
        appBar: selection.active
            ? AppBar(
                leading: IconButton(
                  key: const Key('exit-selection'),
                  tooltip: 'Cancelar seleção',
                  icon: const Icon(Icons.close),
                  onPressed: selecting.exit,
                ),
                title: Text(
                  Formatters.count(
                    selection.ids.length,
                    'selecionada',
                    'selecionadas',
                  ),
                ),
                actions: [
                  TextButton(
                    key: const Key('select-all'),
                    onPressed: items.isEmpty
                        ? null
                        : () => selecting.addAll(items.map((q) => q.id)),
                    child: Text('Todas (${items.length})'),
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                title: const PageTitle('Questões'),
                actions: [
                  TextButton.icon(
                    key: const Key('open-content-tree'),
                    onPressed: () => context.push(Routes.contentTree),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Conteúdos'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
        floatingActionButton: selection.active
            ? (selection.ids.isEmpty
                  ? null
                  : FloatingActionButton.extended(
                      heroTag: null,
                      key: const Key('create-list-from-selection'),
                      onPressed: () =>
                          createListAndOpen(context, ref, selection.ids),
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('Criar lista (${selection.ids.length})'),
                    ))
            : FloatingActionButton.extended(
                heroTag: null,
                key: const Key('fab-new-question'),
                onPressed: () => context.push(Routes.newQuestion),
                icon: const Icon(Icons.add),
                label: const Text('Salvar questão'),
              ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('search-field'),
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: _setQuery,
                      decoration: InputDecoration(
                        hintText: 'Buscar no enunciado, assunto ou plataforma',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar busca',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  _setQuery('');
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('open-bank'),
                            style: _entryStyle,
                            onPressed: () => context.push(Routes.bank),
                            icon: const Icon(Icons.local_library_outlined),
                            label: const Text('Acervo'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('open-import'),
                            style: _entryStyle,
                            onPressed: () => context.push(Routes.import),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Importar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const QuestionFilterBar(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _resultsLabel(
                              filtered.value?.length,
                              total,
                              filter.isEmpty,
                            ),
                            key: const Key('results-count'),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (!filter.isEmpty)
                          TextButton.icon(
                            key: const Key('clear-filters'),
                            onPressed: _clearAll,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Limpar'),
                          )
                        else if (!selection.active && items.isNotEmpty)
                          TextButton.icon(
                            key: const Key('start-selection'),
                            onPressed: selecting.start,
                            icon: const Icon(Icons.checklist),
                            label: const Text('Selecionar'),
                          ),
                      ],
                    ),
                    if (selection.active)
                      Text(
                        'Toque nas questões para incluir na lista.',
                        style: theme.textTheme.bodySmall,
                      )
                    else if (!filter.isEmpty && items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: FilledButton.tonalIcon(
                          key: const Key('build-list-from-filter'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => createListAndOpen(context, ref, [
                            for (final q in items) q.id,
                          ]),
                          icon: const Icon(Icons.playlist_add),
                          label: Text(
                            'Montar lista com '
                            '${items.length == 1 ? 'esta questão' : 'estas ${items.length} questões'}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...filtered.when(
              loading: () => const [
                SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Não foi possível carregar as questões',
                    message: '$error',
                  ),
                ),
              ],
              data: (items) => [
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: filter.isEmpty
                        ? const EmptyState(
                            icon: Icons.quiz_outlined,
                            title: 'Nenhuma questão salva ainda',
                            message:
                                'Cole aqui as questões que você encontra por '
                                'aí.',
                          )
                        : EmptyState(
                            icon: Icons.search_off,
                            title: 'Nenhuma questão com esses filtros',
                            action: OutlinedButton(
                              onPressed: _clearAll,
                              child: const Text('Limpar busca e filtros'),
                            ),
                          ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final question = items[index];
                        return QuestionCard(
                          question: question,
                          selectionMode: selection.active,
                          selected: selection.contains(question.id),
                          onTap: selection.active
                              ? () => selecting.toggle(question.id)
                              : () =>
                                    context.push(Routes.question(question.id)),
                          onLongPress: selection.active
                              ? null
                              : () => selecting.start(question.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _entryStyle = OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  );

  /// "40 questões" sem filtro; "9 de 40 questões" com filtro (nunca solto).
  static String _resultsLabel(int? shown, int? total, bool unfiltered) {
    if (shown == null || total == null) return '';
    if (unfiltered) return Formatters.questions(total);
    return '$shown de ${Formatters.questions(total)}';
  }
}
