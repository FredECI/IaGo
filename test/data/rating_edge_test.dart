import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/community_write_plans.dart';
import 'package:iago/data/firebase/rating_write_plans.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/local/memory_rating_repository.dart';
import 'package:iago/data/local/rating_demo_data.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/rating_models.dart';

RatingTarget _t(
  String id, {
  Area area = Area.mathematics,
  String subject = 'Matemática',
}) => RatingTarget(bankId: id, area: area, subject: subject);

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
    ),
  ],
);

RatingSummary _s(double d, double gd, {int count = 5}) => RatingSummary(
  question: RatingStats(count: count, difficulty: d, quality: 2),
  group: RatingStats(count: 50, difficulty: gd, quality: 2),
  groupLabel: 'Matemática',
);

String _firstId({required int count}) {
  for (var i = 0; i < 500; i++) {
    final id = 'enem-2020-$i';
    if (RatingDemoData.forQuestion(id).count == count) return id;
  }
  throw StateError('sem id com $count avaliações');
}

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

void main() {
  group('limiar de 3 avaliações (CA-A2) pelo repositório', () {
    test('2 simuladas + a minha = 3: o resumo passa a aparecer', () async {
      final id = _firstId(count: 2);
      final repo = MemoryRatingRepository(questions: _qs());
      expect((await repo.summary(_t(id))).isEnough, isFalse);
      expect((await repo.summary(_t(id))).difficultyText, isNull);
      await repo.rate(_t(id), RatingValue(difficulty: 2, quality: 2));
      final three = await repo.summary(_t(id));
      expect(three.question.count, 3);
      expect(three.isEnough, isTrue);
      expect(three.difficultyText, isNotNull);
      await repo.remove(id);
      expect((await repo.summary(_t(id))).isEnough, isFalse);
    });

    test('avaliar várias vezes a mesma questão conta uma só', () async {
      final id = _firstId(count: 2);
      final repo = MemoryRatingRepository(questions: _qs());
      for (var i = 0; i < 5; i++) {
        await repo.rate(_t(id), RatingValue(difficulty: 1, quality: 1));
      }
      expect((await repo.summary(_t(id))).question.count, 3);
    });
  });

  group('empate e margem de "na média"', () {
    test('médias iguais: na média', () {
      expect(_s(2.0, 2.0).difficultyText, startsWith('Dificuldade na média'));
    });

    test('diferença de 0,1 é na média; de 0,3 não é', () {
      expect(_s(2.1, 2.0).difficultyText, startsWith('Dificuldade na média'));
      expect(_s(2.3, 2.0).difficultyText, startsWith('Mais difícil'));
      expect(_s(1.7, 2.0).difficultyText, startsWith('Mais fácil'));
    });

    test(
      'regressão: diferença exata de 0,2 não é "na média" (menor que 0,2)',
      () {
        // 2.0 - 1.8 = 0.19999999999999996 em ponto flutuante; o texto mostra
        // "2,0 × 1,8" e diz "na média", contra a regra "menor que 0,2".
        expect(_s(2.0, 1.8).difficultyText, startsWith('Mais difícil'));
        expect(_s(1.8, 2.0).difficultyText, startsWith('Mais fácil'));
      },
    );
  });

  group('matéria vazia e longa', () {
    test('sem matéria: o grupo é a área e o resumo compara com ela', () async {
      final repo = MemoryRatingRepository(
        questions: _qs(),
        useSimulated: false,
      );
      final t = _t('enem-2022-5', area: Area.humanities, subject: '');
      await repo.rate(t, RatingValue(difficulty: 3, quality: 3));
      final s = await repo.summary(t);
      expect(s.groupLabel, 'Ciências Humanas');
      expect(s.group.count, 1);
      final u = _t('enem-2022-6', area: Area.humanities, subject: '  ');
      expect((await repo.summary(u)).group.count, 1);
      final v = _t('enem-2022-7', area: Area.languages, subject: '');
      expect((await repo.summary(v)).group.count, 0);
    });

    test('matéria com mais de 60 caracteres é cortada no rótulo', () async {
      final repo = MemoryRatingRepository(
        questions: _qs(),
        useSimulated: false,
      );
      await repo.rate(
        _t('enem-2022-8', subject: 'y' * 90),
        RatingValue(difficulty: 1, quality: 1),
      );
      final s = await repo.summary(_t('enem-2022-9', subject: 'y' * 75));
      expect(s.groupLabel, 'y' * 60);
      expect(s.group.count, 1);
    });

    test('limite de 60 caracteres', () {
      expect(_t('enem-1-1', subject: 'z' * 60).group, 'z' * 60);
      expect(_t('enem-1-1', subject: 'z' * 61).group, 'z' * 60);
    });
  });

  group('nota privada', () {
    test('limpar com null apaga as duas; parcial apaga a outra', () async {
      final qs = _qs();
      final repo = MemoryRatingRepository(questions: qs);
      await repo.setPrivateRating('q1', difficulty: 2, quality: 3);
      await repo.setPrivateRating('q1', difficulty: 1);
      var q = qs.current.single;
      expect((q.myDifficulty, q.myQuality), (1, null));
      await repo.setPrivateRating('q1');
      q = qs.current.single;
      expect((q.myDifficulty, q.myQuality), (null, null));
    });

    test('nota inválida não altera o estado nem o updatedAt', () async {
      final qs = _qs();
      final repo = MemoryRatingRepository(questions: qs);
      await repo.setPrivateRating('q1', difficulty: 2, quality: 2);
      for (final bad in [0, 4, -1]) {
        await expectLater(
          repo.setPrivateRating('q1', difficulty: 3, quality: bad),
          throwsA(isA<RatingFailure>()),
        );
      }
      final q = qs.current.single;
      expect((q.myDifficulty, q.myQuality), (2, 2));
      expect(q.updatedAt, DateTime.utc(2026, 11, 1));
    });

    test('a nota privada não mexe na avaliação pública', () async {
      final repo = MemoryRatingRepository(
        questions: _qs(),
        useSimulated: false,
      );
      await repo.setPrivateRating('q1', difficulty: 3, quality: 3);
      expect(await repo.myRating('enem-2022-1'), isNull);
      expect((await repo.summary(_t('enem-2022-1'))).question.count, 0);
    });
  });

  group('planos de escrita', () {
    test('o id leva o uid: duas pessoas, dois documentos', () {
      final v = RatingValue(difficulty: 1, quality: 2);
      final a = ratePlan(uid: 'ana', target: _t('enem-2022-1'), value: v);
      final b = ratePlan(uid: 'bob', target: _t('enem-2022-1'), value: v);
      expect(a.single.path, 'questionRatings/enem-2022-1_ana');
      expect(b.single.path, 'questionRatings/enem-2022-1_bob');
      expect(a.single.data!['uid'], 'ana');
      expect(a.single.data!['bankId'], 'enem-2022-1');
    });

    test('subject gravado tem de 1 a 60 caracteres, sempre', () {
      final v = RatingValue(difficulty: 1, quality: 1);
      for (final s in ['', '   ', 'a', 'x' * 60, 'x' * 61, 'x' * 500]) {
        final d = ratePlan(
          uid: 'ana',
          target: _t('enem-2022-1', subject: s),
          value: v,
        ).single.data!;
        expect((d['subject'] as String).length, inInclusiveRange(1, 60));
      }
    });

    test('a avaliação pública grava só os campos que as regras aceitam', () {
      final d = ratePlan(
        uid: 'ana',
        target: _t('enem-2022-1'),
        value: RatingValue(difficulty: 1, quality: 1),
      ).single.data!;
      expect(d.keys.toSet(), {
        'bankId',
        'uid',
        'area',
        'subject',
        'difficulty',
        'quality',
        'updatedAt',
      });
    });

    test('nota privada: só toca em myDifficulty e myQuality', () {
      for (final p in [
        privateRatingPlan(uid: 'a', questionId: 'q', difficulty: 1, quality: 2),
        privateRatingPlan(uid: 'a', questionId: 'q'),
        privateRatingPlan(uid: 'a', questionId: 'q', quality: 3),
      ]) {
        expect(p.single.kind, WriteKind.update);
        expect(p.single.path, 'users/a/questions/q');
        expect(p.single.data!.keys.toSet(), {'myDifficulty', 'myQuality'});
      }
    });

    test('remover mira só o documento da própria pessoa', () {
      final p = removeRatingPlan(uid: 'ana', bankId: 'enem-2022-1').single;
      expect(p.kind, WriteKind.delete);
      expect(p.path, 'questionRatings/enem-2022-1_ana');
    });
  });

  test('isValidScore rejeita nulo, decimal, texto e fora da faixa', () {
    for (final bad in <Object?>[null, 0, 4, 2.5, '2', -1, true]) {
      expect(isValidScore(bad), isFalse, reason: '$bad');
    }
    for (final ok in [1, 2, 3]) {
      expect(isValidScore(ok), isTrue);
    }
  });

  test('CA-A4: falha sem rede tem tipo e mensagem esperados', () {
    const f = RatingFailure.offline();
    expect(f.kind, RatingFailureKind.unavailable);
    expect(f.message, 'Avaliações indisponíveis sem conexão');
    expect(f.toString(), 'Avaliações indisponíveis sem conexão');
    expect(f, isA<Exception>());
  });

  group('varredura do código', () {
    test('CA-T5: nenhum arquivo em lib/ importa flutter/material.dart', () {
      for (final f in _dartFiles('lib')) {
        expect(
          f.readAsStringSync().contains('package:flutter/material.dart'),
          isFalse,
          reason: f.path,
        );
      }
    });

    test('CA-A6: o código das avaliações não fala em alternativa correta', () {
      final files = [
        'lib/domain/rating_models.dart',
        'lib/data/rating_repository.dart',
        'lib/data/firebase/rating_write_plans.dart',
        'lib/data/firebase/firestore_rating_repository.dart',
        'lib/data/local/memory_rating_repository.dart',
        'lib/data/local/rating_demo_data.dart',
        ..._dartFiles('lib/features/rating').map((f) => f.path),
      ];
      final re = RegExp(
        r'acertei|alternativa correta|gabarito|correctAnswer|isCorrect',
        caseSensitive: false,
      );
      for (final p in files) {
        expect(re.hasMatch(File(p).readAsStringSync()), isFalse, reason: p);
      }
    });

    test('CA-A4: o app não cria documento contador de avaliações', () {
      final re = RegExp(r'ratingCount|ratingCounter|questionRatingCount');
      for (final f in _dartFiles('lib')) {
        expect(re.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('CA-R4: as avaliações usam o bankId, não o id local da questão', () {
      expect(ratingDocId('enem-2022-1', 'ana'), 'enem-2022-1_ana');
      final p = ratePlan(
        uid: 'ana',
        target: _t('obmep-2019-12'),
        value: RatingValue(difficulty: 1, quality: 1),
      ).single;
      expect(p.path, 'questionRatings/obmep-2019-12_ana');
    });
  });
}
