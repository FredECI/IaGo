import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../domain/ai_ports.dart';

/// Traduz o que o SDK lança em uma [AiFailure]. Em release o `runtimeType`
/// vem minificado: classifica pelo tipo do pacote e, no resto, pelo texto da
/// mensagem; nunca por `runtimeType.toString()`.
AiFailure classifyAiError(Object error) {
  if (error is AiException) return error.failure;
  if (error is TimeoutException) return AiFailure.timeout;
  if (error is QuotaExceeded) return AiFailure.quotaExhausted;
  if (error is ServiceApiNotEnabled || error is UnsupportedUserLocation) {
    return AiFailure.disabled;
  }
  if (error is FirebaseException &&
      (error.plugin.contains('app-check') ||
          error.plugin.contains('app_check'))) {
    return AiFailure.appCheckDenied;
  }
  final text = switch (error) {
    FirebaseAIException(:final message) => message,
    FirebaseException(:final message) => '${error.code} ${message ?? ''}',
    _ => error.toString(),
  }.toLowerCase();

  // Números (códigos HTTP) só valem como palavra inteira.
  bool has(Iterable<String> needles) => needles.any(
    (n) => RegExp(r'^\d+$').hasMatch(n)
        ? RegExp('\\b$n\\b').hasMatch(text)
        : text.contains(n),
  );

  // App Check antes de "403": o 403 do AI Logic sem token válido cita o App
  // Check; um 403 qualquer não é motivo para culpar o aparelho.
  if (has(['app check', 'appcheck', 'app-check', 'firebaseappcheck'])) {
    return AiFailure.appCheckDenied;
  }
  if (has(['429', 'quota', 'resource_exhausted', 'rate limit'])) {
    return AiFailure.quotaExhausted;
  }
  if (has(['blocked', 'safety', 'prohibited', 'recitation'])) {
    return AiFailure.blocked;
  }
  if (has(['413', 'too large', 'request payload size', 'payload too'])) {
    return AiFailure.tooLarge;
  }
  if (has(['deadline', 'timed out', 'timeout'])) return AiFailure.timeout;
  // Rede antes de "indisponível": "Network is unavailable" é falta de rede.
  if (has([
    'socketexception',
    'failed host lookup',
    'network',
    'failed to fetch',
    'clientexception',
    'xmlhttprequest',
  ])) {
    return AiFailure.offline;
  }
  if (has([
    'high demand',
    'service unavailable',
    'overloaded',
    '503',
    '500',
    'internal error',
  ])) {
    return AiFailure.unavailable;
  }
  if (has(['403', 'permission_denied', 'permission denied'])) {
    // Sem o texto do App Check, o mais provável ainda é o token rejeitado.
    return AiFailure.appCheckDenied;
  }
  return AiFailure.unknown;
}

/// Versão pronta para `throw`.
AiException translateAiError(Object error) =>
    error is AiException ? error : AiException(classifyAiError(error));
