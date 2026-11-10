import '../../domain/community_models.dart';
import 'community_write_plans.dart';

/// Lote máximo por exclusão (o limite do Firestore é 500 operações).
const int erasureBatchSize = 400;

List<List<PlannedWrite>> _chunks(List<PlannedWrite> writes) => [
  for (var i = 0; i < writes.length; i += erasureBatchSize)
    writes.sublist(
      i,
      i + erasureBatchSize > writes.length
          ? writes.length
          : i + erasureBatchSize,
    ),
];

/// Lotes que apagam o que a pessoa tem no Conecta e nas avaliações (C5), na
/// ordem em que devem rodar:
///
/// 1. dados públicos: posts, respostas, votos dados, avaliações e denúncias
///    **resolvidas** (a denúncia aberta fica até o moderador decidir, exceção
///    ao CA-T7); em lotes de até [erasureBatchSize];
/// 2. `conectaLimits`, `memberships` e `profiles` no **mesmo** lote, como as
///    regras exigem (`memberships` só sai com `profiles` saindo junto, e
///    `conectaLimits` só sem `memberships`).
///
/// Os votos recebidos ficam: as regras só deixam o votante apagar o voto.
/// O `bans/{uid}` também fica, de propósito. Sem efeito colateral: refazer o
/// plano depois de uma falha apaga só o que sobrou.
List<List<PlannedWrite>> accountErasureStages({
  required String uid,
  required CommunityFootprint footprint,
  required List<String> ratingIds,
}) {
  final writes = <PlannedWrite>[
    for (final id in footprint.postIds)
      PlannedWrite(WriteKind.delete, 'posts/$id'),
    for (final id in footprint.replyIds)
      PlannedWrite(WriteKind.delete, 'replies/$id'),
    for (final id in footprint.votesGiven)
      PlannedWrite(WriteKind.delete, 'helpfulVotes/$id'),
    for (final id in ratingIds)
      PlannedWrite(WriteKind.delete, 'questionRatings/$id'),
    for (final id in footprint.resolvedReportIds)
      PlannedWrite(WriteKind.delete, 'reports/$id'),
  ];
  return [
    ..._chunks(writes),
    [PlannedWrite(WriteKind.delete, 'conectaLimits/$uid'), ...leavePlan(uid)],
  ];
}

/// O que a exclusão encontrou antes de apagar qualquer coisa.
class ErasureInventory {
  const ErasureInventory({required this.footprint, required this.ratingIds});

  final CommunityFootprint footprint;
  final List<String> ratingIds;
}

/// `true` enquanto uma exclusão de conta está em andamento. As métricas
/// ([FirestoreMetricsRepository]) ignoram eventos nesse período, para nenhum
/// deles recriar `users/{uid}/events` depois de apagados.
abstract final class AccountErasureState {
  static bool inProgress = false;
}

/// Orquestra a exclusão em cascata: inventário, dados públicos, membro e
/// perfil, subcoleções privadas de `users/{uid}`. Qualquer falha propaga e
/// interrompe a sequência (quem chama só apaga o usuário do Auth depois que
/// [run] termina). É idempotente: a nova tentativa refaz o inventário.
class AccountEraser {
  AccountEraser({
    required this.inventory,
    required this.commit,
    required this.deleteUserData,
  });

  /// Consulta o que a pessoa tem (antes de qualquer exclusão, porque algumas
  /// leituras dependem de ela ainda ser membro).
  final Future<ErasureInventory> Function() inventory;

  /// Grava um lote; deve lançar se não for confirmado.
  final Future<void> Function(List<PlannedWrite> batch) commit;

  /// Subcoleções e documento de perfil em `users/{uid}`.
  final Future<void> Function() deleteUserData;

  Future<void> run(String uid) async {
    final found = await inventory();
    final stages = accountErasureStages(
      uid: uid,
      footprint: found.footprint,
      ratingIds: found.ratingIds,
    );
    for (final batch in stages) {
      await commit(batch);
    }
    await deleteUserData();
  }
}
