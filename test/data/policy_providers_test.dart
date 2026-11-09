import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/data/firebase/firebase_bootstrap.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';

void main() {
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
}
