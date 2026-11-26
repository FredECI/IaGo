import 'area.dart';

/// Modelos do Direciona. Dart puro e sem nenhum tipo de provedor de IA:
/// o provedor pode ser trocado sem mexer aqui.

enum ExamTarget {
  enem('ENEM'),
  vestibular('Vestibular'),
  concurso('Concurso'),
  other('Outro');

  const ExamTarget(this.label);
  final String label;

  /// Nome gravado no Firestore e enviado ao planejador (`enem`, `vestibular`,
  /// `concurso`, `outro`).
  String get wireName => this == other ? 'outro' : name;

  static ExamTarget? tryParse(String? value) {
    for (final e in values) {
      if (e.wireName == value) return e;
    }
    return null;
  }
}

enum StepAction {
  collect('Reunir questões'),
  buildList('Montar lista'),
  practice('Praticar'),
  review('Revisar');

  const StepAction(this.label);
  final String label;

  static StepAction? tryParse(Object? value) {
    for (final a in values) {
      if (a.name == value) return a;
    }
    return null;
  }
}

enum StepStatus { proposed, accepted, done, missed }

enum StepSource {
  ai('Proposta pela IA'),
  rules('Proposta automática');

  const StepSource(this.label);

  /// Rótulo mostrado ao usuário.
  final String label;
}

