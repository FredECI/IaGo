import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_calendar.dart';
import 'package:iago/domain/direction_models.dart';

StudyStep _step(DateTime due) => StudyStep(
  id: 's',
  action: StepAction.practice,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: due,
  source: StepSource.rules,
  rationale: 'Poucas questões & "pouco" tempo',
  createdAt: DateTime(2026, 11, 1),
);

void main() {
  test('URL da agenda: título e dia do prazo (evento de dia inteiro)', () {
    final uri = stepCalendarUri(_step(DateTime(2026, 11, 20, 23, 59, 59, 999)));
    expect(uri.scheme, 'https');
    expect(uri.host, 'calendar.google.com');
    expect(uri.path, '/calendar/render');
    expect(uri.queryParameters['action'], 'TEMPLATE');
    expect(uri.queryParameters['text'], 'IaGo: Praticar 10 · Matemática');
    expect(uri.queryParameters['dates'], '20261120/20261121');
    expect(uri.queryParameters['details'], 'Poucas questões & "pouco" tempo');
  });

  test('fim exclusivo vira o mês e o ano certos', () {
    final uri = stepCalendarUri(_step(DateTime(2026, 12, 31, 23, 59)));
    expect(uri.queryParameters['dates'], '20261231/20270101');
  });

  test('caracteres especiais sobrevivem à codificação', () {
    final uri = stepCalendarUri(_step(DateTime(2026, 11, 20)));
    final decoded = Uri.parse(uri.toString());
    expect(decoded.queryParameters['details'], contains('&'));
    expect(uri.toString(), isNot(contains(' ')));
  });
}
