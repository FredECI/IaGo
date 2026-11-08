import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/metric_event.dart';
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

    test('documento antigo, sem os campos novos, vira manual', () {
      final old = Map<String, Object?>.from(sampleQuestion().toMap())
        ..remove('origin')
        ..remove('bankId')
        ..remove('myDifficulty')
        ..remove('myQuality');
      final q = Question.fromMap('old', old);
      expect(q.origin, QuestionOrigin.manual);
      expect(q.bankId, isNull);
      expect(q.myDifficulty, isNull);
      expect(q.myQuality, isNull);
      expect(
        Question.fromMap('x', const {'origin': '???'}).origin,
        QuestionOrigin.manual,
      );
    });

    test('campos novos ida e volta e copyWith', () {
      final q = sampleQuestion().copyWith(
        origin: QuestionOrigin.bank,
        bankId: 'enem-2022-1',
        myDifficulty: 2,
        myQuality: 3,
      );
      final back = Question.fromMap(q.id, q.toMap());
      expect(back, q);
      expect(back.origin, QuestionOrigin.bank);
      expect(back.bankId, 'enem-2022-1');
      expect(q.copyWith(topic: 'x').bankId, 'enem-2022-1');
      expect(q.copyWith(bankId: null, myDifficulty: null).bankId, isNull);
      expect(q.copyWith(myDifficulty: null).myQuality, 3);
    });

    test('isEdited só vale para cópia do acervo alterada depois', () {
      final base = sampleQuestion().copyWith(origin: QuestionOrigin.bank);
      expect(base.isEdited, isTrue);
      expect(base.copyWith(updatedAt: base.createdAt).isEdited, isFalse);
      expect(sampleQuestion().isEdited, isFalse);
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

  group('MetricEventType', () {
    test('códigos novos da spec existem e são únicos', () {
      for (final code in [
        'questions_bulk_saved',
        'import_run',
        'direction_plan_created',
        'direction_step_done',
        'direction_step_missed',
        'ai_fallback',
        'rating_saved',
        'community_post',
        'community_reply',
        'helpful_given',
        'report_filed',
      ]) {
        expect(MetricEventType.tryParse(code), isNotNull, reason: code);
      }
      final codes = MetricEventType.values.map((t) => t.code).toSet();
      expect(codes, hasLength(MetricEventType.values.length));
    });

    test('dado chamado type não sobrescreve o tipo do evento', () {
      final at = DateTime(2026);
      final e = MetricEvent(
        type: MetricEventType.questionsBulkSaved,
        at: at,
        data: const {'type': 'x', 'origin': 'bank', 'count': 3},
      );
      expect(e.toMap()['type'], 'questions_bulk_saved');
      expect(e.toMap()['at'], at);
      expect(e.toMap()['count'], 3);
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
