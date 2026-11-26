import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import 'auth_flow_test.dart' show FakeAuthRepository, pumpWithAuth;

/// Repositório que só aceita o convite "CONVITE", como as regras do servidor.
class _InviteOnlyRepository extends MemoryCommunityRepository {
  _InviteOnlyRepository() : super(clock: () => testNow);

  @override
  Future<void> join({
    required String nickname,
    String? inviteCode,
    required int declaredMinAge,
    required String rulesVersion,
  }) async {
    if (inviteCode != 'CONVITE') {
      throw const CommunityFailure(
        CommunityFailureKind.denied,
        'Sem permissão para esta ação.',
      );
    }
    return super.join(
      nickname: nickname,
      inviteCode: inviteCode,
      declaredMinAge: declaredMinAge,
      rulesVersion: rulesVersion,
    );
  }
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'senha-certa',
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> goTo(WidgetTester tester, String route) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await reveal(tester, finder);
  await tester.enterText(finder, text);
}

Future<void> check(WidgetTester tester, String key) async {
  await tapVisible(tester, find.byKey(Key(key)));
}

void main() {
  setUpAll(initTestLocale);

  group('Novo aceite dos termos', () {
    testWidgets(
      'termos antigos bloqueiam o app até aceitar e gravam a versão',
      (tester) async {
        final auth = await pumpWithAuth(tester);
        auth.acceptedTerms = '2026-11-03';
        await signIn(tester);

        expect(find.text('Novos termos de uso'), findsOneWidget);
        expect(find.text('Olá, Ana'), findsNothing);
        expect(find.text('Versão de ${AppInfo.termsVersion}'), findsOneWidget);

        // Sem marcar nada, não passa.
        await tapVisible(tester, find.byKey(const Key('reaccept-submit')));
        expect(find.byKey(const Key('reaccept-error')), findsOneWidget);
        expect(find.text('Olá, Ana'), findsNothing);

        await check(tester, 'reaccept-terms');
        await check(tester, 'reaccept-age');
        await tapVisible(tester, find.byKey(const Key('reaccept-submit')));

        expect(auth.acceptedTerms, AppInfo.termsVersion);
        expect(auth.acceptedAge, AppInfo.termsMinAge);
        expect(find.text('Olá, Ana'), findsOneWidget);
        expect(find.text('Novos termos de uso'), findsNothing);
      },
    );

    testWidgets('quem não aceita pode excluir a conta na mesma tela', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = null;
      await signIn(tester);
      expect(find.text('Novos termos de uso'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('reaccept-delete')));
      // Sem senha, nada é apagado.
      await tapVisible(
        tester,
        find.byKey(const Key('reaccept-delete-confirm')),
      );
      expect(auth.deletedWithPassword, isNull);
      expect(find.byKey(const Key('reaccept-error')), findsOneWidget);

      await typeInto(tester, 'reaccept-delete-password', 'senha-certa');
      await tapVisible(
        tester,
        find.byKey(const Key('reaccept-delete-confirm')),
      );
      expect(auth.deletedWithPassword, 'senha-certa');
      // Sem sessão, volta para a entrada.
      expect(find.byKey(const Key('login-email')), findsOneWidget);
      expect(find.text('Novos termos de uso'), findsNothing);
    });

    testWidgets('a mesma tela explica a denúncia aberta e o limite de idade', (
      tester,
    ) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = '2026-11-03';
      await signIn(tester);
      final age = find.textContaining(
        'tem menos de ${AppInfo.termsMinAge} anos',
      );
      await reveal(tester, age);
      expect(age, findsOneWidget);
      final report = find
          .textContaining('denúncia sua que ainda está aberta')
          .last;
      await reveal(tester, report);
      expect(report, findsOneWidget);
    });

    testWidgets('a demonstração nunca é barrada pelos termos', (tester) async {
      final auth = await pumpWithAuth(tester);
      auth.acceptedTerms = '2026-11-03';
      await enterDemo(tester);
      expect(find.text('Novos termos de uso'), findsNothing);
      expect(find.text('Modo demonstração · dados locais'), findsOneWidget);
    });
  });

  group('Entrar no piloto', () {
    const open = {'conectaEnabled': true};

    Future<(FakeAuthRepository, MemoryCommunityRepository)> pumpJoin(
      WidgetTester tester, {
      Map<String, Object?> config = open,
      MemoryCommunityRepository? repo,
      bool verified = true,
    }) async {
      final community = repo ?? MemoryCommunityRepository(clock: () => testNow);
      final auth = await pumpWithAuth(
        tester,
        runtimeConfig: config,
        extra: [communityRepositoryProvider.overrideWithValue(community)],
      );
      auth.emailVerified = verified;
      await signIn(tester);
      await goTo(tester, Routes.becomeMember);
      return (auth, community);
    }

    Future<void> fillAndSubmit(
      WidgetTester tester, {
      String? invite = 'CONVITE',
      String nickname = 'ana_estuda',
    }) async {
      if (invite != null) await typeInto(tester, 'join-invite', invite);
      await typeInto(tester, 'join-nickname', nickname);
      await check(tester, 'join-age');
      await check(tester, 'join-rules');
      await tapVisible(tester, find.byKey(const Key('join-submit')));
    }

    testWidgets('com convite: grava a participação e abre o Conecta', (
      tester,
    ) async {
      final (_, community) = await pumpJoin(
        tester,
        repo: _InviteOnlyRepository(),
      );
      expect(find.text('Entrar no piloto'), findsWidgets);
      await fillAndSubmit(tester);

      final m = await community.myMembership();
      expect(m?.nickname, 'ana_estuda');
      expect(m?.inviteCode, 'CONVITE');
      expect(m?.declaredMinAge, AppInfo.termsMinAge);
      expect(m?.rulesVersion, communityRulesVersion);
      expect(
        find.textContaining('Comunidades em que estudantes se ajudam'),
        findsOneWidget,
      );
    });

    testWidgets('sem convite quando a política dispensa', (tester) async {
      final (_, community) = await pumpJoin(
        tester,
        config: {'conectaEnabled': true, 'inviteRequired': false},
      );
      expect(find.byKey(const Key('join-invite')), findsNothing);
      await fillAndSubmit(tester, invite: null);

      final m = await community.myMembership();
      expect(m?.nickname, 'ana_estuda');
      expect(m?.inviteCode, isNull);
    });

    testWidgets('convite exigido e em branco não envia nada', (tester) async {
      final (_, community) = await pumpJoin(tester);
      await fillAndSubmit(tester, invite: '');
      expect(find.text('Informe o código de convite.'), findsOneWidget);
      expect(await community.myMembership(), isNull);
    });

    testWidgets('convite inválido mostra a mensagem em português', (
      tester,
    ) async {
      final (_, community) = await pumpJoin(
        tester,
        repo: _InviteOnlyRepository(),
      );
      await fillAndSubmit(tester, invite: 'ERRADO');
      expect(
        find.textContaining('Confira o código de convite'),
        findsOneWidget,
      );
      expect(await community.myMembership(), isNull);
    });

    testWidgets('apelido inválido mostra a mensagem e não entra', (
      tester,
    ) async {
      final (_, community) = await pumpJoin(tester);
      await fillAndSubmit(tester, nickname: 'ab');
      expect(
        find.text(
          'O apelido precisa ter de $nicknameMin a $nicknameMax '
          'caracteres.',
        ),
        findsOneWidget,
      );
      expect(await community.myMembership(), isNull);
    });

    testWidgets('sem a declaração de idade ou as regras, não entra', (
      tester,
    ) async {
      final (_, community) = await pumpJoin(tester);
      await typeInto(tester, 'join-invite', 'CONVITE');
      await typeInto(tester, 'join-nickname', 'ana_estuda');
      await tapVisible(tester, find.byKey(const Key('join-submit')));
      expect(find.text('Declare a idade mínima para entrar.'), findsOneWidget);

      await check(tester, 'join-age');
      await tapVisible(tester, find.byKey(const Key('join-submit')));
      expect(
        find.text('Aceite as regras da comunidade para entrar.'),
        findsOneWidget,
      );
      expect(await community.myMembership(), isNull);
    });

    testWidgets('e-mail não verificado: reenvia, confere e libera', (
      tester,
    ) async {
      final (auth, community) = await pumpJoin(tester, verified: false);
      await fillAndSubmit(tester);
      expect(
        find.text('Verifique o seu e-mail antes de entrar.'),
        findsOneWidget,
      );
      expect(await community.myMembership(), isNull);

      await tapVisible(tester, find.byKey(const Key('join-resend')));
      expect(auth.verificationsSent, 1);

      auth.verifiedAfterRefresh = false;
      await tapVisible(tester, find.byKey(const Key('join-recheck')));
      expect(find.byKey(const Key('join-verify-info')), findsOneWidget);

      auth.verifiedAfterRefresh = true;
      await tapVisible(tester, find.byKey(const Key('join-recheck')));
      expect(find.text('E-mail verificado'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('join-submit')));
      expect((await community.myMembership())?.nickname, 'ana_estuda');
    });

    testWidgets('quem já é membro vê o aviso, não o formulário', (
      tester,
    ) async {
      await pumpJoin(
        tester,
        repo: MemoryCommunityRepository(
          clock: () => testNow,
          membership: Membership(
            nickname: 'ana_antiga',
            declaredMinAge: 18,
            rulesVersion: communityRulesVersion,
            joinedAt: testNow,
          ),
        ),
      );
      expect(find.byKey(const Key('join-open')), findsOneWidget);
      expect(find.byKey(const Key('join-submit')), findsNothing);
    });
  });

  group('Conecta para o membro', () {
    testWidgets('conta membro com a flag ligada vê o card e abre', (
      tester,
    ) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'conectaEnabled': true},
        extra: [
          communityRepositoryProvider.overrideWithValue(
            MemoryCommunityRepository(
              clock: () => testNow,
              membership: Membership(
                nickname: 'ana_antiga',
                declaredMinAge: 18,
                rulesVersion: communityRulesVersion,
                joinedAt: testNow,
              ),
            ),
          ),
        ],
      );
      await signIn(tester);
      await tapVisible(tester, find.byKey(const Key('conecta-card')));
      expect(find.byKey(const Key('community-matematica')), findsOneWidget);
    });

    testWidgets('conta sem participação não vê o card', (tester) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'conectaEnabled': true},
        extra: [
          communityRepositoryProvider.overrideWithValue(
            MemoryCommunityRepository(clock: () => testNow),
          ),
        ],
      );
      await signIn(tester);
      expect(find.byKey(const Key('conecta-card')), findsNothing);
    });

    testWidgets('na demonstração o Pedro já é membro', (tester) async {
      await pumpWithAuth(tester);
      await enterDemo(tester);
      expect(find.byKey(const Key('conecta-card')), findsOneWidget);
    });
  });
}
