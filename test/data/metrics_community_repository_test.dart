import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/metrics_community_repository.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/domain/metric_event.dart';

void main() {
  test('registra post, resposta só com ids (sem texto)', () async {
    var now = DateTime(2026, 11, 20, 10);
    final logged = <(MetricEventType, Map<String, Object?>)>[];
    final repo = MetricsCommunityRepository(
      MemoryCommunityRepository(
        clock: () => now,
        membership: Membership(
          nickname: 'pedro',
          declaredMinAge: 18,
          rulesVersion: 'x',
          joinedAt: DateTime(2026, 11, 1),
        ),
      ),
      (type, data) => logged.add((type, data)),
    );

    final post = await repo.createPost(
      const NewPost(
        communityId: 'matematica',
        title: 'Título secreto',
        body: 'Texto secreto',
      ),
    );
    now = now.add(const Duration(minutes: 1));
    final reply = await repo.reply(post.id, 'Resposta secreta');

    expect(logged.map((e) => e.$1), [
      MetricEventType.communityPost,
      MetricEventType.communityReply,
    ]);
    expect(logged[0].$2, {'communityId': 'matematica', 'postId': post.id});
    expect(logged[1].$2, {'postId': post.id, 'replyId': reply.id});
    expect(logged.toString(), isNot(contains('secret')));
  });
}
