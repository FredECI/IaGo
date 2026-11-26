import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../domain/list_builder.dart';
import '../../domain/question.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import '../lists/list_name_dialog.dart';
import 'bank_filter_bar.dart';
import 'bank_format.dart';
import 'bank_providers.dart';

/// Acervo do ENEM: busca, filtros e contadores iguais aos de "Minhas
/// questões", só leitura. Tocar numa questão abre o detalhe, de onde se salva.
class BankPage extends ConsumerStatefulWidget {
  const BankPage({super.key});

  @override
  ConsumerState<BankPage> createState() => _BankPageState();
}

class _BankPageState extends ConsumerState<BankPage> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(bankFilterProvider).query,
  );
  Timer? _debounce;
  bool _building = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(bankSearchDebounce, () {
      if (mounted) ref.read(bankFilterProvider.notifier).setQuery(value);
    });
    setState(() {});
  }

  void _setNow(String value) {
    _debounce?.cancel();
    ref.read(bankFilterProvider.notifier).setQuery(value);
    setState(() {});
  }

  void _clearAll() {
    _debounce?.cancel();
    _search.clear();
    ref.read(bankFilterProvider.notifier).clearAll();
    setState(() {});
  }

  void _retry() {
    ref.invalidate(bankResultsProvider);
    ref.invalidate(bankFacetsProvider);
    ref.invalidate(bankTotalProvider);
    ref.invalidate(bankUnclassifiedProvider);
  }

  Future<void> _buildList(int count) async {
    if (_building) return;
    final filter = ref.read(bankFilterProvider);
    final name = await showListNameDialog(
      context,
      title: 'Nova lista com ${bankQuestions(count)}',
      initial: suggestListName(ref.read(clockProvider)()),
    );
    if (name == null || !mounted) return;
    setState(() => _building = true);
    try {
      final page = await ref
          .read(bankCatalogProvider)
          .search(filter, limit: maxBankListQuestions);
      final list = await ref
          .read(bankActionsProvider)
          .createList(name: name, questions: page.items);
      if (!mounted) return;
      context.go(Routes.list(list.id));
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Não foi possível montar a lista. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bankFilterProvider);
    final results = ref.watch(bankResultsProvider);
    final total = ref.watch(bankTotalProvider).value;
    final unclassified = ref.watch(bankUnclassifiedProvider).value ?? 0;
    final saved = ref.watch(savedBankIdsProvider);
    final data = results.value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('Acervo'),
        actions: [
          TextButton.icon(
            key: const Key('open-bank-sources'),
            onPressed: () => context.push(Routes.bankSources),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Fontes'),
          ),
          const SizedBox(width: 4),
        ],
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
                    key: const Key('bank-search-field'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: _setNow,
                    decoration: InputDecoration(
                      hintText: 'Buscar no enunciado ou nas alternativas',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                _setNow('');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const BankFilterBar(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _resultsLabel(data?.total, total, filter.isEmpty),
                          key: const Key('bank-results-count'),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (!filter.isEmpty || _search.text.isNotEmpty)
                        TextButton.icon(
                          key: const Key('bank-clear-filters'),
                          onPressed: _clearAll,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Limpar'),
                        ),
                    ],
                  ),
                  if (unclassified > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${bankQuestions(unclassified)} ainda sem matéria '
                        'aparecem só na busca e no filtro por área.',
                        key: const Key('bank-unclassified-note'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (!filter.isEmpty && data != null && data.total > 0)
                    _BuildListButton(
                      count: data.total,
                      busy: _building,
                      onPressed: () => _buildList(data.total),
                    ),
                  if (results.isLoading && data != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          if (data == null && results.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Não foi possível abrir o acervo',
                message: 'Confira se o app está atualizado e tente de novo.',
                action: OutlinedButton(
                  key: const Key('bank-retry'),
                  onPressed: _retry,
                  child: const Text('Tentar de novo'),
                ),
              ),
            )
          else if (data == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _LoadingBank(),
            )
          else if (data.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off,
                title: 'Nenhuma questão com esses filtros',
                message: 'Tente outra palavra ou tire algum filtro.',
                action: OutlinedButton(
                  key: const Key('bank-empty-clear'),
                  onPressed: _clearAll,
                  child: const Text('Limpar busca e filtros'),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverList.separated(
                itemCount: data.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final question = data.items[index];
                  return _BankCard(
                    key: Key('bank-card-${question.bankId}'),
                    question: question,
                    saved: saved.contains(question.id),
                    onTap: () =>
                        context.push(Routes.bankQuestion(question.bankId!)),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverToBoxAdapter(
                child: _LoadMore(
                  shown: data.items.length,
                  state: data,
                  onPressed: ref.read(bankResultsProvider.notifier).loadMore,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "1.687 questões" sem filtro; "9 de 1.687 questões" com filtro.
  static String _resultsLabel(int? shown, int? total, bool unfiltered) {
    if (shown == null || total == null) return '';
    if (unfiltered) return bankQuestions(total);
    return '${formatBankNumber(shown)} de ${bankQuestions(total)}';
  }
}

class _LoadingBank extends StatelessWidget {
  const _LoadingBank();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando o acervo',
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _BuildListButton extends StatelessWidget {
  const _BuildListButton({
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  final int count;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tooMany = count > maxBankListQuestions;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            key: const Key('bank-build-list'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: tooMany || busy ? null : onPressed,
            icon: const Icon(Icons.playlist_add),
            label: Text(
              'Montar lista com '
              '${count == 1 ? 'esta questão' : 'estas ${formatBankNumber(count)} questões'}',
            ),
          ),
          if (tooMany)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Uma lista leva até $maxBankListQuestions questões do acervo. '
                'Refine a busca ou os filtros (agora são '
                '${formatBankNumber(count)}).',
                key: const Key('bank-list-limit-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.shown,
    required this.state,
    required this.onPressed,
  });

  final int shown;
  final BankListState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Mostrando ${formatBankNumber(shown)} de '
          '${formatBankNumber(state.total)}',
          key: const Key('bank-shown-count'),
          style: theme.textTheme.bodySmall,
        ),
        if (state.moreError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Não foi possível carregar mais questões.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (state.nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: state.loadingMore
                ? Semantics(
                    label: 'Carregando mais questões',
                    child: const CircularProgressIndicator(),
                  )
                : OutlinedButton(
                    key: const Key('bank-load-more'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(160, 48),
                    ),
                    onPressed: onPressed,
                    child: Text(
                      state.moreError ? 'Tentar de novo' : 'Carregar mais',
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Cartão do acervo. Não mostra data relativa: a "data" de uma questão do
/// acervo não é de quem a salvou.
class _BankCard extends StatelessWidget {
  const _BankCard({
    super.key,
    required this.question,
    required this.saved,
    required this.onTap,
  });

  final Question question;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = [
      question.subject.isEmpty ? question.area.shortLabel : question.subject,
      if (question.topic.trim().isNotEmpty) question.topic.trim(),
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      question.statement.trim(),
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
                          label: question.platform,
                          icon: Icons.source_outlined,
                        ),
                        InfoTag(
                          label: question.type.label,
                          icon: Icons.radio_button_checked,
                        ),
                        if (saved)
                          const InfoTag(
                            label: 'Já salva',
                            icon: Icons.check_circle_outline,
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
