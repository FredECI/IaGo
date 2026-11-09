/// Modelos e regras puras da importação em lote (sem widgets).
library;

import '../../domain/access_policy.dart';
import '../../domain/ai_ports.dart';
import '../../domain/area.dart';
import '../../domain/extraction_contract.dart';
import '../../domain/paste_parser.dart';
import '../../domain/question.dart';

/// Quantas questões cabem num lote (CA-R7). É o mesmo teto do contrato.
const int maxImportQuestions = maxExtractedQuestions;

/// Quantos arquivos por vez (CA-R7).
const int maxImportFiles = 5;

/// Tamanho máximo de cada arquivo, em bytes (CA-R7).
const int maxImportFileBytes = 10 * 1024 * 1024;

/// Tipos aceitos (CA-I13).
const Set<String> importMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
  'application/pdf',
};

/// Versão do aviso de privacidade da IA (CA-R6). Mudar o texto do aviso
/// exige subir esta versão.
const String aiNoticeVersion = '2026-11-09';

/// Quando a cota diária volta, como a spec informa ao usuário (CA-I6).
const String importQuotaResetHint = 'por volta das 5h';

/// Quanto a IA está disponível nesta tela.
enum ImportAiMode {
  /// Esconde o caminho de arquivos e explica.
  unavailable,

  /// Demonstração: "exemplo simulado", nada sai do aparelho.
  simulated,

  /// Conta de membro com a IA ligada.
  real,
}

/// Decide o modo da IA. Demo usa o extrator simulado sem passar pela
/// política; conta real exige extrator e `canUseAi`.
ImportAiMode resolveImportAiMode({
  required bool isDemo,
  required QuestionExtractor? extractor,
  required AccessPolicy policy,
  required bool isMember,
}) {
  if (extractor == null) return ImportAiMode.unavailable;
  if (isDemo) return ImportAiMode.simulated;
  return policy.canUseAi(isMember: isMember, provider: extractor.provider)
      ? ImportAiMode.real
      : ImportAiMode.unavailable;
}

/// Mensagem de cada falha da IA, conforme a tabela da spec.
String aiFailureMessage(AiFailure failure) => switch (failure) {
  AiFailure.offline => 'Sem conexão. Use a colagem ou tente depois.',
  AiFailure.quotaExhausted =>
    'A cota de IA de hoje acabou. Ela volta $importQuotaResetHint. '
        'A colagem funciona agora.',
  AiFailure.appCheckDenied => 'Não foi possível validar este aparelho.',
  AiFailure.tooLarge => 'Arquivo grande demais. Envie menos páginas.',
  AiFailure.blocked => 'A IA não processou este arquivo.',
  AiFailure.malformed => 'A resposta da IA veio ilegível. Tente de novo.',
  AiFailure.disabled =>
    'A IA está desligada no momento. A colagem continua disponível.',
  AiFailure.timeout => 'A IA demorou demais. Tente de novo.',
  AiFailure.unknown =>
    'Não foi possível processar este arquivo. Tente de novo.',
};

String _mimeOf(ImportFile file) {
  final mime = file.mimeType.toLowerCase();
  if (importMimeTypes.contains(mime)) return mime;
  final name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.pdf')) return 'application/pdf';
  return mime;
}

/// Resultado da checagem de arquivos escolhidos, feita sem rede (CA-I13).
class FileCheck {
  const FileCheck(this.accepted, this.refusals);
  final List<ImportFile> accepted;

  /// Uma frase por arquivo recusado.
  final List<String> refusals;
}

