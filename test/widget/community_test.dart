import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/community_repository.dart';
import 'package:iago/data/local/community_demo_data.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/features/community/community_pages.dart';
import 'package:iago/features/community/community_providers.dart';
import 'package:iago/features/community/community_state.dart';
import 'package:iago/features/community/personal_data.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Registra as decisões da moderação.
class _SpyRepository extends MemoryCommunityRepository {
  _SpyRepository({
    required super.clock,
    super.membership,
    super.posts,
    super.replies,
    super.votes,
    super.moderator,
  });

  final List<ModerationDecision> decisions = [];

  @override
  Future<void> resolve(String reportId, ModerationDecision decision) {
    decisions.add(decision);
    return super.resolve(reportId, decision);
  }
}

class _BannedRepository extends MemoryCommunityRepository {
  _BannedRepository({required super.clock, super.membership, super.posts});

  @override
  Future<bool> isBanned() async => true;
}

DateTime _now = testNow;

Membership _member() => Membership(
  nickname: 'pedro_estuda',
  declaredMinAge: 18,
  rulesVersion: communityRulesVersion,
  joinedAt: testNow,
);

_SpyRepository _repo({
  bool moderator = false,
  List<Post> extraPosts = const [],
  List<Reply> extraReplies = const [],
}) {
  final seed = CommunityDemoData.build(testNow);
  return _SpyRepository(
    clock: () => _now,
    membership: _member(),
    posts: [...seed.posts, ...extraPosts],
    replies: [...seed.replies, ...extraReplies],
    votes: seed.votes,
    moderator: moderator,
  );
}

Future<void> pumpCommunity(
  WidgetTester tester,
  CommunityRepository repo, {
  String location = '/conecta',
}) async {
  _now = testNow;
  tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
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
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        communityRepositoryProvider.overrideWithValue(repo),
        communityUidProvider.overrideWithValue(
          MemoryCommunityRepository.demoUid,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> writePost(WidgetTester tester, String title, String body) async {
  await tapKey(tester, 'new-post');
  await tester.enterText(find.byKey(const Key('post-title')), title);
  await tester.enterText(find.byKey(const Key('post-body')), body);
  await tapKey(tester, 'post-submit');
}

Future<void> sendReply(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('reply-field')), text);
  await tapKey(tester, 'reply-send');
}

Post _post(String id, String community, {String? nick, int minutes = 0}) =>
    Post(
      id: id,
      communityId: community,
      authorUid: 'demo-${nick ?? 'x'}',
      authorNickname: nick ?? 'x',
      title: 'Título $id',
      body: 'Texto $id',
      status: ContentStatus.visible,
      createdAt: testNow.subtract(Duration(minutes: minutes)),
    );

const String _conv = '/conecta/matematica/conversa/demo-p1';

