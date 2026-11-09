import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/clock.dart';
import '../../domain/question.dart';
import '../../domain/rating_models.dart';
import '../repositories.dart';
import 'firestore_mapping.dart';
import 'rating_write_plans.dart';

/// Questões em `users/{uid}/questions`; a imagem compactada fica à parte, em
/// `users/{uid}/questionImages/{id}` (lida só no detalhe e no PDF).
class FirestoreQuestionRepository implements QuestionRepository {
  FirestoreQuestionRepository({
    required this._db,
    required this._uid,
    required this._clock,
  });

  final FirebaseFirestore _db;
  final String _uid;
  final Clock _clock;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> get _questions =>
      _user.collection('questions');

  CollectionReference<Map<String, dynamic>> get _images =>
      _user.collection('questionImages');

  @override
  Stream<List<Question>> watchAll() => _questions
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            Question.fromMap(doc.id, fromFirestore(doc.data())),
        ],
      );

  @override
  Future<Question> create(Question question, {Uint8List? image}) async {
    final doc = _questions.doc();
    final now = _clock();
    final saved = question.copyWith(
      id: doc.id,
      createdAt: now,
      updatedAt: now,
      hasImage: image != null,
    );
    final batch = _db.batch()..set(doc, toFirestore(saved.toMap()));
    if (image != null) {
      batch.set(_images.doc(doc.id), {'bytes': Blob(image), 'updatedAt': now});
    }
    await commitOrQueue(batch.commit());
    return saved;
  }

  @override
  Future<List<Question>> createMany(List<Question> questions) async {
    if (questions.length > QuestionRepository.maxCreateMany) {
      throw ArgumentError.value(questions.length, 'questions', 'lote grande');
    }
    if (questions.isEmpty) return const [];
    final now = _clock();
    final batch = _db.batch();
    final saved = <Question>[];
    for (final q in QuestionRepository.dedupeById(questions)) {
      final doc = q.id.isEmpty ? _questions.doc() : _questions.doc(q.id);
      final item = q.copyWith(
        id: doc.id,
        createdAt: now,
        updatedAt: now,
        hasImage: false,
      );
      batch.set(doc, toFirestore(item.toMap()));
      saved.add(item);
    }
    await commitOrQueue(batch.commit());
    return saved;
  }

  @override
  Future<Question> update(
    Question question, {
    Uint8List? image,
    bool removeImage = false,
  }) async {
    final hasImage = image != null || (question.hasImage && !removeImage);
    final saved = question.copyWith(updatedAt: _clock(), hasImage: hasImage);
    final batch = _db.batch()
      ..set(_questions.doc(question.id), toFirestore(saved.toMap()));
    if (image != null) {
      batch.set(_images.doc(question.id), {
        'bytes': Blob(image),
        'updatedAt': saved.updatedAt,
      });
    } else if (removeImage) {
      batch.delete(_images.doc(question.id));
    }
    await commitOrQueue(batch.commit());
    return saved;
  }

  @override
  Future<void> delete(String id) => commitOrQueue(
    (_db.batch()
          ..delete(_questions.doc(id))
          ..delete(_images.doc(id)))
        .commit(),
  );

  @override
  Future<void> setPrivateRating(
    String id, {
    int? difficulty,
    int? quality,
  }) async {
    final plan = privateRatingPlan(
      uid: _uid,
      questionId: id,
      difficulty: difficulty,
      quality: quality,
    );
    final batch = _db.batch();
    for (final w in plan) {
      batch.update(_db.doc(w.path), w.data!);
    }
    try {
      await commitOrQueue(batch.commit());
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        throw const RatingFailure(
          RatingFailureKind.invalid,
          'Questão não encontrada.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List?> loadImage(String questionId) async {
    final snapshot = await _images.doc(questionId).get();
    final blob = snapshot.data()?['bytes'];
    return blob is Blob ? blob.bytes : null;
  }
}
