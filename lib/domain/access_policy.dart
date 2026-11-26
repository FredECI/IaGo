/// Política de acesso (CA-R1): o único lugar que decide idade mínima, convite,
/// IA e Conecta. Telas e repositórios perguntam aqui, nunca comparam idade
/// nem leem `appConfig/runtime` por conta própria.
///
/// Espelha as funções nomeadas de `firestore.rules` (`termsMinAge()`,
/// `minAge()`, `inviteOk()`, `conectaOpen()`): campo ausente ou de tipo errado
/// vale o padrão seguro, e `minAge` nunca fica abaixo da idade dos termos.
library;

import 'ai_ports.dart';

/// Modelo padrão da IA, usado se `appConfig/runtime.aiModel` faltar.
const String defaultAiModel = 'gemini-3.5-flash-lite';

/// Limite suave de chamadas de IA por usuário e por dia (padrão do runtime).
const int defaultAiDailyPerUser = 12;

class AccessPolicy {
  const AccessPolicy({
    required this.termsMinAge,
    required this.minAge,
    this.inviteRequired = true,
    this.aiEnabled = false,
    this.conectaEnabled = false,
    this.conectaWritesEnabled = false,
    this.aiModel = defaultAiModel,
    this.aiDailyPerUser = defaultAiDailyPerUser,
  }) : assert(minAge >= termsMinAge, 'minAge nunca fica abaixo dos termos');

  /// Padrão seguro: sem rede ou sem documento, vale o comportamento do MVP.
  const AccessPolicy.safeDefault({required int termsMinAge})
    : this(termsMinAge: termsMinAge, minAge: termsMinAge);

  /// Lê `appConfig/runtime`. Campo ausente ou de tipo errado vale o padrão.
  /// `minAge = max(runtime.minAge, termsMinAge)`.
  factory AccessPolicy.fromRuntime(
    Map<String, Object?>? data, {
    required int termsMinAge,
  }) {
    final d = data ?? const <String, Object?>{};
    bool flag(String key, bool fallback) {
      final v = d[key];
      return v is bool ? v : fallback;
    }

    final rawMin = d['minAge'];
    final minAge = rawMin is int && rawMin > termsMinAge ? rawMin : termsMinAge;
    final rawModel = d['aiModel'];
    final rawDaily = d['aiDailyPerUser'];
    return AccessPolicy(
      termsMinAge: termsMinAge,
      minAge: minAge,
      inviteRequired: flag('inviteRequired', true),
      aiEnabled: flag('aiEnabled', false),
      conectaEnabled: flag('conectaEnabled', false),
      conectaWritesEnabled: flag('conectaWritesEnabled', false),
      aiModel: rawModel is String && rawModel.trim().isNotEmpty
          ? rawModel.trim()
          : defaultAiModel,
      aiDailyPerUser: rawDaily is int && rawDaily > 0
          ? rawDaily
          : defaultAiDailyPerUser,
    );
  }

  /// Idade das contas, pelos termos (`AppInfo.termsMinAge`).
  final int termsMinAge;

  /// Idade mínima para virar membro. Nunca abaixo de [termsMinAge].
  final int minAge;
  final bool inviteRequired;
  final bool aiEnabled;
  final bool conectaEnabled;

  /// Só o cliente mostra o estado; quem bloqueia a escrita são as regras.
  final bool conectaWritesEnabled;
  final String aiModel;
  final int aiDailyPerUser;

  /// A idade mínima declarada atende à política de membros.
  bool acceptsDeclaredAge(int declaredMinAge) => declaredMinAge >= minAge;

  /// Só para conta real. A demo NÃO passa por aqui: usa o
  /// `questionExtractorProvider` (IA falsa) direto, como "exemplo simulado",
  /// e não tem Direciona com IA; por isso não há atalho `isDemo`.
  ///
  /// Falso se a IA está desligada, se não for membro ou se a idade dos termos
  /// ou a dos membros ficar abaixo da exigida pelo provedor (CA-R5).
  bool canUseAi({required bool isMember, required AiProviderInfo provider}) =>
      aiEnabled &&
      isMember &&
      termsMinAge >= provider.minUserAge &&
      minAge >= provider.minUserAge;

  /// A demo mostra o Conecta simulado; a conta real, só membro e com a flag.
  bool canSeeConecta({required bool isDemo, required bool isMember}) =>
      isDemo || (conectaEnabled && isMember);

  @override
  bool operator ==(Object other) =>
      other is AccessPolicy &&
      other.termsMinAge == termsMinAge &&
      other.minAge == minAge &&
      other.inviteRequired == inviteRequired &&
      other.aiEnabled == aiEnabled &&
      other.conectaEnabled == conectaEnabled &&
      other.conectaWritesEnabled == conectaWritesEnabled &&
      other.aiModel == aiModel &&
      other.aiDailyPerUser == aiDailyPerUser;

  @override
  int get hashCode => Object.hash(
    termsMinAge,
    minAge,
    inviteRequired,
    aiEnabled,
    conectaEnabled,
    conectaWritesEnabled,
    aiModel,
    aiDailyPerUser,
  );
}
