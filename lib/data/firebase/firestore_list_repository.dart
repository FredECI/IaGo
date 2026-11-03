import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/clock.dart';
import '../../domain/question_list.dart';
import '../repositories.dart';
import 'firestore_mapping.dart';

/// Listas em `users/{uid}/lists` (só nome e ordem dos ids; o PDF não é salvo).
class FirestoreListRepository implements ListRepository {
  FirestoreListRepository({
    required this._db,
    required this._uid,
    required this._clock,
  });

  final FirebaseFirestore _db;
  final String _uid;
  final Clock _clock;

  CollectionReference<Map<String, dynamic>> get _lists =>
      _db.collection('users').doc(_uid).collection('lists');

  @override
  Stream<List<QuestionList>> watchAll() => _lists
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            QuestionList.fromMap(doc.id, fromFirestore(doc.data())),
        ],
      );

  @override
  Future<QuestionList> create(QuestionList list) async {
    final doc = _lists.doc();
    final now = _clock();
    final saved = list.copyWith(id: doc.id, createdAt: now, updatedAt: now);
    await commitOrQueue(doc.set(toFirestore(saved.toMap())));
    return saved;
  }

  @override
  Future<QuestionList> update(QuestionList list) async {
    final saved = list.copyWith(updatedAt: _clock());
    await commitOrQueue(_lists.doc(list.id).set(toFirestore(saved.toMap())));
    return saved;
  }

  @override
  Future<void> delete(String id) => commitOrQueue(_lists.doc(id).delete());

  @override
  Future<QuestionList> registerExport(String id) async {
    final now = _clock();
    final doc = _lists.doc(id);
    await commitOrQueue(
      doc.update({
        'exportCount': FieldValue.increment(1),
        'lastExportedAt': now,
      }),
    );
    final snapshot = await doc.get();
    return QuestionList.fromMap(id, fromFirestore(snapshot.data() ?? {}));
  }

  @override
  Future<void> removeQuestion(String questionId) async {
    final affected = await _lists
        .where('questionIds', arrayContains: questionId)
        .get();
    if (affected.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in affected.docs) {
      batch.update(doc.reference, {
        'questionIds': FieldValue.arrayRemove([questionId]),
        'updatedAt': _clock(),
      });
    }
    await commitOrQueue(batch.commit());
  }
}
