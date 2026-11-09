/// Como o estudante conheceu o IaGo (alimenta a hipótese H4: boca a boca).
enum ReferralSource {
  friend('Indicação de colega'),
  social('Redes sociais'),
  prepCourse('Cursinho'),
  other('Outro');

  const ReferralSource(this.label);

  final String label;

  static ReferralSource? tryParse(String? name) {
    for (final source in values) {
      if (source.name == name) return source;
    }
    return null;
  }
}

/// Dados pedidos no cadastro.
class SignUpData {
  const SignUpData({
    required this.name,
    required this.email,
    required this.password,
    required this.referralSource,
    required this.termsVersion,
    required this.declaredMinAge,
    this.platformsBefore,
  });

  final String name;
  final String email;
  final String password;
  final ReferralSource referralSource;

  /// Versão dos Termos e da Política de Privacidade aceita (LGPD).
  final String termsVersion;

  /// Idade mínima que a pessoa declarou ter (a da política, hoje 18).
  final int declaredMinAge;

  /// "Em quantas plataformas você estuda hoje?" (opcional; H2, antes × depois).
  final int? platformsBefore;
}

/// Usuário autenticado (sem detalhes do Firebase).
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.emailVerified = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool emailVerified;
}

/// Erro de autenticação já com a mensagem para o usuário, em português.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
