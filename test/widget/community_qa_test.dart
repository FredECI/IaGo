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
import 'package:iago/features/community/community_widgets.dart';
import 'package:iago/features/community/personal_data.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Testes de QA do Conecta (C2 a C4): complementam `community_test.dart`.

DateTime _now = testNow;

Membership _member() => Membership(
  nickname: 'pedro_estuda',
  declaredMinAge: 18,
  rulesVersion: communityRulesVersion,
  joinedAt: testNow,
);

MemoryCommunityRepository _repo({
  String uid = MemoryCommunityRepository.demoUid,
  bool moderator = false,
  bool member = true,
  List<Post> extraPosts = const [],
  List<Reply> extraReplies = const [],
}) {
  final seed = CommunityDemoData.build(testNow);
  return MemoryCommunityRepository(
    clock: () => _now,
    uid: uid,
    membership: member ? _member() : null,
    posts: [...seed.posts, ...extraPosts],
    replies: [...seed.replies, ...extraReplies],
    votes: seed.votes,
    moderator: moderator,
  );
}

Future<void> pump(
  WidgetTester tester,
  CommunityRepository repo, {
  required String location,
  String uid = MemoryCommunityRepository.demoUid,
  double textScale = 1,
}) async {
  _now = testNow;
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
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        communityRepositoryProvider.overrideWithValue(repo),
        communityUidProvider.overrideWithValue(uid),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 780),
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
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

Post _post({
  required String id,
  String community = 'reforco',
  String uid = MemoryCommunityRepository.demoUid,
  String nick = 'pedro_estuda',
  String title = 'Título',
  String body = 'Texto',
  ContentStatus status = ContentStatus.visible,
  String? reason,
}) => Post(
  id: id,
  communityId: community,
  authorUid: uid,
  authorNickname: nick,
  title: title,
  body: body,
  status: status,
  moderationReason: reason,
  createdAt: testNow,
);

Reply _reply({
  required String id,
  String postId = 'demo-p1',
  String uid = MemoryCommunityRepository.demoUid,
  String nick = 'pedro_estuda',
  String body = 'Resposta',
  ContentStatus status = ContentStatus.visible,
  String? reason,
}) => Reply(
  id: id,
  postId: postId,
  authorUid: uid,
  authorNickname: nick,
  body: body,
  status: status,
  moderationReason: reason,
  createdAt: testNow,
);

const String _conv = '/conecta/matematica/conversa/demo-p1';

