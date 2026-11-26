import '../domain/bank_source.dart';
import '../domain/question.dart';
import '../domain/question_filter.dart';

/// Acervo de questões (CA-R3). As telas só conhecem esta interface: trocar o
/// asset por Firestore ou API própria só muda a implementação.
abstract interface class BankCatalog {
  /// Uma página do resultado. O cursor é opaco: só a implementação o entende.
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  });

  /// Contadores por faceta, com a mesma semântica de [QuestionFacets].
  Future<QuestionFacets> facets(QuestionFilter filter);

  /// Questões pelos ids estáveis (salvar e montar lista), na ordem pedida.
  /// Id desconhecido é ignorado.
  Future<List<Question>> byIds(List<String> bankIds);

  /// Fontes registradas, com atribuição.
  Future<List<BankSource>> sources();
}

class BankPage {
  const BankPage({required this.items, required this.total, this.nextCursor});

  /// Questões com `origin == bank`.
  final List<Question> items;

  /// Total de resultados da busca (todas as páginas).
  final int total;

  /// `null` na última página.
  final String? nextCursor;
}
