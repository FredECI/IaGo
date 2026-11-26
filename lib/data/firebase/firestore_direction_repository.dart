import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/area.dart';
import '../../domain/direction_models.dart';
import '../direction_repository.dart';
import 'firestore_mapping.dart';

/// Objetivo em `users/{uid}/direction/goal` e etapas em
/// `users/{uid}/directionSteps/{id}`. A regra atual de `users/{uid}` já cobre
/// os dois caminhos (dono lê e escreve).
class FirestoreDirectionRepository implements DirectionRepository {
  FirestoreDirectionRepository({required this._db, required this._uid});

  final FirebaseFirestore _db;
  final String _uid;

  DocumentReference<Map<String, dynamic>> get _goalDoc =>
      _db.collection('users').doc(_uid).collection('direction').doc('goal');

  CollectionReference<Map<String, dynamic>> get _steps =>
      _db.collection('users').doc(_uid).collection('directionSteps');

  @override
  Stream<StudyGoal?> watchGoal() => _goalDoc.snapshots().map((doc) {
    final data = doc.data();
    return data == null ? null : goalFromMap(fromFirestore(data));
  });

  @override
  Future<void> saveGoal(StudyGoal goal) =>
      commitOrQueue(_goalDoc.set(toFirestore(goalToMap(goal))));

  @override
  Stream<List<StudyStep>> watchSteps() =>
      _steps.orderBy('dueAt').snapshots().map((snapshot) {
        final steps = <StudyStep>[];
        for (final doc in snapshot.docs) {
          final step = stepFromMap(doc.id, fromFirestore(doc.data()));
          if (step != null) steps.add(step); // documento inválido é ignorado
        }
        return steps;
      });

  @override
  Future<void> addSteps(List<StudyStep> steps) async {
    if (steps.isEmpty) return;
    final batch = _db.batch();
    for (final step in steps) {
      batch.set(_steps.doc(step.id), toFirestore(stepToMap(step)));
    }
    await commitOrQueue(batch.commit());
  }

  @override
  Future<void> updateSteps(List<StudyStep> steps) async {
    if (steps.isEmpty) return;
    final batch = _db.batch();
    for (final step in steps) {
      batch.set(_steps.doc(step.id), toFirestore(stepToMap(step)));
    }
    await commitOrQueue(batch.commit());
  }

  @override
  Future<void> updateStep(StudyStep step) =>
      commitOrQueue(_steps.doc(step.id).set(toFirestore(stepToMap(step))));
}

Map<String, Object?> goalToMap(StudyGoal goal) => {
  'exam': goal.exam.wireName,
  'targetDate': goal.targetDate,
  'weeklyHours': goal.weeklyHours,
  'focusAreas': [for (final a in goal.focusAreas) a.name],
  'lastAiAt': goal.lastAiAt,
  'createdAt': goal.createdAt,
  'updatedAt': goal.updatedAt,
};

/// `null` se o documento estiver inválido (a tela volta ao convite). Nunca
/// lança: campo opcional de tipo errado é ignorado; obrigatório inválido
/// descarta o documento.
StudyGoal? goalFromMap(Map<String, Object?> map) {
  final rawExam = map['exam'];
  final exam = ExamTarget.tryParse(rawExam is String ? rawExam : null);
  final hours = map['weeklyHours'];
  final createdAt = map['createdAt'];
  final updatedAt = map['updatedAt'];
  if (exam == null ||
      hours is! int ||
      hours < 1 ||
      hours > 40 ||
      createdAt is! DateTime ||
      updatedAt is! DateTime) {
    return null;
  }
  final focus = map['focusAreas'];
  final targetDate = map['targetDate'];
  final lastAiAt = map['lastAiAt'];
  return StudyGoal(
    exam: exam,
    targetDate: targetDate is DateTime ? targetDate : null,
    weeklyHours: hours,
    focusAreas: [
      if (focus is List)
        for (final name in focus) ?Area.tryParse(name is String ? name : null),
    ],
    lastAiAt: lastAiAt is DateTime ? lastAiAt : null,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

Map<String, Object?> stepToMap(StudyStep s) => {
  'action': s.action.name,
  'area': s.area.name,
  'subject': s.subject,
  'targetCount': s.targetCount,
  'dueAt': s.dueAt,
  'status': s.status.name,
  'postponedAt': s.postponedAt,
  'doneAt': s.doneAt,
  'source': s.source.name,
  'rationale': s.rationale,
  'createdAt': s.createdAt,
};

StudyStep? stepFromMap(String id, Map<String, Object?> map) {
  final rawArea = map['area'];
  final action = StepAction.tryParse(map['action']);
  final area = Area.tryParse(rawArea is String ? rawArea : null);
  final status = StepStatus.values.asNameMap()[map['status']];
  final source = StepSource.values.asNameMap()[map['source']];
  final subject = map['subject'];
  final count = map['targetCount'];
  final dueAt = map['dueAt'];
  final createdAt = map['createdAt'];
  if (action == null ||
      area == null ||
      status == null ||
      source == null ||
      subject is! String ||
      count is! int ||
      count < 1 ||
      !area.subjects.contains(subject) ||
      dueAt is! DateTime ||
      createdAt is! DateTime) {
    return null;
  }
  final postponedAt = map['postponedAt'];
  final doneAt = map['doneAt'];
  final rationale = map['rationale'];
  return StudyStep(
    id: id,
    action: action,
    area: area,
    subject: subject,
    targetCount: count,
    dueAt: dueAt,
    status: status,
    postponedAt: postponedAt is DateTime ? postponedAt : null,
    doneAt: doneAt is DateTime ? doneAt : null,
    source: source,
    rationale: rationale is String ? rationale : '',
    createdAt: createdAt,
  );
}
