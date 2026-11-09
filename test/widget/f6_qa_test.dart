import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/local/memory_runtime_config.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:iago/app/router.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/domain/user_profile.dart';
import 'package:iago/features/auth/terms_gate.dart';
import 'package:iago/features/auth/terms_page.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import 'auth_flow_test.dart' show FakeAuthRepository, pumpWithAuth;

/// Imita o Firestore real: o perfil só existe depois do cadastro terminar
/// (o stream não emite antes) e a gravação chega com atraso.
class _SlowProfileAuth extends FakeAuthRepository {
  final profile = StreamController<String?>.broadcast();

  @override
  Stream<String?> watchAcceptedTermsVersion() => profile.stream;

  @override
  Future<void> signUp(SignUpData data) async {
    lastSignUp = data;
    // O usuário aparece primeiro, o documento do perfil depois.
    emit(AuthUser(uid: 'u2', email: data.email, displayName: data.name));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    profile.add(data.termsVersion);
  }
}

/// Perfil que nunca responde, ou responde com erro.
class _DeafAuth extends FakeAuthRepository {
  _DeafAuth({this.fail = false});
  final bool fail;

  @override
  Stream<String?> watchAcceptedTermsVersion() => fail
      ? Stream<String?>.error(Exception('unavailable'))
      : StreamController<String?>().stream;
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'senha-certa',
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
}

void main() {
  setUpAll(initTestLocale);

  group('CA-T13: conteúdo dos termos', () {
    test('cita IA, Google, camada gratuita, público x privado, moderação, '
        'idade e contato', () {
      final all = TermsContent.sections
          .map((s) => '${s.$1}\n${s.$2}')
          .join('\n')
          .toLowerCase();
      for (final needle in [
        'inteligência artificial',
        'google',
        'gemini',
        'camada gratuita',
        'público',
        'privado',
        'moderação',
        '${AppInfo.termsMinAge} anos ou mais',
        'contato',
        projectEmailPlaceholder,
      ]) {
        expect(all, contains(needle.toLowerCase()), reason: needle);
      }
    });

    test(
      'CA-R6: a versão dos termos é uma data ISO e a idade vem da constante',
      () {
        expect(AppInfo.termsVersion, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(AppInfo.termsVersion.compareTo('2026-11-03'), greaterThan(0));
      },
    );
  });

  group('CA-T8 / CA-T10: porta dos termos', () {
    testWidgets('logo após o cadastro, não cai na tela de reaceite', (
      tester,
    ) async {
      final auth = _SlowProfileAuth();
      await pumpIagoApp(tester, overrides: await _overrides(auth));
      await reveal(tester, find.byKey(const Key('go-sign-up')));
      await tester.tap(find.byKey(const Key('go-sign-up')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup-name')), 'Pedro');
      await tester.enterText(find.byKey(const Key('signup-email')), 'p@ex.com');
      await tester.enterText(
        find.byKey(const Key('signup-password')),
        'segura123',
      );
      for (final k in ['referral-friend', 'signup-terms', 'signup-age']) {
        await reveal(tester, find.byKey(Key(k)));
        await tester.tap(find.byKey(Key(k)));
      }
      await reveal(tester, find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));

      // Usuário já existe, perfil ainda não: nunca mostrar "Novos termos".
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('Novos termos de uso'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('Novos termos de uso'), findsNothing);
      expect(find.text('Olá, Pedro'), findsOneWidget);
      expect(auth.lastSignUp?.termsVersion, AppInfo.termsVersion);
      await auth.profile.close();
    });

    testWidgets('perfil sem aceite algum (versão nula) pede o aceite', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = null;
      await signIn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Novos termos de uso'), findsOneWidget);
    });

    testWidgets('perfil que nunca responde: libera o app após o timeout', (
      tester,
    ) async {
      final auth = _DeafAuth();
      await pumpIagoApp(tester, overrides: await _overrides(auth));
      await signIn(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Conferindo os termos'), findsNothing); // semântica
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Novos termos de uso'), findsNothing);

      await tester.pump(termsLookupTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Novos termos de uso'), findsNothing);
      expect(find.text('Olá, Ana'), findsOneWidget);
    });

    testWidgets('erro de rede ao ler o perfil não prende a pessoa', (
      tester,
    ) async {
      final auth = _DeafAuth(fail: true);
      await pumpIagoApp(tester, overrides: await _overrides(auth));
      await signIn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Novos termos de uso'), findsNothing);
      expect(find.text('Olá, Ana'), findsOneWidget);
    });

    testWidgets('demo nunca é barrada, nem com o perfil mudo', (tester) async {
      final auth = _DeafAuth();
      await pumpIagoApp(tester, overrides: await _overrides(auth));
      await enterDemo(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Novos termos de uso'), findsNothing);
      expect(find.text('Modo demonstração · dados locais'), findsOneWidget);
      await tester.pump(termsLookupTimeout * 2);
      expect(find.text('Novos termos de uso'), findsNothing);
    });

    testWidgets('versão aceita igual à atual não mostra o reaceite', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = AppInfo.termsVersion;
      await signIn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Novos termos de uso'), findsNothing);
    });

    testWidgets('sair por enquanto volta à entrada sem apagar nada', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = '2026-11-03';
      await signIn(tester);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('reaccept-signout')));
      expect(find.byKey(const Key('login-email')), findsOneWidget);
      expect(auth.deletedWithPassword, isNull);
    });
  });

  group('CA-R1: a idade vem da política', () {
    testWidgets('reaceite e cadastro usam minAge do runtime (21)', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester, runtimeConfig: {'minAge': 21});
      auth.acceptedTerms = '2026-11-03';
      await signIn(tester);
      await tester.pumpAndSettle();
      final label = find.text('Declaro ter 21 anos ou mais.');
      await reveal(tester, label);
      expect(label, findsOneWidget);
      expect(find.text('Declaro ter 18 anos ou mais.'), findsNothing);

      await tester.tap(find.byKey(const Key('reaccept-terms')));
      await tester.tap(find.byKey(const Key('reaccept-age')));
      await tester.tap(find.byKey(const Key('reaccept-submit')));
      await tester.pumpAndSettle();
      expect(auth.acceptedAge, 21);
    });

    testWidgets('minAge abaixo do piso dos termos vale o piso', (tester) async {
      final auth = await pumpWithAuth(tester, runtimeConfig: {'minAge': 16});
      auth.acceptedTerms = null;
      await signIn(tester);
      await tester.pumpAndSettle();
      final label = find.text(
        'Declaro ter ${AppInfo.termsMinAge} anos ou mais.',
      );
      await reveal(tester, label);
      expect(label, findsOneWidget);
    });
  });

  group('F7: rota /conecta/membro', () {
    testWidgets('com o Conecta desligado, o link direto volta ao Painel', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.becomeMember);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-submit')), findsNothing);
      expect(find.text('Olá, Ana'), findsOneWidget);
    });

    testWidgets('na demonstração com o Conecta desligado também não abre', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await enterDemo(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.becomeMember);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-submit')), findsNothing);
    });
  });
}

Future<List<Override>> _overrides(FakeAuthRepository auth) async => [
  firebaseStatusProvider.overrideWith((ref) async => FirebaseStatus.ready),
  authRepositoryProvider.overrideWithValue(auth),
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
  runtimeConfigRepositoryProvider.overrideWithValue(MemoryRuntimeConfig(null)),
];
