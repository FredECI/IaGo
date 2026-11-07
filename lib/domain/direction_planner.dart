import 'area.dart';
import 'direction_models.dart';
import 'direction_tuning.dart';

/// Planejador por regras: função pura e determinística (plano B da IA).
///
/// 1. Matérias: áreas de foco primeiro, depois menos questões nos últimos
///    14 dias, depois menos questões no total (proxy de "trabalhada há mais
///    tempo", já que o contexto não traz datas) e por fim a ordem do
///    catálogo. Não repete matéria.
/// 2. Ação: `collect` se há menos de 10 questões; `buildList` se não há lista
///    exportada em 14 dias; `review` se nada foi salvo em 14 dias (proxy de
///    "última prática há mais de 14 dias"); senão `practice`.
/// 3. Prazo: esforço estimado dividido pelas horas por semana, de 2 a 7 dias,
///    com intervalo mínimo entre prazos (nunca passa de `maxDaysAhead`).
///
/// O relógio vem em [DirectionContext.today]; não há `DateTime.now()` aqui.
List<ProposedStep> planDirection(
  DirectionContext context, {
  PlannerTuning tuning = const PlannerTuning(),
}) {
  final limits = context.limits;
  final byKey = <String, SubjectCoverage>{
    for (final c in context.coverage) '${c.area.name}|${c.subject}': c,
  };
  final focus = context.goal.focusAreas.toSet();

  // Todas as matérias do catálogo, com a cobertura (zerada se faltar).
  final candidates = <SubjectCoverage>[
    for (final area in Area.values)
      for (final subject in area.subjects)
        byKey['${area.name}|$subject'] ??
            SubjectCoverage(area: area, subject: subject),
  ];
  // sort do Dart não é estável: o índice no catálogo desempata.
  final order = {for (var i = 0; i < candidates.length; i++) candidates[i]: i};
  candidates.sort((a, b) {
    final fa = focus.contains(a.area) ? 0 : 1;
    final fb = focus.contains(b.area) ? 0 : 1;
    if (fa != fb) return fa.compareTo(fb);
    final recent = a.savedLast14d.compareTo(b.savedLast14d);
    if (recent != 0) return recent;
    final total = a.saved.compareTo(b.saved);
    if (total != 0) return total;
    return order[a]!.compareTo(order[b]!);
  });

  final steps = <ProposedStep>[];
  var previousDue = 0;
  for (final c in candidates) {
    if (steps.length >= limits.maxSteps) break;
    final action = _chooseAction(c, tuning);
    final count = _targetCount(action, c, limits, tuning);
    // Respeita o teto antes de tudo: com limites apertados, o 1º prazo é
    // encurtado em vez de descartar o plano.
    var due = _daysFor(action, count, context.goal.weeklyHours, tuning);
    if (due > limits.maxDaysAhead) due = limits.maxDaysAhead;
    if (steps.isNotEmpty) {
      final minDue = previousDue + limits.minDaysBetweenDeadlines;
      if (due < minDue) due = minDue;
    }
    // Não cabe mais nenhuma etapa: devolve o maior plano válido até aqui.
    if (due < 1 || due > limits.maxDaysAhead) break;
    previousDue = due;
    steps.add(
      ProposedStep(
        action: action,
        area: c.area,
        subject: c.subject,
        targetCount: count,
        dueInDays: due,
        rationale: _rationale(
          action,
          c,
          focus.contains(c.area),
          limits,
          tuning,
        ),
      ),
    );
  }
  return steps;
}

StepAction _chooseAction(SubjectCoverage c, PlannerTuning t) {
  if (c.saved < t.minQuestionsPerSubject) return StepAction.collect;
  if (c.listsExportedLast14d == 0) return StepAction.buildList;
  if (c.savedLast14d == 0) return StepAction.review;
  return StepAction.practice;
}

int _targetCount(
  StepAction action,
  SubjectCoverage c,
  DirectionLimits l,
  PlannerTuning t,
) {
  final raw = switch (action) {
    StepAction.collect => (t.minQuestionsPerSubject - c.saved).clamp(
      t.minCollectTarget,
      t.maxCollectTarget,
    ),
    StepAction.buildList => t.buildListTarget,
    StepAction.practice => t.practiceTarget,
    StepAction.review => t.reviewTarget,
  };
  return raw.clamp(1, l.maxTargetCount);
}

int _minutesPer(StepAction a, PlannerTuning t) => switch (a) {
  StepAction.collect => t.minutesPerCollect,
  StepAction.buildList => t.minutesPerBuildList,
  StepAction.practice => t.minutesPerPractice,
  StepAction.review => t.minutesPerReview,
};

/// Prazo em dias: o esforço, espalhado pelas horas semanais.
int _daysFor(StepAction action, int count, int weeklyHours, PlannerTuning t) {
  final hours = weeklyHours < 1 ? 1 : weeklyHours;
  final effortMinutes = count * _minutesPer(action, t);
  final minutesPerDay = hours * 60 / 7;
  final days = (effortMinutes / (minutesPerDay / t.dailyShareDivisor)).ceil();
  return days.clamp(t.minDays, t.maxDays);
}

String _rationale(
  StepAction action,
  SubjectCoverage c,
  bool inFocus,
  DirectionLimits l,
  PlannerTuning t,
) {
  final s = c.subject;
  final text = switch (action) {
    StepAction.collect =>
      c.savedLast14d == 0
          ? '$s não teve questões salvas nos últimos $directionWindowDays dias e tem ${c.saved} no acervo.'
          : '$s tem só ${c.saved} no acervo, abaixo de ${t.minQuestionsPerSubject}.',
    StepAction.buildList =>
      '$s tem ${c.saved} questões e nenhuma lista exportada nos últimos $directionWindowDays dias.',
    StepAction.review =>
      '$s não teve questões salvas nos últimos $directionWindowDays dias; vale rever o que já tem.',
    StepAction.practice =>
      inFocus
          ? '$s é uma área de foco do seu objetivo e já tem lista recente.'
          : '$s já tem lista recente e questões novas: hora de praticar o que você salvou.',
  };
  return text.length <= l.maxRationaleLength
      ? text
      : text.substring(0, l.maxRationaleLength);
}
