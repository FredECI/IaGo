import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import '../../domain/session.dart';
import 'community_providers.dart';

/// Participação da conta no Conecta (`null` = não é membro). Na demo, o Pedro
/// já é membro. Em conta real, só consulta o servidor com o Conecta ligado, e
/// qualquer falha vale "não é membro": o app nunca trava por isso.
/// Depois de entrar, invalide este provider e aguarde `.future`.
final myMembershipProvider = FutureProvider<Membership?>((ref) async {
  final owner = ref.watch(dataOwnerProvider);
  if (owner == null) return null;
  if (owner is! DemoSession &&
      !ref.watch(accessPolicyProvider).conectaEnabled) {
    return null;
  }
  try {
    return await ref.watch(communityRepositoryProvider).myMembership();
  } catch (_) {
    return null;
  }
});

/// A conta atual é membro da comunidade?
final isMemberProvider = Provider<bool>(
  (ref) => ref.watch(myMembershipProvider).value != null,
);

/// Única pergunta das telas e do roteador sobre o Conecta: quem decide é a
/// `AccessPolicy` (demo: simulado; conta: flag + membro).
final conectaVisibleProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;
  return ref
      .watch(accessPolicyProvider)
      .canSeeConecta(
        isDemo: session.isDemo,
        isMember: ref.watch(isMemberProvider),
      );
});

/// "Virar membro" só abre com o Conecta ligado: na demo ou com
/// `policy.conectaEnabled`. A conta ainda não precisa ser membro.
final conectaJoinableProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;
  return session.isDemo || ref.watch(accessPolicyProvider).conectaEnabled;
});
