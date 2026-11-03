import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';
import '../features/account/account_page.dart';
import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/lists/lists_page.dart';
import '../features/questions/questions_page.dart';
import 'shell.dart';

/// Caminhos das telas (em português, como aparecem na barra do navegador).
abstract final class Routes {
  static const String login = '/entrar';
  static const String dashboard = '/painel';
  static const String questions = '/questoes';
  static const String lists = '/listas';
  static const String account = '/conta';
}

final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: Routes.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final onLogin = state.matchedLocation == Routes.login;
      if (!signedIn && !onLogin) return Routes.login;
      if (signedIn && onLogin) return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (_, _) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.questions,
                builder: (_, _) => const QuestionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.lists, builder: (_, _) => const ListsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                builder: (_, _) => const AccountPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
