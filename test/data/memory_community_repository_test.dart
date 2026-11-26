import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/community_demo_data.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/domain/community_models.dart';

void main() {
  var now = DateTime(2026, 11, 20, 10);
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 11, 20, 10));

  Membership member(String nick) => Membership(
    nickname: nick,
    declaredMinAge: 18,
    rulesVersion: '1',
    joinedAt: now,
  );

  /// Dois usuários sobre o mesmo conteúdo: cada um com a sua instância, o
  /// que simula "o que os outros veem".
  MemoryCommunityRepository demo({
    String uid = MemoryCommunityRepository.demoUid,
    bool moderator = false,
    bool joined = true,
  }) {
    final seed = CommunityDemoData.build(now);
    return MemoryCommunityRepository(
      clock: clock,
      uid: uid,
      membership: joined ? member('pedro_estuda') : null,
      posts: seed.posts,
      replies: seed.replies,
      votes: seed.votes,
      moderator: moderator,
    );
  }

  const newPost = NewPost(
    communityId: 'matematica',
    title: 'Dúvida sobre funções',
    body: 'Como estudar funções em 3 dias?',
  );

  group('entrar', () {
    test('sem entrar, ler ou escrever dá notMember', () async {
      final repo = demo(joined: false);
      expect(await repo.myMembership(), isNull);
      await expectLater(
        repo.posts('matematica'),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.kind,
            'kind',
            CommunityFailureKind.notMember,
          ),
        ),
      );
      await expectLater(
        repo.createPost(newPost),
        throwsA(isA<CommunityFailure>()),
      );
    });

    test('join valida o apelido e vira membro; rename e leave', () async {
      final repo = demo(joined: false);
      await expectLater(
        repo.join(nickname: 'ab', declaredMinAge: 18, rulesVersion: '1'),
        throwsA(isA<CommunityFailure>()),
      );
      await repo.join(
        nickname: '  lia_estuda ',
        inviteCode: 'ABC',
        declaredMinAge: 18,
        rulesVersion: '1',
      );
      final m = (await repo.myMembership())!;
      expect(m.nickname, 'lia_estuda');
      expect(m.inviteCode, 'ABC');
      await repo.rename('lia_nova');
      expect((await repo.myMembership())!.nickname, 'lia_nova');
      await repo.leave();
      expect(await repo.myMembership(), isNull);
    });
  });

  group('posts e respostas', () {
    test('lista a comunidade, do mais novo ao mais antigo, e pagina', () async {
      final repo = demo();
      final page = await repo.posts('matematica', limit: 1);
      expect(page.items.single.id, 'demo-p1');
      expect(page.nextCursor, isNotNull);
      final next = await repo.posts(
        'matematica',
        cursor: page.nextCursor,
        limit: 1,
      );
      expect(next.items.single.id, 'demo-p2');
      expect(next.nextCursor, isNull);
      expect((await repo.posts('natureza')).items.single.id, 'demo-p3');
    });

    test('postar usa o apelido e valida título e texto', () async {
      final repo = demo();
      final post = await repo.createPost(newPost);
      expect(post.authorNickname, 'pedro_estuda');
      expect(post.status, ContentStatus.visible);
      expect((await repo.posts('matematica')).items.first.id, post.id);
      now = now.add(const Duration(minutes: 1));
      await expectLater(
        repo.createPost(
          const NewPost(communityId: 'matematica', title: 'abc', body: 'x'),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        repo.createPost(
          NewPost(
            communityId: 'matematica',
            title: 'Título válido',
            body: 'a' * 2001,
          ),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        repo.createPost(
          const NewPost(
            communityId: 'outra',
            title: 'Título válido',
            body: 'x',
          ),
        ),
        throwsA(isA<CommunityFailure>()),
      );
    });

    test('responder aparece na conversa em ordem cronológica', () async {
      final repo = demo();
      final reply = await repo.reply('demo-p1', ' Uma dica. ');
      final list = await repo.replies('demo-p1');
      expect(list.last.id, reply.id);
      expect(list.last.body, 'Uma dica.');
      expect(
        list.map((r) => r.createdAt),
        orderedEquals([...list.map((r) => r.createdAt)]..sort()),
      );
      await expectLater(
        repo.reply('nao-existe', 'oi'),
        throwsA(isA<CommunityFailure>()),
      );
    });

    test('texto com HTML fica como texto puro', () async {
      final repo = demo();
      final post = await repo.createPost(
        const NewPost(
          communityId: 'reforco',
          title: 'Título válido',
          body: '<b>oi</b> https://exemplo.com',
        ),
      );
      expect(post.body, '<b>oi</b> https://exemplo.com');
    });
  });

  group('intervalo de 30 s', () {
    test(
      'a segunda escrita antes de 30 s dá tooSoon com o tempo restante',
      () async {
        final repo = demo();
        await repo.createPost(newPost);
        now = now.add(const Duration(seconds: 10));
        await expectLater(
          repo.reply('demo-p1', 'oi'),
          throwsA(
            isA<CommunityFailure>()
                .having((e) => e.kind, 'kind', CommunityFailureKind.tooSoon)
                .having((e) => e.waitSeconds, 'wait', 20),
          ),
        );
        now = now.add(const Duration(seconds: 20));
        await repo.reply('demo-p1', 'oi');
      },
    );

    test('post e resposta dividem o mesmo intervalo', () async {
      final repo = demo();
      await repo.reply('demo-p1', 'oi');
      await expectLater(
        repo.createPost(newPost),
        throwsA(isA<CommunityFailure>()),
      );
    });
  });

  group('"Ajudou"', () {
    test('conta uma vez por pessoa e desmarca', () async {
      final repo = demo();
      final r2 = (await repo.replies('demo-p1'))
          .firstWhere((r) => r.id == 'demo-r2');
      expect(await repo.helpfulCount('demo-r2'), 1);
      await repo.setHelpful(r2, helpful: true);
      await repo.setHelpful(r2, helpful: true);
      expect(await repo.helpfulCount('demo-r2'), 2);
      expect(await repo.myHelpfulVotes('demo-p1'), {'demo-r2'});
      expect((await repo.helpfulCounts('demo-p1'))['demo-r2'], 2);
      await repo.setHelpful(r2, helpful: false);
      expect(await repo.helpfulCount('demo-r2'), 1);
      expect(await repo.myHelpfulVotes('demo-p1'), isEmpty);
    });

    test('nunca na própria resposta', () async {
      final repo = demo();
      final mine = await repo.reply('demo-p1', 'minha resposta');
      await expectLater(
        repo.setHelpful(mine, helpful: true),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.kind,
            'kind',
            CommunityFailureKind.ownReply,
          ),
        ),
      );
      expect(await repo.helpfulCount(mine.id), 0);
    });

    test('reputação traz as ajudas e a média do grupo', () async {
      final repo = demo();
      final rep = await repo.reputation(CommunityDemoData.uidOf('caio_log'));
      expect(rep.helpful, 3);
      expect(rep.groupAverage, greaterThan(0));
    });
  });

  group('denúncia', () {
    test('o conteúdo denunciado de outro autor some da lista', () async {
      final repo = demo();
      await repo.report(
        const NewReport(
          targetType: ReportTarget.post,
          targetId: 'demo-p2',
          postId: 'demo-p2',
          reason: ReportReason.spam,
        ),
      );
      final seen = (await repo.posts('matematica')).items.map((p) => p.id);
      expect(seen, isNot(contains('demo-p2')));
      expect(seen, contains('demo-p1'));
    });

    test('o autor continua vendo o próprio conteúdo denunciado', () async {
      final repo = demo();
      final post = await repo.createPost(newPost);
      await repo.report(
        NewReport(
          targetType: ReportTarget.post,
          targetId: post.id,
          postId: post.id,
          reason: ReportReason.offensive,
          details: ' detalhe ',
        ),
      );
      final mine = (await repo.posts('matematica')).items
          .firstWhere((p) => p.id == post.id);
      expect(mine.status, ContentStatus.pending);
      final footprint = await repo.myFootprint();
      expect(footprint.openReportIds, ['${post.id}_demo-me']);
    });

    test(
      'a mesma pessoa não denuncia duas vezes; resposta também some',
      () async {
        final repo = demo();
        const report = NewReport(
          targetType: ReportTarget.reply,
          targetId: 'demo-r1',
          postId: 'demo-p1',
          reason: ReportReason.harassment,
        );
        await repo.report(report);
        expect(
          (await repo.replies('demo-p1')).map((r) => r.id),
          isNot(contains('demo-r1')),
        );
        await expectLater(
          repo.report(report),
          throwsA(
            isA<CommunityFailure>().having(
              (e) => e.kind,
              'kind',
              CommunityFailureKind.alreadyReported,
            ),
          ),
        );
      },
    );

    test('detalhes acima de 500 caracteres são recusados', () async {
      final repo = demo();
      await expectLater(
        repo.report(
          NewReport(
            targetType: ReportTarget.post,
            targetId: 'demo-p1',
            postId: 'demo-p1',
            reason: ReportReason.other,
            details: 'a' * 501,
          ),
        ),
        throwsA(isA<CommunityFailure>()),
      );
    });
  });

  group('moderação', () {
    test('não moderador não vê a fila nem decide', () async {
      final repo = demo();
      await expectLater(repo.openReports(), throwsA(isA<CommunityFailure>()));
      await expectLater(
        repo.resolve('x', const ModerationDecision(ModerationKind.restore)),
        throwsA(isA<CommunityFailure>()),
      );
    });

    test('restaurar e ocultar com motivo', () async {
      final repo = demo(moderator: true);
      const target = NewReport(
        targetType: ReportTarget.post,
        targetId: 'demo-p2',
        postId: 'demo-p2',
        reason: ReportReason.spam,
      );
      await repo.report(target);
      var queue = await repo.openReports();
      expect(queue.single.report.targetId, 'demo-p2');
      expect(queue.single.title, isNotNull);

      await repo.resolve(
        queue.single.report.id,
        const ModerationDecision(ModerationKind.restore),
      );
      expect(await repo.openReports(), isEmpty);
      var p = (await repo.posts('matematica')).items
          .firstWhere((p) => p.id == 'demo-p2');
      expect(p.status, ContentStatus.visible);

      await repo.report(
        const NewReport(
          targetType: ReportTarget.reply,
          targetId: 'demo-r1',
          postId: 'demo-p1',
          reason: ReportReason.offensive,
        ),
      );
      queue = await repo.openReports();
      await repo.resolve(
        queue.single.report.id,
        const ModerationDecision(ModerationKind.hide, reason: 'Ofensivo'),
      );
      final r1 = (await repo.replies('demo-p1'))
          .firstWhere((r) => r.id == 'demo-r1');
      expect(r1.status, ContentStatus.hidden);
      expect(r1.moderationReason, 'Ofensivo');
      p = (await repo.posts('matematica')).items.first;
      expect(p, isNotNull);
    });
  });

  test('alvo apagado: aparece na fila como apagado e resolve fecha', () async {
    final repo = demo(moderator: true);
    final post = await repo.createPost(newPost);
    await repo.report(
      NewReport(
        targetType: ReportTarget.post,
        targetId: post.id,
        postId: post.id,
        reason: ReportReason.spam,
      ),
    );
    await repo.deletePost(post.id);
    final queue = await repo.openReports();
    expect(queue.single.targetDeleted, isTrue);
    await repo.resolve(
      queue.single.report.id,
      const ModerationDecision(ModerationKind.restore),
    );
    expect(await repo.openReports(), isEmpty);
  });

  test('myFootprint traz as ajudas recebidas', () async {
    final seed = CommunityDemoData.build(now);
    final repo = MemoryCommunityRepository(
      clock: clock,
      uid: CommunityDemoData.uidOf('caio_log'),
      membership: member('caio_log'),
      posts: seed.posts,
      replies: seed.replies,
      votes: seed.votes,
    );
    expect((await repo.myFootprint()).votesReceived, hasLength(3));
  });

  test('excluir só o que é seu; excluir post leva as respostas', () async {
    final repo = demo();
    await expectLater(
      repo.deletePost('demo-p1'),
      throwsA(isA<CommunityFailure>()),
    );
    final post = await repo.createPost(newPost);
    await repo.deletePost(post.id);
    expect(
      (await repo.posts('matematica')).items.map((p) => p.id),
      isNot(contains(post.id)),
    );
  });

  test('conteúdo simulado não tem emoji', () {
    final seed = CommunityDemoData.build(now);
    final emoji = RegExp(
      r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]',
      unicode: true,
    );
    for (final p in seed.posts) {
      expect(emoji.hasMatch('${p.title}${p.body}${p.authorNickname}'), isFalse);
    }
    for (final r in seed.replies) {
      expect(emoji.hasMatch(r.body), isFalse);
    }
  });

  test('cada instância começa limpa (sessão demo nova)', () async {
    final a = demo();
    await a.createPost(newPost);
    final b = demo();
    expect((await b.myFootprint()).postIds, isEmpty);
  });
}
