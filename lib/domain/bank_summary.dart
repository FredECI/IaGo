import 'area.dart';

/// Quantas questões do acervo há numa matéria (e, se houver, numa faixa de
/// dificuldade). `difficulty == null` reúne as questões sem faixa.
class BankCount {
  const BankCount({
    required this.area,
    required this.subject,
    this.difficulty,
    required this.count,
  });

  final Area area;
  final String subject;
  final int? difficulty;
  final int count;
}

/// Contagens do índice do acervo, sem carregar o texto das questões.
class BankSummary {
  const BankSummary({
    required this.generatedAt,
    required this.counts,
    this.taxonomy = const {},
  });

  /// Data de geração do acervo (AAAA-MM-DD), como vem do índice.
  final String generatedAt;
  final List<BankCount> counts;

  /// Matéria -> assuntos, na ordem da taxonomia.
  final Map<String, List<String>> taxonomy;

  /// Soma de todas as faixas da matéria.
  int available(String subject) => counts
      .where((c) => c.subject == subject)
      .fold<int>(0, (n, c) => n + c.count);

  /// Questões da matéria na faixa (`null`: as sem faixa).
  int availableAt(String subject, int? difficulty) => counts
      .where((c) => c.subject == subject && c.difficulty == difficulty)
      .fold<int>(0, (n, c) => n + c.count);

  /// Calcula o resumo a partir de contagens já agrupadas por (matéria, faixa).
  static BankSummary fromTally({
    required String generatedAt,
    required Map<(Area, String, int?), int> tally,
    Map<String, List<String>> taxonomy = const {},
  }) {
    final rows =
        [
          for (final e in tally.entries)
            BankCount(
              area: e.key.$1,
              subject: e.key.$2,
              difficulty: e.key.$3,
              count: e.value,
            ),
        ]..sort((a, b) {
          final byArea = a.area.index.compareTo(b.area.index);
          if (byArea != 0) return byArea;
          final bySubject = a.subject.compareTo(b.subject);
          if (bySubject != 0) return bySubject;
          return (a.difficulty ?? 0).compareTo(b.difficulty ?? 0);
        });
    return BankSummary(
      generatedAt: generatedAt,
      counts: rows,
      taxonomy: taxonomy,
    );
  }
}
