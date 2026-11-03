import '../domain/user_profile.dart';

/// Cadastro e login. Implementação: Firebase Auth (+ perfil no Firestore).
abstract interface class AuthRepository {
  /// Usuário atual e mudanças (entrar, sair, excluir).
  Stream<AuthUser?> authStateChanges();

  /// Lança [AuthFailure] com mensagem em português.
  Future<void> signIn({required String email, required String password});

  /// Cria a conta e o perfil (origem do cadastro e aceite dos termos).
  Future<void> signUp(SignUpData data);

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// LGPD: apaga todos os dados do usuário e depois a conta.
  /// Pede a senha de novo, por segurança.
  Future<void> deleteAccount({required String password});
}
