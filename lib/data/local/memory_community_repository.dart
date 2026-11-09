import '../../core/clock.dart';
import '../../domain/community_models.dart';
import '../../domain/community_validation.dart';
import '../community_repository.dart';

class _StoredReport {
  _StoredReport(this.record, this.authorUid);

  ReportRecord record;
  final String authorUid;
}

/// Conecta em memória (demo e testes). Estado novo a cada instância, sem
/// rede. Imita as regras do Firestore: intervalo de 30 s, "Ajudou" uma vez
/// por pessoa e nunca na própria resposta, denúncia que esconde o conteúdo
/// dos outros e uma denúncia por pessoa e alvo.
class MemoryCommunityRepository implements CommunityRepository {
  MemoryCommunityRepository({
    required this._clock,
    this.uid = demoUid,
    this._membership,
    List<Post> posts = const [],
    List<Reply> replies = const [],
    Map<String, int> votes = const {},
    this._moderator = false,
  }) : _posts = [...posts],
       _replies = [...replies],
       _otherVotes = {...votes};

  /// Uid do usuário da demo.
  static const String demoUid = 'demo-me';

  final Clock _clock;
  final String uid;
  Membership? _membership;
  final bool _moderator;
  final List<Post> _posts;
  final List<Reply> _replies;

  /// Ajudas de membros fictícios, por resposta.
  final Map<String, int> _otherVotes;

  /// Minhas ajudas: `replyId`.
  final Set<String> _myVotes = {};
  final Map<String, _StoredReport> _reports = {};
  final Set<String> _banned = {};
  DateTime? _lastWriteAt;
  int _seq = 0;

  String _newId(String prefix) => '$prefix${++_seq}';

  Membership _requireMember() {
    final m = _membership;
    if (m == null || _banned.contains(uid)) {
      throw const CommunityFailure(CommunityFailureKind.notMember);
    }
    return m;
  }

  void _checkCooldown() {
    final wait = cooldownRemainingSeconds(_lastWriteAt, _clock());
    if (wait > 0) {
      throw CommunityFailure(
        CommunityFailureKind.tooSoon,
        'Espere $wait s para escrever de novo.',
        wait,
      );
    }
  }

  @override
  Future<Membership?> myMembership() async => _membership;

  @override
  Future<void> join({
    required String nickname,
    String? inviteCode,
    required int declaredMinAge,
    required String rulesVersion,
  }) async {
    final nick = validateNickname(nickname);
    _membership = Membership(
      nickname: nick,
      inviteCode: inviteCode,
      declaredMinAge: declaredMinAge,
      rulesVersion: rulesVersion,
      joinedAt: _clock(),
    );
  }

  @override
  Future<void> rename(String nickname) async {
    final m = _requireMember();
    _membership = Membership(
      nickname: validateNickname(nickname),
      inviteCode: m.inviteCode,
      declaredMinAge: m.declaredMinAge,
      rulesVersion: m.rulesVersion,
      joinedAt: m.joinedAt,
    );
  }

  @override
  Future<void> leave() async => _membership = null;

  bool _seen(ContentStatus status, String authorUid) =>
      status == ContentStatus.visible || authorUid == uid || _moderator;

