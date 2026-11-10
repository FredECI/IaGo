import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/clock.dart';
import '../../domain/community_models.dart';
import '../../domain/metric_event.dart';
import '../../domain/user_profile.dart';
import '../auth_repository.dart';
import 'account_erasure.dart';
import 'community_write_plans.dart';
import 'firestore_community_repository.dart';
import 'firestore_mapping.dart';

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
    'direction',
    'directionSteps',
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
            emailVerified: user.emailVerified,
          ),
  );

  @override
  Stream<String?> watchAcceptedTermsVersion() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .where((snap) => snap.exists)
        .map((snap) {
          final version = snap.data()?['termsVersion'];
          return version is String ? version : null;
        });
  }

  @override
  Future<void> acceptTerms({
    required String termsVersion,
    required int declaredMinAge,
  }) => _guard(() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthFailure('Entre na conta antes de aceitar os termos.');
    }
    final now = _clock();
    await commitOrQueue(
      _db.collection('users').doc(uid).set({
        'termsVersion': termsVersion,
        'termsAcceptedAt': now,
        'declaredMinAge': declaredMinAge,
        'declaredMinAgeAt': now,
      }, SetOptions(merge: true)),
    );
  });

  @override
  Future<void> sendEmailVerification() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Entre na conta antes de verificar o e-mail.');
    }
    await user.sendEmailVerification();
  });

  @override
  Future<bool> refreshEmailVerified() => _guardValue(() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final verified = _auth.currentUser?.emailVerified ?? false;
    // `reload` não renova o ID token, e as regras de `memberships` leem
    // `email_verified` do token: sem isto, a entrada seria negada por até 1 h.
    if (verified) await _auth.currentUser?.getIdToken(true);
    return verified;
  });

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
      'declaredMinAge': data.declaredMinAge,
      'declaredMinAgeAt': now,
      'createdAt': now,
    });
    // Verificação do e-mail: se falhar (rede), a pessoa pede de novo na tela
    // "Entrar no piloto". Nunca impede o cadastro.
    try {
      await user.sendEmailVerification();
    } on FirebaseException {
      // Segue sem o envio.
    }
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
    final uid = user.uid;
    AccountErasureState.inProgress = true;
    try {
      await _eraseAll(user, uid);
    } finally {
      AccountErasureState.inProgress = false;
    }
  });

  Future<void> _eraseAll(User user, String uid) async {
    // Ordem: dados públicos, participação e perfil, subcoleções privadas e,
    // por último, o usuário do Auth (depois dele, as regras negam tudo). Se
    // uma etapa falhar, o Auth fica intacto e uma nova tentativa continua.
    try {
      await AccountEraser(
        inventory: () => _inventory(uid),
        commit: _commitDeletes,
        deleteUserData: () => _deleteUserData(uid),
      ).run(uid);
    } on FirebaseException catch (e) {
      throw AuthFailure(
        'Não foi possível apagar todos os seus dados agora '
        '(${messageFor(e.code)}) A conta não foi excluída: tente de novo.',
      );
    } on CommunityFailure {
      throw const AuthFailure(
        'Não foi possível ler seus dados do Conecta agora. '
        'A conta não foi excluída: tente de novo.',
      );
    } on TimeoutException {
      throw const AuthFailure(
        'Sem conexão para apagar seus dados. '
        'A conta não foi excluída: tente de novo.',
      );
    }
    await user.delete();
  }

  Future<ErasureInventory> _inventory(String uid) async {
    final footprint = await FirestoreCommunityRepository(
      db: _db,
      uid: uid,
      clock: _clock,
    ).myFootprint(fromServer: true);
    // As regras deixam cada pessoa listar as próprias avaliações, mesmo sem ser
    // membro ou banida (C5): falha aqui não pode virar "sem avaliações".
    final snap = await _db
        .collection('questionRatings')
        .where('uid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    final ratingIds = [for (final d in snap.docs) d.id];
    return ErasureInventory(footprint: footprint, ratingIds: ratingIds);
  }

  /// Sem `commitOrQueue`: na exclusão, escrita só na fila não vale.
  Future<void> _commitDeletes(List<PlannedWrite> writes) {
    final batch = _db.batch();
    for (final w in writes) {
      batch.delete(_db.doc(w.path));
    }
    return batch.commit().timeout(_erasureTimeout);
  }

  static const Duration _erasureTimeout = Duration(seconds: 30);

  Future<void> _deleteUserData(String uid) async {
    final userDoc = _db.collection('users').doc(uid);
    for (final name in userCollections) {
      final docs = await userDoc
          .collection(name)
          .get(const GetOptions(source: Source.server));
      for (var i = 0; i < docs.docs.length; i += erasureBatchSize) {
        final batch = _db.batch();
        for (final doc in docs.docs.skip(i).take(erasureBatchSize)) {
          batch.delete(doc.reference);
        }
        await batch.commit().timeout(_erasureTimeout);
      }
    }
    await userDoc.delete().timeout(_erasureTimeout);
  }

  Future<void> _guard(Future<void> Function() action) =>
      _guardValue<void>(action);

  Future<T> _guardValue<T>(Future<T> Function() action) async {
    try {
      return await action();
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
