import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/data/auth_repository.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_runtime_config.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/user_profile.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Auth falso: senha "senha-certa" entra; o resto falha como o Firebase.
class FakeAuthRepository implements AuthRepository {
  final _users = StreamController<AuthUser?>.broadcast();
  SignUpData? lastSignUp;

  /// Versão dos termos que o perfil tem (`null` = perfil sem aceite).
  String? acceptedTerms = AppInfo.termsVersion;
  final _terms = StreamController<String?>.broadcast();
  int? acceptedAge;
  String? deletedWithPassword;
  bool emailVerified = true;
  bool verifiedAfterRefresh = true;
  int verificationsSent = 0;

  void emit(AuthUser? user) => _users.add(user);

  @override
  Stream<AuthUser?> authStateChanges() => _users.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != 'senha-certa') {
      throw const AuthFailure('E-mail ou senha incorretos.');
    }
    emit(
      AuthUser(
        uid: 'u1',
        email: email,
        displayName: 'Ana Souza',
        emailVerified: emailVerified,
      ),
    );
  }

  @override
  Future<void> signUp(SignUpData data) async {
    lastSignUp = data;
    acceptedTerms = data.termsVersion;
    emit(AuthUser(uid: 'u2', email: data.email, displayName: data.name));
  }

  @override
  Stream<String?> watchAcceptedTermsVersion() async* {
    yield acceptedTerms;
    yield* _terms.stream;
  }

  @override
  Future<void> acceptTerms({
    required String termsVersion,
    required int declaredMinAge,
  }) async {
    acceptedTerms = termsVersion;
    acceptedAge = declaredMinAge;
    _terms.add(termsVersion);
  }

  @override
  Future<void> sendEmailVerification() async => verificationsSent++;

  @override
  Future<bool> refreshEmailVerified() async => verifiedAfterRefresh;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<void> deleteAccount({required String password}) async {
    deletedWithPassword = password;
    emit(null);
  }
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

Future<FakeAuthRepository> pumpWithAuth(
  WidgetTester tester, {
  List<Override> extra = const [],
  Map<String, Object?>? runtimeConfig,
}) async {
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
      metricsRepositoryProvider.overrideWithValue(
        MemoryMetricsRepository(clock: () => testNow),
      ),
      directionRepositoryProvider.overrideWith((ref) {
        final repo = MemoryDirectionRepository();
        ref.onDispose(repo.dispose);
        return repo;
      }),
      runtimeConfigRepositoryProvider.overrideWithValue(
        MemoryRuntimeConfig(runtimeConfig),
      ),
      ...extra,
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

  Future<void> signInAna(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'senha-certa',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  group('Conecta no Painel de conta real', () {
    testWidgets('sem flag e sem membro, não aparece (Direciona sim)', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await signInAna(tester);
      expect(find.byKey(const Key('direction-card')), findsOneWidget);
      expect(find.text('Definir objetivo'), findsOneWidget);
      expect(find.byKey(const Key('conecta-card')), findsNothing);
    });

    testWidgets('com a flag ligada, mas sem ser membro, não aparece', (
      tester,
    ) async {
      await pumpWithAuth(tester, runtimeConfig: {'conectaEnabled': true});
      await signInAna(tester);
      expect(find.byKey(const Key('conecta-card')), findsNothing);
    });

    testWidgets('com a flag ligada e membro, aparece e abre', (tester) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'conectaEnabled': true},
        extra: [isMemberProvider.overrideWithValue(true)],
      );
      await signInAna(tester);
      await tapVisible(tester, find.byKey(const Key('conecta-card')));
      expect(find.text('Conecta'), findsWidgets);
      expect(find.byKey(const Key('placeholder-back')), findsOneWidget);
    });
  });

  group('Rota "Virar membro"', () {
    testWidgets('conta real com a flag desligada volta ao Painel', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await signInAna(tester);
      GoRouter.of(tester.element(find.text('Olá, Ana')))
          .go(Routes.becomeMember);
      await tester.pumpAndSettle();
      expect(find.text('Virar membro'), findsNothing);
      expect(find.text('Olá, Ana'), findsOneWidget);
    });

    testWidgets('com a flag ligada, abre mesmo sem ser membro', (tester) async {
      await pumpWithAuth(tester, runtimeConfig: {'conectaEnabled': true});
      await signInAna(tester);
      GoRouter.of(tester.element(find.text('Olá, Ana')))
          .go(Routes.becomeMember);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-submit')), findsOneWidget);
      expect(find.text('Entrar no piloto'), findsWidgets);
    });
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
    expect(
      find.text('É preciso declarar a idade mínima para criar a conta.'),
      findsOneWidget,
    );
    expect(auth.lastSignUp, isNull);

    await reveal(tester, 'signup-age');
    await tester.tap(find.byKey(const Key('signup-age')));
    await reveal(tester, 'signup-submit');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    expect(auth.lastSignUp?.declaredMinAge, AppInfo.termsMinAge);
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
