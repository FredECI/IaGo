/// Fonte registrada no acervo (licença e atribuição vêm do asset).
class BankSource {
  const BankSource({
    required this.id,
    required this.name,
    required this.officialUrl,
    required this.attribution,
    required this.notice,
    this.via = '',
    this.kind = 'questions',
  });

  final String id;
  final String name;
  final String officialUrl;
  final String attribution;

  /// Aviso exibido ao usuário (CA-B7). Nunca afirma licença.
  final String notice;
  final String via;

  /// `questions` (fornece questões) ou `difficulty` (só dados de dificuldade).
  final String kind;

  bool get isDifficultyData => kind == 'difficulty';

  factory BankSource.fromMap(Map<String, Object?> map) => BankSource(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    officialUrl: map['officialUrl'] as String? ?? '',
    attribution: map['attribution'] as String? ?? '',
    notice: map['notice'] as String? ?? '',
    via: map['via'] as String? ?? '',
    kind: map['kind'] as String? ?? 'questions',
  );
}
