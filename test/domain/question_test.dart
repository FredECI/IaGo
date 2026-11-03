import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_list.dart';

Question sampleQuestion() => Question(
  id: 'q1',
  statement: 'Considere a função f(x) = 2x + 1.',
  type: QuestionType.objective,
  alternatives: const ['1', '2', '3', '4', '5'],
  area: Area.mathematics,
  subject: 'Matemática',
  topic: 'Funções',
  platform: 'Site de questões',
  sourceUrl: 'https://example.com/q1',
  notes: 'revisar',
  createdAt: DateTime(2026, 11, 1, 10),
  updatedAt: DateTime(2026, 11, 2, 10),
);

void main() {
  group('Question', () {
    test('toMap/fromMap preserva todos os campos', () {
      final q = sampleQuestion();
      expect(Question.fromMap(q.id, q.toMap()), q);
    });

    test('fromMap tolera campos ausentes', () {
      final q = Question.fromMap('x', const {});
      expect(q.statement, '');
      expect(q.type, QuestionType.discursive);
      expect(q.alternatives, isEmpty);
      expect(q.subject, q.area.subjects.first);
    });

    test('copyWith consegue limpar campos opcionais', () {
      final q = sampleQuestion().copyWith(sourceUrl: null, notes: null);
      expect(q.sourceUrl, isNull);
      expect(q.notes, isNull);
      expect(sampleQuestion().copyWith(topic: 'Gráficos').topic, 'Gráficos');
    });

    test('texto de busca inclui enunciado, alternativas e categoria', () {
      final text = sampleQuestion().searchText;
      expect(text, contains('funcao'));
      expect(text, contains('matematica'));
      expect(text, contains('site de questao'));
      expect(text, contains('revisar'));
    });

    test('alternativas são imutáveis', () {
      expect(
        () => sampleQuestion().alternatives.add('6'),
        throwsUnsupportedError,
      );
    });
  });

  group('Area', () {
    test('Matemática tem matéria padrão; as demais não', () {
      expect(Area.mathematics.defaultSubject, 'Matemática');
      expect(Area.languages.defaultSubject, isNull);
      expect(Area.tryParse('naturalSciences'), Area.naturalSciences);
      expect(Area.tryParse('???'), isNull);
    });
  });

  group('QuestionList', () {
    test('toMap/fromMap preserva todos os campos', () {
      final list = QuestionList(
        id: 'l1',
        name: 'Reforço — Funções',
        questionIds: const ['a', 'b'],
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 2),
        exportCount: 2,
        lastExportedAt: DateTime(2026, 11, 3),
      );
      expect(QuestionList.fromMap(list.id, list.toMap()), list);
    });
  });
}
