/// Identidade fixa do app: nome, versão exibida e versão dos termos.
abstract final class AppInfo {
  static const String name = 'IaGo';
  static const String expandedName =
      'Inteligência Artificial de Gerenciamento e Organização de Estudos';
  static const String versionLabel = 'Beta 0.1';
  static const String tagline =
      'Suas questões de todas as plataformas, num lugar só.';

  /// Versão do texto de Termos e Privacidade aceita no cadastro (LGPD).
  static const String termsVersion = '2026-11-03';

  /// Idade mínima das contas, pelos termos. É o piso de `AccessPolicy.minAge`
  /// e deve valer o mesmo que `termsMinAge()` em `firestore.rules`.
  static const int termsMinAge = 18;

  /// Meta de tempo para salvar uma questão (requisito do beta).
  static const Duration saveQuestionGoal = Duration(seconds: 30);
}
