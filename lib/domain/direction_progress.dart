import 'area.dart';
import 'direction_models.dart';
import 'direction_tuning.dart';
import 'question.dart';
import 'question_list.dart';

/// Regras puras do acompanhamento do Direciona: comparação relativa (CA-D7),
/// concluir e adiar (CA-D8) e montagem do [DirectionContext]. Sem relógio
/// próprio: todo cálculo recebe `now`.

const Duration progressWindow = Duration(days: directionWindowDays);
const int postponeDays = 2;

/// "N de M nos últimos 14 dias; nos 14 anteriores, X de Y".
class StepProgress {
  const StepProgress({
    required this.doneRecent,
    required this.totalRecent,
    required this.donePrevious,
    required this.totalPrevious,
  });

  final int doneRecent;
  final int totalRecent;
  final int donePrevious;
  final int totalPrevious;

  /// Sem nenhuma etapa nas duas janelas: a tela não deve mostrar número solto.
  bool get isEmpty => totalRecent == 0 && totalPrevious == 0;

  /// Frase pronta (CA-D7 / CA-T11). Vazia quando não há etapas a comparar.
  String get sentence {
    if (isEmpty) return '';
    final recent =
        'Você cumpriu $doneRecent de $totalRecent etapas nos últimos '
        '$directionWindowDays dias';
    if (totalPrevious == 0) return '$recent.';
    return '$recent; nos $directionWindowDays anteriores, $donePrevious de $totalPrevious.';
  }
}

/// Data que posiciona a etapa nas janelas: a conclusão, se concluída; senão o
/// prazo, mas só quando já venceu (etapa em dia ainda não conta como falha).
DateTime? _reference(StudyStep step, DateTime now) {
  if (step.status == StepStatus.done) return step.doneAt ?? step.dueAt;
  return step.dueAt.isAfter(now) ? null : step.dueAt;
}

bool _inWindow(DateTime d, DateTime now, int fromDays, int toDays) {
  final start = now.subtract(Duration(days: toDays));
  final end = now.subtract(Duration(days: fromDays));
  return d.isAfter(start) && !d.isAfter(end);
}

StepProgress computeStepProgress(Iterable<StudyStep> steps, DateTime now) {
  var doneRecent = 0, totalRecent = 0, donePrevious = 0, totalPrevious = 0;
  for (final step in steps) {
    final ref = _reference(step, now);
    if (ref == null) continue;
    final done = step.status == StepStatus.done;
    if (_inWindow(ref, now, 0, directionWindowDays)) {
      totalRecent++;
      if (done) doneRecent++;
    } else if (_inWindow(
      ref,
      now,
      directionWindowDays,
      2 * directionWindowDays,
    )) {
      totalPrevious++;
      if (done) donePrevious++;
    }
  }
  return StepProgress(
    doneRecent: doneRecent,
    totalRecent: totalRecent,
    donePrevious: donePrevious,
    totalPrevious: totalPrevious,
  );
}

/// Só etapa ainda não concluída e nunca adiada pode ser adiada (CA-D8).
bool canPostpone(StudyStep step) =>
    step.postponedAt == null &&
    step.status != StepStatus.done &&
    step.status != StepStatus.missed;

StudyStep _copy(
  StudyStep s, {
  StepStatus? status,
  DateTime? dueAt,
  DateTime? postponedAt,
  DateTime? doneAt,
}) => StudyStep(
  id: s.id,
  action: s.action,
  area: s.area,
  subject: s.subject,
  targetCount: s.targetCount,
  dueAt: dueAt ?? s.dueAt,
  status: status ?? s.status,
  postponedAt: postponedAt ?? s.postponedAt,
  doneAt: doneAt ?? s.doneAt,
  source: s.source,
  rationale: s.rationale,
  createdAt: s.createdAt,
);

/// Marca como concluída. Idempotente: concluir de novo mantém a 1ª data.
StudyStep completeStep(StudyStep step, DateTime now) {
  if (step.status == StepStatus.done) return step;
  return _copy(step, status: StepStatus.done, doneAt: now);
}

/// Marca como perdida (gravado na proposta seguinte).
StudyStep markMissed(StudyStep step) =>
    isPending(step) ? _copy(step, status: StepStatus.missed) : step;

/// Aceita uma etapa proposta (mantém as demais como estão).
StudyStep acceptStep(StudyStep step) => step.status == StepStatus.proposed
    ? _copy(step, status: StepStatus.accepted)
    : step;

/// Adia por 2 dias, uma única vez. Devolve `null` se não for permitido.
/// O novo prazo é o fim do dia de `max(prazo, hoje) + 2`.
StudyStep? postponeStep(StudyStep step, DateTime now) {
  if (!canPostpone(step)) return null;
  final base = step.dueAt.isAfter(now) ? step.dueAt : now;
  return _copy(
    step,
    dueAt: DateTime(
      base.year,
      base.month,
      base.day + postponeDays,
      23,
      59,
      59,
      999,
    ),
    postponedAt: now,
  );
}

/// Etapa pendente (não concluída nem perdida).
bool isPending(StudyStep s) =>
    s.status == StepStatus.proposed || s.status == StepStatus.accepted;

/// "Atrasada" é calculado na leitura (a spec grava `missed` só na proposta
/// seguinte).
bool isOverdue(StudyStep s, DateTime now) =>
    isPending(s) && !s.dueAt.isAfter(now);

/// Monta o contexto do planejador só com contagens por matéria do catálogo:
/// nada de enunciado, tag livre, plataforma ou id.
DirectionContext buildDirectionContext({
  required StudyGoal goal,
  required Iterable<Question> questions,
  required Iterable<QuestionList> lists,
  Iterable<StudyStep> steps = const [],
  required DateTime now,
}) {
  final since = now.subtract(progressWindow);
  final subjectByQuestion = <String, (Area, String)>{
    for (final q in questions) q.id: (q.area, q.subject),
  };

  final saved = <(Area, String), int>{};
  final recent = <(Area, String), int>{};
  for (final q in questions) {
    final key = (q.area, q.subject);
    saved[key] = (saved[key] ?? 0) + 1;
    if (q.createdAt.isAfter(since) && !q.createdAt.isAfter(now)) {
      recent[key] = (recent[key] ?? 0) + 1;
    }
  }

  // Cada lista exportada na janela conta uma vez por matéria que contém.
  final exported = <(Area, String), int>{};
  for (final list in lists) {
    final at = list.lastExportedAt;
    if (at == null || !at.isAfter(since) || at.isAfter(now)) continue;
    final keys = {for (final id in list.questionIds) ?subjectByQuestion[id]};
    for (final k in keys) {
      exported[k] = (exported[k] ?? 0) + 1;
    }
  }

  final keys = {...saved.keys, ...exported.keys};
  var done = 0, missed = 0;
  for (final s in steps) {
    final ref = _reference(s, now);
    if (ref == null || !_inWindow(ref, now, 0, directionWindowDays)) continue;
    if (s.status == StepStatus.done) {
      done++;
    } else {
      missed++;
    }
  }

  return DirectionContext(
    today: now,
    goal: GoalSummary.fromGoal(goal, now),
    coverage: [
      for (final k in keys)
        SubjectCoverage(
          area: k.$1,
          subject: k.$2,
          saved: saved[k] ?? 0,
          savedLast14d: recent[k] ?? 0,
          listsExportedLast14d: exported[k] ?? 0,
        ),
    ],
    history: DirectionHistory(doneLast14d: done, missedLast14d: missed),
  );
}
