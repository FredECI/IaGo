/// Portas de IA do domínio (CA-R2): só tipos do domínio, nenhum SDK.
///
/// Trocar de provedor é escrever outro adaptador destas portas; telas e
/// regras não mudam. O pacote `firebase_ai` só pode aparecer em
/// `lib/data/ai/gemini/` (conferido por `test/architecture_test.dart`).
library;

import 'dart:typed_data';

import 'direction_models.dart';
import 'extraction_contract.dart';

/// Quem fornece a IA e a idade mínima que os termos dele exigem (CA-R5).
class AiProviderInfo {
  const AiProviderInfo({required this.name, required this.minUserAge});

  /// Aparece nos termos e no aviso da IA (CA-R6).
  final String name;

  /// 18 no Gemini, pelos termos do Google.
  final int minUserAge;
}

/// Arquivo enviado à IA (print ou PDF).
class ImportFile {
  const ImportFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Motivo de uma chamada de IA ter falhado.
enum AiFailure {
  offline,
  quotaExhausted,
  appCheckDenied,
  tooLarge,
  blocked,
  malformed,
  disabled,
  timeout,
  unknown,
}

/// Erro lançado pelas portas de IA, com o motivo em [failure]. Quem chama o
/// captura com `on AiException`.
class AiException implements Exception {
  const AiException(this.failure);
  final AiFailure failure;

  @override
  String toString() => 'AiException: ${failure.name}';
}

/// Extrai questões de um arquivo. Lança [AiException].
abstract interface class QuestionExtractor {
  AiProviderInfo get provider;
  Future<ExtractionResult> extract(ImportFile file);
}

/// Propõe etapas de estudo. A resposta passa por `validateProposalJsonFor`
/// antes de chegar aqui. Lança [AiException].
abstract interface class StepProposer {
  AiProviderInfo get provider;
  Future<List<ProposedStep>> propose(DirectionContext context);
}
