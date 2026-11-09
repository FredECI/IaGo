import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase/firestore_rating_repository.dart';
import '../../data/local/memory_rating_repository.dart';
import '../../data/providers.dart';
import '../../data/rating_repository.dart';
import '../../domain/rating_models.dart';
import '../../domain/session.dart';

/// Demo -> memória com avaliações simuladas (estado novo a cada `DemoSession`);
/// conta -> Firestore; sem sessão -> memória sem dados simulados. Quem pode
/// avaliar (membro) é decidido pela política de acesso, na tela. A nota
/// privada vai para o repositório de questões da mesma sessão.
final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  final questions = ref.watch(questionRepositoryProvider);
  if (owner case final String uid) {
    return FirestoreRatingRepository(
      db: FirebaseFirestore.instance,
      uid: uid,
      questions: questions,
    );
  }
  return MemoryRatingRepository(
    questions: questions,
    useSimulated: owner is DemoSession,
  );
});

/// Resumo sob demanda; recarrega com `ref.invalidate`.
final ratingSummaryProvider = FutureProvider.autoDispose
    .family<RatingSummary, RatingTarget>(
      (ref, target) => ref.watch(ratingRepositoryProvider).summary(target),
    );

/// Minha avaliação pública da questão (por `bankId`).
final myRatingProvider = FutureProvider.autoDispose
    .family<RatingValue?, String>(
      (ref, bankId) => ref.watch(ratingRepositoryProvider).myRating(bankId),
    );
