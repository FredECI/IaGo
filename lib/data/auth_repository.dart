import '../domain/user_profile.dart';

/// Cadastro e login. Implementação: Firebase Auth (+ perfil no Firestore).
abstract interface class AuthRepository {
  /// Usuário atual e mudanças (entrar, sair, excluir).
  Stream<AuthUser?> authStateChanges();

  /// Lança [AuthFailure] com mensagem em português.
  Future<void> signIn({required String email, required String password});

  /// Cria a conta e o perfil (origem do cadastro e aceite dos termos).
  Future<void> signUp(SignUpData data);

  /// Versão dos termos gravada no perfil (`null` se o perfil não tem). Só emite
  /// quando o perfil existe; o primeiro valor chega do cache, se houver.
  Stream<String?> watchAcceptedTermsVersion();

  /// Grava o aceite dos termos e a idade mínima declarada no perfil.
  Future<void> acceptTerms({
    required String termsVersion,
    required int declaredMinAge,
  });

  /// Envia (de novo) o e-mail de verificação.
  Future<void> sendEmailVerification();

  /// Recarrega o usuário e diz se o e-mail já foi verificado.
  Future<bool> refreshEmailVerified();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// LGPD: apaga todos os dados do usuário e depois a conta.
  /// Pede a senha de novo, por segurança.
  Future<void> deleteAccount({required String password});
}
