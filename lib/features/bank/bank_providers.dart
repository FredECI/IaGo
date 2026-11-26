import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/bank_asset_catalog.dart';
import '../../data/bank_catalog.dart';
import '../../data/providers.dart';
import '../../domain/area.dart';
import '../../domain/bank_source.dart';
import '../../domain/question.dart';
import '../../domain/question_filter.dart';
import '../../domain/question_list.dart';
import '../lists/lists_providers.dart';
import '../questions/questions_providers.dart';

/// Limite de questões do acervo numa lista (CA-R7: definido uma vez só).
const int maxBankListQuestions = 30;

/// Tamanho de cada página da lista do acervo ("Carregar mais").
const int bankPageSize = 40;

/// Pausa da digitação antes de buscar no acervo.
const Duration bankSearchDebounce = Duration(milliseconds: 300);

/// Acervo do ENEM, lido do asset (sem rede e sem Firestore). Uma instância por
/// sessão: o asset é carregado só no primeiro uso. Nos testes, sobrescreva
/// com um catálogo falso.
final bankCatalogProvider = Provider<BankCatalog>((ref) => AssetBankCatalog());

/// Fontes registradas (crédito e aviso exibidos na tela do acervo).
final bankSourcesProvider = FutureProvider<List<BankSource>>(
  (ref) => ref.watch(bankCatalogProvider).sources(),
);

/// Busca e filtros do acervo. É outro estado: buscar no acervo nunca mexe
/// nos contadores de "Minhas questões" (CA-B3).
final bankFilterProvider =
    NotifierProvider<BankFilterController, QuestionFilter>(
      BankFilterController.new,
    );

class BankFilterController extends Notifier<QuestionFilter> {
  @override
  QuestionFilter build() {
    ref.watch(sessionProvider);
    return const QuestionFilter();
  }

  /// Montar uma lista pelo acervo também conta no tempo de montagem (H2).
  void _set(QuestionFilter next) {
    if (!next.isEmpty) ref.read(listAssemblyTimerProvider.notifier).markStart();
    state = next;
  }

  void setQuery(String query) => _set(state.copyWith(query: query));

  void toggleArea(Area area) => _set(state.toggleArea(area));

  void toggleSubject(String subject) => _set(state.toggleSubject(subject));

  void toggleTopic(String topicKey) => _set(state.toggleTopic(topicKey));

  void toggleType(QuestionType type) => _set(state.toggleType(type));

  void togglePlatform(String platformKey) =>
      _set(state.togglePlatform(platformKey));

  void clearDimension(FilterDimension dimension) => _set(switch (dimension) {
    FilterDimension.area => state.copyWith(areas: const {}),
    FilterDimension.subject => state.copyWith(subjects: const {}),
    FilterDimension.topic => state.copyWith(topicKeys: const {}),
    FilterDimension.type => state.copyWith(type: null),
    FilterDimension.platform => state.copyWith(platformKeys: const {}),
  });

  void clearAll() => state = const QuestionFilter();
}

/// Páginas já carregadas do resultado atual.
class BankListState {
  const BankListState({
    required this.items,
    required this.total,
    this.nextCursor,
    this.loadingMore = false,
    this.moreError = false,
  });

  final List<Question> items;

  /// Total de resultados da busca (todas as páginas).
  final int total;
  final String? nextCursor;
  final bool loadingMore;

  /// A última tentativa de "Carregar mais" falhou.
  final bool moreError;

  BankListState copyWith({
    List<Question>? items,
    int? total,
    Object? nextCursor = _keep,
    bool? loadingMore,
    bool? moreError,
  }) => BankListState(
    items: items ?? this.items,
    total: total ?? this.total,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: moreError ?? this.moreError,
  );
}

const Object _keep = Object();

/// Resultado do acervo para o filtro atual, página a página. Trocar o filtro
/// recomeça da primeira página.
final bankResultsProvider =
    AsyncNotifierProvider<BankResultsController, BankListState>(
      BankResultsController.new,
    );

