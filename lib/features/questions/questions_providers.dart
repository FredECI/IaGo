import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/area.dart';
import '../../domain/question.dart';
import '../../domain/question_filter.dart';
import '../../domain/suggestions.dart';

/// Todas as questões do usuário atual, mais recentes primeiro.
final questionsProvider = StreamProvider<List<Question>>(
  (ref) => ref.watch(questionRepositoryProvider).watchAll(),
);

/// Uma questão pelo id (`null` se não existir ou ainda não carregou).
final questionByIdProvider = Provider.family<Question?, String>((ref, id) {
  final questions = ref.watch(questionsProvider).value;
  return questions?.firstWhereOrNull((q) => q.id == id);
});

/// Imagem compactada de uma questão (carregada sob demanda).
final questionImageProvider = FutureProvider.family<Uint8List?, String>(
  (ref, id) => ref.watch(questionRepositoryProvider).loadImage(id),
);

/// Busca e filtros da tela de questões (zerados a cada nova sessão).
final questionFilterProvider =
    NotifierProvider<QuestionFilterController, QuestionFilter>(
      QuestionFilterController.new,
    );

class QuestionFilterController extends Notifier<QuestionFilter> {
  @override
  QuestionFilter build() {
    ref.watch(sessionProvider);
    return const QuestionFilter();
  }

  void setQuery(String query) => state = state.copyWith(query: query);

  void toggleArea(Area area) => state = state.toggleArea(area);

  void toggleSubject(String subject) => state = state.toggleSubject(subject);

  void toggleTopic(String topicKey) => state = state.toggleTopic(topicKey);

  void toggleType(QuestionType type) => state = state.toggleType(type);

  void togglePlatform(String platformKey) =>
      state = state.togglePlatform(platformKey);

  void clearDimension(FilterDimension dimension) => state = switch (dimension) {
    FilterDimension.area => state.copyWith(areas: const {}),
    FilterDimension.subject => state.copyWith(subjects: const {}),
    FilterDimension.topic => state.copyWith(topicKeys: const {}),
    FilterDimension.type => state.copyWith(type: null),
    FilterDimension.platform => state.copyWith(platformKeys: const {}),
  };

  void clearAll() => state = const QuestionFilter();

  /// Troca o filtro inteiro (ex.: tocar num assunto na tela "Por conteúdo").
  void replace(QuestionFilter filter) => state = filter;
}

/// Questões que passam na busca e nos filtros atuais.
final filteredQuestionsProvider = Provider<AsyncValue<List<Question>>>((ref) {
  final filter = ref.watch(questionFilterProvider);
  return ref.watch(questionsProvider).whenData(filter.apply);
});

/// Contadores por filtro (`null` enquanto as questões carregam).
final questionFacetsProvider = Provider<QuestionFacets?>((ref) {
  final questions = ref.watch(questionsProvider).value;
  if (questions == null) return null;
  return QuestionFacets.compute(questions, ref.watch(questionFilterProvider));
});

/// Assuntos já usados (da matéria, se informada) para o autocompletar.
final topicSuggestionsProvider = Provider.family<List<String>, String?>((
  ref,
  subject,
) {
  final questions = ref.watch(questionsProvider).value ?? const [];
  return usedTopics(questions, subject: subject);
});

/// Plataformas já usadas para o autocompletar.
final platformSuggestionsProvider = Provider<List<String>>((ref) {
  return usedPlatforms(ref.watch(questionsProvider).value ?? const []);
});

/// Ações que envolvem mais de um repositório.
final questionActionsProvider = Provider<QuestionActions>(QuestionActions.new);

class QuestionActions {
  QuestionActions(this._ref);

  final Ref _ref;

  /// Exclui a questão e a retira das listas em que aparecia.
  Future<void> delete(String id) async {
    await _ref.read(questionRepositoryProvider).delete(id);
    await _ref.read(listRepositoryProvider).removeQuestion(id);
  }
}
