/// Porta interna do adaptador Gemini (CA-R2): os adaptadores
/// `GeminiQuestionExtractor` e `GeminiStepProposer` falam só com ela. Quem
/// importa `firebase_ai` é a implementação, em `firebase_ai_gateway.dart`.
/// Demo e testes usam um gateway falso; a demo nunca chega aqui.
library;

import '../../../domain/ai_ports.dart';

/// Qual chamada está sendo feita (só para o gateway escolher limites).
enum AiCall { extraction, proposal }

/// Se a IA de verdade pode ser chamada neste aparelho e nesta compilação.
enum AiAvailability {
  available,

  /// Firebase sem configuração, sem rede na abertura ou em emulador (o AI
  /// Logic não tem emulador).
  firebaseUnavailable,

  /// App Check não ativou: sem chave de site (por exemplo, o APK sem
  /// `FIREBASE_APPCHECK_ANDROID_SITE_KEY`) ou a ativação falhou.
  appCheckUnavailable,
}

abstract interface class AiGateway {
  Future<AiAvailability> availability();

  /// Devolve o texto JSON da resposta. Lança só [AiException], já traduzida
  /// (cota, alta demanda, tempo esgotado, App Check, bloqueio...).
  ///
  /// [responseSchema] é um esquema simples em mapas (`type`, `properties`,
  /// `items`, `enum`, `nullable`); a implementação o converte no `Schema` do
  /// SDK. [model] vem de `AccessPolicy.aiModel`.
  Future<String> generateJson({
    required AiCall call,
    required String model,
    required String systemInstruction,
    required String prompt,
    List<ImportFile> files = const [],
    required Map<String, Object?> responseSchema,
    required Duration timeout,
  });
}
