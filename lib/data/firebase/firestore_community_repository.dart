import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/clock.dart';
import '../../domain/community_models.dart';
import '../../domain/community_validation.dart';
import '../community_repository.dart';
import 'community_write_plans.dart';
import 'firestore_mapping.dart';

typedef _Query = Query<Map<String, dynamic>>;

/// Conecta no Firestore (coleções públicas, regras em `firestore.rules`).
///
/// - Leitura de posts e respostas sempre com `status == 'visible'`; o que é do
///   próprio autor (em análise ou oculto) vem de uma consulta à parte, por
///   `authorUid`, sem `orderBy` (não exige índice composto novo).
/// - Escritas em lote, pelos planos de `community_write_plans.dart`, com
///   `commitOrQueue` (no máximo 4 s de espera).
/// - Erros do SDK viram [CommunityFailure]; nada de stack trace na tela.
class FirestoreCommunityRepository implements CommunityRepository {
  FirestoreCommunityRepository({
    required this._db,
    required this._uid,
    required this._clock,
  });

  final FirebaseFirestore _db;
  final String _uid;
  final Clock _clock;

  /// Apelido em cache (o autor falso é barrado nas regras, o apelido também).
  String? _nickname;

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection(name);

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CommunityFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw switch (e.code) {
        'permission-denied' => const CommunityFailure(
          CommunityFailureKind.denied,
          'Sem permissão para esta ação.',
        ),
        'not-found' => const CommunityFailure(CommunityFailureKind.notFound),
        _ => const CommunityFailure(
          CommunityFailureKind.unavailable,
          'Sem conexão com o servidor. Tente de novo.',
        ),
      };
    }
  }

  Future<void> _commit(List<PlannedWrite> plan) {
    final batch = _db.batch();
    for (final w in plan) {
      final ref = _db.doc(w.path);
      switch (w.kind) {
        case WriteKind.set:
          batch.set(ref, w.data!);
        case WriteKind.update:
          batch.update(ref, w.data!);
        case WriteKind.delete:
          batch.delete(ref);
      }
    }
    return commitOrQueue(batch.commit());
  }

  Future<String> _myNickname() async {
    final cached = _nickname;
    if (cached != null) return cached;
    final m = await myMembership();
    if (m == null) throw const CommunityFailure(CommunityFailureKind.notMember);
    return _nickname = m.nickname;
  }

  /// Confere o intervalo de 30 s pelo `conectaLimits` (as regras também
  /// conferem; aqui é para dar a mensagem certa). Se não der para ler, segue.
  Future<void> _checkCooldown() async {
    try {
      final doc = await _col('conectaLimits').doc(_uid).get();
      final last = doc.data()?['lastWriteAt'];
      final wait = cooldownRemainingSeconds(
        last is Timestamp ? last.toDate() : null,
        _clock(),
      );
      if (wait > 0) {
        throw CommunityFailure(
          CommunityFailureKind.tooSoon,
          'Espere $wait s para escrever de novo.',
          wait,
        );
      }
    } on FirebaseException {
      // Sem leitura: as regras decidem.
    }
  }

  @override
  Future<Membership?> myMembership() => _guard(() async {
    final doc = await _col('memberships').doc(_uid).get();
    final data = doc.data();
    if (data == null) return null;
    final m = membershipFromMap(fromFirestore(data), _clock());
    _nickname = m?.nickname;
    return m;
  });

  @override
  Future<void> join({
    required String nickname,
    String? inviteCode,
    required int declaredMinAge,
    required String rulesVersion,
  }) => _guard(() async {
    final nick = validateNickname(nickname);
    await _commit(
      joinPlan(
        uid: _uid,
        nickname: nick,
        inviteCode: inviteCode?.trim().isEmpty ?? true
            ? null
            : inviteCode!.trim(),
        declaredMinAge: declaredMinAge,
        rulesVersion: rulesVersion,
      ),
    );
    _nickname = nick;
  });

  @override
  Future<void> rename(String nickname) => _guard(() async {
    final nick = validateNickname(nickname);
    await _commit(renamePlan(uid: _uid, nickname: nick));
    _nickname = nick;
  });

  @override
  Future<void> leave() => _guard(() async {
    await _commit(leavePlan(_uid));
    _nickname = null;
  });

  List<Post> _posts(QuerySnapshot<Map<String, dynamic>> snap) {
    final now = _clock();
    return [
      for (final d in snap.docs)
        ?postFromMap(d.id, fromFirestore(d.data()), now),
    ];
  }

  @override
  Future<PostPage> posts(
    String communityId, {
    Object? cursor,
    int limit = 20,
  }) => _guard(() async {
    _Query q = _col('posts')
        .where('communityId', isEqualTo: communityId)
        .where('status', isEqualTo: 'visible')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      q = q.startAfterDocument(cursor);
    }
    final snap = await q.get();
    final items = _posts(snap);
    if (cursor == null) {
      // Os meus que não estão visíveis (em análise ou ocultos).
      final mine = await _col('posts')
          .where('authorUid', isEqualTo: _uid)
          .where('communityId', isEqualTo: communityId)
          .limit(50)
          .get();
      final ids = {for (final p in items) p.id};
      items.addAll(
        _posts(mine).where(
          (p) => p.status != ContentStatus.visible && !ids.contains(p.id),
        ),
      );
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return PostPage(
      items: items,
      nextCursor: snap.docs.length >= limit ? snap.docs.last : null,
    );
  });

  @override
  Future<Post> createPost(NewPost input) => _guard(() async {
    final data = validateNewPost(input);
    final nick = await _myNickname();
    await _checkCooldown();
    final ref = _col('posts').doc();
    await _commit(
      postPlan(uid: _uid, nickname: nick, postId: ref.id, post: data),
    );
    return Post(
      id: ref.id,
      communityId: data.communityId,
      authorUid: _uid,
      authorNickname: nick,
      title: data.title,
      body: data.body,
      bankId: data.bankId,
      status: ContentStatus.visible,
      createdAt: _clock(),
    );
  });

  @override
  Future<List<Reply>> replies(String postId) => _guard(() async {
    final now = _clock();
    List<Reply> parse(QuerySnapshot<Map<String, dynamic>> s) => [
      for (final d in s.docs) ?replyFromMap(d.id, fromFirestore(d.data()), now),
    ];
    final visible = await _col('replies')
        .where('postId', isEqualTo: postId)
        .where('status', isEqualTo: 'visible')
        .orderBy('createdAt')
        .get();
    final items = parse(visible);
    final mine = await _col('replies')
        .where('postId', isEqualTo: postId)
        .where('authorUid', isEqualTo: _uid)
        .get();
    final ids = {for (final r in items) r.id};
    items.addAll(
      parse(
        mine,
      ).where((r) => r.status != ContentStatus.visible && !ids.contains(r.id)),
    );
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  });

  @override
  Future<Reply> reply(String postId, String body) => _guard(() async {
    final text = validateBody(body);
    final nick = await _myNickname();
    await _checkCooldown();
    final ref = _col('replies').doc();
    await _commit(
      replyPlan(
        uid: _uid,
        nickname: nick,
        replyId: ref.id,
        postId: postId,
        body: text,
      ),
    );
    return Reply(
      id: ref.id,
      postId: postId,
      authorUid: _uid,
      authorNickname: nick,
      body: text,
      status: ContentStatus.visible,
      createdAt: _clock(),
    );
  });

  @override
  Future<Set<String>> myHelpfulVotes(String postId) => _guard(() async {
    final snap = await _col('helpfulVotes')
        .where('voterUid', isEqualTo: _uid)
        .where('postId', isEqualTo: postId)
        .get();
    return {
      for (final d in snap.docs)
        if (d.data()['replyId'] case final String id) id,
    };
  });

  @override
  Future<int> helpfulCount(String replyId) => _guard(() async {
    final agg = await _col('helpfulVotes')
        .where('replyId', isEqualTo: replyId)
        .count()
        .get();
    return agg.count ?? 0;
  });

  @override
  Future<Map<String, int>> helpfulCounts(String postId) => _guard(() async {
    final snap = await _col('helpfulVotes')
        .where('postId', isEqualTo: postId)
        .get();
    final counts = <String, int>{};
    for (final d in snap.docs) {
      if (d.data()['replyId'] case final String id) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  });

  @override
  Future<void> setHelpful(Reply reply, {required bool helpful}) =>
      _guard(() async {
        if (reply.authorUid == _uid) {
          throw const CommunityFailure(
            CommunityFailureKind.ownReply,
            'Não dá para marcar a própria resposta.',
          );
        }
        await _commit(
          helpfulPlan(voterUid: _uid, reply: reply, helpful: helpful),
        );
      });

  /// Ajudas recebidas e média do grupo (ajudas totais por membro). Três
  /// agregações de contagem; se alguma falhar (offline), a tela mostra o
  /// que tiver.
  @override
  Future<Reputation> reputation(String uid) => _guard(() async {
    final mine = await _col('helpfulVotes')
        .where('authorUid', isEqualTo: uid)
        .count()
        .get();
    final total = await _col('helpfulVotes').count().get();
    final members = await _col('profiles').count().get();
    final n = members.count ?? 0;
    return Reputation(
      helpful: mine.count ?? 0,
      groupAverage: n == 0 ? 0 : (total.count ?? 0) / n,
    );
  });

  @override
  Future<void> report(NewReport input) => _guard(() async {
    final data = validateNewReport(input);
    // Uma denúncia por pessoa e alvo (a regra também barra o 2º `create`
    // como "denúncia nova"; aqui damos a mensagem certa).
    try {
      final prior = await _col('reports')
          .where('reporterUid', isEqualTo: _uid)
          .where('targetId', isEqualTo: data.targetId)
          .limit(1)
          .get();
      if (prior.docs.isNotEmpty) {
        throw const CommunityFailure(CommunityFailureKind.alreadyReported);
      }
    } on FirebaseException {
      // Sem leitura: as regras decidem.
    }
    var hide = true;
    try {
      final target = await _col(
        data.targetType == ReportTarget.post ? 'posts' : 'replies',
      ).doc(data.targetId).get();
      if (!target.exists) {
        throw const CommunityFailure(CommunityFailureKind.notFound);
      }
      hide = target.data()?['status'] == 'visible';
    } on FirebaseException catch (e) {
      // Sem permissão de leitura = o alvo não está visível (já em análise ou
      // oculto): só grava a denúncia. Outro erro: tenta esconder.
      hide = e.code != 'permission-denied';
    }
    await _commit(reportPlan(uid: _uid, report: data, hideTarget: hide));
  });

  @override
  Future<void> deletePost(String id) =>
      _guard(() => commitOrQueue(_col('posts').doc(id).delete()));

  @override
  Future<void> deleteReply(String id) =>
      _guard(() => commitOrQueue(_col('replies').doc(id).delete()));

  @override
  Future<bool> isModerator() => _guard(() async {
    final doc = await _col('moderators').doc(_uid).get();
    return doc.exists;
  });

  @override
  Future<bool> isBanned() => _guard(() async {
    final doc = await _col('bans').doc(_uid).get();
    return doc.exists;
  });

  @override
  Future<List<ModerationItem>> openReports() => _guard(() async {
    final now = _clock();
    final snap = await _col('reports')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt')
        .limit(50)
        .get();
    final items = <ModerationItem>[];
    for (final d in snap.docs) {
      final report = reportFromMap(d.id, fromFirestore(d.data()), now);
      if (report == null) continue;
      final isPost = report.targetType == ReportTarget.post;
      final target = await _col(isPost ? 'posts' : 'replies')
          .doc(report.targetId)
          .get();
      final data = target.data();
      if (data == null) {
        items.add(ModerationItem.deleted(report)); // conteúdo já apagado
        continue;
      }
      final map = fromFirestore(data);
      final status = ContentStatus.tryParse(map['status']);
      final author = map['authorUid'];
      final nick = map['authorNickname'];
      final body = map['body'];
      if (status == null || author is! String || body is! String) continue;
      items.add(
        ModerationItem(
          report: report,
          authorUid: author,
          authorNickname: nick is String ? nick : '',
          title: isPost && map['title'] is String
              ? map['title'] as String
              : null,
          body: body,
          status: status,
        ),
      );
    }
    return items;
  });

  @override
  Future<void> resolve(String reportId, ModerationDecision decision) =>
      _guard(() async {
        final doc = await _col('reports').doc(reportId).get();
        final data = doc.data();
        if (data == null) {
          throw const CommunityFailure(CommunityFailureKind.notFound);
        }
        final report = reportFromMap(reportId, fromFirestore(data), _clock());
        if (report == null) {
          throw const CommunityFailure(CommunityFailureKind.notFound);
        }
        final target = await _col(
          report.targetType == ReportTarget.post ? 'posts' : 'replies',
        ).doc(report.targetId).get();
        if (!target.exists) {
          await _commit(
            resolveDeletedTargetPlan(moderatorUid: _uid, reportId: reportId),
          );
          return;
        }
        final author = target.data()?['authorUid'];
        if (author is! String) {
          throw const CommunityFailure(CommunityFailureKind.notFound);
        }
        await _commit(
          resolvePlan(
            moderatorUid: _uid,
            reportId: reportId,
            targetType: report.targetType,
            targetId: report.targetId,
            authorUid: author,
            decision: decision,
          ),
        );
      });

  @override
  Future<CommunityFootprint> myFootprint({
    bool fromServer = false,
  }) => _guard(() async {
    // Na exclusão de conta (C5) o inventário não pode vir do cache: sem rede,
    // a leitura falha e nada é apagado.
    final opts = fromServer ? const GetOptions(source: Source.server) : null;
    Future<List<String>> ids(_Query q) async => [
      for (final d in (await q.get(opts)).docs) d.id,
    ];
    final reports = await _col('reports')
        .where('reporterUid', isEqualTo: _uid)
        .get(opts);
    return CommunityFootprint(
      postIds: await ids(_col('posts').where('authorUid', isEqualTo: _uid)),
      replyIds: await ids(_col('replies').where('authorUid', isEqualTo: _uid)),
      votesGiven: await ids(
        _col('helpfulVotes').where('voterUid', isEqualTo: _uid),
      ),
      votesReceived: await ids(
        _col('helpfulVotes').where('authorUid', isEqualTo: _uid),
      ),
      openReportIds: [
        for (final d in reports.docs)
          if (d.data()['status'] == 'open') d.id,
      ],
      resolvedReportIds: [
        for (final d in reports.docs)
          if (d.data()['status'] != 'open') d.id,
      ],
    );
  });
}
