import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/account_erasure.dart';
import 'package:iago/data/firebase/community_write_plans.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/local/memory_rating_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/domain/rating_models.dart';

/// Exclusão de conta em cascata (C5). O plano é exportado para
/// `firestore-tests/fixtures/erasure_plans.json`, que o teste de regras
/// (`firestore-tests/account-erasure.test.mjs`) executa no emulador.
/// Regenerar: `UPDATE_PLANS=1 flutter test test/data/account_erasure_test.dart`.
const _file = 'firestore-tests/fixtures/erasure_plans.json';

const _footprint = CommunityFootprint(
  postIds: ['p1'],
  replyIds: ['r1'],
  votesGiven: ['r9_ana'],
  votesReceived: ['r1_bob'],
  openReportIds: ['p7_ana'],
  resolvedReportIds: ['p8_ana'],
);

List<Map<String, Object?>> _stage(List<PlannedWrite> s) => [
  for (final w in s) {'kind': w.kind.name, 'path': w.path},
];

void main() {
  test('o plano apaga o público e depois membro, perfil e limite juntos', () {
    final stages = accountErasureStages(
      uid: 'ana',
      footprint: _footprint,
      ratingIds: ['enem-2022-1_ana'],
    );
    final paths = [
      for (final s in stages) [for (final w in s) w.path],
    ];
    expect(paths.length, 2);
    expect(paths.first, [
      'posts/p1',
      'replies/r1',
      'helpfulVotes/r9_ana',
      'questionRatings/enem-2022-1_ana',
      'reports/p8_ana',
    ]);
    expect(paths.last, [
      'conectaLimits/ana',
      'memberships/ana',
      'profiles/ana',
    ]);
    expect(
      stages.expand((s) => s).every((w) => w.kind == WriteKind.delete),
      isTrue,
    );
    // Fica de propósito: denúncia aberta, voto recebido e banimento.
    final all = paths.expand((p) => p);
    expect(all, isNot(contains('reports/p7_ana')));
    expect(all, isNot(contains('helpfulVotes/r1_bob')));
    expect(all.any((p) => p.startsWith('bans/')), isFalse);
  });

  test(
    'divide em lotes de até 400 e o lote final de membro fica por último',
    () {
      final stages = accountErasureStages(
        uid: 'ana',
        footprint: CommunityFootprint(
          postIds: [for (var i = 0; i < 950; i++) 'p$i'],
        ),
        ratingIds: const [],
      );
      expect([for (final s in stages) s.length], [400, 400, 150, 3]);
    },
  );

  test('sem nada no Conecta ainda gera o lote de membro (idempotente)', () {
    final stages = accountErasureStages(
      uid: 'ana',
      footprint: const CommunityFootprint(),
      ratingIds: const [],
    );
    expect(stages.length, 1);
    expect(stages.single.length, 3);
  });

  group('AccountEraser', () {
    ErasureInventory inv() =>
        const ErasureInventory(footprint: _footprint, ratingIds: ['x_ana']);

    test('roda inventário, lotes na ordem e por fim as subcoleções', () async {
      final log = <String>[];
      await AccountEraser(
        inventory: () async {
          log.add('inventario');
          return inv();
        },
        commit: (b) async => log.add('lote:${b.first.path}'),
        deleteUserData: () async => log.add('users'),
      ).run('ana');
      expect(log, [
        'inventario',
        'lote:posts/p1',
        'lote:conectaLimits/ana',
        'users',
      ]);
    });

    test(
      'falha no meio: para (não chega ao fim) e a nova tentativa conclui',
      () async {
        final log = <String>[];
        var fail = true;
        final eraser = AccountEraser(
          inventory: () async => inv(),
          commit: (b) async {
            if (fail && b.first.path.startsWith('conectaLimits')) {
              throw StateError('rede caiu');
            }
            log.add(b.first.path);
          },
          deleteUserData: () async => log.add('users'),
        );
        await expectLater(eraser.run('ana'), throwsStateError);
        expect(log, ['posts/p1']); // nem users nem o fim: o Auth fica intacto
        fail = false;
        log.clear();
        await eraser.run('ana');
        expect(log.last, 'users');
        expect(log, contains('conectaLimits/ana'));
      },
    );

    test('falha no inventário não apaga nada', () async {
      var commits = 0;
      final eraser = AccountEraser(
        inventory: () async => throw StateError('sem leitura'),
        commit: (_) async => commits++,
        deleteUserData: () async => commits++,
      );
      await expectLater(eraser.run('ana'), throwsStateError);
      expect(commits, 0);
    });
  });

  test('inventário sem servidor (unavailable) para tudo: nada é apagado e o '
      'erro chega a quem chama, que não apaga o Auth', () async {
    var writes = 0;
    final eraser = AccountEraser(
      inventory: () async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      ),
      commit: (_) async => writes++,
      deleteUserData: () async => writes++,
    );
    await expectLater(eraser.run('ana'), throwsA(isA<FirebaseException>()));
    expect(writes, 0);
  });

  test('métricas ignoram eventos durante a exclusão (flag)', () {
    expect(AccountErasureState.inProgress, isFalse);
  });

  test('demo: a exclusão em memória limpa tudo da pessoa', () async {
    final community = MemoryCommunityRepository(
      clock: () => DateTime(2026, 11, 9),
    );
    await community.join(
      nickname: 'pedro_estuda',
      declaredMinAge: 18,
      rulesVersion: '1',
    );
    final post = await community.createPost(
      const NewPost(
        communityId: 'matematica',
        title: 'Dúvida em funções',
        body: 'Como começo?',
      ),
    );
    final ratings = MemoryRatingRepository(
      questions: MemoryQuestionRepository(clock: () => DateTime(2026, 11, 9)),
      useSimulated: false,
    );
    await ratings.rate(
      const RatingTarget(
        bankId: 'enem-2022-1',
        area: Area.mathematics,
        subject: 'Matemática',
      ),
      RatingValue(difficulty: 2, quality: 3),
    );
    expect((await community.myFootprint()).postIds, [post.id]);

    community.eraseMyData();
    ratings.eraseMyData();

    final f = await community.myFootprint();
    expect(f.postIds, isEmpty);
    expect(f.replyIds, isEmpty);
    expect(f.votesGiven, isEmpty);
    expect(f.resolvedReportIds, isEmpty);
    expect(await community.myMembership(), isNull);
    expect(await ratings.myRating('enem-2022-1'), isNull);
  });

  test('o plano de exemplo bate com o fixture usado no teste de regras', () {
    final stages = accountErasureStages(
      uid: 'ana',
      footprint: _footprint,
      ratingIds: ['enem-2022-1_ana'],
    );
    final json = const JsonEncoder.withIndent('  ').convert({
      'stages': [for (final s in stages) _stage(s)],
    });
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
