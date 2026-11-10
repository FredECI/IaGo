import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';
import '../features/account/account_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/sign_up_page.dart';
import '../features/auth/terms_page.dart';
import '../features/bank/bank_pages.dart';
import '../features/community/community_access.dart';
import '../features/community/community_pages.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/direction/direction_pages.dart';
import '../features/import/import_page.dart';
import '../features/lists/list_editor_page.dart';
import '../features/metrics/metrics_page.dart';
import '../features/lists/lists_page.dart';
import '../features/questions/content_tree_page.dart';
import '../features/questions/question_detail_page.dart';
import '../features/questions/question_form_page.dart';
import '../features/questions/questions_page.dart';
import 'shell.dart';

/// Caminhos das telas (em português, como aparecem na barra do navegador).
abstract final class Routes {
  static const String login = '/entrar';
  static const String signUp = '/cadastro';
  static const String terms = '/termos';
  static const String dashboard = '/painel';
  static const String questions = '/questoes';
  static const String lists = '/listas';
  static const String account = '/conta';

  /// Formulário em tela cheia (fora das abas).
  static const String newQuestion = '/questao/nova';
  static String editQuestion(String id) => '/questao/$id/editar';

  /// Detalhe dentro da aba Questões.
  static String question(String id) => '$questions/$id';

  /// Acervo organizado por área → matéria → assunto.
  static const String contentTree = '$questions/conteudos';

  /// Acervo (só leitura) dentro da aba Questões.
  static const String bank = '$questions/acervo';
  static const String bankSources = '$bank/fontes';
  static String bankQuestion(String id) => '$bank/$id';

  /// Importar várias questões (tela cheia, fora das abas).
  static const String import = '/importar';

  /// Direciona (tela cheia, aberta pelo Painel).
  static const String direction = '/direciona';
  static const String directionGoal = '$direction/objetivo';

  /// Conecta (tela cheia). Só aparece para quem a `AccessPolicy` libera.
  static const String community = '/conecta';
  static const String becomeMember = '$community/membro';
  static const String moderation = '$community/moderacao';
  static String communityRoom(String id) => '$community/$id';
  static String communityPost(String id, String postId) =>
      '$community/$id/conversa/$postId';

  /// Editor de uma lista (aba Listas).
  static String list(String id) => '$lists/$id';

  /// H1–H6 do piloto (administradores; na demo, dados simulados).
  static const String metrics = '/metricas';
}

final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(conectaVisibleProvider, (_, _) => refresh.value++);
  ref.listen(conectaJoinableProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: Routes.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final location = state.matchedLocation;
      final onEntry = location == Routes.login || location == Routes.signUp;
      // Termos: abertos para todos (o cadastro aponta para eles).
      if (!signedIn && !onEntry && location != Routes.terms) {
        return Routes.login;
      }
      if (signedIn && onEntry) return Routes.dashboard;
      // Conecta: a rota também obedece à política (link direto não burla).
      // "Virar membro" abre só se o Conecta estiver ligado (F6).
      final inConecta =
          location == Routes.community ||
          location.startsWith('${Routes.community}/');
      if (signedIn &&
          inConecta &&
          !(ref.read(conectaVisibleProvider) ||
              (location == Routes.becomeMember &&
                  ref.read(conectaJoinableProvider)))) {
        return Routes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(path: Routes.terms, builder: (_, _) => const TermsPage()),
      GoRoute(path: Routes.metrics, builder: (_, _) => const MetricsPage()),
      GoRoute(path: Routes.import, builder: (_, _) => const ImportPage()),
      GoRoute(
        path: Routes.direction,
        builder: (_, _) => const DirectionPage(),
        routes: [
          GoRoute(path: 'objetivo', builder: (_, _) => const GoalPage()),
        ],
      ),
      GoRoute(
        path: Routes.community,
        builder: (_, _) => const CommunityHomePage(),
        routes: [
          // Antes de ':communityId', senão viraria um id.
          GoRoute(path: 'membro', builder: (_, _) => const BecomeMemberPage()),
          GoRoute(path: 'moderacao', builder: (_, _) => const ModerationPage()),
          GoRoute(
            path: ':communityId',
            builder: (_, state) => CommunityPage(
              communityId: state.pathParameters['communityId']!,
            ),
            routes: [
              GoRoute(
                path: 'conversa/:postId',
                builder: (_, state) => CommunityPostPage(
                  communityId: state.pathParameters['communityId']!,
                  postId: state.pathParameters['postId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.newQuestion,
        builder: (_, _) => const QuestionFormPage(),
      ),
      GoRoute(
        path: '/questao/:id/editar',
        builder: (_, state) =>
            QuestionFormPage(questionId: state.pathParameters['id']),
      ),
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
                routes: [
                  // Antes de ':id', senão "conteudos" e "acervo" viram ids.
                  GoRoute(
                    path: 'acervo',
                    builder: (_, _) => const BankPage(),
                    routes: [
                      GoRoute(
                        path: 'fontes',
                        builder: (_, _) => const BankSourcesPage(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, state) => BankQuestionPage(
                          questionId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'conteudos',
                    builder: (_, _) => const ContentTreePage(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => QuestionDetailPage(
                      questionId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.lists,
                builder: (_, _) => const ListsPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        ListEditorPage(listId: state.pathParameters['id']!),
                  ),
                ],
              ),
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
