import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_bank_catalog.dart';
import '../helpers/test_app.dart';
import 'auth_flow_test.dart' show pumpWithAuth;

/// Validação da F7 (QA): rotas novas, guard do Conecta e 360 px.
void main() {
  setUpAll(initTestLocale);

  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)))
          .read(routerProvider);

  String locationOf(WidgetTester tester) =>
      routerOf(tester).state.uri.toString();

  Future<void> go(WidgetTester tester, String path) async {
    routerOf(tester).go(path);
    await tester.pumpAndSettle();
  }

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

  group('rotas novas na demo (360 px, sem estouro)', () {
    const routes = <String, String>{
      '/questoes/acervo': 'Acervo',
      '/questoes/acervo/fontes': 'Fontes',
      '/questoes/acervo/enem-2023-1': 'Questão',
      '/importar': 'Importar questões',
      '/direciona': 'Direciona',
      '/direciona/objetivo': 'Objetivo de estudo',
      '/conecta': 'Conecta',
      '/conecta/membro': 'membro',
      '/conecta/moderacao': 'oderação',
      '/conecta/geral': 'Comunidade',
      '/conecta/geral/conversa/p1': 'Conversa',
    };
    for (final e in routes.entries) {
      testWidgets('abre ${e.key}', (tester) async {
        await pumpIagoApp(
          tester,
          overrides: [bankCatalogProvider.overrideWithValue(FakeBankCatalog())],
        );
        await enterDemo(tester);
        await go(tester, e.key);
        expect(locationOf(tester), e.key, reason: 'não pode redirecionar');
        expect(find.textContaining(e.value), findsWidgets);
        // Qualquer estouro de layout vira exceção capturada pelo tester.
        expect(tester.takeException(), isNull);
        // Direciona (DI4) e Acervo (A4/A5) já são telas de verdade, sem
        // página provisória.
        expect(
          find.byKey(const Key('placeholder-back')),
          e.key.startsWith('/direciona') || e.key.startsWith('/questoes/acervo')
              ? findsNothing
              : findsOneWidget,
        );
      });
    }

    testWidgets('/questoes/conteudos e /questoes/:id seguem funcionando', (
      tester,
    ) async {
      await pumpIagoApp(tester);
      await enterDemo(tester);
      await go(tester, '/questoes/conteudos');
      expect(find.byKey(const Key('placeholder-back')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('guard do Conecta', () {
    testWidgets('sem sessão, link direto vai para o login', (tester) async {
      await pumpIagoApp(tester);
      await go(tester, '/conecta/geral/conversa/p1');
      expect(locationOf(tester), '/entrar');
    });

    testWidgets('conta sem permissão: /conecta/** volta ao Painel', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await signInAna(tester);
      for (final p in const [
        '/conecta',
        '/conecta/moderacao',
        '/conecta/geral',
        '/conecta/geral/conversa/p1',
        '/conecta/',
      ]) {
        await go(tester, p);
        expect(locationOf(tester), '/painel', reason: p);
        expect(find.byKey(const Key('placeholder-back')), findsNothing);
      }
    });

    testWidgets('conta com a flag desligada: /conecta/membro volta ao Painel', (
      tester,
    ) async {
      await pumpWithAuth(tester);
      await signInAna(tester);
      await go(tester, '/conecta/membro');
      expect(locationOf(tester), '/painel');
    });

    testWidgets('flag ligada mas não membro: guard barra', (tester) async {
      await pumpWithAuth(tester, runtimeConfig: {'conectaEnabled': true});
      await signInAna(tester);
      await go(tester, '/conecta');
      expect(locationOf(tester), '/painel');
    });

    testWidgets('membro com flag: /conecta/** abre', (tester) async {
      await pumpWithAuth(
        tester,
        runtimeConfig: {'conectaEnabled': true},
        extra: [isMemberProvider.overrideWithValue(true)],
      );
      await signInAna(tester);
      await go(tester, '/conecta/geral/conversa/p1');
      expect(locationOf(tester), '/conecta/geral/conversa/p1');
    });

    testWidgets(
      'perder a permissão com o Conecta aberto expulsa para o Painel',
      (tester) async {
        var member = true;
        await pumpWithAuth(
          tester,
          runtimeConfig: {'conectaEnabled': true},
          extra: [isMemberProvider.overrideWith((ref) => member)],
        );
        await signInAna(tester);
        await go(tester, '/conecta');
        expect(locationOf(tester), '/conecta');
        member = false;
        ProviderScope.containerOf(tester.element(find.byType(IagoApp)))
            .invalidate(isMemberProvider);
        await tester.pumpAndSettle();
        expect(locationOf(tester), '/painel');
      },
    );
  });

  group('conta real: Direciona, Acervo e Importar (sem guard)', () {
    testWidgets('abrem na conta real', (tester) async {
      await pumpWithAuth(
        tester,
        extra: [bankCatalogProvider.overrideWithValue(FakeBankCatalog())],
      );
      await signInAna(tester);
      for (final p in const ['/direciona', '/importar', '/questoes/acervo']) {
        await go(tester, p);
        expect(locationOf(tester), p);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
