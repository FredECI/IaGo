import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/community_write_plans.dart';
import 'package:iago/domain/community_models.dart';

/// Os planos de escrita precisam bater com `firestore.rules`: caminhos,
/// campos (`hasOnly`), tipos e o que vai no mesmo lote.
void main() {
  final serverTime = isA<FieldValue>();

  Map<String, Object?> dataOf(List<PlannedWrite> plan, String path) =>
      plan.singleWhere((w) => w.path == path).data!;

  Matcher keysAre(List<String> keys) => predicate<Map<String, Object?>>(
    (m) =>
        m.keys.toSet().difference(keys.toSet()).isEmpty &&
        keys.toSet().difference(m.keys.toSet()).isEmpty,
    'chaves exatamente $keys',
  );

  test('entrar: membership e profile no mesmo lote, mesmo apelido', () {
    final plan = joinPlan(
      uid: 'u1',
      nickname: 'lia_estuda',
      inviteCode: 'CODE',
      declaredMinAge: 18,
      rulesVersion: '1',
    );
    expect(plan.map((w) => w.path), ['memberships/u1', 'profiles/u1']);
    expect(plan.every((w) => w.kind == WriteKind.set), isTrue);
    final m = dataOf(plan, 'memberships/u1');
    expect(
      m,
      keysAre([
        'nickname',
        'inviteCode',
        'declaredMinAge',
        'rulesVersion',
        'joinedAt',
      ]),
    );
    expect(m['declaredMinAge'], isA<int>());
    expect(m['rulesVersion'], isA<String>());
    expect(m['joinedAt'], serverTime);
    final p = dataOf(plan, 'profiles/u1');
    expect(p, keysAre(['nickname', 'joinedAt']));
    expect(p['joinedAt'], serverTime);
    expect(p['nickname'], m['nickname']);
  });

  test('entrar sem convite não grava inviteCode', () {
    final plan = joinPlan(
      uid: 'u1',
      nickname: 'lia_estuda',
      declaredMinAge: 18,
      rulesVersion: '1',
    );
    expect(dataOf(plan, 'memberships/u1').containsKey('inviteCode'), isFalse);
  });

  test('renomear: update nos dois, só o apelido; sair: delete nos dois', () {
    final rename = renamePlan(uid: 'u1', nickname: 'novo_apelido');
    expect(rename.map((w) => w.path), ['memberships/u1', 'profiles/u1']);
    expect(rename.every((w) => w.kind == WriteKind.update), isTrue);
    for (final w in rename) {
      expect(w.data, {'nickname': 'novo_apelido'});
    }
    final leave = leavePlan('u1');
    expect(leave.map((w) => w.path), ['memberships/u1', 'profiles/u1']);
    expect(leave.every((w) => w.kind == WriteKind.delete), isTrue);
  });

  test('post: campos do hasOnly, status visible e limite no mesmo lote', () {
    const post = NewPost(
      communityId: 'matematica',
      title: 'Título válido',
      body: 'Corpo',
      bankId: 'enem-2020-q1',
    );
    final plan = postPlan(uid: 'u1', nickname: 'lia', postId: 'p9', post: post);
    expect(plan.map((w) => w.path), ['posts/p9', 'conectaLimits/u1']);
    final d = dataOf(plan, 'posts/p9');
    expect(
      d,
      keysAre([
        'communityId',
        'authorUid',
        'authorNickname',
        'title',
        'body',
        'bankId',
        'status',
        'createdAt',
      ]),
    );
    expect(d['authorUid'], 'u1');
    expect(d['authorNickname'], 'lia');
    expect(d['status'], 'visible');
    expect(d['createdAt'], serverTime);
    final limit = dataOf(plan, 'conectaLimits/u1');
    expect(limit, keysAre(['lastWriteAt', 'lastDocPath']));
    expect(limit['lastWriteAt'], serverTime);
    expect(limit['lastDocPath'], 'posts/p9');
  });

  test('post sem citação não grava bankId', () {
    final plan = postPlan(
      uid: 'u1',
      nickname: 'lia',
      postId: 'p9',
      post: const NewPost(
        communityId: 'reforco',
        title: 'Título válido',
        body: 'x',
      ),
    );
    expect(dataOf(plan, 'posts/p9').containsKey('bankId'), isFalse);
  });

  test('resposta: campos do hasOnly e lastDocPath = replies/<id>', () {
    final plan = replyPlan(
      uid: 'u1',
      nickname: 'lia',
      replyId: 'r5',
      postId: 'p9',
      body: 'oi',
    );
    expect(plan.map((w) => w.path), ['replies/r5', 'conectaLimits/u1']);
    final d = dataOf(plan, 'replies/r5');
    expect(
      d,
      keysAre([
        'postId',
        'authorUid',
        'authorNickname',
        'body',
        'status',
        'createdAt',
      ]),
    );
    expect(d['status'], 'visible');
    expect(d['createdAt'], serverTime);
    expect(dataOf(plan, 'conectaLimits/u1')['lastDocPath'], 'replies/r5');
    expect(dataOf(plan, 'conectaLimits/u1')['lastWriteAt'], serverTime);
  });

  Reply reply0({String author = 'u2'}) => Reply(
    id: 'r5',
    postId: 'p9',
    authorUid: author,
    authorNickname: 'x',
    body: 'b',
    status: ContentStatus.visible,
    createdAt: DateTime(2026),
  );

  test('Ajudou: id replyId_voterUid, campos do hasOnly; desmarcar apaga', () {
    final on = helpfulPlan(voterUid: 'u1', reply: reply0(), helpful: true);
    expect(on.single.path, 'helpfulVotes/r5_u1');
    expect(on.single.kind, WriteKind.set);
    final d = on.single.data!;
    expect(
      d,
      keysAre(['replyId', 'postId', 'authorUid', 'voterUid', 'createdAt']),
    );
    expect(d['voterUid'], 'u1');
    expect(d['authorUid'], 'u2');
    expect(d['createdAt'], serverTime);
    final off = helpfulPlan(voterUid: 'u1', reply: reply0(), helpful: false);
    expect(off.single.kind, WriteKind.delete);
    expect(off.single.path, 'helpfulVotes/r5_u1');
  });

  test('denúncia de post: id targetId_uid e alvo vai a pending no lote', () {
    final plan = reportPlan(
      uid: 'u1',
      report: const NewReport(
        targetType: ReportTarget.post,
        targetId: 'p9',
        postId: 'p9',
        reason: ReportReason.personalData,
      ),
      hideTarget: true,
    );
    expect(plan.map((w) => w.path), ['reports/p9_u1', 'posts/p9']);
    final d = dataOf(plan, 'reports/p9_u1');
    expect(
      d,
      keysAre([
        'targetType',
        'targetId',
        'postId',
        'reason',
        'details',
        'reporterUid',
        'status',
        'createdAt',
      ]),
    );
    expect(d['targetType'], 'post');
    expect(d['reason'], 'personal_data');
    expect(d['details'], '');
    expect(d['status'], 'open');
    expect(d['reporterUid'], 'u1');
    expect(d['createdAt'], serverTime);
    final hide = plan.last;
    expect(hide.kind, WriteKind.update);
    expect(hide.data, {'status': 'pending'});
  });

  test('denúncia de resposta aponta para replies e leva o postId', () {
    final plan = reportPlan(
      uid: 'u1',
      report: const NewReport(
        targetType: ReportTarget.reply,
        targetId: 'r5',
        postId: 'p9',
        reason: ReportReason.spam,
        details: 'x',
      ),
      hideTarget: true,
    );
    expect(plan.map((w) => w.path), ['reports/r5_u1', 'replies/r5']);
    expect(dataOf(plan, 'reports/r5_u1')['postId'], 'p9');
    expect(dataOf(plan, 'reports/r5_u1')['targetType'], 'reply');
  });

  test('alvo que já não está visível: grava só a denúncia', () {
    final plan = reportPlan(
      uid: 'u1',
      report: const NewReport(
        targetType: ReportTarget.post,
        targetId: 'p9',
        postId: 'p9',
        reason: ReportReason.spam,
      ),
      hideTarget: false,
    );
    expect(plan.map((w) => w.path), ['reports/p9_u1']);
  });

  test('moderação: só os campos permitidos; denúncia fica resolved', () {
    final hide = resolvePlan(
      moderatorUid: 'm1',
      reportId: 'p9_u1',
      targetType: ReportTarget.post,
      targetId: 'p9',
      authorUid: 'a1',
      decision: const ModerationDecision(
        ModerationKind.hideAndBan,
        reason: 'Ofensivo',
      ),
    );
    expect(hide.map((w) => w.path), ['posts/p9', 'reports/p9_u1', 'bans/a1']);
    final target = dataOf(hide, 'posts/p9');
    expect(target, keysAre(['status', 'moderationReason', 'moderatedAt']));
    expect(target['status'], 'hidden');
    expect(target['moderationReason'], 'Ofensivo');
    final report = dataOf(hide, 'reports/p9_u1');
    expect(report['status'], 'resolved');
    expect(report['decision'], 'hidden_banned');
    expect(report['resolvedBy'], 'm1');
    expect(dataOf(hide, 'bans/a1'), keysAre(['at', 'reason']));

    final restore = resolvePlan(
      moderatorUid: 'm1',
      reportId: 'r5_u1',
      targetType: ReportTarget.reply,
      targetId: 'r5',
      authorUid: 'a1',
      decision: const ModerationDecision(ModerationKind.restore),
    );
    expect(restore.map((w) => w.path), ['replies/r5', 'reports/r5_u1']);
    expect(dataOf(restore, 'replies/r5')['status'], 'visible');
    expect(dataOf(restore, 'reports/r5_u1')['decision'], 'restored');
  });

  test('leitura: documentos válidos viram modelo; inválidos viram null', () {
    final t = DateTime(2026, 11, 20);
    final post = postFromMap('p1', {
      'communityId': 'humanas',
      'authorUid': 'u',
      'authorNickname': 'n',
      'title': 'Título',
      'body': 'b',
      'status': 'pending',
      'createdAt': t,
      'moderationReason': 'x',
    }, DateTime(2000))!;
    expect(post.status, ContentStatus.pending);
    expect(post.createdAt, t);
    expect(post.moderationReason, 'x');
    expect(postFromMap('p', {'status': 'visible'}, t), isNull);
    expect(postFromMap('p', {'status': 'zzz'}, t), isNull);
    // createdAt ainda sem hora do servidor: usa o relógio local.
    final local = replyFromMap('r', {
      'postId': 'p',
      'authorUid': 'u',
      'authorNickname': 'n',
      'body': 'b',
      'status': 'visible',
      'createdAt': null,
    }, t)!;
    expect(local.createdAt, t);
    expect(reportFromMap('x', {'targetType': 'post'}, t), isNull);
    expect(membershipFromMap({'nickname': 'abc'}, t), isNull);
  });
}
