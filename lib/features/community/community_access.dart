import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import 'community_providers.dart';

/// Participação da conta no piloto (`null` = não é membro). Na demo, o Pedro
/// já é membro. Em conta real, consulta `memberships/{uid}` sempre,
/// independente de `conectaEnabled` (D1: IA e avaliações são para membros, e
/// virar membro não depende do fórum estar aberto). Qualquer falha vale "não é
/// membro": o app nunca trava por isso.
/// Depois de entrar, invalide este provider e aguarde `.future`.
final myMembershipProvider = FutureProvider<Membership?>((ref) async {
  final owner = ref.watch(dataOwnerProvider);
  if (owner == null) return null;
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

/// "Entrar no piloto" (virar membro) abre para qualquer conta logada, com o
/// Conecta ligado ou não: a tela não expõe o fórum. O nome é histórico. O que
/// o servidor exige (e-mail verificado, convite, idade) está nas regras.
final conectaJoinableProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider) != null,
);

/// Conta real que ainda não é membro e pode ser convidada: mostra os avisos
/// "Entrar no piloto". Na demo o Pedro já é membro.
final canOfferJoinProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null || session.isDemo) return false;
  if (ref.watch(myMembershipProvider).isLoading) return false;
  return !ref.watch(isMemberProvider);
});