class BankResultsController extends AsyncNotifier<BankListState> {
  @override
  Future<BankListState> build() async {
    final filter = ref.watch(bankFilterProvider);
    final page = await ref
        .watch(bankCatalogProvider)
        .search(filter, limit: bankPageSize);
    return BankListState(
      items: page.items,
      total: page.total,
      nextCursor: page.nextCursor,
    );
  }

  /// Busca a próxima página (`nextCursor`) e a junta às anteriores.
  Future<void> loadMore() async {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        current.nextCursor == null ||
        current.loadingMore) {
      return;
    }
    final filter = ref.read(bankFilterProvider);
    state = AsyncData(current.copyWith(loadingMore: true, moreError: false));
    try {
      final page = await ref
          .read(bankCatalogProvider)
          .search(filter, cursor: current.nextCursor, limit: bankPageSize);
      // O filtro mudou no meio: o `build` já recomeçou, esta página é velha.
      if (!ref.mounted || ref.read(bankFilterProvider) != filter) return;
      state = AsyncData(
        BankListState(
          items: [...current.items, ...page.items],
          total: page.total,
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (!ref.mounted || ref.read(bankFilterProvider) != filter) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreError: true));
    }
  }
}

/// Contadores do acervo para o filtro atual.
final bankFacetsProvider = FutureProvider<QuestionFacets>(
  (ref) => ref.watch(bankCatalogProvider).facets(ref.watch(bankFilterProvider)),
);

/// Total do acervo sem filtro (o "de 1.687" da contagem com contexto).
final bankTotalProvider = FutureProvider<int>((ref) async {
  final page = await ref
      .watch(bankCatalogProvider)
      .search(const QuestionFilter(), limit: 1);
  return page.total;
});

/// Questões que ainda não têm matéria: só aparecem pela busca e pela área.
final bankUnclassifiedProvider = FutureProvider<int>((ref) async {
  final catalog = ref.watch(bankCatalogProvider);
  final total = await ref.watch(bankTotalProvider.future);
  final facets = await catalog.facets(const QuestionFilter());
  final classified = facets.subjects.fold<int>(0, (n, s) => n + s.count);
  return (total - classified).clamp(0, total);
});

/// Uma questão do acervo pelo id estável (`null` se não existir).
final bankQuestionProvider = FutureProvider.family<Question?, String>((
  ref,
  bankId,
) async {
  final found = await ref.watch(bankCatalogProvider).byIds([bankId]);
  return found.isEmpty ? null : found.first;
});

/// Ids (`bank_{id}`) das questões do acervo já salvas em "Minhas questões".
final savedBankIdsProvider = Provider<Set<String>>((ref) {
  final questions = ref.watch(questionsProvider).value ?? const <Question>[];
  return {
    for (final q in questions)
      if (q.origin == QuestionOrigin.bank) q.id,
  };
});

/// Salvar e montar lista a partir do acervo.
final bankActionsProvider = Provider<BankActions>(BankActions.new);

class BankActions {
  BankActions(this._ref);

  final Ref _ref;

  Future<Set<String>> _savedIds() async {
    final questions = await _ref.read(questionsProvider.future);
    return {for (final q in questions) q.id};
  }

  /// Salva a cópia em "Minhas questões". Devolve `false`, sem gravar, se ela
  /// já existe: regravar apagaria as edições do aluno (CA-B4).
  Future<bool> save(Question question) async {
    if ((await _savedIds()).contains(question.id)) return false;
    await _ref.read(questionRepositoryProvider).createMany([question]);
    return true;
  }

  /// Salva as cópias que faltam (as já salvas ficam como estão) e cria a
  /// lista com todas, na ordem dada.
  Future<QuestionList> createList({
    required String name,
    required List<Question> questions,
  }) async {
    if (questions.isEmpty || questions.length > maxBankListQuestions) {
      throw ArgumentError.value(
        questions.length,
        'questions',
        'de 1 a $maxBankListQuestions questões',
      );
    }
    final saved = await _savedIds();
    final fresh = [
      for (final q in questions)
        if (!saved.contains(q.id)) q,
    ];
    if (fresh.isNotEmpty) {
      await _ref.read(questionRepositoryProvider).createMany(fresh);
    }
    return _ref
        .read(listActionsProvider)
        .create(name: name, questionIds: [for (final q in questions) q.id]);
  }
}
