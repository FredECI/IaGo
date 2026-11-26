import 'area.dart';

/// Mínimo de avaliações para o resumo aparecer (CA-A2).
const int minRatingsForSummary = 3;

/// Rótulos das escalas de 3 níveis (1 a 3).
const List<String> difficultyLabels = ['Fácil', 'Média', 'Difícil'];
const List<String> qualityLabels = ['Ruim', 'Ok', 'Boa'];

bool isValidScore(Object? v) => v is int && v >= 1 && v <= 3;

/// Máximo de caracteres do campo `subject` nas regras.
const int _maxSubjectLength = 60;

/// Nota de dificuldade e qualidade (1 a 3). Valor fora da faixa nunca é
/// construído: o construtor lança [RatingFailure] (CA-A3).
class RatingValue {
  RatingValue({required this.difficulty, required this.quality}) {
    if (!isValidScore(difficulty) || !isValidScore(quality)) {
      throw const RatingFailure(
        RatingFailureKind.invalid,
        'A nota deve ser de 1 a 3.',
      );
    }
  }

  final int difficulty;
  final int quality;

  @override
  bool operator ==(Object other) =>
      other is RatingValue &&
      other.difficulty == difficulty &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(difficulty, quality);
}

/// O que se avalia: a questão do acervo (id estável) e onde ela se encaixa.
///
/// **Matéria vazia.** Muitas questões do acervo ainda não têm matéria, mas as
/// regras exigem `subject` de 1 a 60 caracteres. Nesse caso o grupo vira o
/// rótulo da área (por exemplo, "Ciências Humanas"): a avaliação é gravada e
/// compara a questão com as demais do mesmo grupo. A alternativa de bloquear a
/// avaliação tiraria o recurso de quase 80% do acervo.
class RatingTarget {
  const RatingTarget({
    required this.bankId,
    required this.area,
    required this._subject,
  });

  final String bankId;
  final Area area;
  final String _subject;

  /// Valor gravado em `subject` e usado como grupo da média.
  String get group {
    final s = _subject.trim();
    final value = s.isEmpty ? area.label : s;
    return value.length > _maxSubjectLength
        ? value.substring(0, _maxSubjectLength)
        : value;
  }

  @override
  bool operator ==(Object other) =>
      other is RatingTarget &&
      other.bankId == bankId &&
      other.area == area &&
      other.group == group;

  @override
  int get hashCode => Object.hash(bankId, area, group);
}

/// Média e total de um conjunto de avaliações.
class RatingStats {
  const RatingStats({
    required this.count,
    required this.difficulty,
    required this.quality,
  });

  final int count;
  final double difficulty;
  final double quality;
}

/// Resumo da questão. Com menos de [minRatingsForSummary] avaliações,
/// [isEnough] é falso e a tela mostra "Poucas avaliações ainda".
class RatingSummary {
  const RatingSummary({
    required this.question,
    required this.group,
    required this.groupLabel,
    this.simulated = false,
  });

  /// Quando ainda não há avaliações suficientes.
  final RatingStats question;

  /// Média da matéria (ou da área, se a questão não tem matéria).
  final RatingStats group;
  final String groupLabel;

  /// Dados simulados da demo (CA-A7).
  final bool simulated;

  bool get isEnough => question.count >= minRatingsForSummary;

  static const String fewMessage = 'Poucas avaliações ainda';

  /// "Mais difícil que a média de Matemática (2,4 × 1,9; 7 avaliações)".
  /// `null` se há poucas avaliações.
  String? get difficultyText => !isEnough
      ? null
      : _compare(
          question.difficulty,
          group.difficulty,
          up: 'Mais difícil',
          down: 'Mais fácil',
          same: 'Dificuldade na média',
        );

  /// "Melhor avaliada que a média de Matemática (2,6 × 2,1; 7 avaliações)".
  String? get qualityText => !isEnough
      ? null
      : _compare(
          question.quality,
          group.quality,
          up: 'Melhor avaliada',
          down: 'Pior avaliada',
          same: 'Qualidade na média',
        );

  /// Diferença menor que isto é "na média".
  static const double sameMargin = 0.2;

  String _compare(
    double mine,
    double others, {
    required String up,
    required String down,
    required String same,
  }) {
    final nums =
        '${formatScore(mine)} × ${formatScore(others)}; '
        '${question.count} avaliações';
    final diff = mine - others;
    // Em décimos, para não depender do erro do ponto flutuante.
    if ((diff.abs() * 10).round() < (sameMargin * 10).round()) {
      return '$same de $groupLabel ($nums)';
    }
    return '${diff > 0 ? up : down} que a média de $groupLabel ($nums)';
  }
}

/// Número com uma casa e vírgula decimal: 2,4.
String formatScore(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

enum RatingFailureKind { invalid, unavailable, denied }

class RatingFailure implements Exception {
  const RatingFailure(this.kind, [this.message = '']);

  final RatingFailureKind kind;
  final String message;

  /// Texto da CA-A4, sem rede.
  static const String offlineMessage = 'Avaliações indisponíveis sem conexão';

  const RatingFailure.offline()
    : kind = RatingFailureKind.unavailable,
      message = offlineMessage;

  @override
  String toString() => message.isEmpty ? 'RatingFailure($kind)' : message;
}
