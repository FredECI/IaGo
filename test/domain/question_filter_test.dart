import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/text_normalizer.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';

Question q(
  String id, {
  required Area area,
  required String subject,
  String topic = '',
  QuestionType type = QuestionType.objective,
  String platform = 'Site',
  String statement = 'Enunciado',
}) => Question(
  id: id,
  statement: statement,
  type: type,
  area: area,
  subject: subject,
  topic: topic,
  platform: platform,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

final questions = [
  q('m1', area: Area.mathematics, subject: 'Matemática', topic: 'Funções'),
  q(
    'm2',
    area: Area.mathematics,
    subject: 'Matemática',
    topic: 'funções',
    type: QuestionType.discursive,
    platform: 'Apostila',
  ),
  q('m3', area: Area.mathematics, subject: 'Matemática', topic: 'Geometria'),
  q(
    'b1',
    area: Area.naturalSciences,
    subject: 'Biologia',
    statement: 'Qual a função da mitocôndria?',
  ),
  q(
    'p1',
    area: Area.languages,
    subject: 'Português',
    topic: 'Funções da linguagem',
    platform: 'Apostila',
  ),
];

List<String> ids(List<Question> items) => [for (final i in items) i.id];

void main() {
  group('QuestionFilter.apply', () {
    test('filtro vazio devolve tudo, na mesma ordem', () {
      expect(ids(const QuestionFilter().apply(questions)), ids(questions));
    });

    test('busca ignora acentos e encontra o plural "Funções"', () {
      final result = const QuestionFilter(query: 'funcao').apply(questions);
      expect(ids(result), ['m1', 'm2', 'b1', 'p1']);
    });

    test('todos os termos da busca precisam aparecer', () {
      final result = const QuestionFilter(query: 'função linguagem')
          .apply(questions);
      expect(ids(result), ['p1']);
    });

    test('opções da mesma dimensão somam (OU) e dimensões cruzam (E)', () {
      final filter = const QuestionFilter()
          .toggleArea(Area.mathematics)
          .toggleArea(Area.languages)
          .togglePlatform(tagKey('apostila'));
      expect(ids(filter.apply(questions)), ['m2', 'p1']);
    });

    test('assunto compara sem diferenciar maiúsculas e acentos', () {
      final filter = const QuestionFilter().toggleTopic(tagKey('FUNCOES'));
      expect(ids(filter.apply(questions)), ['m1', 'm2']);
    });

    test('tocar de novo no mesmo tipo limpa o filtro de tipo', () {
      final once = const QuestionFilter().toggleType(QuestionType.objective);
      expect(once.type, QuestionType.objective);
      expect(once.toggleType(QuestionType.objective).type, isNull);
    });

    test('clearFilters mantém a busca', () {
      final filter = const QuestionFilter(query: 'x')
          .toggleArea(Area.mathematics)
          .clearFilters();
      expect(filter.query, 'x');
      expect(filter.hasFilters, isFalse);
    });
  });

  group('QuestionFacets', () {
    test('contadores sem filtros contam tudo', () {
      final facets = QuestionFacets.compute(questions, const QuestionFilter());
      final areas = {for (final o in facets.areas) o.value: o.count};
      expect(areas, {
        Area.languages: 1,
        Area.humanities: 0,
        Area.naturalSciences: 1,
        Area.mathematics: 3,
      });
      expect(facets.types.map((o) => o.count), [4, 1]);
    });

    test('cada contador respeita a busca e as outras dimensões', () {
      final filter = const QuestionFilter(query: 'função')
          .toggleArea(Area.mathematics);
      final facets = QuestionFacets.compute(questions, filter);
      // Área ignora o próprio filtro: mostra quanto cada área teria.
      final areas = {for (final o in facets.areas) o.value: o.count};
      expect(areas[Area.mathematics], 2);
      expect(areas[Area.languages], 1);
      expect(areas[Area.naturalSciences], 1);
      // Tipo respeita área = Matemática e a busca.
      expect(facets.types.map((o) => o.count), [1, 1]);
      expect(
        facets.areas.firstWhere((o) => o.selected).value,
        Area.mathematics,
      );
    });

    test('assunto agrupa grafias e usa a primeira como rótulo', () {
      final facets = QuestionFacets.compute(questions, const QuestionFilter());
      final top = facets.topics.first;
      expect(top.label, 'Funções');
      expect(top.count, 2);
    });

    test('opção selecionada continua visível mesmo com contador zero', () {
      final filter = const QuestionFilter(query: 'mitocôndria')
          .toggleTopic(tagKey('Geometria'));
      final facets = QuestionFacets.compute(questions, filter);
      final geometry = facets.topics.firstWhere(
        (o) => o.value == tagKey('Geometria'),
      );
      expect(geometry.count, 0);
      expect(geometry.selected, isTrue);
    });
  });
}
