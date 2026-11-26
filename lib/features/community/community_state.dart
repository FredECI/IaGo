import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../data/local/memory_community_repository.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import 'community_providers.dart';

/// Contato para contestar uma decisão da moderação: o e-mail do projeto.
const String communityContactEmail = AppInfo.projectContactEmail;

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

/// "Ver como moderador (demonstração)": só existe na demo. Liga o papel de
/// moderador no repositório em memória; volta a desligado a cada nova sessão.
/// Conta real nunca usa isto (o papel vem do Firestore).
class DemoModeratorMode extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(dataOwnerProvider);
    return false;
  }

  void set(bool value) {
    final repo = ref.read(communityRepositoryProvider);
    if (repo is! MemoryCommunityRepository) return;
    repo.moderator = value;
    state = value;
    ref.invalidate(isModeratorProvider);
  }
}

final demoModeratorModeProvider = NotifierProvider<DemoModeratorMode, bool>(
  DemoModeratorMode.new,
);

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
