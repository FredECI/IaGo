import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../data/community_repository.dart';
import '../../data/firebase/firestore_community_repository.dart';
import '../../data/local/community_demo_data.dart';
import '../../data/local/memory_community_repository.dart';
import '../../data/metrics_community_repository.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import '../../domain/session.dart';
import '../metrics/metrics_providers.dart';

/// Versão das regras da comunidade que o app mostra e o usuário aceita.
/// Subir o número pede novo aceite (C2). Vale a data do documento
/// `docs/conecta/regras-da-comunidade.md` (C6).
const String communityRulesVersion = '2026-11-08';

/// Implementação trocada pela sessão: demo -> memória com conteúdo simulado
/// (estado novo a cada `DemoSession`, o Pedro já é membro); conta ->
/// Firestore. Quem pode ver o Conecta é a `AccessPolicy`, não este provider.
final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  final clock = ref.watch(clockProvider);
  if (owner case final String uid) {
    // Em conta real, registra os eventos da H6 (só ids). Na demo as métricas
    // são simuladas, então a memória fica sem o decorador.
    return MetricsCommunityRepository(
      FirestoreCommunityRepository(
        db: FirebaseFirestore.instance,
        uid: uid,
        clock: clock,
      ),
      ref.read(metricsLoggerProvider).log,
    );
  }
  if (owner is DemoSession) {
    final seed = CommunityDemoData.build(owner.startedAt);
    final flagged = CommunityDemoData.buildModeration(owner.startedAt);
    return MemoryCommunityRepository(
      clock: clock,
      membership: Membership(
        nickname: 'pedro_estuda',
        declaredMinAge: 18,
        rulesVersion: communityRulesVersion,
        joinedAt: owner.startedAt,
      ),
      posts: [...seed.posts, ...flagged.posts],
      replies: [...seed.replies, ...flagged.replies],
      reports: flagged.reports,
      votes: seed.votes,
    );
  }
  return MemoryCommunityRepository(clock: clock);
});
