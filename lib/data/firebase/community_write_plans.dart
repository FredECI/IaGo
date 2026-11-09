import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/community_models.dart';

enum WriteKind { set, update, delete }

/// Uma escrita de um lote do Conecta. O repositório só traduz os planos para
/// o `WriteBatch`, o que deixa o contrato com as regras testável sem o SDK
/// conectado: os testes conferem caminho, tipo e campos de cada escrita.
class PlannedWrite {
  const PlannedWrite(this.kind, this.path, [this.data]);

  final WriteKind kind;
  final String path;
  final Map<String, Object?>? data;
}

FieldValue _now() => FieldValue.serverTimestamp();

PlannedWrite _limit(String uid, String docPath) => PlannedWrite(
  WriteKind.set,
  'conectaLimits/$uid',
  {'lastWriteAt': _now(), 'lastDocPath': docPath},
);

/// Entrar: participação e perfil público no mesmo lote, com o mesmo apelido.
List<PlannedWrite> joinPlan({
  required String uid,
  required String nickname,
  String? inviteCode,
  required int declaredMinAge,
  required String rulesVersion,
}) => [
  PlannedWrite(WriteKind.set, 'memberships/$uid', {
    'nickname': nickname,
    'inviteCode': ?inviteCode,
    'declaredMinAge': declaredMinAge,
    'rulesVersion': rulesVersion,
    'joinedAt': _now(),
  }),
  PlannedWrite(WriteKind.set, 'profiles/$uid', {
    'nickname': nickname,
    'joinedAt': _now(),
  }),
];

/// Renomear: `update` nos dois documentos, só o apelido.
List<PlannedWrite> renamePlan({
  required String uid,
  required String nickname,
}) => [
  PlannedWrite(WriteKind.update, 'memberships/$uid', {'nickname': nickname}),
  PlannedWrite(WriteKind.update, 'profiles/$uid', {'nickname': nickname}),
];

/// Sair: apaga os dois documentos no mesmo lote.
List<PlannedWrite> leavePlan(String uid) => [
  PlannedWrite(WriteKind.delete, 'memberships/$uid'),
  PlannedWrite(WriteKind.delete, 'profiles/$uid'),
];

/// Post e limite de escrita no mesmo lote (`lastDocPath` = `posts/<id>`).
List<PlannedWrite> postPlan({
  required String uid,
  required String nickname,
  required String postId,
  required NewPost post,
}) => [
  PlannedWrite(WriteKind.set, 'posts/$postId', {
    'communityId': post.communityId,
    'authorUid': uid,
    'authorNickname': nickname,
    'title': post.title,
    'body': post.body,
    'bankId': ?post.bankId,
    'status': 'visible',
    'createdAt': _now(),
  }),
  _limit(uid, 'posts/$postId'),
];

List<PlannedWrite> replyPlan({
  required String uid,
  required String nickname,
  required String replyId,
  required String postId,
  required String body,
}) => [
  PlannedWrite(WriteKind.set, 'replies/$replyId', {
    'postId': postId,
    'authorUid': uid,
    'authorNickname': nickname,
    'body': body,
    'status': 'visible',
    'createdAt': _now(),
  }),
  _limit(uid, 'replies/$replyId'),
];

String helpfulId(String replyId, String voterUid) => '${replyId}_$voterUid';

List<PlannedWrite> helpfulPlan({
  required String voterUid,
  required Reply reply,
  required bool helpful,
}) {
  final path = 'helpfulVotes/${helpfulId(reply.id, voterUid)}';
  if (!helpful) return [PlannedWrite(WriteKind.delete, path)];
  return [
    PlannedWrite(WriteKind.set, path, {
      'replyId': reply.id,
      'postId': reply.postId,
      'authorUid': reply.authorUid,
      'voterUid': voterUid,
      'createdAt': _now(),
    }),
  ];
}

/// Denúncia e mudança do alvo para `pending` no mesmo lote. [hideTarget] só
/// vale se o alvo ainda está `visible` (a regra só deixa essa transição):
/// se já estiver em análise, grava só a denúncia.
List<PlannedWrite> reportPlan({
  required String uid,
  required NewReport report,
  required bool hideTarget,
}) {
  final targetPath =
      '${report.targetType == ReportTarget.post ? 'posts' : 'replies'}/${report.targetId}';
  return [
    PlannedWrite(WriteKind.set, 'reports/${report.targetId}_$uid', {
      'targetType': report.targetType.name,
      'targetId': report.targetId,
      'postId': report.postId,
      'reason': report.reason.wireName,
      'details': report.details,
      'reporterUid': uid,
      'status': 'open',
      'createdAt': _now(),
    }),
    if (hideTarget)
      PlannedWrite(WriteKind.update, targetPath, {'status': 'pending'}),
  ];
}