class StudyGoal {
  const StudyGoal({
    required this.exam,
    this.targetDate,
    required this.weeklyHours,
    this.focusAreas = const [],
    this.lastAiAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final ExamTarget exam;
  final DateTime? targetDate;

  /// De 1 a 40.
  final int weeklyHours;
  final List<Area> focusAreas;
  final DateTime? lastAiAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class StudyStep {
  const StudyStep({
    required this.id,
    required this.action,
    required this.area,
    required this.subject,
    required this.targetCount,
    required this.dueAt,
    this.status = StepStatus.proposed,
    this.postponedAt,
    this.doneAt,
    required this.source,
    required this.rationale,
    required this.createdAt,
  });

  /// Converte uma proposta validada em etapa. O prazo é o fim do dia local
  /// de `today + dueInDays`, porque a IA informa dias, nunca datas.
  factory StudyStep.fromProposed(
    ProposedStep proposed, {
    required String id,
    required DateTime today,
    required StepSource source,
    required DateTime createdAt,
  }) {
    return StudyStep(
      id: id,
      action: proposed.action,
      area: proposed.area,
      subject: proposed.subject,
      targetCount: proposed.targetCount,
      dueAt: DateTime(
        today.year,
        today.month,
        today.day + proposed.dueInDays,
        23,
        59,
        59,
        999,
      ),
      source: source,
      rationale: proposed.rationale,
      createdAt: createdAt,
    );
  }

  final String id;
  final StepAction action;
  final Area area;
  final String subject;
  final int targetCount;
  final DateTime dueAt;
  final StepStatus status;

  /// Preenchido impede novo adiamento.
  final DateTime? postponedAt;
  final DateTime? doneAt;
  final StepSource source;
  final String rationale;
  final DateTime createdAt;
}

/// Etapa proposta (pelas regras ou pela IA), ainda sem data: só `dueInDays`.
class ProposedStep {
  const ProposedStep({
    required this.action,
    required this.area,
    required this.subject,
    required this.targetCount,
    required this.dueInDays,
    required this.rationale,
  });

  final StepAction action;
  final Area area;
  final String subject;
  final int targetCount;
  final int dueInDays;
  final String rationale;

  Map<String, Object?> toJson() => {
    'action': action.name,
    'area': area.name,
    'subject': subject,
    'targetCount': targetCount,
    'dueInDays': dueInDays,
    'rationale': rationale,
  };
}

/// Limites da proposta, enviados também à IA.
class DirectionLimits {
  const DirectionLimits({
    this.maxSteps = 3,
    this.minDaysBetweenDeadlines = 2,
    this.maxDaysAhead = 14,
    this.maxTargetCount = 30,
    this.maxRationaleLength = 140,
  });

  final int maxSteps;
  final int minDaysBetweenDeadlines;
  final int maxDaysAhead;
  final int maxTargetCount;
  final int maxRationaleLength;

  Map<String, Object?> toJson() => {
    'maxSteps': maxSteps,
    'minDaysBetweenDeadlines': minDaysBetweenDeadlines,
    'maxDaysAhead': maxDaysAhead,
  };
}

/// Objetivo reduzido ao que o planejador precisa (sem datas exatas).
class GoalSummary {
  const GoalSummary({
    required this.exam,
    this.daysToTarget,
    required this.weeklyHours,
    this.focusAreas = const [],
  });

  factory GoalSummary.fromGoal(StudyGoal goal, DateTime today) {
    final target = goal.targetDate;
    final days = target == null
        ? null
        : DateTime(
            target.year,
            target.month,
            target.day,
          ).difference(DateTime(today.year, today.month, today.day)).inDays;
    return GoalSummary(
      exam: goal.exam,
      daysToTarget: days,
      weeklyHours: goal.weeklyHours,
      focusAreas: goal.focusAreas,
    );
  }

  final ExamTarget exam;
  final int? daysToTarget;
  final int weeklyHours;
  final List<Area> focusAreas;

  Map<String, Object?> toJson() => {
    'exam': exam.wireName,
    if (daysToTarget != null) 'daysToTarget': daysToTarget,
    'weeklyHours': weeklyHours,
    'focusAreas': [for (final a in focusAreas) a.name],
  };
}

/// Cobertura de uma matéria: só contagens agregadas.
class SubjectCoverage {
  const SubjectCoverage({
    required this.area,
    required this.subject,
    this.saved = 0,
    this.savedLast14d = 0,
    this.listsExportedLast14d = 0,
  });

  final Area area;
  final String subject;
  final int saved;
  final int savedLast14d;
  final int listsExportedLast14d;

  Map<String, Object?> toJson() => {
    'area': area.name,
    'subject': subject,
    'saved': saved,
    'savedLast14d': savedLast14d,
    'listsExportedLast14d': listsExportedLast14d,
  };
}

class DirectionHistory {
  const DirectionHistory({this.doneLast14d = 0, this.missedLast14d = 0});

  final int doneLast14d;
  final int missedLast14d;

  Map<String, Object?> toJson() => {
    'doneLast14d': doneLast14d,
    'missedLast14d': missedLast14d,
  };
}

/// Entrada do planejador e da IA. Só dados agregados: sem nome, e-mail, uid,
/// enunciado nem tag livre. [toJson] é exatamente o pedido da C.2 da spec.
class DirectionContext {
  DirectionContext({
    required DateTime today,
    required this.goal,
    required List<SubjectCoverage> coverage,
    this.history = const DirectionHistory(),
    this.limits = const DirectionLimits(),
  }) : today = DateTime(today.year, today.month, today.day),
       // Privacidade (CA-D6): o filtro fica no construtor, para que nenhum
       // jeito de montar o contexto deixe uma tag livre chegar ao `toJson`.
       // Só matéria do catálogo da própria área entra.
       // Matéria repetida tem as contagens somadas (nada de "o último vence").
       coverage = List.unmodifiable(_mergeCoverage(coverage));

  /// Só a data (sem hora).
  final DateTime today;
  final GoalSummary goal;
  final List<SubjectCoverage> coverage;
  final DirectionHistory history;
  final DirectionLimits limits;

  /// Catálogo fixo (área → matérias).
  Map<Area, List<String>> get allowedSubjects => {
    for (final a in Area.values) a: a.subjects,
  };

  Map<String, Object?> toJson() => {
    'today': _isoDate(today),
    'goal': goal.toJson(),
    'coverage': [for (final c in coverage) c.toJson()],
    'history': history.toJson(),
    'allowedSubjects': {
      for (final e in allowedSubjects.entries) e.key.name: e.value,
    },
    'limits': limits.toJson(),
  };
}

List<SubjectCoverage> _mergeCoverage(Iterable<SubjectCoverage> items) {
  final merged = <String, SubjectCoverage>{};
  for (final c in items) {
    if (!c.area.subjects.contains(c.subject)) continue;
    final key = '${c.area.name}|${c.subject}';
    final prev = merged[key];
    merged[key] = prev == null
        ? c
        : SubjectCoverage(
            area: c.area,
            subject: c.subject,
            saved: prev.saved + c.saved,
            savedLast14d: prev.savedLast14d + c.savedLast14d,
            listsExportedLast14d:
                prev.listsExportedLast14d + c.listsExportedLast14d,
          );
  }
  return merged.values.toList();
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
