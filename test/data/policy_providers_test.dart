import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/data/ai/gemini/ai_gateway.dart';
import 'package:iago/data/ai/gemini/app_check_setup.dart';
import 'package:iago/data/ai/gemini/gemini_adapters.dart';
import 'package:iago/data/local/memory_runtime_config.dart';
import 'package:iago/domain/session.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';

class _Account extends SessionController {
  @override
  Session? build() => const AccountSession(uid: 'u1', email: 'a@b.c');
}

class _Gateway implements AiGateway {
  _Gateway(this.value);
  final AiAvailability value;
  int availabilityCalls = 0;
  @override
  Future<AiAvailability> availability() async {
    availabilityCalls++;
    return value;
  }

  @override
  Future<String> generateJson({
    required AiCall call,
    required String model,
    required String systemInstruction,
    required String prompt,
    List<dynamic> files = const [],
    required Map<String, Object?> responseSchema,
    required Duration timeout,
  }) => throw UnimplementedError();
}

Future<ProviderContainer> _real({
  required AiAvailability availability,
  Map<String, Object?>? runtime,
  FirebaseStatus status = FirebaseStatus.ready,
}) async {
  final container = ProviderContainer(
    overrides: [
      firebaseStatusProvider.overrideWith((ref) async => status),
      sessionProvider.overrideWith(_Account.new),
      aiGatewayProvider.overrideWithValue(_Gateway(availability)),
      runtimeConfigRepositoryProvider.overrideWithValue(
        MemoryRuntimeConfig(runtime),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accessPolicyAsyncProvider.future);
  await container.read(aiAvailabilityProvider.future);
  return container;
}

void main() {
  test('demo não aciona o gateway real nem o App Check', () async {
    resetAppCheckOutcome();
    final gateway = _Gateway(AiAvailability.available);
    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWith(
          (ref) async => FirebaseStatus.ready,
        ),
        aiGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).enterDemo();
    expect(
      container.read(questionExtractorProvider),
      isA<FakeQuestionExtractor>(),
    );
    expect(container.read(stepProposerProvider), isA<FakeStepProposer>());
    await Future<void>.delayed(Duration.zero);
    expect(gateway.availabilityCalls, 0);
    expect(lastAppCheckOutcome, AppCheckOutcome.notAttempted);
  });

  test('o bootstrap não ativa o App Check', () async {
    resetAppCheckOutcome();
    await initFirebase();
    expect(lastAppCheckOutcome, AppCheckOutcome.notAttempted);
  });

  test('demo usa a IA falsa, mas canUseAi continua falso', () {
    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWith(
          (ref) async => FirebaseStatus.notConfigured,
        ),
      ],
    );
    addTearDown(container.dispose);

    // Sem sessão: nada de IA.
    expect(container.read(questionExtractorProvider), isNull);

    container.read(sessionProvider.notifier).enterDemo();
    final extractor = container.read(questionExtractorProvider);
    expect(extractor, isA<FakeQuestionExtractor>());

    final policy = container.read(accessPolicyProvider);
    expect(
      policy.canUseAi(isMember: true, provider: extractor!.provider),
      isFalse,
    );
    expect(
      policy.canUseAi(isMember: false, provider: extractor.provider),
      isFalse,
    );
  });

  group('conta real', () {
    test('Gemini com aiEnabled, App Check ativo e modelo do runtime', () async {
      final c = await _real(
        availability: AiAvailability.available,
        runtime: {'aiEnabled': true, 'aiModel': 'modelo-x'},
      );
      final ex = c.read(questionExtractorProvider);
      expect(ex, isA<GeminiQuestionExtractor>());
      expect((ex! as GeminiQuestionExtractor).model, 'modelo-x');
      expect(c.read(stepProposerProvider), isA<GeminiStepProposer>());
    });

    test('modelo padrão sem aiModel', () async {
      final c = await _real(
        availability: AiAvailability.available,
        runtime: {'aiEnabled': true},
      );
      final ex = c.read(questionExtractorProvider)! as GeminiQuestionExtractor;
      expect(ex.model, 'gemini-3.5-flash-lite');
    });

    test('política desligada (padrão): sem IA', () async {
      final c = await _real(availability: AiAvailability.available);
      expect(c.read(questionExtractorProvider), isNull);
      expect(c.read(stepProposerProvider), isNull);
    });

    test('sem App Check (APK sem chave): sem IA', () async {
      final c = await _real(
        availability: AiAvailability.appCheckUnavailable,
        runtime: {'aiEnabled': true},
      );
      expect(c.read(questionExtractorProvider), isNull);
      expect(c.read(stepProposerProvider), isNull);
    });

    test('Firebase indisponível: sem IA, mesmo com gateway pronto', () async {
      final c = await _real(
        availability: AiAvailability.available,
        runtime: {'aiEnabled': true},
        status: FirebaseStatus.unavailable,
      );
      expect(c.read(questionExtractorProvider), isNull);
    });
  });
}
