import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/firestore_mapping.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';

Question bankQuestion() => Question(
  id: 'bank_enem-2022-1',
  statement: 'Enunciado',
  type: QuestionType.objective,
  alternatives: const ['a', 'b', 'c', 'd', 'e'],
  area: Area.mathematics,
  subject: 'Matemática',
  platform: 'ENEM 2022',
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 2),
  origin: QuestionOrigin.bank,
  bankId: 'enem-2022-1',
  myDifficulty: 2,
);

void main() {
  test('campos novos vão para o Firestore e voltam', () {
    final q = bankQuestion();
    final stored = toFirestore(q.toMap());
    expect(stored['origin'], 'bank');
    expect(stored['bankId'], 'enem-2022-1');
    expect(stored['myDifficulty'], 2);
    expect(stored.containsKey('myQuality'), isFalse);

    final read = {
      for (final e in stored.entries)
        e.key: e.value is DateTime
            ? Timestamp.fromDate(e.value! as DateTime)
            : e.value,
    };
    expect(Question.fromMap(q.id, fromFirestore(read)), q);
  });

  test('documento antigo do Firestore vira manual', () {
    final stored = toFirestore(bankQuestion().toMap())
      ..remove('origin')
      ..remove('bankId')
      ..remove('myDifficulty');
    final q = Question.fromMap('old', fromFirestore(stored));
    expect(q.origin, QuestionOrigin.manual);
    expect(q.bankId, isNull);
  });
}
