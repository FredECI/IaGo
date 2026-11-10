import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:iago/features/import/import_models.dart';
import 'package:iago/features/import/import_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import 'auth_flow_test.dart' show pumpWithAuth;

class _Gateway implements AiGateway {
  @override
  Future<AiAvailability> availability() async => AiAvailability.available;

  @override
  Future<String> generateJson({
    required AiCall call,
    required String model,
    required String systemInstruction,
    required String prompt,
    List<ImportFile> files = const [],
    required Map<String, Object?> responseSchema,
    required Duration timeout,
  }) => throw UnimplementedError();
}

class _Account extends SessionController {
  @override
  Session? build() => const AccountSession(uid: 'u1', email: 'a@b.c');
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login-email')), 'ana@ex.com');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'senha-certa',
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> _scrollTap(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  group('provider: sem depender do Conecta', () {
    ProviderContainer container({
      required MemoryCommunityRepository repo,
      Map<String, Object?>? runtime,
    }) {
      final c = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(_Account.new),
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('conta real com conectaEnabled=false lê a participação', () async {
      final repo = MemoryCommunityRepository(clock: () => testNow);
      await repo.join(
        nickname: 'ana_estuda',
        declaredMinAge: 18,
        rulesVersion: 'v',
      );
      final c = container(repo: repo);
      expect(c.read(accessPolicyProvider).conectaEnabled, isFalse);
      final m = await c.read(myMembershipProvider.future);
      expect(m?.nickname, 'ana_estuda');
      expect(c.read(isMemberProvider), isTrue);
      // Mas o fórum continua fechado.
      expect(c.read(conectaVisibleProvider), isFalse);
      expect(c.read(conectaJoinableProvider), isTrue);
      expect(c.read(canOfferJoinProvider), isFalse);
    });

    test('quem não é membro recebe a oferta de entrar', () async {
      final c = container(
        repo: MemoryCommunityRepository(clock: () => testNow),
      );
      await c.read(myMembershipProvider.future);
      expect(c.read(isMemberProvider), isFalse);
      expect(c.read(canOfferJoinProvider), isTrue);
    });

    test('demo: já é membro, vê o Conecta e não recebe a oferta', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(sessionProvider.notifier).enterDemo();
      await c.read(myMembershipProvider.future);
      expect(c.read(isMemberProvider), isTrue);
      expect(c.read(conectaVisibleProvider), isTrue);
      expect(c.read(canOfferJoinProvider), isFalse);
    });
  });

  group('fluxo em conta real, Conecta desligado', () {
    testWidgets('vira membro pela aba Conta: ganha IA, sem ver o fórum', (
      tester,
    ) async {
      final repo = MemoryCommunityRepository(clock: () => testNow);
      await pumpWithAuth(
        tester,
        runtimeConfig: {'aiEnabled': true, 'inviteRequired': false},
        extra: [
          communityRepositoryProvider.overrideWithValue(repo),
          aiGatewayProvider.overrideWithValue(_Gateway()),
        ],
      );
      await _signIn(tester);
      ProviderContainer container() =>
          ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

      // Antes: sem IA, e o Painel não tem Conecta.
      await container().read(accessPolicyAsyncProvider.future);
      expect(container().read(questionExtractorProvider), isNull);
      expect(container().read(conectaVisibleProvider), isFalse);

      // A aba Conta oferece a entrada.
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.account);
      await tester.pumpAndSettle();
      await _scrollTap(tester, const Key('account-join'));
      expect(find.byKey(const Key('join-nickname')), findsOneWidget);
      expect(find.textContaining('O piloto é fechado'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('join-nickname')),
        'ana_estuda',
      );
      await _scrollTap(tester, const Key('join-age'));
      await _scrollTap(tester, const Key('join-rules'));
      await _scrollTap(tester, const Key('join-submit'));

      // Gravou a participação (o repositório de verdade grava memberships e
      // profiles no mesmo lote: `joinPlan`).
      expect((await repo.myMembership())?.nickname, 'ana_estuda');
      // Voltou ao Painel, não ao fórum.
      expect(find.text('Olá, Ana'), findsOneWidget);
      expect(container().read(isMemberProvider), isTrue);
      expect(container().read(conectaVisibleProvider), isFalse);

      // Agora tem IA (e a avaliação deixa de ser "só membros").
      await container().read(aiAvailabilityProvider.future);
      expect(container().read(questionExtractorProvider), isNotNull);
      expect(container().read(importAiModeProvider), ImportAiMode.real);

      // O link direto do fórum continua barrado.
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/conecta');
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .routeInformationProvider
            .value
            .uri
            .path,
        '/painel',
      );
    });

    testWidgets('importação: aviso "Entrar no piloto" para quem não é membro', (
      tester,
    ) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'aiEnabled': true},
        extra: [
          communityRepositoryProvider.overrideWithValue(
            MemoryCommunityRepository(clock: () => testNow),
          ),
          aiGatewayProvider.overrideWithValue(_Gateway()),
        ],
      );
      await _signIn(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.import);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-files-unavailable')), findsOneWidget);
      await _scrollTap(tester, const Key('import-join'));
      expect(find.byKey(const Key('join-nickname')), findsOneWidget);
    });

    testWidgets('Direciona: nota "Entrar no piloto" só para não membros', (
      tester,
    ) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'aiEnabled': true},
        extra: [
          communityRepositoryProvider.overrideWithValue(
            MemoryCommunityRepository(clock: () => testNow),
          ),
        ],
      );
      await _signIn(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IagoApp)),
      );
      await container.read(accessPolicyAsyncProvider.future);
      await container.read(myMembershipProvider.future);
      expect(container.read(canOfferJoinProvider), isTrue);
      await container
          .read(directionRepositoryProvider)
          .saveGoal(
            StudyGoal(
              exam: ExamTarget.enem,
              weeklyHours: 8,
              createdAt: testNow,
              updatedAt: testNow,
            ),
          );
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.direction);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direction-join-note')), findsOneWidget);
      await _scrollTap(tester, const Key('direction-join'));
      expect(find.byKey(const Key('join-nickname')), findsOneWidget);
    });

    testWidgets('demo: a aba Conta não oferece entrada', (tester) async {
      await pumpIagoApp(tester);
      await enterDemo(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go(Routes.account);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-join')), findsNothing);
    });
  });
}
