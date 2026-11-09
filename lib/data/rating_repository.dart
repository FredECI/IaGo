import '../domain/rating_models.dart';

/// Avaliações das questões (dificuldade e qualidade, 1 a 3), chaveadas pelo id
/// estável do acervo (`bankId`, CA-R4). Implementações: memória (demo, com
/// dados simulados) e Firestore. Falhas esperadas lançam [RatingFailure].
abstract interface class RatingRepository {
  /// Minha avaliação pública da questão do acervo; `null` se não avaliei.
  Future<RatingValue?> myRating(String bankId);

  /// Avalia ou altera. Uma avaliação por pessoa e questão (id fixo).
  Future<void> rate(RatingTarget target, RatingValue value);

  /// Remove a minha avaliação (se não existir, não faz nada).
  Future<void> remove(String bankId);

  /// Resumo da questão contra a média da matéria, calculado na leitura (sem
  /// contador, ADR 0003). Sem rede lança `RatingFailure.offline()`.
  Future<RatingSummary> summary(RatingTarget target);

  /// Avaliação privada de uma questão minha, guardada na própria questão
  /// (`myDifficulty` e `myQuality`), **sem mudar `updatedAt`**: mudar marcaria
  /// a cópia do acervo como "editada". `null` apaga a nota.
  Future<void> setPrivateRating(
    String questionId, {
    int? difficulty,
    int? quality,
  });
}
