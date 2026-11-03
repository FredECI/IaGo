import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/list_builder.dart';
import 'package:iago/domain/question.dart';

import '../helpers/test_app.dart';

Question q(String id, QuestionType type) => Question(
  id: id,
  statement: 'x',
  type: type,
  area: Area.mathematics,
  subject: 'Matemática',
  platform: 'Site',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  setUpAll(initTestLocale);

  group('reorderIds (posição final, como o onReorderItem)', () {
    const ids = ['a', 'b', 'c', 'd'];

    test('move para baixo', () {
      expect(reorderIds(ids, 0, 2), ['b', 'c', 'a', 'd']);
    });

    test('move para cima', () {
      expect(reorderIds(ids, 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('índices fora da lista não quebram', () {
      expect(reorderIds(ids, 9, 0), ids);
      expect(reorderIds(ids, 0, 99), ['b', 'c', 'd', 'a']);
    });
  });

  test('appendIds acrescenta no fim sem repetir', () {
    expect(appendIds(['a', 'b'], ['b', 'c', 'c', 'd']), ['a', 'b', 'c', 'd']);
  });

  test('removeId tira só o id pedido', () {
    expect(removeId(['a', 'b', 'c'], 'b'), ['a', 'c']);
  });

  test('resolveQuestions segue a ordem da lista e ignora excluídas', () {
    final questions = [
      q('a', QuestionType.objective),
      q('b', QuestionType.objective),
    ];
    expect(resolveQuestions(['b', 'x', 'a'], questions).map((e) => e.id), [
      'b',
      'a',
    ]);
  });

  test('describeComposition compara objetivas e discursivas', () {
    final obj = q('a', QuestionType.objective);
    final dis = q('b', QuestionType.discursive);
    expect(describeComposition([]), '0 questões');
    expect(describeComposition([obj]), '1 questão · todas objetivas');
    expect(describeComposition([dis, dis]), '2 questões · todas discursivas');
    expect(
      describeComposition([obj, obj, dis]),
      '3 questões · 2 objetivas e 1 discursiva',
    );
  });

  test('nome sugerido e nome de arquivo seguro', () {
    expect(suggestListName(DateTime(2026, 11, 6)), 'Lista de 06/11');
    expect(pdfFileName('Reforço — Funções'), 'Reforço - Funções.pdf');
    expect(pdfFileName('a/b:c*?'), 'abc.pdf');
    expect(pdfFileName('   '), 'lista.pdf');
  });
}
