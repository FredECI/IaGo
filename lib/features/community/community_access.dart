import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/policy_providers.dart';
import '../../data/providers.dart';

/// A conta atual é membro da comunidade?
///
/// TODO(F6): ler do perfil/sessão. Até a F6 não existe `isMember`, então conta
/// real vale `false` e o Conecta fica escondido nela (CA-R5).
final isMemberProvider = Provider<bool>((ref) => false);

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
