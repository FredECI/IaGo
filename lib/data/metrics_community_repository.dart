import '../domain/community_models.dart';
import '../domain/metric_event.dart';
import 'community_repository.dart';

/// Registra eventos de métrica (H6) em volta de outro [CommunityRepository].
/// Só ids e a comunidade: nunca título, texto nem apelido. Registra depois do
/// sucesso; falhas seguem para a tela como antes.
class MetricsCommunityRepository implements CommunityRepository {
  MetricsCommunityRepository(this._inner, this._log);

  final CommunityRepository _inner;
  final void Function(MetricEventType type, Map<String, Object?> data) _log;

  @override
  Future<Post> createPost(NewPost post) async {
    final created = await _inner.createPost(post);
    _log(MetricEventType.communityPost, {
      'communityId': created.communityId,
      'postId': created.id,
    });
    return created;
  }

  @override
  Future<Reply> reply(String postId, String body) async {
    final created = await _inner.reply(postId, body);
    _log(MetricEventType.communityReply, {
      'postId': postId,
      'replyId': created.id,
    });
    return created;
  }

  @override
  Future<void> setHelpful(Reply reply, {required bool helpful}) async {
    await _inner.setHelpful(reply, helpful: helpful);
    if (helpful) {
      _log(MetricEventType.helpfulGiven, {
        'postId': reply.postId,
        'replyId': reply.id,
      });
    }
  }

  @override
  Future<void> report(NewReport report) async {
    await _inner.report(report);
    _log(MetricEventType.reportFiled, {'reason': report.reason.wireName});
  }

  @override
  Future<Membership?> myMembership() => _inner.myMembership();

  @override
  Future<void> join({
    required String nickname,
    String? inviteCode,
    required int declaredMinAge,
    required String rulesVersion,
  }) => _inner.join(
    nickname: nickname,
    inviteCode: inviteCode,
    declaredMinAge: declaredMinAge,
    rulesVersion: rulesVersion,
  );

  @override
  Future<void> rename(String nickname) => _inner.rename(nickname);

  @override
  Future<void> leave() => _inner.leave();

  @override
  Future<PostPage> posts(
    String communityId, {
    Object? cursor,
    int limit = 20,
  }) => _inner.posts(communityId, cursor: cursor, limit: limit);

  @override
  Future<List<Reply>> replies(String postId) => _inner.replies(postId);

  @override
  Future<Set<String>> myHelpfulVotes(String postId) =>
      _inner.myHelpfulVotes(postId);

  @override
  Future<int> helpfulCount(String replyId) => _inner.helpfulCount(replyId);

  @override
  Future<Map<String, int>> helpfulCounts(String postId) =>
      _inner.helpfulCounts(postId);

  @override
  Future<Reputation> reputation(String uid) => _inner.reputation(uid);

  @override
  Future<void> deletePost(String id) => _inner.deletePost(id);

  @override
  Future<void> deleteReply(String id) => _inner.deleteReply(id);

  @override
  Future<bool> isModerator() => _inner.isModerator();

  @override
  Future<bool> isBanned() => _inner.isBanned();

  @override
  Future<List<ModerationItem>> openReports() => _inner.openReports();

  @override
  Future<void> resolve(String reportId, ModerationDecision decision) =>
      _inner.resolve(reportId, decision);

  @override
  Future<CommunityFootprint> myFootprint() => _inner.myFootprint();
}
