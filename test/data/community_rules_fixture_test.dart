import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/community_write_plans.dart';
import 'package:iago/domain/community_models.dart';

/// Exporta os planos de escrita do Conecta para
/// `firestore-tests/fixtures/community_plans.json`, que o teste de regras
/// (`firestore-tests/community-plans.test.mjs`) executa no emulador, campo a
/// campo. Este teste falha se o arquivo estiver desatualizado em relação aos
/// planos; para regenerar: `UPDATE_PLANS=1 flutter test <este arquivo>`.
const _file = 'firestore-tests/fixtures/community_plans.json';

Object? _value(Object? v) {
  if (v == null || v is String || v is num || v is bool) return v;
  if (v is FieldValue) {
    if (v == FieldValue.serverTimestamp()) return {r'$': 'serverTimestamp'};
    if (v == FieldValue.delete()) return {r'$': 'delete'};
    throw StateError('FieldValue desconhecido');
  }
  throw StateError('Tipo não serializável: ${v.runtimeType}');
}

List<Map<String, Object?>> _plan(List<PlannedWrite> plan) => [
  for (final w in plan)
    {
      'kind': w.kind.name,
      'path': w.path,
      if (w.data != null)
        'data': {for (final e in w.data!.entries) e.key: _value(e.value)},
    },
];

void main() {
  final reply = Reply(
    id: 'r1',
    postId: 'p1',
    authorUid: 'bob',
    authorNickname: 'bob_ok',
    body: 'x',
    status: ContentStatus.visible,
    createdAt: _epoch,
  );

  final scenarios = <String, List<PlannedWrite>>{
    'join': joinPlan(
      uid: 'novo',
      nickname: 'novo_ok',
      inviteCode: 'turma1',
      declaredMinAge: 18,
      rulesVersion: '2026-11-08',
    ),
    'joinNoInvite': joinPlan(
      uid: 'novo',
      nickname: 'novo_ok',
      declaredMinAge: 18,
      rulesVersion: '2026-11-08',
    ),
    'rename': renamePlan(uid: 'ana', nickname: 'ana_nova'),
    'leave': leavePlan('ana'),
    'post': postPlan(
      uid: 'ana',
      nickname: 'ana_ok',
      postId: 'pNovo',
      post: const NewPost(
        communityId: 'matematica',
        title: 'Dúvida em funções',
        body: 'Como começo?',
      ),
    ),
    'postBank': postPlan(
      uid: 'ana',
      nickname: 'ana_ok',
      postId: 'pNovo',
      post: const NewPost(
        communityId: 'matematica',
        title: 'Dúvida em funções',
        body: 'Como começo?',
        bankId: 'enem-2022-136',
      ),
    ),
    'reply': replyPlan(
      uid: 'bob',
      nickname: 'bob_ok',
      replyId: 'rNovo',
      postId: 'p1',
      body: 'Comece pelo gráfico.',
    ),
    'helpful': helpfulPlan(voterUid: 'ana', reply: reply, helpful: true),
    'unhelpful': helpfulPlan(voterUid: 'ana', reply: reply, helpful: false),
    'reportPost': reportPlan(
      uid: 'bob',
      report: const NewReport(
        targetType: ReportTarget.post,
        targetId: 'p1',
        postId: 'p1',
        reason: ReportReason.spam,
        details: 'propaganda',
      ),
      hideTarget: true,
    ),
    'reportPostNoHide': reportPlan(
      uid: 'bob',
      report: const NewReport(
        targetType: ReportTarget.post,
        targetId: 'p1',
        postId: 'p1',
        reason: ReportReason.other,
      ),
      hideTarget: false,
    ),
    'reportReply': reportPlan(
      uid: 'bob',
      report: const NewReport(
        targetType: ReportTarget.reply,
        targetId: 'r1',
        postId: 'p1',
        reason: ReportReason.personalData,
        details: 'telefone',
      ),
      hideTarget: true,
    ),
    'resolveRestorePost': resolvePlan(
      moderatorUid: 'mod',
      reportId: 'p1_bob',
      targetType: ReportTarget.post,
      targetId: 'p1',
      authorUid: 'ana',
      decision: const ModerationDecision(ModerationKind.restore),
    ),
    'resolveHidePost': resolvePlan(
      moderatorUid: 'mod',
      reportId: 'p1_bob',
      targetType: ReportTarget.post,
      targetId: 'p1',
      authorUid: 'ana',
      decision: const ModerationDecision(ModerationKind.hide, reason: 'spam'),
    ),
    'resolveBanPost': resolvePlan(
      moderatorUid: 'mod',
      reportId: 'p1_bob',
      targetType: ReportTarget.post,
      targetId: 'p1',
      authorUid: 'ana',
      decision: const ModerationDecision(
        ModerationKind.hideAndBan,
        reason: 'spam',
      ),
    ),
    'resolveHideReply': resolvePlan(
      moderatorUid: 'mod',
      reportId: 'r1_bob',
      targetType: ReportTarget.reply,
      targetId: 'r1',
      authorUid: 'bob',
      decision: const ModerationDecision(ModerationKind.hide, reason: 'ofensa'),
    ),
    'resolveDeletedTarget': resolveDeletedTargetPlan(
      moderatorUid: 'mod',
      reportId: 'p1_bob',
    ),
    'resolveRestoreReply': resolvePlan(
      moderatorUid: 'mod',
      reportId: 'r1_bob',
      targetType: ReportTarget.reply,
      targetId: 'r1',
      authorUid: 'bob',
      decision: const ModerationDecision(ModerationKind.restore),
    ),
  };

  final json = const JsonEncoder.withIndent('  ')
      .convert({for (final e in scenarios.entries) e.key: _plan(e.value)});

  test('planos do Conecta batem com o fixture usado no teste de regras', () {
    final file = File(_file);
    if (Platform.environment['UPDATE_PLANS'] == '1') {
      file.writeAsStringSync('$json\n');
    }
    expect(file.existsSync(), isTrue, reason: 'rode com UPDATE_PLANS=1');
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n').trim(),
      json,
      reason: 'fixture desatualizado: UPDATE_PLANS=1 flutter test $_file',
    );
  });
}

final DateTime _epoch = DateTime.utc(2026);
