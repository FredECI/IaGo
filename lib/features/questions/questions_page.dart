import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import 'filter_bar.dart';
import 'question_card.dart';
import 'questions_providers.dart';

/// Tela de questões: busca por texto, filtros com contadores e resultados.
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const PageTitle('Questões')),
      floatingActionButton: FloatingActionButton.extended(
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
                        ),
                    ],
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
                              'Cole aqui as questões que você encontra por aí.',
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final question = items[index];
                      return QuestionCard(
                        question: question,
                        onTap: () => context.push(Routes.question(question.id)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// "40 questões" sem filtro; "9 de 40 questões" com filtro (nunca solto).
  static String _resultsLabel(int? shown, int? total, bool unfiltered) {
    if (shown == null || total == null) return '';
    if (unfiltered) return Formatters.questions(total);
    return '$shown de ${Formatters.questions(total)}';
  }
}
