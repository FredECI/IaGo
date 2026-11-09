import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../domain/access_policy.dart';
import '../domain/ai_ports.dart';
import '../domain/session.dart';
import 'ai/fake_ai.dart';
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

/// Extrator de questões: simulado na demo, que o usa sem passar por
/// `AccessPolicy.canUseAi` (que continua falso na demo); `null` = indisponível (a
/// implementação do Gemini entra na F5b).
final questionExtractorProvider = Provider<QuestionExtractor?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  return owner is DemoSession ? FakeQuestionExtractor() : null;
});

/// Proponente de etapas: mesma regra do extrator.
final stepProposerProvider = Provider<StepProposer?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  return owner is DemoSession ? FakeStepProposer() : null;
});
