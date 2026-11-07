import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/firestore_direction_repository.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';

void main() {
  final at = DateTime(2026, 11, 30, 12);

  test('etapa ida e volta, com os nomes da spec', () {
    final step = StudyStep(
      id: 's1',
      action: StepAction.buildList,
      area: Area.naturalSciences,
      subject: 'Física',
      targetCount: 10,
      dueAt: at,
      status: StepStatus.accepted,
      postponedAt: at,
      source: StepSource.ai,
      rationale: 'motivo',
      createdAt: at,
    );
    final map = stepToMap(step);
    expect(map['action'], 'buildList');
    expect(map['status'], 'accepted');
    expect(map['source'], 'ai');
    final back = stepFromMap('s1', map)!;
    expect(back.action, StepAction.buildList);
    expect(back.area, Area.naturalSciences);
    expect(back.postponedAt, at);
    expect(back.doneAt, isNull);
  });

  test('documento de etapa inválido vira null', () {
    expect(stepFromMap('x', {'action': 'dance'}), isNull);
    expect(stepFromMap('x', {}), isNull);
  });

  test('objetivo ida e volta e rejeita horas fora de 1 a 40', () {
    final goal = StudyGoal(
      exam: ExamTarget.other,
      weeklyHours: 12,
      focusAreas: const [Area.mathematics],
      createdAt: at,
      updatedAt: at,
    );
    final map = goalToMap(goal);
    expect(map['exam'], 'outro');
    final back = goalFromMap(map)!;
    expect(back.exam, ExamTarget.other);
    expect(back.focusAreas, [Area.mathematics]);
    expect(goalFromMap({...map, 'weeklyHours': 41}), isNull);
    expect(goalFromMap({...map, 'weeklyHours': 0}), isNull);
  });
}
