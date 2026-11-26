import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/rating_models.dart';
import 'community_write_plans.dart';

String ratingDocId(String bankId, String uid) => '${bankId}_$uid';

/// Avaliar ou alterar: um documento por pessoa e questão. As regras conferem
/// o id, o `uid`, a área, a matéria (1 a 60 caracteres) e a faixa das notas.
List<PlannedWrite> ratePlan({
  required String uid,
  required RatingTarget target,
  required RatingValue value,
}) => [
  PlannedWrite(
    WriteKind.set,
    'questionRatings/${ratingDocId(target.bankId, uid)}',
    {
      'bankId': target.bankId,
      'uid': uid,
      'area': target.area.name,
      'subject': target.group,
      'difficulty': value.difficulty,
      'quality': value.quality,
      'updatedAt': FieldValue.serverTimestamp(),
    },
  ),
];

List<PlannedWrite> removeRatingPlan({
  required String uid,
  required String bankId,
}) => [
  PlannedWrite(WriteKind.delete, 'questionRatings/${ratingDocId(bankId, uid)}'),
];

/// Nota privada na própria questão. Não toca em `updatedAt`.
List<PlannedWrite> privateRatingPlan({
  required String uid,
  required String questionId,
  int? difficulty,
  int? quality,
}) {
  if (difficulty != null && !isValidScore(difficulty) ||
      quality != null && !isValidScore(quality)) {
    throw const RatingFailure(
      RatingFailureKind.invalid,
      'A nota deve ser de 1 a 3.',
    );
  }
  return [
    PlannedWrite(WriteKind.update, 'users/$uid/questions/$questionId', {
      'myDifficulty': difficulty ?? FieldValue.delete(),
      'myQuality': quality ?? FieldValue.delete(),
    }),
  ];
}
