import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/clock.dart';
import '../../domain/metric_event.dart';
import '../../domain/user_profile.dart';
import '../auth_repository.dart';

/// Cadastro e login com e-mail e senha (Firebase Auth) e perfil em
/// `users/{uid}`. Nada de servidor próprio: as regras do Firestore garantem
/// que cada usuário só lê e escreve os próprios dados.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required this._auth,
    required this._db,
    required this._clock,
  });

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final Clock _clock;

  /// Subcoleções apagadas na exclusão da conta (LGPD).
  static const List<String> userCollections = [
    'questions',
    'questionImages',
    'lists',
    'events',
  ];

  /// `userChanges` também avisa mudanças de perfil (o nome gravado logo
  /// depois do cadastro), não só entrar e sair.
  @override
  Stream<AuthUser?> authStateChanges() => _auth.userChanges().map(
    (user) => user == null
        ? null
        : AuthUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
          ),
  );

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );

  @override
  Future<void> signUp(SignUpData data) => _guard(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: data.email.trim(),
      password: data.password,
    );
    final user = credential.user!;
    await user.updateDisplayName(data.name.trim());
    final now = _clock();
    await _db.collection('users').doc(user.uid).set({
      'name': data.name.trim(),
      'email': data.email.trim(),
      'referralSource': data.referralSource.name,
      'platformsBefore': ?data.platformsBefore,
      'termsVersion': data.termsVersion,
      'termsAcceptedAt': now,
      'createdAt': now,
    });
    // H4 (origem) e H2 (plataformas antes): evento de cadastro.
    await _db.collection('users').doc(user.uid).collection('events').add({
      'type': MetricEventType.signedUp.code,
      'at': now,
      'referralSource': data.referralSource.name,
      'platformsBefore': ?data.platformsBefore,
    });
  });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount({required String password}) => _guard(() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthFailure('Entre na conta antes de excluí-la.');
    }
    // Confirma a senha antes de apagar qualquer coisa.
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    final userDoc = _db.collection('users').doc(user.uid);
    for (final name in userCollections) {
      final docs = await userDoc.collection(name).get();
      // Lotes de até 400 exclusões (o limite do Firestore é 500).
      for (var i = 0; i < docs.docs.length; i += 400) {
        final batch = _db.batch();
        for (final doc in docs.docs.skip(i).take(400)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await userDoc.delete();
    await user.delete();
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageFor(e.code));
    } on FirebaseException catch (e) {
      throw AuthFailure(messageFor(e.code));
    }
  }

  /// Mensagens de erro em português (sem revelar se o e-mail existe).
  static String messageFor(String code) => switch (code) {
    'email-already-in-use' =>
      'Este e-mail já tem conta. Entre ou recupere a senha.',
    'invalid-email' => 'E-mail inválido.',
    'weak-password' => 'Senha fraca: use pelo menos 8 caracteres.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' ||
    'invalid-login-credentials' => 'E-mail ou senha incorretos.',
    'user-disabled' => 'Esta conta foi desativada.',
    'too-many-requests' =>
      'Muitas tentativas. Espere um pouco e tente de novo.',
    'network-request-failed' ||
    'unavailable' => 'Sem conexão com o servidor. Confira a internet.',
    'requires-recent-login' =>
      'Por segurança, saia e entre de novo antes de excluir a conta.',
    'permission-denied' => 'Sem permissão para esta operação.',
    _ => 'Não foi possível concluir agora. Tente de novo.',
  };
}
