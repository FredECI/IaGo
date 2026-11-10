import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../domain/access_policy.dart';
import '../domain/ai_ports.dart';
import '../domain/session.dart';
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
final aiAvailabilityProvider = FutureProvider<AiAvailability>((ref) async {
  final status = await ref.watch(firebaseStatusProvider.future);
  if (status != FirebaseStatus.ready) return AiAvailability.firebaseUnavailable;
  return ref.watch(aiGatewayProvider).availability();
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

/// Extrator de questões: simulado na demo, que o usa sem passar por
/// `AccessPolicy.canUseAi` (que continua falso na demo); Gemini na conta real
/// quando a política e o App Check permitem; senão `null` (indisponível).
final questionExtractorProvider = Provider<QuestionExtractor?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is DemoSession) return FakeQuestionExtractor();
  final gateway = _realGateway(ref);
  if (gateway == null) return null;
  return GeminiQuestionExtractor(
    gateway: gateway,
    model: ref.watch(accessPolicyProvider).aiModel,
  );
});

/// Proponente de etapas: mesma regra do extrator.
final stepProposerProvider = Provider<StepProposer?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is DemoSession) return FakeStepProposer();
  final gateway = _realGateway(ref);
  if (gateway == null) return null;
  return GeminiStepProposer(
    gateway: gateway,
    model: ref.watch(accessPolicyProvider).aiModel,
  );
});
