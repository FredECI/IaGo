/// Identidade fixa do app: nome, versão exibida e versão dos termos.
abstract final class AppInfo {
  static const String name = 'IaGo';
  static const String expandedName =
      'Inteligência Artificial de Gerenciamento e Organização de Estudos';
  static const String versionLabel = 'MVP 0.2';
  static const String tagline =
      'Suas questões de todas as plataformas, num lugar só.';

  /// Versão do texto de Termos e Privacidade aceita no cadastro (LGPD).
  /// Mudar o texto ou a idade mínima exige uma versão nova (CA-R6): quem
  /// aceitou outra versão precisa aceitar de novo para usar o app.
  static const String termsVersion = '2026-11-09';

  /// Idade mínima das contas, pelos termos. É o piso de `AccessPolicy.minAge`
  /// e deve valer o mesmo que `termsMinAge()` em `firestore.rules`.
  static const int termsMinAge = 18;

  /// E-mail do projeto para contestar moderação e pedir remoção de conteúdo
  /// (Conecta, acervo e termos). Ainda é um marcador: o e-mail real sai da
  /// D6/P4 e é obrigatório antes da publicação de 26/11 (veja
  /// `test/publish_ready_test.dart`).
  static const String projectContactEmail = '<e-mail do projeto>';

  /// Meta de tempo para salvar uma questão (requisito do beta).
  static const Duration saveQuestionGoal = Duration(seconds: 30);
}