/// Confere tipo, tamanho e quantidade. [alreadyChosen] conta no limite.
FileCheck checkImportFiles(List<ImportFile> picked, {int alreadyChosen = 0}) {
  final accepted = <ImportFile>[];
  final refusals = <String>[];
  for (final file in picked) {
    final mime = _mimeOf(file);
    if (!importMimeTypes.contains(mime)) {
      refusals.add('${file.name}: só aceitamos PNG, JPEG, WebP e PDF.');
    } else if (file.bytes.length > maxImportFileBytes) {
      refusals.add(
        '${file.name}: maior que ${maxImportFileBytes ~/ (1024 * 1024)} MB.',
      );
    } else if (alreadyChosen + accepted.length >= maxImportFiles) {
      refusals.add(
        '${file.name}: o limite é $maxImportFiles arquivos por vez.',
      );
    } else {
      accepted.add(
        ImportFile(name: file.name, mimeType: mime, bytes: file.bytes),
      );
    }
  }
  return FileCheck(accepted, refusals);
}

/// Estado de um arquivo na fila de extração.
enum FileJobStatus { pending, running, done, failed }

class FileJob {
  FileJob(this.file);

  final ImportFile file;
  FileJobStatus status = FileJobStatus.pending;
  AiFailure? failure;
  int extracted = 0;

  /// Avisos do lote deste arquivo (por exemplo, "Aproveitamos 3 questões").
  List<String> notes = const [];
}

/// Rascunho de questão na revisão. Mutável: a tela edita direto.
class ImportDraft {
  ImportDraft({
    required this.id,
    this.statement = '',
    this.type = QuestionType.objective,
    List<String> alternatives = const [],
    this.area,
    this.subject,
    this.platform = '',
    this.warnings = const [],
    this.selected = true,
  }) : alternatives = [
         for (var i = 0; i < Question.letters.length; i++)
           i < alternatives.length ? alternatives[i] : '',
       ];

  final int id;
  String statement;
  QuestionType type;

  /// Sempre com 5 posições (A a E); as vazias não são salvas.
  final List<String> alternatives;
  Area? area;
  String? subject;
  String platform;
  List<String> warnings;
  bool selected;
  bool expanded = false;

  factory ImportDraft.fromPasted(int id, PastedQuestion pasted) {
    final warnings = <String>[
      if (pasted.statement.trim().isEmpty)
        'Não achamos o enunciado. Confira antes de salvar.',
    ];
    return ImportDraft(
      id: id,
      statement: pasted.statement,
      type: pasted.hasAlternatives
          ? QuestionType.objective
          : QuestionType.discursive,
      alternatives: pasted.alternatives.take(5).toList(),
      warnings: warnings,
      selected: warnings.isEmpty,
    );
  }

  factory ImportDraft.fromExtracted(int id, ExtractedQuestion q) {
    final warnings = <String>[
      if (q.hasFigure)
        'Depende de figura, gráfico ou tabela que não foi copiado.',
      if (!q.isComplete) 'A questão pode estar cortada.',
      ...q.warnings,
    ];
    return ImportDraft(
      id: id,
      statement: q.statement,
      type: q.type,
      alternatives: q.alternatives.take(5).toList(),
      area: q.suggestedArea,
      subject: q.suggestedSubject ?? q.suggestedArea?.defaultSubject,
      warnings: warnings,
      selected: q.selectedByDefault,
    );
  }

  List<String> get filledAlternatives => [
    for (final a in alternatives)
      if (a.trim().isNotEmpty) a.trim(),
  ];

  /// O que impede de salvar. Vazio = pronta.
  List<String> get problems => [
    if (statement.trim().isEmpty) 'Falta o enunciado.',
    if (type == QuestionType.objective && filledAlternatives.length < 2)
      'Preencha pelo menos duas alternativas.',
    if (area == null) 'Escolha a área.',
    if (area != null && subject == null) 'Escolha a matéria.',
    if (platform.trim().isEmpty) 'Informe a plataforma de origem.',
  ];

  Question toQuestion(DateTime now) => Question(
    id: '',
    statement: statement.trim(),
    type: type,
    alternatives: type == QuestionType.objective
        ? filledAlternatives
        : const [],
    area: area!,
    subject: subject!,
    platform: platform.trim(),
    createdAt: now,
    updatedAt: now,
    origin: QuestionOrigin.import,
  );
}
