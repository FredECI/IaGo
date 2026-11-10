import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/memory_community_repository.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import 'community_providers.dart';

/// Contato para contestar uma decisão da moderação. Ainda é um marcador: o
/// e-mail do projeto sai da D6 (veja `docs/conecta/regras-da-comunidade.md`).
const String communityContactEmail = '<e-mail do projeto>';

/// Uid de quem usa o Conecta (na demo, o do repositório em memória). As telas
/// só o usam para reconhecer o que é do próprio usuário.
final communityUidProvider = Provider<String?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is String) return owner;
  if (owner != null) return MemoryCommunityRepository.demoUid;
  return null;
});

/// Moderador? Qualquer falha vale "não": a tela de moderação some.
final isModeratorProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(communityRepositoryProvider).isModerator();
  } catch (_) {
    return false;
  }
});

/// Banido? Falha vale "não" (o servidor nega a escrita do mesmo jeito).
final isBannedProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(communityRepositoryProvider).isBanned();
  } catch (_) {
    return false;
  }
});

/// Ajudas recebidas e a média do grupo de um membro.
final reputationProvider = FutureProvider.autoDispose
    .family<Reputation, String>(
      (ref, uid) => ref.watch(communityRepositoryProvider).reputation(uid),
    );
