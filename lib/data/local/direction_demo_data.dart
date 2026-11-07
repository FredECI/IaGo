import '../../domain/area.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_planner.dart';
import '../../domain/direction_progress.dart';
import 'demo_seed.dart';

/// Dados simulados do Direciona para a demo (sem rede, sem IA). Ficam fora de
/// `DemoSeed`, cujos números são invariantes testados.
///
/// - Objetivo do Pedro: ENEM, 10 h por semana.
/// - Histórico: 3 de 4 etapas cumpridas nos últimos 14 dias e 1 de 3 nos 14
///   anteriores (a comparação relativa da CA-D7 já nasce com contexto).
/// - 3 etapas pendentes, vindas do planejador real sobre a seed.
class DirectionDemoData {
  const DirectionDemoData({required this.goal, required this.steps});

  final StudyGoal goal;
  final List<StudyStep> steps;

  static DirectionDemoData build(DateTime now) {
    final goal = StudyGoal(
      exam: ExamTarget.enem,
      weeklyHours: 10,
      focusAreas: const [Area.mathematics],
      createdAt: _day(now, 30, 9),
      updatedAt: _day(now, 30, 9),
    );

    final seed = DemoSeed.build(now);
    final context = buildDirectionContext(
      goal: goal,
      questions: seed.questions,
      lists: seed.lists,
      now: now,
    );
    final today = DateTime(now.year, now.month, now.day);
    final pending = [
      for (final (i, p) in planDirection(context).indexed)
        StudyStep.fromProposed(
          p,
          id: 'demo-pending-$i',
          today: today,
          source: StepSource.rules,
          createdAt: now,
        ),
    ];

    final past = [
      // Últimos 14 dias: 3 de 4.
      _past(
        'demo-r1',
        now,
        Area.mathematics,
        'Matemática',
        StepAction.practice,
        3,
        true,
      ),
      _past(
        'demo-r2',
        now,
        Area.naturalSciences,
        'Biologia',
        StepAction.collect,
        6,
        true,
      ),
      _past(
        'demo-r3',
        now,
        Area.humanities,
        'História',
        StepAction.buildList,
        9,
        true,
      ),
      _past(
        'demo-r4',
        now,
        Area.languages,
        'Português',
        StepAction.collect,
        12,
        false,
      ),
      // 14 dias anteriores: 1 de 3.
      _past(
        'demo-p1',
        now,
        Area.mathematics,
        'Matemática',
        StepAction.collect,
        17,
        true,
      ),
      _past(
        'demo-p2',
        now,
        Area.naturalSciences,
        'Física',
        StepAction.collect,
        21,
        false,
      ),
      _past(
        'demo-p3',
        now,
        Area.humanities,
        'Geografia',
        StepAction.collect,
        25,
        false,
      ),
    ];
    return DirectionDemoData(goal: goal, steps: [...past, ...pending]);
  }
}

DateTime _day(DateTime now, int daysAgo, int hour) =>
    DateTime(now.year, now.month, now.day - daysAgo, hour);

StudyStep _past(
  String id,
  DateTime now,
  Area area,
  String subject,
  StepAction action,
  int daysAgo,
  bool done,
) {
  final due = DateTime(now.year, now.month, now.day - daysAgo, 23, 59, 59, 999);
  return StudyStep(
    id: id,
    action: action,
    area: area,
    subject: subject,
    targetCount: 10,
    dueAt: due,
    status: done ? StepStatus.done : StepStatus.missed,
    doneAt: done ? _day(now, daysAgo, 18) : null,
    source: StepSource.rules,
    rationale: 'Etapa de exemplo da demonstração.',
    createdAt: _day(now, daysAgo + 5, 9),
  );
}