  @override
  Future<PostPage> posts(
    String communityId, {
    Object? cursor,
    int limit = 20,
  }) async {
    _requireMember();
    final all =
        _posts
            .where(
              (p) =>
                  p.communityId == communityId && _seen(p.status, p.authorUid),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = cursor is int ? cursor : 0;
    final end = (start + limit).clamp(0, all.length);
    return PostPage(
      items: all.sublist(start.clamp(0, all.length), end),
      nextCursor: end < all.length ? end : null,
    );
  }

  @override
  Future<Post> createPost(NewPost input) async {
    final m = _requireMember();
    final data = validateNewPost(input);
    _checkCooldown();
    final now = _clock();
    final post = Post(
      id: _newId('p'),
      communityId: data.communityId,
      authorUid: uid,
      authorNickname: m.nickname,
      title: data.title,
      body: data.body,
      bankId: data.bankId,
      status: ContentStatus.visible,
      createdAt: now,
    );
    _posts.add(post);
    _lastWriteAt = now;
    return post;
  }

  @override
  Future<List<Reply>> replies(String postId) async {
    _requireMember();
    return _replies
        .where((r) => r.postId == postId && _seen(r.status, r.authorUid))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<Reply> reply(String postId, String body) async {
    final m = _requireMember();
    final text = validateBody(body);
    final post = _posts.where((p) => p.id == postId).firstOrNull;
    if (post == null || post.status != ContentStatus.visible) {
      throw const CommunityFailure(CommunityFailureKind.notFound);
    }
    _checkCooldown();
    final now = _clock();
    final reply = Reply(
      id: _newId('r'),
      postId: postId,
      authorUid: uid,
      authorNickname: m.nickname,
      body: text,
      status: ContentStatus.visible,
      createdAt: now,
    );
    _replies.add(reply);
    _lastWriteAt = now;
    return reply;
  }

  @override
  Future<Set<String>> myHelpfulVotes(String postId) async {
    _requireMember();
    final ids = {
      for (final r in _replies)
        if (r.postId == postId) r.id,
    };
    return _myVotes.intersection(ids);
  }

  int _count(String replyId) =>
      (_otherVotes[replyId] ?? 0) + (_myVotes.contains(replyId) ? 1 : 0);

  @override
  Future<int> helpfulCount(String replyId) async {
    _requireMember();
    return _count(replyId);
  }

  @override
  Future<Map<String, int>> helpfulCounts(String postId) async {
    _requireMember();
    return {
      for (final r in _replies)
        if (r.postId == postId) r.id: _count(r.id),
    };
  }

  @override
  Future<void> setHelpful(Reply reply, {required bool helpful}) async {
    _requireMember();
    if (reply.authorUid == uid) {
      throw const CommunityFailure(
        CommunityFailureKind.ownReply,
        'Não dá para marcar a própria resposta.',
      );
    }
    if (helpful) {
      _myVotes.add(reply.id);
    } else {
      _myVotes.remove(reply.id);
    }
  }

  @override
  Future<Reputation> reputation(String uid) async {
    _requireMember();
    var mine = 0;
    var total = 0;
    final members = <String>{};
    for (final r in _replies) {
      final n = _count(r.id);
      total += n;
      members.add(r.authorUid);
      if (r.authorUid == uid) mine += n;
    }
    for (final p in _posts) {
      members.add(p.authorUid);
    }
    if (_membership != null) members.add(this.uid);
    return Reputation(
      helpful: mine,
      groupAverage: members.isEmpty ? 0 : total / members.length,
    );
  }

  @override
  Future<void> report(NewReport input) async {
    _requireMember();
    final data = validateNewReport(input);
    final key = '${data.targetId}_$uid';
    if (_reports.containsKey(key)) {
      throw const CommunityFailure(CommunityFailureKind.alreadyReported);
    }
    final String authorUid;
    if (data.targetType == ReportTarget.post) {
      final i = _posts.indexWhere((p) => p.id == data.targetId);
      if (i < 0) throw const CommunityFailure(CommunityFailureKind.notFound);
      authorUid = _posts[i].authorUid;
      if (_posts[i].status == ContentStatus.visible) {
        _posts[i] = _posts[i].copyWith(status: ContentStatus.pending);
      }
    } else {
      final i = _replies.indexWhere((r) => r.id == data.targetId);
      if (i < 0) throw const CommunityFailure(CommunityFailureKind.notFound);
      authorUid = _replies[i].authorUid;
      if (_replies[i].status == ContentStatus.visible) {
        _replies[i] = _replies[i].copyWith(status: ContentStatus.pending);
      }
    }
    _reports[key] = _StoredReport(
      ReportRecord(
        id: key,
        targetType: data.targetType,
        targetId: data.targetId,
        postId: data.postId,
        reason: data.reason,
        details: data.details,
        reporterUid: uid,
        open: true,
        createdAt: _clock(),
      ),
      authorUid,
    );
  }

  @override
  Future<void> deletePost(String id) async {
    _requireMember();
    final i = _posts.indexWhere((p) => p.id == id);
    if (i < 0) return;
    if (_posts[i].authorUid != uid && !_moderator) {
      throw const CommunityFailure(CommunityFailureKind.denied);
    }
    _posts.removeAt(i);
    _replies.removeWhere((r) => r.postId == id);
  }

  @override
  Future<void> deleteReply(String id) async {
    _requireMember();
    final i = _replies.indexWhere((r) => r.id == id);
    if (i < 0) return;
    if (_replies[i].authorUid != uid && !_moderator) {
      throw const CommunityFailure(CommunityFailureKind.denied);
    }
    _replies.removeAt(i);
    _myVotes.remove(id);
  }

  @override
  Future<bool> isModerator() async => _moderator;

  @override
  Future<bool> isBanned() async => _banned.contains(uid);

  @override
  Future<List<ModerationItem>> openReports() async {
    if (!_moderator) {
      throw const CommunityFailure(CommunityFailureKind.denied);
    }
    final items = <ModerationItem>[];
    final open = _reports.values.where((r) => r.record.open).toList()
      ..sort((a, b) => a.record.createdAt.compareTo(b.record.createdAt));
    for (final stored in open) {
      final rec = stored.record;
      if (rec.targetType == ReportTarget.post) {
        final p = _posts.where((p) => p.id == rec.targetId).firstOrNull;
        if (p == null) {
          items.add(ModerationItem.deleted(rec));
          continue;
        }
        items.add(
          ModerationItem(
            report: rec,
            authorUid: p.authorUid,
            authorNickname: p.authorNickname,
            title: p.title,
            body: p.body,
            status: p.status,
          ),
        );
      } else {
        final r = _replies.where((r) => r.id == rec.targetId).firstOrNull;
        if (r == null) {
          items.add(ModerationItem.deleted(rec));
          continue;
        }
        items.add(
          ModerationItem(
            report: rec,
            authorUid: r.authorUid,
            authorNickname: r.authorNickname,
            body: r.body,
            status: r.status,
          ),
        );
      }
    }
    return items;
  }

  @override
  Future<void> resolve(String reportId, ModerationDecision decision) async {
    if (!_moderator) {
      throw const CommunityFailure(CommunityFailureKind.denied);
    }
    final stored = _reports[reportId];
    if (stored == null) {
      throw const CommunityFailure(CommunityFailureKind.notFound);
    }
    final restore = decision.kind == ModerationKind.restore;
    final exists = stored.record.targetType == ReportTarget.post
        ? _posts.any((p) => p.id == stored.record.targetId)
        : _replies.any((r) => r.id == stored.record.targetId);
    if (!exists) {
      _closeReport(stored);
      return;
    }
    final status = restore ? ContentStatus.visible : ContentStatus.hidden;
    final reason = restore ? null : decision.reason;
    final rec = stored.record;
    if (rec.targetType == ReportTarget.post) {
      final i = _posts.indexWhere((p) => p.id == rec.targetId);
      if (i >= 0) {
        _posts[i] = _posts[i].copyWith(
          status: status,
          moderationReason: reason,
        );
      }
    } else {
      final i = _replies.indexWhere((r) => r.id == rec.targetId);
      if (i >= 0) {
        _replies[i] = _replies[i].copyWith(
          status: status,
          moderationReason: reason,
        );
      }
    }
    if (decision.kind == ModerationKind.hideAndBan) {
      _banned.add(stored.authorUid);
    }
    _closeReport(stored);
  }

  void _closeReport(_StoredReport stored) {
    final rec = stored.record;
    stored.record = ReportRecord(
      id: rec.id,
      targetType: rec.targetType,
      targetId: rec.targetId,
      postId: rec.postId,
      reason: rec.reason,
      details: rec.details,
      reporterUid: rec.reporterUid,
      open: false,
      createdAt: rec.createdAt,
    );
  }

  @override
  Future<CommunityFootprint> myFootprint() async => CommunityFootprint(
    postIds: [
      for (final p in _posts)
        if (p.authorUid == uid) p.id,
    ],
    replyIds: [
      for (final r in _replies)
        if (r.authorUid == uid) r.id,
    ],
    votesGiven: [for (final id in _myVotes) '${id}_$uid'],
    votesReceived: [
      for (final r in _replies)
        if (r.authorUid == uid)
          for (var i = 0; i < (_otherVotes[r.id] ?? 0); i++) '${r.id}_other$i',
    ],
    openReportIds: [
      for (final r in _reports.values)
        if (r.record.reporterUid == uid && r.record.open) r.record.id,
    ],
    resolvedReportIds: [
      for (final r in _reports.values)
        if (r.record.reporterUid == uid && !r.record.open) r.record.id,
    ],
  );
}
