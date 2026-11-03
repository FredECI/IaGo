import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/suggestions.dart';

Question q(String subject, String topic, String platform) => Question(
  id: '$subject$topic$platform',
  statement: 'x',
  type: QuestionType.objective,
  area: subject == 'Matemática' ? Area.mathematics : Area.naturalSciences,
  subject: subject,
  topic: topic,
  platform: platform,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  final questions = [
    q('Matemática', 'Funções', 'Site A'),
    q('Matemática', 'funções', 'Site A'),
    q('Matemática', 'Geometria', 'Apostila'),
    q('Biologia', 'Genética', 'Site A'),
    q('Biologia', '', 'Livro didático'),
  ];

  test('assuntos usados agrupam grafias e vêm por frequência', () {
    expect(usedTopics(questions), ['Funções', 'Genética', 'Geometria']);
  });

  test('assuntos podem ser restritos à matéria', () {
    expect(usedTopics(questions, subject: 'Matemática'), [
      'Funções',
      'Geometria',
    ]);
    expect(usedTopics(questions, subject: 'Física'), isEmpty);
  });

  test('plataformas usadas vêm antes das comuns, sem repetir', () {
    final platforms = usedPlatforms(questions);
    expect(platforms.take(3), ['Site A', 'Apostila', 'Livro didático']);
    expect(
      platforms.where((p) => p == 'Livro didático'),
      hasLength(1),
      reason: 'a comum igual a uma usada não se repete',
    );
    expect(platforms, contains('App de simulados'));
  });

  test('sugestões filtram pelo que foi digitado, sem acento', () {
    final options = ['Funções', 'Funções da linguagem', 'Geometria'];
    expect(matchSuggestions(options, 'func'), [
      'Funções',
      'Funções da linguagem',
    ]);
    expect(matchSuggestions(options, ''), options);
    expect(matchSuggestions(options, 'funções'), [
      'Funções da linguagem',
    ], reason: 'não sugere o texto que já está no campo');
  });
}
