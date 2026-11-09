import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/rating_models.dart';
import '../rating_repository.dart';
import '../repositories.dart';
import 'community_write_plans.dart';
import 'firestore_mapping.dart';
import 'rating_write_plans.dart';

/// Avaliações no Firestore (`questionRatings/{bankId}_{uid}`, regras em
/// `firestore.rules`). Sem documento contador: o resumo sai de
/// `count()` e `average()` na leitura (ADR 0003, CA-A4).
class FirestoreRatingRepository implements RatingRepository {
  FirestoreRatingRepository({
    required this._db,
    required this._uid,
    required this._questions,
  });

  final FirebaseFirestore _db;
  final String _uid;

  /// Onde mora a nota privada (a própria questão).
  final QuestionRepository _questions;

  /// Agregação não funciona offline: não esperar para sempre.
  static const Duration aggregateTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _ratings =>
      _db.collection('questionRatings');

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on RatingFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw switch (e.code) {
        'permission-denied' => const RatingFailure(
          RatingFailureKind.denied,
          'Sem permissão para avaliar.',
        ),
        'not-found' => const RatingFailure(
          RatingFailureKind.invalid,
          'Questão não encontrada.',
        ),
        _ => const RatingFailure.offline(),
      };
    }
  }

  Future<void> _commit(List<PlannedWrite> plan) {
    final batch = _db.batch();
    for (final w in plan) {
      final ref = _db.doc(w.path);
      switch (w.kind) {
        case WriteKind.set:
          batch.set(ref, w.data!);
        case WriteKind.update:
          batch.update(ref, w.data!);
        case WriteKind.delete:
          batch.delete(ref);
      }
    }
    return commitOrQueue(batch.commit());
  }

  @override
  Future<RatingValue?> myRating(String bankId) => _guard(() async {
    final doc = await _ratings.doc(ratingDocId(bankId, _uid)).get();
    final d = doc.data()?['difficulty'];
    final q = doc.data()?['quality'];
    return isValidScore(d) && isValidScore(q)
        ? RatingValue(difficulty: d as int, quality: q as int)
        : null;
  });

  @override
  Future<void> rate(RatingTarget target, RatingValue value) =>
      _guard(() => _commit(ratePlan(uid: _uid, target: target, value: value)));

  @override
  Future<void> remove(String bankId) =>
      _guard(() => _commit(removeRatingPlan(uid: _uid, bankId: bankId)));

  Future<RatingStats> _stats(Query<Map<String, dynamic>> q) async {
    final snap = await q
        .aggregate(count(), average('difficulty'), average('quality'))
        .get()
        .timeout(
          aggregateTimeout,
          onTimeout: () => throw const RatingFailure.offline(),
        );
    return RatingStats(
      count: snap.count ?? 0,
      difficulty: snap.getAverage('difficulty') ?? 0,
      quality: snap.getAverage('quality') ?? 0,
    );
  }

  @override
  Future<RatingSummary> summary(RatingTarget target) => _guard(() async {
    final question = await _stats(
      _ratings.where('bankId', isEqualTo: target.bankId),
    );
    // Poucas avaliações: nada a comparar, então não gasta a 2ª leitura.
    const empty = RatingStats(count: 0, difficulty: 0, quality: 0);
    final group = question.count < minRatingsForSummary
        ? empty
        : await _stats(_ratings.where('subject', isEqualTo: target.group));
    return RatingSummary(
      question: question,
      group: group,
      groupLabel: target.group,
    );
  });

  @override
  Future<void> setPrivateRating(
    String questionId, {
    int? difficulty,
    int? quality,
  }) => _guard(
    () => _questions.setPrivateRating(
      questionId,
      difficulty: difficulty,
      quality: quality,
    ),
  );
}
