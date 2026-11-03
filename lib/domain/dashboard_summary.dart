import 'area.dart';
import 'question.dart';
import 'question_list.dart';

/// Contagem num período comparada com o período anterior de mesmo tamanho.
/// Regra do IaGo: nenhum número solto, sempre com uma referência.
class PeriodComparison {
  const PeriodComparison({required this.current, required this.previous});

  final int current;
  final int previous;

  int get delta => current - previous;

  /// "4 a mais que nos 7 dias anteriores", "2 a menos...", "o mesmo número...".
  String describe() {
    if (delta > 0) return '$delta a mais que nos 7 dias anteriores';
    if (delta < 0) return '${-delta} a menos que nos 7 dias anteriores';
    return 'o mesmo número dos 7 dias anteriores';
  }
}

/// Área com mais questões, em relação ao total.
class AreaShare {
  const AreaShare({
    required this.area,
    required this.count,
    required this.total,
  });

  final Area area;
  final int count;
  final int total;

  int get percent => total == 0 ? 0 : (count * 100 / total).round();
}

/// Resumo do painel inicial.
class DashboardSummary {
  const DashboardSummary({
    required this.questionsSaved,
    required this.listsCreated,
    required this.totalQuestions,
    required this.areasCovered,
    this.topArea,
  });

  /// Questões salvas nos últimos 7 dias × nos 7 dias anteriores.
  final PeriodComparison questionsSaved;

  /// Listas montadas nos últimos 7 dias × nos 7 dias anteriores.
  final PeriodComparison listsCreated;

  final int totalQuestions;

  /// Em quantas das 4 áreas há questões.
  final int areasCovered;
  final AreaShare? topArea;

  bool get isEmpty => totalQuestions == 0;
}

/// Janelas móveis de 7 dias (justas em qualquer dia da semana, inclusive na
/// segunda-feira, quando "esta semana" acabou de começar).
DashboardSummary buildDashboardSummary({
  required List<Question> questions,
  required List<QuestionList> lists,
  required DateTime now,
}) {
  final weekAgo = now.subtract(const Duration(days: 7));
  final twoWeeksAgo = now.subtract(const Duration(days: 14));

  PeriodComparison compare(Iterable<DateTime> dates) {
    var current = 0;
    var previous = 0;
    for (final date in dates) {
      if (date.isAfter(now)) continue;
      if (date.isAfter(weekAgo)) {
        current++;
      } else if (date.isAfter(twoWeeksAgo)) {
        previous++;
      }
    }
    return PeriodComparison(current: current, previous: previous);
  }

  final byArea = <Area, int>{};
  for (final q in questions) {
    byArea.update(q.area, (n) => n + 1, ifAbsent: () => 1);
  }
  AreaShare? top;
  for (final area in Area.values) {
    final count = byArea[area] ?? 0;
    if (count > 0 && (top == null || count > top.count)) {
      top = AreaShare(area: area, count: count, total: questions.length);
    }
  }

  return DashboardSummary(
    questionsSaved: compare(questions.map((q) => q.createdAt)),
    listsCreated: compare(lists.map((l) => l.createdAt)),
    totalQuestions: questions.length,
    areasCovered: byArea.length,
    topArea: top,
  );
}
