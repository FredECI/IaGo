import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/local/memory_rating_repository.dart';
import 'package:iago/data/local/rating_demo_data.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/rating_models.dart';

const _target = RatingTarget(
  bankId: 'enem-2022-136',
  area: Area.mathematics,
  subject: 'Matemática',
);

RatingTarget _t(String id, {Area area = Area.mathematics}) =>
    RatingTarget(bankId: id, area: area, subject: 'Matemática');

void main() {
  test('CA-A1: avalia, altera e remove; uma avaliação por questão', () async {
    final repo = MemoryRatingRepository(questions: _qs(), useSimulated: false);
    expect(await repo.myRating(_target.bankId), isNull);

    await repo.rate(_target, RatingValue(difficulty: 2, quality: 3));
    expect(
      await repo.myRating(_target.bankId),
      RatingValue(difficulty: 2, quality: 3),
    );

    await repo.rate(_target, RatingValue(difficulty: 3, quality: 1));
    expect(
      await repo.myRating(_target.bankId),
      RatingValue(difficulty: 3, quality: 1),
    );
    // Alterar não duplica: continua 1 avaliação.
    expect((await repo.summary(_target)).question.count, 1);

    await repo.remove(_target.bankId);
    expect(await repo.myRating(_target.bankId), isNull);
    expect((await repo.summary(_target)).question.count, 0);
    await repo.remove(_target.bankId); // idempotente
  });

  test('CA-A2: com 3 avaliações o resumo aparece; com 2, não', () async {
    final repo = MemoryRatingRepository(questions: _qs(), useSimulated: false);
    // Na memória a mesma pessoa só tem uma avaliação por questão: sem
    // simulação, só 1 avaliação por questão existe. O limiar é testado
    // com os dados simulados, que trazem de 2 a 8 por questão.
    expect((await repo.summary(_target)).isEnough, isFalse);

    final sim = MemoryRatingRepository(questions: _qs());
    var few = 0, enough = 0;
    for (var i = 0; i < 200; i++) {
      final s = await sim.summary(_t('enem-2022-$i'));
      final n = RatingDemoData.forQuestion('enem-2022-$i').count;
      expect(s.question.count, n);
      expect(s.isEnough, n >= minRatingsForSummary);
      s.isEnough ? enough++ : few++;
    }
    expect(few, greaterThan(0), reason: 'a demo mostra "Poucas avaliações"');
    expect(enough, greaterThan(few));
  });

  test('CA-A2: compara com a média do grupo, que inclui as minhas', () async {
    final repo = MemoryRatingRepository(questions: _qs());
    final before = await repo.summary(_target);
    expect(before.group.count, RatingDemoData.forGroup('Matemática').count);
    await repo.rate(_target, RatingValue(difficulty: 3, quality: 3));
    final after = await repo.summary(_target);
    expect(after.question.count, before.question.count + 1);
    expect(after.group.count, before.group.count + 1);
    expect(after.groupLabel, 'Matemática');
    expect(
      after.difficultyText,
      anyOf(isNull, contains('média de Matemática')),
    );
  });

  test('CA-A7: o resumo da demo vem marcado como simulado', () async {
    expect(
      (await MemoryRatingRepository(questions: _qs()).summary(_target))
          .simulated,
      isTrue,
    );
    expect(
      (await MemoryRatingRepository(
        questions: _qs(),
        useSimulated: false,
      ).summary(_target)).simulated,
      isFalse,
    );
  });

  test('dados simulados são determinísticos e dentro da escala', () {
    for (var i = 0; i < 300; i++) {
      final id = 'enem-2021-$i';
      final a = RatingDemoData.forQuestion(id);
      final b = RatingDemoData.forQuestion(id);
      expect(a.count, b.count);
      expect(a.difficulty, b.difficulty);
      expect(a.difficulty, inInclusiveRange(1, 3));
      expect(a.quality, inInclusiveRange(1, 3));
      final g = RatingDemoData.forGroup('Física');
      expect(g.difficulty, inInclusiveRange(1, 3));
      expect(g.quality, inInclusiveRange(1, 3));
    }
  });

  test(
    'avaliação privada: vai para o Question sem mexer em updatedAt',
    () async {
      final qs = _qs();
      final repo = MemoryRatingRepository(questions: qs);
      final before = qs.current.single;
      await repo.setPrivateRating('q1', difficulty: 2, quality: 3);
      var q = qs.current.single;
      expect((q.myDifficulty, q.myQuality), (2, 3));
      expect(q.updatedAt, before.updatedAt);
      expect(q.isEdited, isFalse);
      await repo.setPrivateRating('q1');
      q = qs.current.single;
      expect((q.myDifficulty, q.myQuality), (null, null));
      expect(q.updatedAt, before.updatedAt);
      await expectLater(
        repo.setPrivateRating('q1', difficulty: 4),
        throwsA(isA<RatingFailure>()),
      );
      await expectLater(
        repo.setPrivateRating('nao-existe', difficulty: 1),
        throwsA(isA<RatingFailure>()),
      );
    },
  );
}

MemoryQuestionRepository _qs() => MemoryQuestionRepository(
  clock: () => DateTime.utc(2026, 11, 9),
  initial: [
    Question(
      id: 'q1',
      statement: 'x',
      type: QuestionType.objective,
      area: Area.mathematics,
      subject: 'Matemática',
      platform: 'ENEM',
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
      origin: QuestionOrigin.bank,
      bankId: 'enem-2022-1',
    ),
  ],
);
