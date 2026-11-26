import '../../domain/rating_models.dart';

/// Avaliações simuladas da demo (CA-A7). Determinísticas: o mesmo `bankId`
/// sempre dá o mesmo resultado, em qualquer plataforma (FNV-1a, não
/// `String.hashCode`).
class RatingDemoData {
  const RatingDemoData._();

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// De 2 a 8 avaliações por questão: algumas ficam abaixo do limiar de 3 e
  /// mostram "Poucas avaliações ainda".
  static RatingStats forQuestion(String bankId) {
    final h = _fnv(bankId);
    return RatingStats(
      count: 2 + h % 7,
      difficulty: 1.2 + ((h >> 8) % 17) / 10,
      quality: 1.4 + ((h >> 16) % 13) / 10,
    );
  }

  /// Média do grupo (matéria ou área): perto do meio da escala.
  static RatingStats forGroup(String group) {
    final h = _fnv('grupo:$group');
    return RatingStats(
      count: 40 + h % 60,
      difficulty: 1.7 + ((h >> 8) % 7) / 10,
      quality: 1.9 + ((h >> 16) % 5) / 10,
    );
  }
}
