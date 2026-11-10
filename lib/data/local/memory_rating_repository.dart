import '../../domain/rating_models.dart';
import '../rating_repository.dart';
import '../repositories.dart';
import 'rating_demo_data.dart';

/// Avaliações em memória (demo e testes). Sobre os dados simulados de
/// [RatingDemoData] entram as avaliações feitas na sessão, então avaliar ao
/// vivo muda o resumo. O resumo sai marcado como simulado (CA-A7).
class MemoryRatingRepository implements RatingRepository {
  MemoryRatingRepository({required this._questions, this.useSimulated = true});

  /// `false` nos testes que querem contar só as avaliações feitas.
  final bool useSimulated;

  /// Onde mora a nota privada (a própria questão).
  final QuestionRepository _questions;

  final Map<String, RatingValue> _mine = {};
  final Map<String, RatingTarget> _targets = {};

  @override
  Future<RatingValue?> myRating(String bankId) async => _mine[bankId];

  @override
  Future<void> rate(RatingTarget target, RatingValue value) async {
    _mine[target.bankId] = value;
    _targets[target.bankId] = target;
  }

  /// Exclusão de conta (C5): apaga todas as avaliações públicas feitas.
  void eraseMyData() {
    _mine.clear();
    _targets.clear();
  }

  @override
  Future<void> remove(String bankId) async {
    _mine.remove(bankId);
    _targets.remove(bankId);
  }

  static RatingStats _add(RatingStats base, Iterable<RatingValue> extra) {
    var n = base.count;
    var d = base.difficulty * n;
    var q = base.quality * n;
    for (final v in extra) {
      n++;
      d += v.difficulty;
      q += v.quality;
    }
    return n == 0
        ? const RatingStats(count: 0, difficulty: 0, quality: 0)
        : RatingStats(count: n, difficulty: d / n, quality: q / n);
  }

  @override
  Future<RatingSummary> summary(RatingTarget target) async {
    const none = RatingStats(count: 0, difficulty: 0, quality: 0);
    final mineHere = _mine[target.bankId];
    final question = _add(
      useSimulated ? RatingDemoData.forQuestion(target.bankId) : none,
      [?mineHere],
    );
    final groupMine = [
      for (final e in _mine.entries)
        if (_targets[e.key]?.group == target.group) e.value,
    ];
    final group = _add(
      useSimulated ? RatingDemoData.forGroup(target.group) : none,
      groupMine,
    );
    return RatingSummary(
      question: question,
      group: group,
      groupLabel: target.group,
      simulated: useSimulated,
    );
  }

  @override
  Future<void> setPrivateRating(
    String questionId, {
    int? difficulty,
    int? quality,
  }) => _questions.setPrivateRating(
    questionId,
    difficulty: difficulty,
    quality: quality,
  );
}
