/// Fonte registrada no acervo (licença e atribuição vêm do asset).
class BankSource {
  const BankSource({
    required this.id,
    required this.name,
    required this.officialUrl,
    required this.attribution,
    required this.notice,
    this.via = '',
  });

  final String id;
  final String name;
  final String officialUrl;
  final String attribution;

  /// Aviso exibido ao usuário (CA-B7). Nunca afirma licença.
  final String notice;
  final String via;

  factory BankSource.fromMap(Map<String, Object?> map) => BankSource(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    officialUrl: map['officialUrl'] as String? ?? '',
    attribution: map['attribution'] as String? ?? '',
    notice: map['notice'] as String? ?? '',
    via: map['via'] as String? ?? '',
  );
}
