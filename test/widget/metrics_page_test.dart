import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/app.dart';
import 'package:iago/data/local/community_demo_data.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/metrics_community_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/features/community/community_pages.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:iago/features/community/community_state.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

class _AccountController extends SessionController {
  @override
  Session? build() => const AccountSession(uid: 'u1', email: 'a@b.c');
}

void main() {
  setUpAll(initTestLocale);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  testWidgets('CA-M2/M3/T11: /metricas na demo, a 360 px, sem número solto', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    tester.view.physicalSize = const Size(360 * 3, 4000 * 3);
    containerOf(tester).read(sessionProvider.notifier).enterDemo();
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/metricas');
    await tester.pumpAndSettle();

    expect(find.text('Métricas do piloto'), findsOneWidget);
    expect(find.byKey(const Key('simulated-banner')), findsOneWidget);
    for (final code in ['H1', 'H2', 'H3', 'H4', 'H5', 'H6']) {
      expect(find.byKey(Key('hypothesis-$code')), findsOneWidget, reason: code);
    }
    // CA-M3: valores atuais da demo.
    expect(find.text('38%'), findsOneWidget);
    expect(find.text('0,8'), findsOneWidget);
    // CA-M2: H5 (1) + H6 (2) com "meta provisória".
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('meta provisória'),
      ),
      findsNWidgets(3),
    );
    // CA-T11: 10 métricas; cada uma tem meta e situação ao lado do valor.
    final status = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          const {
            'Meta atingida',
            'Abaixo da meta',
            'Sem dados ainda',
          }.contains(w.data),
    );
    expect(status, findsNWidgets(10));
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('meta'),
      ),
      findsNWidgets(10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('conta real nunca vê o interruptor de moderador da demo', (
    tester,
  ) async {
    final repo = MetricsCommunityRepository(
      MemoryCommunityRepository(
        clock: () => testNow,
        membership: Membership(
          nickname: 'real',
          declaredMinAge: 18,
          rulesVersion: communityRulesVersion,
          joinedAt: testNow,
        ),
        posts: CommunityDemoData.build(testNow).posts,
      ),
      (_, _) {},
    );
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_AccountController.new),
        communityRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: CommunityHomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('demo-moderator-switch')), findsNothing);
    // Mesmo por código, o setter não liga nada fora do repositório em memória.
    c.read(demoModeratorModeProvider.notifier).set(true);
    expect(c.read(demoModeratorModeProvider), isFalse);
  });
}
