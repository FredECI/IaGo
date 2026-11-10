import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/community_demo_data.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/metrics_community_repository.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/domain/metric_event.dart';

/// CA-I14: os eventos do Conecta levam só ids e motivo, e só depois do sucesso.
void main() {
  final now = DateTime(2026, 11, 20, 10);
  late List<(MetricEventType, Map<String, Object?>)> logged;
  late MetricsCommunityRepository repo;
  late CommunityDemoData seed;

  setUp(() {
    logged = [];
    seed = CommunityDemoData.build(now);
    repo = MetricsCommunityRepository(
      MemoryCommunityRepository(
        clock: () => now,
        membership: Membership(
          nickname: 'pedro',
          declaredMinAge: 18,
          rulesVersion: 'x',
          joinedAt: DateTime(2026, 11, 1),
        ),
        posts: seed.posts,
        replies: seed.replies,
        votes: seed.votes,
      ),
      (type, data) => logged.add((type, data)),
    );
  });

  test('denúncia grava só o motivo (sem detalhes nem texto)', () async {
    final post = seed.posts.firstWhere((p) => p.authorUid != 'demo-me');
    await repo.report(
      NewReport(
        targetType: ReportTarget.post,
        targetId: post.id,
        postId: post.id,
        reason: ReportReason.spam,
        details: 'DETALHE-SECRETO',
      ),
    );
    expect(logged, hasLength(1));
    expect(logged.single.$1, MetricEventType.reportFiled);
    expect(logged.single.$2, {'reason': 'spam'});
  });

  test('denúncia repetida (falha) não registra evento', () async {
    final post = seed.posts.firstWhere((p) => p.authorUid != 'demo-me');
    final report = NewReport(
      targetType: ReportTarget.post,
      targetId: post.id,
      postId: post.id,
      reason: ReportReason.spam,
    );
    await repo.report(report);
    await expectLater(repo.report(report), throwsA(isA<CommunityFailure>()));
    expect(logged, hasLength(1));
  });

  test('resposta em post inexistente falha sem registrar', () async {
    await expectLater(
      repo.reply('nao-existe', 'texto-secreto'),
      throwsA(isA<CommunityFailure>()),
    );
    expect(logged, isEmpty);
  });

  test('"Ajudou": marcar registra ids; desmarcar não registra', () async {
    final reply = seed.replies.firstWhere((r) => r.authorUid != 'demo-me');
    await repo.setHelpful(reply, helpful: true);
    await repo.setHelpful(reply, helpful: false);
    expect(logged, hasLength(1));
    expect(logged.single.$1, MetricEventType.helpfulGiven);
    expect(logged.single.$2, {'postId': reply.postId, 'replyId': reply.id});
  });
}
