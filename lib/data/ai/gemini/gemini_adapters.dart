import 'dart:convert';

import '../../../domain/access_policy.dart';
import '../../../domain/ai_ports.dart';
import '../../../domain/direction_models.dart';
import '../../../domain/direction_validation.dart';
import '../../../domain/extraction_contract.dart';
import 'ai_gateway.dart';
import 'ai_schemas.dart';

/// Google, pelos termos do Gemini: 18 anos (CA-R5).
const AiProviderInfo geminiProvider = AiProviderInfo(
  name: 'Google Gemini',
  minUserAge: 18,
);

/// Porta [QuestionExtractor] sobre o [AiGateway]. O contrato do domínio
/// (`parseExtraction`) valida a resposta; o que vier ilegível vira
/// `AiFailure.malformed`.
class GeminiQuestionExtractor implements QuestionExtractor {
  GeminiQuestionExtractor({
    required this.gateway,
    this.model = defaultAiModel,
    this.timeout = extractionTimeout,
  });

  final AiGateway gateway;
  final String model;
  final Duration timeout;

  @override
  AiProviderInfo get provider => geminiProvider;

  @override
  Future<ExtractionResult> extract(ImportFile file) async {
    final raw = await gateway.generateJson(
      call: AiCall.extraction,
      model: model,
      systemInstruction: extractionSystemInstruction,
      prompt: extractionPrompt,
      files: [file],
      responseSchema: extractionResponseSchema,
      timeout: timeout,
    );
    try {
      return parseExtraction(raw);
    } on MalformedExtractionException {
      throw const AiException(AiFailure.malformed);
    }
  }
}

/// Porta [StepProposer] sobre o [AiGateway]. Só o contexto agregado vai no
/// pedido (`DirectionContext.toJson`). Resposta fora da C.2 vira `malformed`,
/// e quem chama cai nas regras.
class GeminiStepProposer implements StepProposer {
  GeminiStepProposer({
    required this.gateway,
    this.model = defaultAiModel,
    this.timeout = proposalTimeout,
  });

  final AiGateway gateway;
  final String model;
  final Duration timeout;

  @override
  AiProviderInfo get provider => geminiProvider;

  @override
  Future<List<ProposedStep>> propose(DirectionContext context) async {
    final raw = await gateway.generateJson(
      call: AiCall.proposal,
      model: model,
      systemInstruction: proposalSystemInstruction,
      prompt: '$proposalPromptPrefix${jsonEncode(context.toJson())}',
      responseSchema: proposalResponseSchema,
      timeout: timeout,
    );
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const AiException(AiFailure.malformed);
    }
    final result = validateProposalJsonFor(context, decoded);
    if (!result.isValid) throw const AiException(AiFailure.malformed);
    return result.steps;
  }
}
