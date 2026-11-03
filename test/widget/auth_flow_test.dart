import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/auth_repository.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/user_profile.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Auth falso: senha "senha-certa" entra; o resto falha como o Firebase.
class FakeAuthRepository implements AuthRepository {
  final _users = StreamController<AuthUser?>.broadcast();
  SignUpData? lastSignUp;

  void emit(AuthUser? user) => _users.add(user);

  @override
  Stream<AuthUser?> authStateChanges() => _users.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != 'senha-certa') {
      throw const AuthFailure('E-mail ou senha incorretos.');
    }
    emit(AuthUser(uid: 'u1', email: email, displayName: 'Ana Souza'));
  }

  @override
  Future<void> signUp(SignUpData data) async {
    lastSignUp = data;
    emit(AuthUser(uid: 'u2', email: data.email, displayName: data.name));
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<void> deleteAccount({required String password}) async => emit(null);
}

/// Rola a lista (preguiçosa) até o campo existir e ficar visível.
Future<void> reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<FakeAuthRepository> pumpWithAuth(WidgetTester tester) async {
  final auth = FakeAuthRepository();
  await pumpIagoApp(
    tester,
    overrides: [
      firebaseStatusProvider.overrideWith((ref) async => FirebaseStatus.ready),
      authRepositoryProvider.overrideWithValue(auth),
      // Conta real usa memória nos testes (sem Firestore de verdade).
      questionRepositoryProvider.overrideWithValue(
        MemoryQuestionRepository(clock: () => testNow),
      ),
      listRepositoryProvider.overrideWithValue(
        MemoryListRepository(clock: () => testNow),
      ),
    ],
  );
  return auth;
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('sem Firebase configurado, a entrada oferece só a demo', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    expect(find.byKey(const Key('accounts-off')), findsOneWidget);
    expect(find.byKey(const Key('enter-demo')), findsOneWidget);
  });

  testWidgets('login com senha errada mostra o erro em português', (
    tester,
  ) async {
    await pumpWithAuth(tester);
    await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'errada');
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
  });

  testWidgets('login certo leva ao painel da conta', (tester) async {
    await pumpWithAuth(tester);
    await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'senha-certa',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(find.text('Modo demonstração · dados locais'), findsNothing);
  });

  testWidgets('cadastro exige origem e aceite dos termos', (tester) async {
    final auth = await pumpWithAuth(tester);
    await reveal(tester, 'go-sign-up');
    await tester.tap(find.byKey(const Key('go-sign-up')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signup-name')), 'Pedro Lima');
    await tester.enterText(
      find.byKey(const Key('signup-email')),
      'pedro@ex.com',
    );
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'segura123',
    );
    await reveal(tester, 'signup-submit');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Escolha uma opção.'), findsOneWidget);
    expect(
      find.text('É preciso aceitar os termos para criar a conta.'),
      findsOneWidget,
    );
    expect(auth.lastSignUp, isNull);

    await reveal(tester, 'referral-friend');
    await tester.tap(find.byKey(const Key('referral-friend')));
    await reveal(tester, 'signup-terms');
    await tester.tap(find.byKey(const Key('signup-terms')));
    await reveal(tester, 'signup-submit');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    expect(auth.lastSignUp?.referralSource, ReferralSource.friend);
    expect(auth.lastSignUp?.termsVersion, isNotEmpty);
    expect(find.text('Olá, Pedro'), findsOneWidget);
  });

  testWidgets('login que chega atrasado não derruba a demonstração', (
    tester,
  ) async {
    final auth = await pumpWithAuth(tester);
    await enterDemo(tester);
    expect(find.text('Modo demonstração · dados locais'), findsOneWidget);

    // O Firebase termina de iniciar e avisa um usuário logado: a demo fica.
    auth.emit(const AuthUser(uid: 'u9', email: 'outra@ex.com'));
    await tester.pumpAndSettle();
    expect(find.text('Modo demonstração · dados locais'), findsOneWidget);
  });
}
