/// IA simulada das portas, para a demo e os testes: sem rede e sem SDK.
library;

import '../../domain/ai_ports.dart';
import '../../domain/direction_models.dart';
import '../../domain/direction_planner.dart';
import '../../domain/extraction_contract.dart';

const AiProviderInfo fakeAiProvider = AiProviderInfo(
  name: 'IA simulada',
  minUserAge: 0,
);

const String _fakeExtractionJson = '''
{
  "schemaVersion": 1,
  "containsPersonalData": false,
  "questions": [
    {
      "statement": "Questão de exemplo: qual é o valor de 2 + 3?",
      "type": "objective",
      "alternatives": ["4", "5", "6", "7", "8"],
      "hasFigure": false,
      "isComplete": true,
      "page": 1,
      "suggestedArea": "mathematics",
      "suggestedSubject": "Matemática"
    },
    {
      "statement": "Questão de exemplo: explique com suas palavras o que é uma função.",
      "type": "discursive",
      "alternatives": [],
      "hasFigure": false,
      "isComplete": true,
      "page": 1,
      "suggestedArea": "mathematics",
      "suggestedSubject": "Matemática"
    }
  ]
}
''';

/// Devolve sempre o mesmo exemplo (passando pelo mesmo `parseExtraction` da
/// IA de verdade) ou, se [failure] vier, lança a falha pedida.
class FakeQuestionExtractor implements QuestionExtractor {
  FakeQuestionExtractor({
    this.provider = fakeAiProvider,
    this.failure,
    this.rawResponse = _fakeExtractionJson,
  });

  @override
  final AiProviderInfo provider;
  final AiFailure? failure;

  /// Texto JSON "do provedor"; os testes podem trocá-lo.
  final String rawResponse;
  int calls = 0;

  @override
  Future<ExtractionResult> extract(ImportFile file) async {
    calls++;
    if (failure case final f?) throw AiException(f);
    try {
      return parseExtraction(rawResponse);
    } on MalformedExtractionException {
      throw const AiException(AiFailure.malformed);
    }
  }
}

/// Propõe as etapas do planejador por regras (determinístico), ou lança
/// [failure].
class FakeStepProposer implements StepProposer {
  FakeStepProposer({this.provider = fakeAiProvider, this.failure});

  @override
  final AiProviderInfo provider;
  final AiFailure? failure;
  int calls = 0;

  @override
  Future<List<ProposedStep>> propose(DirectionContext context) async {
    calls++;
    if (failure case final f?) throw AiException(f);
    return planDirection(context);
  }
}
