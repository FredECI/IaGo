import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/rating_models.dart';

RatingSummary _summary({
  required int count,
  required double d,
  required double gd,
  double q = 2.6,
  double gq = 2.1,
}) => RatingSummary(
  question: RatingStats(count: count, difficulty: d, quality: q),
  group: RatingStats(count: 80, difficulty: gd, quality: gq),
  groupLabel: 'Matemática',
);

void main() {
  group('RatingValue (CA-A3)', () {
    test('aceita de 1 a 3', () {
      for (final d in [1, 2, 3]) {
        for (final q in [1, 2, 3]) {
          expect(RatingValue(difficulty: d, quality: q).difficulty, d);
        }
      }
    });

    test('nota fora da faixa nunca é construída', () {
      for (final bad in [0, 4, -1, 99]) {
        expect(
          () => RatingValue(difficulty: bad, quality: 2),
          throwsA(isA<RatingFailure>()),
        );
        expect(
          () => RatingValue(difficulty: 2, quality: bad),
          throwsA(isA<RatingFailure>()),
        );
      }
    });
  });

  group('RatingTarget.group (matéria vazia)', () {
    test('usa a matéria quando existe', () {
      const t = RatingTarget(
        bankId: 'enem-2022-136',
        area: Area.naturalSciences,
        subject: ' Física ',
      );
      expect(t.group, 'Física');
    });

    test('sem matéria, usa o rótulo da área (1 a 60 caracteres)', () {
      for (final area in Area.values) {
        final t = RatingTarget(bankId: 'enem-2022-1', area: area, subject: '');
        expect(t.group, area.label);
        expect(t.group.length, inInclusiveRange(1, 60));
      }
      const blank = RatingTarget(
        bankId: 'enem-2022-1',
        area: Area.humanities,
        subject: '   ',
      );
      expect(blank.group, 'Ciências Humanas');
    });

    test('matéria longa é cortada em 60', () {
      final t = RatingTarget(
        bankId: 'enem-2022-1',
        area: Area.languages,
        subject: 'x' * 90,
      );
      expect(t.group.length, 60);
    });

    test('alvos iguais são iguais (chave de provider)', () {
      const a = RatingTarget(
        bankId: 'enem-2022-1',
        area: Area.languages,
        subject: 'Inglês',
      );
      const b = RatingTarget(
        bankId: 'enem-2022-1',
        area: Area.languages,
        subject: 'Inglês',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('RatingSummary (CA-A2)', () {
    test('limiar: 2 avaliações não bastam, 3 bastam', () {
      expect(_summary(count: 2, d: 2.4, gd: 1.9).isEnough, isFalse);
      expect(_summary(count: 2, d: 2.4, gd: 1.9).difficultyText, isNull);
      expect(_summary(count: 3, d: 2.4, gd: 1.9).isEnough, isTrue);
      expect(RatingSummary.fewMessage, 'Poucas avaliações ainda');
    });

    test('compara com a média da matéria, com números e total', () {
      expect(
        _summary(count: 7, d: 2.4, gd: 1.9).difficultyText,
        'Mais difícil que a média de Matemática (2,4 × 1,9; 7 avaliações)',
      );
      expect(
        _summary(count: 7, d: 1.3, gd: 1.9).difficultyText,
        'Mais fácil que a média de Matemática (1,3 × 1,9; 7 avaliações)',
      );
      expect(
        _summary(count: 7, d: 2.0, gd: 1.9).difficultyText,
        'Dificuldade na média de Matemática (2,0 × 1,9; 7 avaliações)',
      );
      expect(
        _summary(count: 7, d: 2.0, gd: 2.0, q: 2.6, gq: 2.1).qualityText,
        'Melhor avaliada que a média de Matemática (2,6 × 2,1; 7 avaliações)',
      );
      expect(
        _summary(count: 7, d: 2.0, gd: 2.0, q: 1.4, gq: 2.1).qualityText,
        startsWith('Pior avaliada que a média'),
      );
    });
  });

  test('mensagem sem rede (CA-A4)', () {
    expect(
      const RatingFailure.offline().message,
      'Avaliações indisponíveis sem conexão',
    );
  });
}
