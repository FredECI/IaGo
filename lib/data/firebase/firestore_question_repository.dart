import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/clock.dart';
import '../../domain/question.dart';
import '../repositories.dart';
import 'firestore_mapping.dart';

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
  Future<Uint8List?> loadImage(String questionId) async {
    final snapshot = await _images.doc(questionId).get();
    final blob = snapshot.data()?['bytes'];
    return blob is Blob ? blob.bytes : null;
  }
}