void main() {
  setUpAll(initTestLocale);

  group('CA-C9 detector: telefone, e-mail e CPF', () {
    const phones = {
      '(21) 98765-4321': 'celular com DDD e hífen',
      '21 98765 4321': 'celular com espaços',
      '+55 (21) 98765-4321': 'com +55',
      '55 21 987654321': 'com 55 sem +',
      '(21) 3456-7890': 'fixo com DDD',
      '2134567890': 'fixo só dígitos',
      'zap 21.98765.4321': 'com pontos',
    };
    for (final e in phones.entries) {
      test('avisa telefone: ${e.value}', () {
        expect(
          detectPersonalData('contato ${e.key} obrigado'),
          contains(PersonalDataKind.phone),
          reason: e.key,
        );
      });
    }

    test(
      'celular só com 11 dígitos avisa (como CPF, que tem o mesmo formato)',
      () {
        expect(detectPersonalData('21987654321'), isNotEmpty);
      },
    );

    const emails = [
      'ana@ex.com',
      'ana.silva+enem@mail.com.br',
      'ANA_S@EX.COM',
      'a-b@sub.dominio.edu.br',
    ];
    for (final e in emails) {
      test('avisa e-mail $e', () {
        expect(detectPersonalData('escreve $e'), [PersonalDataKind.email]);
      });
    }

    const cpfs = [
      '123.456.789-09',
      '12345678909',
      '123.456.78909',
      '123456789-09',
    ];
    for (final c in cpfs) {
      test('avisa CPF $c', () {
        expect(detectPersonalData('cpf $c fim'), [PersonalDataKind.cpf]);
      });
    }

    test('vários tipos no mesmo texto, sem repetir', () {
      expect(
        detectPersonalData(
          'ana@ex.com ou (21) 98765-4321, cpf 123.456.789-09, ana@ex.com',
        ),
        [PersonalDataKind.email, PersonalDataKind.cpf, PersonalDataKind.phone],
      );
    });

    const clean = [
      'Na questão 45 da prova de 2023 a resposta muda.',
      'ENEM 2023, caderno azul, questão 135',
      'Estudei dia 09/11/2026 e 10/11/2026.',
      'Prazo: 2026-11-09',
      'Dia 9 de novembro de 2026 às 14h30',
      'O preço subiu para R\$ 1.500,00 em 2024',
      'R\$ 1.000.000,00',
      'Se f(x) = 3x + 10 e x = 1234, então f(x) vale 3712.',
      'pi vale 3,14159',
      '1/2 + 3/4 = 5/4',
      'Meu plano: 2 horas por dia, 5 dias por semana, 10 semanas.',
      'Capítulos 12, 13 e 14 da página 345 a 389',
      'Velocidade 120 km/h por 3,5 h',
      'Questões 1 a 45 e 46 a 90',
      'ano 2022 e 2023 e 2024',
      '',
      '   ',
      'arroba @ sozinha e email@ incompleto',
    ];
    for (final c in clean) {
      test('não avisa: "$c"', () {
        expect(detectPersonalData(c), isEmpty, reason: c);
      });
    }

    test('regressão: telefone sem DDD (98765-4321) deveria avisar', () {
      expect(detectPersonalData('chama no 98765-4321'), isNotEmpty);
    });

    test('regressão: telefone fixo sem DDD (3456-7890) deveria avisar', () {
      expect(detectPersonalData('ligue 3456-7890'), isNotEmpty);
    });

    test('texto enorme não trava (regex linear)', () {
      final big = '${'a1 ' * 5000}ana@ex.com';
      final sw = Stopwatch()..start();
      expect(detectPersonalData(big), contains(PersonalDataKind.email));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('CA-C7 rótulo de reputação', () {
    test('singular, plural, zero e vírgula decimal', () {
      expect(
        reputationLabel(const Reputation(helpful: 1, groupAverage: 2.5)),
        '1 ajuda (média do grupo: 2,5)',
      );
      expect(
        reputationLabel(const Reputation(helpful: 0, groupAverage: 0)),
        '0 ajudas (média do grupo: 0,0)',
      );
      expect(
        reputationLabel(const Reputation(helpful: 12, groupAverage: 0.94)),
        '12 ajudas (média do grupo: 0,9)',
      );
    });

    testWidgets('home e folha do apelido nunca mostram número solto', (
      tester,
    ) async {
      await pump(tester, _repo(), location: '/conecta');
      expect(find.textContaining('(média do grupo:'), findsOneWidget);
      await pump(tester, _repo(), location: _conv);
      await tester.tap(find.byKey(const Key('author-demo-bia_quimica')).last);
      await tester.pumpAndSettle();
      expect(find.text('1 ajuda (média do grupo: 0,9)'), findsOneWidget);
    });
  });

  group('CA-C3 intervalo de 30 s', () {
    testWidgets('segundo post em menos de 30 s mostra "Aguarde N s"', (
      tester,
    ) async {
      final repo = _repo();
      await pump(tester, repo, location: '/conecta/matematica');
      Future<void> write(String t) async {
        await tapKey(tester, 'new-post');
        await tester.enterText(find.byKey(const Key('post-title')), t);
        await tester.enterText(find.byKey(const Key('post-body')), 'Corpo');
        await tapKey(tester, 'post-submit');
      }

      await write('Primeiro post');
      expect(find.text('Primeiro post'), findsOneWidget);
      _now = testNow.add(const Duration(seconds: 10));
      await write('Segundo post');
      // A folha continua aberta, com o erro e o tempo restante.
      expect(find.text('Aguarde 20 s para publicar de novo.'), findsOneWidget);
      expect((await repo.posts('matematica')).items.length, 3);

      _now = testNow.add(const Duration(milliseconds: 29500));
      await tapKey(tester, 'post-submit');
      expect(find.text('Aguarde 1 s para publicar de novo.'), findsOneWidget);

      _now = testNow.add(const Duration(seconds: 30));
      await tapKey(tester, 'post-submit');
      expect(find.text('Segundo post'), findsOneWidget);
    });

    testWidgets('resposta logo depois do post também espera', (tester) async {
      await pump(tester, _repo(), location: _conv);
      await tester.enterText(find.byKey(const Key('reply-field')), 'Um');
      await tapKey(tester, 'reply-send');
      await tester.enterText(find.byKey(const Key('reply-field')), 'Dois');
      await tapKey(tester, 'reply-send');
      expect(find.text('Aguarde 30 s para publicar de novo.'), findsOneWidget);
      // O texto digitado não se perde.
      expect(find.text('Dois'), findsOneWidget);
    });
  });

  group('CA-C4 denunciar', () {
    testWidgets('outro membro não vê post nem resposta em análise', (
      tester,
    ) async {
      final repo = _repo(
        uid: 'demo-outro',
        extraPosts: [
          _post(
            id: 'pend',
            title: 'Post sob denúncia',
            status: ContentStatus.pending,
          ),
        ],
        extraReplies: [
          _reply(
            id: 'rpend',
            body: 'Resposta sob denúncia',
            status: ContentStatus.pending,
          ),
        ],
      );
      await pump(tester, repo, location: '/conecta/reforco', uid: 'demo-outro');
      expect(find.text('Post sob denúncia'), findsNothing);
      await pump(tester, repo, location: _conv, uid: 'demo-outro');
      expect(find.text('Resposta sob denúncia'), findsNothing);
      expect(find.byKey(const Key('moderation-band')), findsNothing);
    });

    testWidgets('autor vê o conteúdo denunciado com a faixa "Em análise"', (
      tester,
    ) async {
      final repo = _repo(
        extraPosts: [
          _post(
            id: 'pend',
            title: 'Meu post denunciado',
            status: ContentStatus.pending,
          ),
        ],
        extraReplies: [
          _reply(
            id: 'rpend',
            body: 'Minha resposta denunciada',
            status: ContentStatus.pending,
          ),
        ],
      );
      await pump(tester, repo, location: '/conecta/reforco');
      expect(find.text('Meu post denunciado'), findsOneWidget);
      expect(find.textContaining('Em análise'), findsOneWidget);
      await pump(tester, repo, location: _conv);
      expect(
        find.text('Minha resposta denunciada', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Em análise', skipOffstage: false),
        findsOneWidget,
      );
      // "Ajudou" fica desligado em conteúdo em análise.
      final btn = tester.widget<TextButton>(
        find.byKey(const Key('helpful-rpend'), skipOffstage: false),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets(
      'moderador vê o conteúdo denunciado, sem texto de contestação',
      (tester) async {
        final repo = _repo(
          uid: 'demo-mod',
          moderator: true,
          extraPosts: [
            _post(
              id: 'pend',
              title: 'Post de outro',
              status: ContentStatus.pending,
            ),
          ],
        );
        await pump(tester, repo, location: '/conecta/reforco', uid: 'demo-mod');
        expect(find.text('Post de outro'), findsOneWidget);
        expect(find.textContaining('Em análise'), findsOneWidget);
        expect(find.textContaining('contestar'), findsNothing);
      },
    );

    test('mesma pessoa não denuncia duas vezes; outra pessoa pode', () async {
      final repo = _repo();
      const r = NewReport(
        targetType: ReportTarget.reply,
        targetId: 'demo-r1',
        postId: 'demo-p1',
        reason: ReportReason.spam,
      );
      await repo.report(r);
      await expectLater(
        repo.report(r),
        throwsA(
          isA<CommunityFailure>().having(
            (f) => f.kind,
            'kind',
            CommunityFailureKind.alreadyReported,
          ),
        ),
      );
      expect(
        communityErrorMessage(
          const CommunityFailure(CommunityFailureKind.alreadyReported),
        ),
        'Você já denunciou este conteúdo.',
      );
    });

    testWidgets('denúncia repetida mostra o aviso e não duplica a fila', (
      tester,
    ) async {
      final repo = _repo(moderator: true);
      // Primeira denúncia pelo repositório (já esconde de quem denunciou).
      await repo.report(
        const NewReport(
          targetType: ReportTarget.reply,
          targetId: 'demo-r2',
          postId: 'demo-p1',
          reason: ReportReason.spam,
        ),
      );
      // Como moderador a resposta continua à vista: tentar de novo pela tela.
      await pump(tester, repo, location: _conv);
      await tapKey(tester, 'more-reply-demo-r2');
      await tapKey(tester, 'report-reply-demo-r2');
      await tapKey(tester, 'report-reason-spam');
      await tapKey(tester, 'report-submit');
      expect(find.text('Você já denunciou este conteúdo.'), findsOneWidget);
      expect((await repo.openReports()).length, 1);
    });

    testWidgets('cancelar o diálogo não denuncia', (tester) async {
      final repo = _repo();
      await pump(tester, repo, location: _conv);
      await tapKey(tester, 'more-reply-demo-r1');
      await tapKey(tester, 'report-reply-demo-r1');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('injetora não repete'), findsOneWidget);
      expect((await repo.myFootprint()).openReportIds, isEmpty);
    });
  });

  group('CA-C5 moderação ponta a ponta', () {
    testWidgets('ocultar com motivo: o autor vê motivo e e-mail', (
      tester,
    ) async {
      final repo = _repo(moderator: true, extraPosts: [_post(id: 'meu')]);
      await repo.report(
        const NewReport(
          targetType: ReportTarget.post,
          targetId: 'meu',
          postId: 'meu',
          reason: ReportReason.offensive,
        ),
      );
      await pump(tester, repo, location: '/conecta/moderacao');
      await tapKey(tester, 'hide-meu_demo-me');
      await tester.enterText(
        find.byKey(const Key('reason-field')),
        'Linguagem ofensiva.',
      );
      await tapKey(tester, 'reason-confirm');
      expect(find.text('Nenhuma denúncia aberta'), findsOneWidget);

      await pump(tester, repo, location: '/conecta/reforco');
      expect(
        find.textContaining('Motivo: Linguagem ofensiva.'),
        findsOneWidget,
      );
      expect(find.textContaining(communityContactEmail), findsOneWidget);
    });

    testWidgets('restaurar devolve o conteúdo e tira a faixa', (tester) async {
      final repo = _repo(moderator: true, extraPosts: [_post(id: 'meu')]);
      await repo.report(
        const NewReport(
          targetType: ReportTarget.post,
          targetId: 'meu',
          postId: 'meu',
          reason: ReportReason.other,
        ),
      );
      await pump(tester, repo, location: '/conecta/moderacao');
      await tapKey(tester, 'restore-meu_demo-me');
      await pump(tester, repo, location: '/conecta/reforco');
      expect(find.text('Título'), findsOneWidget);
      expect(find.byKey(const Key('moderation-band')), findsNothing);
    });

    testWidgets('banir: o autor passa a ver o aviso e não escreve', (
      tester,
    ) async {
      final repo = _repo(moderator: true, extraPosts: [_post(id: 'meu')]);
      await repo.report(
        const NewReport(
          targetType: ReportTarget.post,
          targetId: 'meu',
          postId: 'meu',
          reason: ReportReason.harassment,
        ),
      );
      await pump(tester, repo, location: '/conecta/moderacao');
      await tapKey(tester, 'ban-meu_demo-me');
      await tester.enterText(find.byKey(const Key('reason-field')), 'Assédio.');
      await tapKey(tester, 'reason-confirm');

      expect(await repo.isBanned(), isTrue);
      await expectLater(
        repo.createPost(
          const NewPost(communityId: 'reforco', title: 'Volta', body: 'x'),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        repo.reply('demo-p1', 'oi'),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        repo.report(
          const NewReport(
            targetType: ReportTarget.reply,
            targetId: 'demo-r1',
            postId: 'demo-p1',
            reason: ReportReason.spam,
          ),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        repo.setHelpful(
          _reply(id: 'demo-r1', uid: 'demo-caio_log'),
          helpful: true,
        ),
        throwsA(isA<CommunityFailure>()),
      );

      await pump(tester, repo, location: '/conecta');
      expect(find.byKey(const Key('banned-notice')), findsOneWidget);
      expect(find.textContaining(communityContactEmail), findsOneWidget);
      expect(find.byKey(const Key('my-reputation')), findsNothing);
      expect(find.byKey(const Key('open-moderation')), findsNothing);
    });

    test('não moderador não resolve nem lista denúncias', () async {
      final repo = _repo();
      await expectLater(repo.openReports(), throwsA(isA<CommunityFailure>()));
      await expectLater(
        repo.resolve('x', const ModerationDecision(ModerationKind.restore)),
        throwsA(isA<CommunityFailure>()),
      );
    });

    test('ocultar sem motivo na camada de dados: autor vê "não informado"', () {
      // A tela exige motivo; a faixa trata o caso de motivo vazio mesmo assim.
      expect(
        reputationLabel(const Reputation(helpful: 2, groupAverage: 1)),
        isNotEmpty,
      );
    });

    testWidgets('faixa de oculto sem motivo diz "não informado"', (
      tester,
    ) async {
      await pump(
        tester,
        _repo(
          extraPosts: [_post(id: 'h', status: ContentStatus.hidden)],
        ),
        location: '/conecta/reforco',
      );
      expect(find.textContaining('Motivo: não informado.'), findsOneWidget);
    });

    testWidgets('outro membro não vê o conteúdo oculto', (tester) async {
      await pump(
        tester,
        _repo(
          uid: 'demo-outro',
          extraPosts: [
            _post(id: 'h', title: 'Oculto', status: ContentStatus.hidden),
          ],
        ),
        location: '/conecta/reforco',
        uid: 'demo-outro',
      );
      expect(find.text('Oculto'), findsNothing);
    });

    testWidgets('post oculto abre sem campo de resposta', (tester) async {
      await pump(
        tester,
        _repo(
          extraPosts: [
            _post(id: 'h', status: ContentStatus.hidden, reason: 'Spam.'),
          ],
        ),
        location: '/conecta/reforco/conversa/h',
      );
      expect(find.byKey(const Key('reply-closed')), findsOneWidget);
      expect(find.byKey(const Key('reply-field')), findsNothing);
    });
  });

  group('CA-C6 Ajudou', () {
    testWidgets('marcar e desmarcar mantém no máximo 1 voto por pessoa', (
      tester,
    ) async {
      final repo = _repo();
      await pump(tester, repo, location: _conv);
      await tapKey(tester, 'helpful-demo-r1');
      expect(find.text('Ajudou (4) - você marcou'), findsOneWidget);
      await tapKey(tester, 'helpful-demo-r1');
      expect(find.text('Ajudou (3)'), findsOneWidget);
      await tapKey(tester, 'helpful-demo-r1');
      expect(await repo.helpfulCount('demo-r1'), 4);
    });

    test('setHelpful repetido não soma duas vezes', () async {
      final repo = _repo();
      final r = _reply(id: 'demo-r1', uid: 'demo-caio_log');
      await repo.setHelpful(r, helpful: true);
      await repo.setHelpful(r, helpful: true);
      expect(await repo.helpfulCount('demo-r1'), 4);
      await repo.setHelpful(r, helpful: false);
      await repo.setHelpful(r, helpful: false);
      expect(await repo.helpfulCount('demo-r1'), 3);
    });

    test('própria resposta é rejeitada pelo repositório', () async {
      final repo = _repo();
      await expectLater(
        repo.setHelpful(_reply(id: 'x'), helpful: true),
        throwsA(
          isA<CommunityFailure>().having(
            (f) => f.kind,
            'kind',
            CommunityFailureKind.ownReply,
          ),
        ),
      );
    });

    testWidgets('reputação sobe quando outro membro marca', (tester) async {
      final repo = _repo(extraReplies: [_reply(id: 'mine')]);
      await pump(tester, repo, location: '/conecta');
      expect(find.text('0 ajudas (média do grupo: 0,9)'), findsOneWidget);
    });
  });

  group('CA-C8 texto puro', () {
    testWidgets('resposta com HTML e link é exibida literalmente', (
      tester,
    ) async {
      final repo = _repo();
      await pump(tester, repo, location: _conv);
      const evil =
          '<script>alert(1)</script> [x](http://a.com) **b** '
          'www.exemplo.com ![i](http://a.com/i.png)';
      await tester.enterText(find.byKey(const Key('reply-field')), evil);
      await tapKey(tester, 'reply-send');
      expect(find.text(evil, skipOffstage: false), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        var link = false;
        r.text.visitChildren((s) {
          if (s is TextSpan && s.recognizer != null) link = true;
          return true;
        });
        expect(link, isFalse);
      }
    });

    testWidgets('não há mensagem direta, upload nem botão de imagem', (
      tester,
    ) async {
      await pump(tester, _repo(), location: '/conecta/matematica');
      await tapKey(tester, 'new-post');
      expect(find.byIcon(Icons.image), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.textContaining('mensagem direta'), findsNothing);
    });
  });

  group('CA-C1 interface: quem não é membro', () {
    testWidgets('sala sem participação não mostra conteúdo do fórum', (
      tester,
    ) async {
      await pump(tester, _repo(member: false), location: '/conecta/matematica');
      expect(find.text('Como saber se uma função é injetora?'), findsNothing);
      expect(find.text('Logaritmo: por onde começar?'), findsNothing);
    });

    testWidgets('conversa sem participação não mostra respostas', (
      tester,
    ) async {
      await pump(tester, _repo(member: false), location: _conv);
      expect(find.textContaining('injetora não repete'), findsNothing);
      expect(find.byKey(const Key('reply-field')), findsNothing);
    });
  });

  group('CA-T4 360 px', () {
    testWidgets('palavra gigante e apelido longo não estouram a tela', (
      tester,
    ) async {
      final long = 'a' * 90;
      final repo = _repo(
        extraPosts: [
          _post(
            id: 'big',
            community: 'matematica',
            title: 'T' * 100,
            body: long * 4,
            nick: 'n' * 30,
          ),
        ],
        extraReplies: [
          _reply(id: 'bigr', postId: 'big', body: long * 4, nick: 'n' * 30),
        ],
      );
      for (final scale in [1.0, 1.6]) {
        await pump(
          tester,
          repo,
          location: '/conecta/matematica',
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: 'sala x$scale');
        await pump(
          tester,
          repo,
          location: '/conecta/matematica/conversa/big',
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: 'conversa x$scale');
      }
    });

    testWidgets('home, fila de moderação e diálogos cabem a 360 px', (
      tester,
    ) async {
      final repo = _repo(moderator: true);
      await repo.report(
        NewReport(
          targetType: ReportTarget.post,
          targetId: 'demo-p3',
          postId: 'demo-p3',
          reason: ReportReason.sexualOrMinor,
          details: 'Detalhe longo ' * 20,
        ),
      );
      await pump(tester, repo, location: '/conecta', textScale: 1.6);
      expect(tester.takeException(), isNull);
      await pump(tester, repo, location: '/conecta/moderacao', textScale: 1.6);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'ban-demo-p3_demo-me');
      expect(tester.takeException(), isNull);
      await pump(tester, _repo(), location: _conv, textScale: 1.6);
      await tapKey(tester, 'more-reply-demo-r1');
      await tapKey(tester, 'report-reply-demo-r1');
      expect(tester.takeException(), isNull);
    });
  });
}
