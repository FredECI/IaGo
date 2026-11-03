import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/demo_seed.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/dashboard_summary.dart';
import 'package:iago/domain/question.dart';

void main() {
  final now = DateTime(2026, 11, 6, 14);

  test('seed da demo: 8 nos últimos 7 dias, 3 a mais que antes', () {
    final seed = DemoSeed.build(now);
    final summary = buildDashboardSummary(
      questions: seed.questions,
      lists: seed.lists,
      now: now,
    );
    expect(summary.questionsSaved.current, 8);
    expect(summary.questionsSaved.previous, 5);
    expect(
      summary.questionsSaved.describe(),
      '3 a mais que nos 7 dias anteriores',
    );
    expect(summary.listsCreated.current, 1);
    expect(summary.listsCreated.previous, 1);
    expect(
      summary.listsCreated.describe(),
      'o mesmo número dos 7 dias anteriores',
    );
    expect(summary.topArea?.area, Area.mathematics);
    expect(summary.topArea?.percent, 40);
    expect(summary.areasCovered, 4);
  });

  test('a comparação descreve queda e acerta as bordas das janelas', () {
    Question at(DateTime date) => Question(
      id: '$date',
      statement: 'x',
      type: QuestionType.objective,
      area: Area.humanities,
      subject: 'História',
      platform: 'Site',
      createdAt: date,
      updatedAt: date,
    );
    final questions = [
      at(now.subtract(const Duration(days: 1))), // agora
      at(now.subtract(const Duration(days: 8))), // antes
      at(now.subtract(const Duration(days: 9))), // antes
      at(now.subtract(const Duration(days: 20))), // fora das janelas
      at(now.add(const Duration(days: 1))), // futuro: ignorado
    ];
    final summary = buildDashboardSummary(
      questions: questions,
      lists: const [],
      now: now,
    );
    expect(summary.questionsSaved.current, 1);
    expect(summary.questionsSaved.previous, 2);
    expect(
      summary.questionsSaved.describe(),
      '1 a menos que nos 7 dias anteriores',
    );
  });

  test('acervo vazio é reconhecido (painel mostra o convite)', () {
    final summary = buildDashboardSummary(
      questions: const [],
      lists: const [],
      now: now,
    );
    expect(summary.isEmpty, isTrue);
    expect(summary.topArea, isNull);
  });
}
