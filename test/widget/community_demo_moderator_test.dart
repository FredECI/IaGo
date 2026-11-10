import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/data/local/community_demo_data.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/features/community/community_pages.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:iago/features/community/community_state.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Repositório cujo "Ajudou" demora até o teste liberar.
class _SlowRepo extends MemoryCommunityRepository {
  _SlowRepo()
    : super(
        clock: () => testNow,
        membership: Membership(
          nickname: 'pedro_estuda',
          declaredMinAge: 18,
          rulesVersion: communityRulesVersion,
          joinedAt: testNow,
        ),
        posts: CommunityDemoData.build(testNow).posts,
        replies: CommunityDemoData.build(testNow).replies,
        votes: CommunityDemoData.build(testNow).votes,
      );

  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<void> setHelpful(Reply reply, {required bool helpful}) async {
    calls++;
    await gate.future;
    return super.setHelpful(reply, helpful: helpful);
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/conecta',
        builder: (_, _) => const CommunityHomePage(),
        routes: [
          GoRoute(path: 'moderacao', builder: (_, _) => const ModerationPage()),
          GoRoute(
            path: ':communityId',
            builder: (_, s) =>
                CommunityPage(communityId: s.pathParameters['communityId']!),
            routes: [
              GoRoute(
                path: 'conversa/:postId',
                builder: (_, s) => CommunityPostPage(
                  communityId: s.pathParameters['communityId']!,
                  postId: s.pathParameters['postId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  ProviderContainer demo() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(sessionProvider.notifier).enterDemo();
    return c;
  }

  testWidgets('"Ajudou" com toque duplo conta uma vez só', (tester) async {
    final repo = _SlowRepo();
    final c = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repo),
        communityUidProvider.overrideWithValue(
          MemoryCommunityRepository.demoUid,
        ),
      ],
    );
    addTearDown(c.dispose);
    await _pump(tester, c, '/conecta/matematica/conversa/demo-p1');
    final button = find.byKey(const Key('helpful-demo-r1'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    repo.gate.complete();
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.text('Ajudou (4) - você marcou'), findsOneWidget);
  });

  group('Ver como moderador (demonstração)', () {
    testWidgets('desligado: sem acesso à fila e sem denúncias na tela', (
      tester,
    ) async {
      final c = demo();
      await _pump(tester, c, '/conecta');
      await tester.scrollUntilVisible(
        find.byKey(const Key('demo-moderator-switch')),
        200,
      );
      expect(find.byKey(const Key('open-moderation')), findsNothing);
      await _pump(tester, c, '/conecta/moderacao');
      expect(find.text('Sem acesso'), findsOneWidget);
      // CA-C4: o post denunciado de outro autor não aparece para o Pedro.
      await _pump(tester, c, '/conecta/humanas');
      expect(find.text('Venda de resumos prontos'), findsNothing);
    });

    testWidgets('ligado: abre a fila com 2 denúncias e decide', (tester) async {
      final c = demo();
      await _pump(tester, c, '/conecta');
      await _tap(tester, 'demo-moderator-switch');
      await _tap(tester, 'open-moderation');
      expect(find.text('Sem acesso'), findsNothing);
      final repo = c.read(communityRepositoryProvider);
      expect(await repo.openReports(), hasLength(2));
      final restore = find.byKey(
        Key('restore-demo-p7_${CommunityDemoData.uidOf('ana_funcoes')}'),
      );
      expect(restore, findsOneWidget);
      await _tap(
        tester,
        'restore-demo-p7_${CommunityDemoData.uidOf('ana_funcoes')}',
      );
      expect(await repo.openReports(), hasLength(1));
    });

    testWidgets('desligar de novo volta ao comportamento comum', (
      tester,
    ) async {
      final c = demo();
      await _pump(tester, c, '/conecta');
      await _tap(tester, 'demo-moderator-switch');
      await _tap(tester, 'demo-moderator-switch');
      expect(find.byKey(const Key('open-moderation')), findsNothing);
      expect(c.read(demoModeratorModeProvider), isFalse);
    });

    testWidgets('sem sessão de demo o interruptor não existe', (tester) async {
      final c = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(
            MemoryCommunityRepository(clock: () => testNow),
          ),
        ],
      );
      addTearDown(c.dispose);
      await _pump(tester, c, '/conecta');
      expect(find.byKey(const Key('demo-moderator-switch')), findsNothing);
    });
  });
}
