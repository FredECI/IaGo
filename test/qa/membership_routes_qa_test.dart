import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../widget/auth_flow_test.dart' show pumpWithAuth;

/// QA ciclo 2: com o Conecta desligado, só /conecta/membro abre; o fórum não.
void main() {
  setUpAll(initTestLocale);

  GoRouter routerOf(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(IagoApp)))
          .read(routerProvider);

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

  const forum = [
    '/conecta',
    '/conecta/',
    '/conecta/moderacao',
    '/conecta/geral',
    '/conecta/geral/conversa/p1',
    '/conecta/membro/x',
    '/conecta/membro/',
  ];

  for (final member in [false, true]) {
    testWidgets('conecta desligado (membro=$member): fórum nunca abre', (
      tester,
    ) async {
      final repo = MemoryCommunityRepository(clock: () => testNow);
      if (member) {
        await repo.join(
          nickname: 'ana_estuda',
          declaredMinAge: 18,
          rulesVersion: 'v',
        );
      }
      await pumpWithAuth(
        tester,
        extra: [communityRepositoryProvider.overrideWithValue(repo)],
      );
      await signIn(tester);
      for (final p in forum) {
        routerOf(tester).go(p);
        await tester.pumpAndSettle();
        final loc = routerOf(tester).state.uri.path;
        expect(
          loc == '/conecta/membro' && p != '/conecta/membro' && p != '/conecta/membro/'
              ? false
              : !loc.startsWith('/conecta') || loc == '/conecta/membro',
          isTrue,
          reason: '$p -> $loc',
        );
        expect(find.textContaining('Comunidade'), findsNothing, reason: p);
      }
    });
  }
}
