import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart';
import '../core/app_info.dart';
import '../core/clock.dart';
import '../domain/access_policy.dart';
import '../domain/ai_ports.dart';
import '../domain/session.dart';
import 'ai/ai_daily_limit.dart';
import 'ai/fake_ai.dart';
import 'ai/gemini/ai_gateway.dart';
import 'ai/gemini/firebase_ai_gateway.dart';
import 'ai/gemini/gemini_adapters.dart';
import 'firebase/firebase_bootstrap.dart';
import 'firebase/firestore_runtime_config.dart';
import 'local/memory_runtime_config.dart';
import 'providers.dart';
import 'runtime_config_repository.dart';

/// Configuração de execução: conta → Firestore; demo ou sem sessão → memória
/// (vazia, ou seja, padrão seguro).
final runtimeConfigRepositoryProvider = Provider<RuntimeConfigRepository>((
  ref,
) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is String) {
    return FirestoreRuntimeConfig(db: FirebaseFirestore.instance);
  }
  return MemoryRuntimeConfig();
});

/// Política carregada; recarrega quando a sessão muda. Nunca dá erro.
final accessPolicyAsyncProvider = FutureProvider<AccessPolicy>((ref) async {
  final data = await ref.watch(runtimeConfigRepositoryProvider).load();
  return AccessPolicy.fromRuntime(data, termsMinAge: AppInfo.termsMinAge);
});

/// Política síncrona para as telas: enquanto carrega, vale o padrão seguro.
final accessPolicyProvider = Provider<AccessPolicy>((ref) {
  return ref.watch(accessPolicyAsyncProvider).value ??
      const AccessPolicy.safeDefault(termsMinAge: AppInfo.termsMinAge);
});

/// Gateway da IA de verdade. Os testes trocam por um falso.
final aiGatewayProvider = Provider<AiGateway>((ref) => FirebaseAiGateway());

/// Se a IA de verdade pode ser chamada (Firebase pronto e App Check ativo).
/// Espera o bootstrap terminar; enquanto isso, indisponível.
///
/// O resultado fica guardado na sessão, inclusive "App Check indisponível",
/// que pode ser falha passageira. Por isso quem vai usar a IA invalida este
/// provider antes, se [aiAvailabilityNeedsRetry]: ao abrir a importação, em
/// "Tentar de novo" e antes de pedir proposta ao Direciona.
final aiAvailabilityProvider = FutureProvider<AiAvailability>((ref) async {
  final status = await ref.watch(firebaseStatusProvider.future);
  if (status != FirebaseStatus.ready) return AiAvailability.firebaseUnavailable;
  return ref.watch(aiGatewayProvider).availability();
});

/// Refaz a checagem da IA se a última não deu "disponível". O gateway não
/// memoiza a falha do App Check, então uma nova tentativa pode dar certo.
/// Funciona com `Ref` e com `WidgetRef` (`invalidate` e `read`).
bool aiAvailabilityNeedsRetry(AsyncValue<AiAvailability> current) =>
    current.hasError ||
    (current.hasValue && current.value != AiAvailability.available);

/// Por que a IA não está disponível, para a mensagem da tela: App Check ou o
/// resto (desligada, Firebase fora do ar).
AiFailure aiUnavailableReason(AsyncValue<AiAvailability> current) =>
    current.value == AiAvailability.appCheckUnavailable
    ? AiFailure.appCheckDenied
    : AiFailure.disabled;

/// Onde mora a contagem diária de chamadas de IA: no aparelho, se houver
/// SharedPreferences; senão, na memória da sessão.
final aiUsageStoreProvider = Provider<AiUsageStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs == null ? MemoryAiUsageStore() : PrefsAiUsageStore(prefs);
});

/// Gemini só para conta real, com `aiEnabled` ligado e App Check ativo. A
/// regra de membro e de idade fica em `AccessPolicy.canUseAi`, aplicada pela
/// tela. `null` = indisponível (a colagem segue).
AiGateway? _realGateway(Ref ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is! String) return null;
  if (!ref.watch(accessPolicyProvider).aiEnabled) return null;
  final availability = ref.watch(aiAvailabilityProvider).value;
  if (availability != AiAvailability.available) return null;
  return ref.watch(aiGatewayProvider);
}

/// Limite suave diário (`aiDailyPerUser`): um só ponto, em volta das duas
/// portas reais (`ai_daily_limit.dart`). A demo não passa por aqui.
AiDailyLimiter _limiter(Ref ref, String owner, AccessPolicy policy) =>
    AiDailyLimiter(
      store: ref.watch(aiUsageStoreProvider),
      owner: owner,
      limit: policy.aiDailyPerUser,
      now: ref.watch(clockProvider),
    );

/// Extrator de questões: simulado na demo, que o usa sem passar por
/// `AccessPolicy.canUseAi` (que continua falso na demo); Gemini na conta real
/// quando a política e o App Check permitem; senão `null` (indisponível).
final questionExtractorProvider = Provider<QuestionExtractor?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is DemoSession) return FakeQuestionExtractor();
  final gateway = _realGateway(ref);
  if (gateway == null) return null;
  final policy = ref.watch(accessPolicyProvider);
  return DailyLimitedQuestionExtractor(
    GeminiQuestionExtractor(gateway: gateway, model: policy.aiModel),
    _limiter(ref, owner as String, policy),
  );
});

/// Proponente de etapas: mesma regra do extrator.
final stepProposerProvider = Provider<StepProposer?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is DemoSession) return FakeStepProposer();
  final gateway = _realGateway(ref);
  if (gateway == null) return null;
  final policy = ref.watch(accessPolicyProvider);
  return DailyLimitedStepProposer(
    GeminiStepProposer(gateway: gateway, model: policy.aiModel),
    _limiter(ref, owner as String, policy),
  );
});
