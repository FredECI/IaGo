import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/gemini/ai_error_translation.dart';
import 'package:iago/domain/ai_ports.dart';

void main() {
  group('classifyAiError', () {
    final cases = <String, (Object, AiFailure)>{
      'QuotaExceeded': (QuotaExceeded('x'), AiFailure.quotaExhausted),
      '429 no texto': (
        ServerException('[429] You exceeded your current quota'),
        AiFailure.quotaExhausted,
      ),
      'RESOURCE_EXHAUSTED': (
        ServerException('RESOURCE_EXHAUSTED: limit 20 per day'),
        AiFailure.quotaExhausted,
      ),
      '500 alta demanda': (
        ServerException('This model is currently experiencing high demand'),
        AiFailure.unavailable,
      ),
      '503 UNAVAILABLE': (
        ServerException('[503] UNAVAILABLE'),
        AiFailure.unavailable,
      ),
      'TimeoutException': (TimeoutException('x'), AiFailure.timeout),
      'deadline expirou': (
        ServerException('Deadline expired before operation could complete'),
        AiFailure.timeout,
      ),
      'App Check no texto': (
        ServerException('[403] Firebase App Check token is invalid'),
        AiFailure.appCheckDenied,
      ),
      'FirebaseException do App Check': (
        FirebaseException(plugin: 'firebase_app_check', code: 'x'),
        AiFailure.appCheckDenied,
      ),
      '403 sem texto': (
        ServerException('[403] PERMISSION_DENIED'),
        AiFailure.appCheckDenied,
      ),
      'bloqueio': (
        FirebaseAIException('Response was blocked due to BlockReason.safety'),
        AiFailure.blocked,
      ),
      'candidato bloqueado': (
        FirebaseAIException('Candidate was blocked due to FinishReason.safety'),
        AiFailure.blocked,
      ),
      '413': (ServerException('[413] Request too large'), AiFailure.tooLarge),
      'API desligada': (ServiceApiNotEnabled('projects/p'), AiFailure.disabled),
      'local nao suportado': (UnsupportedUserLocation(), AiFailure.disabled),
      'sem rede (web)': (
        Exception('ClientException: Failed to fetch'),
        AiFailure.offline,
      ),
      'AiException passa direto': (
        const AiException(AiFailure.tooLarge),
        AiFailure.tooLarge,
      ),
      'qualquer outra': (StateError('bug'), AiFailure.unknown),
      // Número solto (posição, tamanho) não é código HTTP.
      'numero dentro de outro': (
        FormatException('posição 15000 inesperada'),
        AiFailure.unknown,
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(classifyAiError(e.value.$1), e.value.$2));
    }
  });

  test('translateAiError não reembrulha AiException', () {
    const original = AiException(AiFailure.quotaExhausted);
    expect(identical(translateAiError(original), original), isTrue);
    expect(
      translateAiError(QuotaExceeded('x')).failure,
      AiFailure.quotaExhausted,
    );
  });
}