void main() {
  setUpAll(initTestLocale);

  group('detector de dado pessoal', () {
    test('acha e-mail, CPF e telefone; texto comum passa', () {
      expect(detectPersonalData('escreva para ana@ex.com'), [
        PersonalDataKind.email,
      ]);
      expect(detectPersonalData('meu cpf 123.456.789-09'), [
        PersonalDataKind.cpf,
      ]);
      expect(detectPersonalData('12345678909'), [PersonalDataKind.cpf]);
      expect(detectPersonalData('ligue (21) 98765-4321'), [
        PersonalDataKind.phone,
      ]);
      expect(detectPersonalData('+55 21 98765-4321'), [PersonalDataKind.phone]);
      expect(
        detectPersonalData('A questão 12 vale 2 pontos em 2024.'),
        isEmpty,
      );
      expect(detectPersonalData('f(x) = 3x + 10, x = 1234'), isEmpty);
    });
  });

  group('Comunidades', () {
    testWidgets('mostra as 5 fixas e leva a uma comunidade', (tester) async {
      await pumpCommunity(tester, _repo());
      for (final c in communities) {
        expect(find.byKey(Key('community-${c.id}')), findsOneWidget);
      }
      expect(find.byKey(const Key('open-moderation')), findsNothing);
      await tapKey(tester, 'community-matematica');
      expect(find.text('Como saber se uma função é injetora?'), findsOneWidget);
      expect(find.text('Dica para decorar a tabela periódica'), findsNothing);
    });

    testWidgets('sua reputação aparece ao lado da média do grupo', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo());
      expect(find.text('0 ajudas (média do grupo: 0,9)'), findsOneWidget);
    });

    testWidgets('lista vazia e comunidade desconhecida', (tester) async {
      await pumpCommunity(tester, _repo(), location: '/conecta/natureza');
      expect(find.text('Dica para decorar a tabela periódica'), findsOneWidget);
      await pumpCommunity(
        tester,
        MemoryCommunityRepository(clock: () => _now, membership: _member()),
        location: '/conecta/reforco',
      );
      expect(find.text('Ainda não há conversas aqui'), findsOneWidget);
      await pumpCommunity(tester, _repo(), location: '/conecta/nada');
      expect(find.text('Comunidade não encontrada'), findsOneWidget);
    });

    testWidgets('erro ao carregar mostra "Tentar de novo"', (tester) async {
      await pumpCommunity(
        tester,
        MemoryCommunityRepository(clock: () => _now),
        location: '/conecta/matematica',
      );
      expect(find.text('Não foi possível carregar'), findsOneWidget);
      expect(find.byKey(const Key('room-retry')), findsOneWidget);
    });

    testWidgets('pagina: 20 por vez e "Carregar mais"', (tester) async {
      final many = [
        for (var i = 0; i < 25; i++) _post('m$i', 'reforco', minutes: i),
      ];
      await pumpCommunity(
        tester,
        _repo(extraPosts: many),
        location: '/conecta/reforco',
      );
      expect(find.byKey(const Key('post-m0')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('room-more')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('post-m24')), findsNothing);
      await tapKey(tester, 'room-more');
      await tester.scrollUntilVisible(
        find.byKey(const Key('post-m24')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('post-m24')), findsOneWidget);
      expect(find.byKey(const Key('room-more')), findsNothing);
    });
  });

  group('Postar, responder e Ajudou', () {
    testWidgets('posta, responde e respeita o intervalo de 30 s', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo(), location: '/conecta/matematica');
      await writePost(tester, 'Dúvida sobre limites', 'Alguém explica?');
      expect(find.text('Post publicado.'), findsOneWidget);
      expect(find.text('Dúvida sobre limites'), findsOneWidget);

      await tester.tap(find.text('Dúvida sobre limites'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-replies')), findsOneWidget);

      // Menos de 30 s depois do post: o servidor nega.
      await sendReply(tester, 'Eu mesmo respondo');
      expect(find.text('Aguarde 30 s para publicar de novo.'), findsOneWidget);
      expect(find.byKey(const Key('no-replies')), findsOneWidget);

      _now = testNow.add(const Duration(seconds: 31));
      await tapKey(tester, 'reply-send');
      expect(find.byKey(const Key('no-replies')), findsNothing);
      expect(find.byKey(const Key('reply-error')), findsNothing);
    });

    testWidgets('título curto mostra o erro de validação', (tester) async {
      await pumpCommunity(tester, _repo(), location: '/conecta/matematica');
      await writePost(tester, 'oi', 'texto');
      expect(find.byKey(const Key('post-error')), findsOneWidget);
      expect(find.textContaining('título precisa ter'), findsOneWidget);
    });

    testWidgets('Ajudou: soma uma vez e nunca na própria resposta', (
      tester,
    ) async {
      final mine = Reply(
        id: 'mine-1',
        postId: 'demo-p1',
        authorUid: MemoryCommunityRepository.demoUid,
        authorNickname: 'pedro_estuda',
        body: 'Minha resposta',
        status: ContentStatus.visible,
        createdAt: testNow,
      );
      final repo = _repo(extraReplies: [mine]);
      await pumpCommunity(tester, repo, location: _conv);
      expect(find.text('Ajudou (3)'), findsOneWidget);

      await tapKey(tester, 'helpful-demo-r1');
      expect(find.text('Ajudou (4) - você marcou'), findsOneWidget);
      expect(await repo.myHelpfulVotes('demo-p1'), {'demo-r1'});
      expect(await repo.helpfulCount('demo-r1'), 4);

      final own = tester.widget<TextButton>(
        find.byKey(const Key('helpful-mine-1')),
      );
      expect(own.onPressed, isNull);
      expect(await repo.helpfulCount('mine-1'), 0);
    });

    testWidgets('tocar no apelido mostra "N ajudas (média do grupo: M)"', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo(), location: _conv);
      await tester.tap(find.byKey(const Key('author-demo-caio_log')).last);
      await tester.pumpAndSettle();
      expect(find.text('3 ajudas (média do grupo: 0,9)'), findsOneWidget);
    });

    testWidgets('responde só a post visível: link direto abre a conversa', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo(), location: _conv);
      expect(find.text('Como saber se uma função é injetora?'), findsWidgets);
      expect(find.textContaining('injetora não repete'), findsOneWidget);
      expect(find.byKey(const Key('reply-field')), findsOneWidget);
    });
  });

  group('Dado pessoal e texto puro', () {
    testWidgets('avisa antes de publicar telefone; permite revisar', (
      tester,
    ) async {
      final repo = _repo();
      await pumpCommunity(tester, repo, location: _conv);
      await sendReply(tester, 'Me chama em (21) 98765-4321');
      expect(find.byKey(const Key('personal-data-dialog')), findsOneWidget);
      expect(find.textContaining('telefone'), findsWidgets);

      await tapKey(tester, 'personal-data-review');
      expect(await repo.replies('demo-p1'), hasLength(2));

      await tapKey(tester, 'reply-send');
      await tapKey(tester, 'personal-data-publish');
      expect(await repo.replies('demo-p1'), hasLength(3));
      expect(find.text('Me chama em (21) 98765-4321'), findsOneWidget);
    });

    testWidgets('post com e-mail também avisa', (tester) async {
      await pumpCommunity(tester, _repo(), location: '/conecta/matematica');
      await writePost(tester, 'Grupo de estudo', 'Escreva para ana@ex.com');
      expect(find.byKey(const Key('personal-data-dialog')), findsOneWidget);
      expect(find.textContaining('e-mail'), findsWidgets);
    });

    testWidgets('HTML e link aparecem como texto puro', (tester) async {
      final repo = _repo();
      await repo.createPost(
        const NewPost(
          communityId: 'matematica',
          title: 'Texto com marcação',
          body: '<b>negrito</b> https://exemplo.com <img src="x.png">',
        ),
      );
      _now = testNow.add(const Duration(minutes: 5));
      await pumpCommunity(tester, repo, location: '/conecta/matematica');
      await tester.tap(find.text('Texto com marcação'));
      await tester.pumpAndSettle();
      expect(
        find.text('<b>negrito</b> https://exemplo.com <img src="x.png">'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      // Nenhum trecho do texto tem toque de link.
      final rich = tester.widgetList<RichText>(find.byType(RichText));
      for (final r in rich) {
        var hasRecognizer = false;
        r.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) hasRecognizer = true;
          return true;
        });
        expect(hasRecognizer, isFalse);
      }
    });
  });

  group('Denunciar', () {
    testWidgets('denunciar uma resposta a esconde de quem denunciou', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo(), location: _conv);
      expect(find.textContaining('Eu desenho as setas'), findsOneWidget);
      await tapKey(tester, 'more-reply-demo-r2');
      await tapKey(tester, 'report-reply-demo-r2');
      // Os 7 motivos, com os rótulos das regras.
      for (final label in [
        'Ofensivo',
        'Assédio',
        'Dado pessoal',
        'Conteúdo sexual ou envolvendo menor',
        'Direitos autorais',
        'Spam',
        'Outro',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('report-submit')))
            .onPressed,
        isNull,
      );
      await tapKey(tester, 'report-reason-spam');
      await tapKey(tester, 'report-submit');
      expect(find.textContaining('Eu desenho as setas'), findsNothing);
      expect(find.textContaining('Denúncia enviada'), findsOneWidget);
      // Os outros conteúdos ficam.
      expect(find.textContaining('injetora não repete'), findsOneWidget);
    });

    testWidgets('denunciar um post volta à lista sem ele', (tester) async {
      await pumpCommunity(tester, _repo());
      await tapKey(tester, 'community-matematica');
      await tester.tap(find.text('Logaritmo: por onde começar?'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'more-post');
      await tapKey(tester, 'report-post');
      await tapKey(tester, 'report-reason-offensive');
      await tapKey(tester, 'report-submit');
      expect(find.text('Logaritmo: por onde começar?'), findsNothing);
      expect(find.text('Como saber se uma função é injetora?'), findsOneWidget);
    });

    testWidgets('na própria resposta há "Apagar", não "Denunciar"', (
      tester,
    ) async {
      final repo = _repo();
      await repo.reply('demo-p1', 'Resposta minha');
      await pumpCommunity(tester, repo, location: _conv);
      await tapKey(tester, 'more-reply-r1');
      expect(find.byKey(const Key('report-reply-r1')), findsNothing);
      await tapKey(tester, 'delete-reply-r1');
      await tapKey(tester, 'delete-confirm');
      expect(find.text('Resposta minha'), findsNothing);
    });
  });

  group('Conteúdo próprio em análise ou oculto', () {
    testWidgets('faixa com motivo e contato de contestação (CA-C5)', (
      tester,
    ) async {
      final hidden = Post(
        id: 'h1',
        communityId: 'reforco',
        authorUid: MemoryCommunityRepository.demoUid,
        authorNickname: 'pedro_estuda',
        title: 'Meu post oculto',
        body: 'Texto',
        status: ContentStatus.hidden,
        moderationReason: 'Contém ofensa a outro membro.',
        createdAt: testNow,
      );
      final pending = hidden.copyWith(status: ContentStatus.pending);
      await pumpCommunity(
        tester,
        _repo(extraPosts: [hidden]),
        location: '/conecta/reforco',
      );
      expect(
        find.textContaining('Contém ofensa a outro membro.'),
        findsOneWidget,
      );
      expect(find.textContaining('<e-mail do projeto>'), findsOneWidget);

      await pumpCommunity(
        tester,
        _repo(extraPosts: [_withId(pending, 'h2')]),
        location: '/conecta/reforco',
      );
      expect(find.textContaining('Em análise'), findsOneWidget);
      expect(find.textContaining('<e-mail do projeto>'), findsOneWidget);
    });

    testWidgets('banido não escreve e vê o aviso', (tester) async {
      await pumpCommunity(
        tester,
        _BannedRepository(
          clock: () => _now,
          membership: _member(),
          posts: [_post('a', 'reforco')],
        ),
        location: '/conecta/reforco',
      );
      expect(find.byKey(const Key('banned-notice')), findsOneWidget);
      expect(find.byKey(const Key('new-post')), findsNothing);
      expect(find.text('Título a'), findsNothing);
    });

    testWidgets('banido: a conversa mostra o aviso, sem campo de resposta', (
      tester,
    ) async {
      await pumpCommunity(
        tester,
        _BannedRepository(
          clock: () => _now,
          membership: _member(),
          posts: [_post('a', 'reforco')],
        ),
        location: '/conecta/reforco/conversa/a',
      );
      expect(find.byKey(const Key('banned-notice')), findsOneWidget);
      expect(find.byKey(const Key('reply-field')), findsNothing);
    });
  });

  group('Moderação', () {
    Future<_SpyRepository> queue(WidgetTester tester) async {
      final repo = _repo(moderator: true);
      await repo.report(
        const NewReport(
          targetType: ReportTarget.post,
          targetId: 'demo-p3',
          postId: 'demo-p3',
          reason: ReportReason.spam,
          details: 'Propaganda de curso',
        ),
      );
      await repo.report(
        const NewReport(
          targetType: ReportTarget.reply,
          targetId: 'demo-r2',
          postId: 'demo-p1',
          reason: ReportReason.harassment,
        ),
      );
      await pumpCommunity(tester, repo, location: '/conecta/moderacao');
      return repo;
    }

    testWidgets('não moderador fica sem acesso', (tester) async {
      await pumpCommunity(tester, _repo(), location: '/conecta/moderacao');
      expect(find.byKey(const Key('moderation-denied')), findsOneWidget);
      expect(find.text('Sem acesso'), findsOneWidget);
    });

    testWidgets('moderador vê a fila com motivo, detalhe e conteúdo', (
      tester,
    ) async {
      await queue(tester);
      expect(
        find.text('2 denúncias abertas (revisar em até 24 horas)'),
        findsOneWidget,
      );
      expect(find.text('Post denunciado: Spam'), findsOneWidget);
      expect(find.text('Resposta denunciada: Assédio'), findsOneWidget);
      expect(find.text('Detalhes: Propaganda de curso'), findsOneWidget);
      expect(find.text('Dica para decorar a tabela periódica'), findsOneWidget);
    });

    testWidgets('restaurar encerra a denúncia', (tester) async {
      final repo = await queue(tester);
      await tapKey(tester, 'restore-demo-p3_demo-me');
      expect(repo.decisions.single.kind, ModerationKind.restore);
      expect(find.text('Post denunciado: Spam'), findsNothing);
      expect(find.text('Resposta denunciada: Assédio'), findsOneWidget);
    });

    testWidgets('ocultar exige motivo', (tester) async {
      final repo = await queue(tester);
      await tapKey(tester, 'hide-demo-p3_demo-me');
      await tapKey(tester, 'reason-confirm');
      expect(find.textContaining('Escreva o motivo'), findsOneWidget);
      expect(repo.decisions, isEmpty);

      await tester.enterText(
        find.byKey(const Key('reason-field')),
        'É propaganda.',
      );
      await tapKey(tester, 'reason-confirm');
      expect(repo.decisions.single.kind, ModerationKind.hide);
      expect(repo.decisions.single.reason, 'É propaganda.');
      expect(find.text('Post denunciado: Spam'), findsNothing);
    });

    testWidgets('ocultar e banir grava a decisão com o motivo', (tester) async {
      final repo = await queue(tester);
      await tapKey(tester, 'ban-demo-r2_demo-me');
      expect(find.textContaining('será banida'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reason-field')), 'Assédio.');
      await tapKey(tester, 'reason-confirm');
      expect(repo.decisions.single.kind, ModerationKind.hideAndBan);
      expect(repo.decisions.single.reason, 'Assédio.');
      expect(find.text('Resposta denunciada: Assédio'), findsNothing);
    });

    testWidgets('denúncia de conteúdo apagado só se dispensa', (tester) async {
      final repo = _repo(moderator: true);
      await repo.report(
        const NewReport(
          targetType: ReportTarget.reply,
          targetId: 'demo-r2',
          postId: 'demo-p1',
          reason: ReportReason.other,
        ),
      );
      await repo.deleteReply('demo-r2');
      await pumpCommunity(tester, repo, location: '/conecta/moderacao');
      expect(find.text('Conteúdo apagado'), findsOneWidget);
      expect(find.textContaining('restore-'), findsNothing);
      await tapKey(tester, 'dismiss-demo-r2_demo-me');
      expect(find.text('Nenhuma denúncia aberta'), findsOneWidget);
    });

    testWidgets('fila vazia e entrada na home só para moderador', (
      tester,
    ) async {
      await pumpCommunity(tester, _repo(moderator: true));
      expect(find.byKey(const Key('open-moderation')), findsOneWidget);
      await tapKey(tester, 'open-moderation');
      expect(find.text('Nenhuma denúncia aberta'), findsOneWidget);
    });
  });
}

Post _withId(Post p, String id) => Post(
  id: id,
  communityId: p.communityId,
  authorUid: p.authorUid,
  authorNickname: p.authorNickname,
  title: p.title,
  body: p.body,
  status: p.status,
  createdAt: p.createdAt,
);