/// Decisão do moderador: conteúdo, denúncia (que fica `resolved`) e, se for
/// o caso, o banimento do autor.
List<PlannedWrite> resolvePlan({
  required String moderatorUid,
  required String reportId,
  required ReportTarget targetType,
  required String targetId,
  required String authorUid,
  required ModerationDecision decision,
}) {
  final restore = decision.kind == ModerationKind.restore;
  final targetPath =
      '${targetType == ReportTarget.post ? 'posts' : 'replies'}/$targetId';
  return [
    PlannedWrite(WriteKind.update, targetPath, {
      'status': restore ? 'visible' : 'hidden',
      'moderationReason': restore ? FieldValue.delete() : decision.reason,
      'moderatedAt': _now(),
    }),
    PlannedWrite(WriteKind.update, 'reports/$reportId', {
      'status': 'resolved',
      'decision': decision.kind.wireName,
      'resolvedBy': moderatorUid,
      'resolvedAt': _now(),
    }),
    if (decision.kind == ModerationKind.hideAndBan)
      PlannedWrite(WriteKind.set, 'bans/$authorUid', {
        'at': _now(),
        'reason': decision.reason,
      }),
  ];
}

/// Denúncia cujo conteúdo foi apagado: só a denúncia vira `resolved`.
List<PlannedWrite> resolveDeletedTargetPlan({
  required String moderatorUid,
  required String reportId,
}) => [
  PlannedWrite(WriteKind.update, 'reports/$reportId', {
    'status': 'resolved',
    'decision': 'targetDeleted',
    'resolvedBy': moderatorUid,
    'resolvedAt': _now(),
  }),
];

// --- Leitura ---

DateTime _date(Object? v, DateTime fallback) => v is DateTime ? v : fallback;

/// `null` se o documento estiver inválido (é ignorado na lista). Nunca lança.
/// [fallback] vale para `createdAt` ausente (escrita local ainda sem hora do
/// servidor).
Post? postFromMap(String id, Map<String, Object?> m, DateTime fallback) {
  final status = ContentStatus.tryParse(m['status']);
  final community = m['communityId'];
  final uid = m['authorUid'];
  final nick = m['authorNickname'];
  final title = m['title'];
  final body = m['body'];
  if (status == null ||
      community is! String ||
      uid is! String ||
      nick is! String ||
      title is! String ||
      body is! String) {
    return null;
  }
  final bankId = m['bankId'];
  final reason = m['moderationReason'];
  return Post(
    id: id,
    communityId: community,
    authorUid: uid,
    authorNickname: nick,
    title: title,
    body: body,
    bankId: bankId is String ? bankId : null,
    status: status,
    moderationReason: reason is String ? reason : null,
    createdAt: _date(m['createdAt'], fallback),
  );
}

Reply? replyFromMap(String id, Map<String, Object?> m, DateTime fallback) {
  final status = ContentStatus.tryParse(m['status']);
  final postId = m['postId'];
  final uid = m['authorUid'];
  final nick = m['authorNickname'];
  final body = m['body'];
  if (status == null ||
      postId is! String ||
      uid is! String ||
      nick is! String ||
      body is! String) {
    return null;
  }
  final reason = m['moderationReason'];
  return Reply(
    id: id,
    postId: postId,
    authorUid: uid,
    authorNickname: nick,
    body: body,
    status: status,
    moderationReason: reason is String ? reason : null,
    createdAt: _date(m['createdAt'], fallback),
  );
}

Membership? membershipFromMap(Map<String, Object?> m, DateTime fallback) {
  final nick = m['nickname'];
  final age = m['declaredMinAge'];
  final rules = m['rulesVersion'];
  if (nick is! String || age is! int || rules is! String) return null;
  final code = m['inviteCode'];
  return Membership(
    nickname: nick,
    declaredMinAge: age,
    rulesVersion: rules,
    inviteCode: code is String ? code : null,
    joinedAt: _date(m['joinedAt'], fallback),
  );
}

ReportRecord? reportFromMap(
  String id,
  Map<String, Object?> m,
  DateTime fallback,
) {
  final type = ReportTarget.values.asNameMap()[m['targetType']];
  final reason = ReportReason.tryParse(m['reason']);
  final targetId = m['targetId'];
  final postId = m['postId'];
  final reporter = m['reporterUid'];
  if (type == null ||
      reason == null ||
      targetId is! String ||
      postId is! String ||
      reporter is! String) {
    return null;
  }
  final details = m['details'];
  return ReportRecord(
    id: id,
    targetType: type,
    targetId: targetId,
    postId: postId,
    reason: reason,
    details: details is String ? details : '',
    reporterUid: reporter,
    open: m['status'] == 'open',
    createdAt: _date(m['createdAt'], fallback),
  );
}
