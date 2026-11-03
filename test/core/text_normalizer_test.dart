import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/text_normalizer.dart';

void main() {
  group('foldAccents', () {
    test('remove acentos e passa para minúsculas', () {
      expect(foldAccents('Função ÁGUA Coração'), 'funcao agua coracao');
    });

    test('remove diacríticos combinantes (texto colado de PDF)', () {
      expect(foldAccents('função'), 'funcao');
    });
  });

  group('searchTerms', () {
    test('quebra em termos e reduz o plural "-ões"', () {
      expect(searchTerms('Funções da Linguagem!'), [
        'funcao',
        'da',
        'linguagem',
      ]);
    });

    test('ignora pontuação e espaços extras', () {
      expect(searchTerms('  f(x) = 2x + 1  '), ['f', 'x', '2x', '1']);
    });
  });

  test('tagKey trata grafias diferentes como a mesma tag', () {
    expect(tagKey('  Funções '), tagKey('funcoes'));
    expect(tagKey('Site de Questões'), tagKey('site de questao'));
    expect(tagKey('Funções'), isNot(tagKey('Geometria')));
  });
}
