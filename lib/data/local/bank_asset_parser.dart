import 'dart:convert';

import '../../domain/area.dart';
import '../../domain/bank_source.dart';
import '../../domain/bank_summary.dart';
import '../../domain/question.dart';

/// Resultado da leitura do asset do acervo.
class BankData {
  const BankData({
    required this.sources,
    required this.questions,
    this.taxonomy = const {},
    this.generatedAt = '',
  });

  final List<BankSource> sources;
  final List<Question> questions;

  /// Matéria -> assuntos (vem do índice v2; vazio no v1).
  final Map<String, List<String>> taxonomy;

  /// AAAA-MM-DD, como no asset (vazio se desconhecida).
  final String generatedAt;
}

/// Formato antigo: um arquivo só.
const int supportedBankSchemaVersion = 1;

/// Formato v2: índice mais uma parte por área.
const int supportedBankSchemaVersionV2 = 2;

/// Rótulo da variante da prova no `platform` ("ENEM PPL 2024").
const Map<String, String> bankVariantLabels = {
  'ppl': 'PPL',
  'reaplicacao': 'Reaplicação',
};

/// Lê o JSON do acervo (v1) e monta as cópias prontas para salvar: `id` com
/// prefixo `bank_`, `origin = bank` e `platform = "ENEM {year}"` (nome da
/// fonte, sem o parêntese). Aceita matéria ausente (vira vazia) e ignora campos
/// desconhecidos. Roda em isolate: já calcula o texto de busca de cada questão.
BankData parseBankAsset(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final version = root['schemaVersion'];
  if (version != supportedBankSchemaVersion) {
    throw FormatException('schemaVersion $version não suportado');
  }
  final sources = _sourcesOf(root);
  return BankData(
    sources: sources,
    questions: _questionsOf(root['questions'], sources, _stampOf(root)),
    generatedAt: root['generatedAt'] as String? ?? '',
  );
}

/// Uma parte do índice v2.
class BankShardRef {
  const BankShardRef({
    required this.area,
    required this.path,
    required this.count,
  });

  final Area area;
  final String path;
  final int count;
}

/// Índice v2: fontes, taxonomia, partes e contagens (poucos KB).
class BankIndex {
  const BankIndex({
    required this.sources,
    required this.summary,
    required this.shards,
    required this.generatedAt,
  });

  final List<BankSource> sources;
  final BankSummary summary;
  final List<BankShardRef> shards;

  /// Data de geração (ou 2026, se o índice não a traz). Carimbo das cópias.
  final DateTime generatedAt;
}

/// Lê o `index.json` do v2. Ignora campos desconhecidos (CA-R3).
BankIndex parseBankIndex(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final version = root['schemaVersion'];
  if (version != supportedBankSchemaVersionV2) {
    throw FormatException('schemaVersion $version não suportado');
  }
  final taxonomy = <String, List<String>>{
    for (final e in ((root['taxonomy'] as Map?) ?? const {}).entries)
      e.key as String: [
        for (final t in (e.value as List? ?? const []))
          if (t is String) t,
      ],
  };
  final counts = <BankCount>[];
  for (final raw in (root['counts'] as List? ?? const [])) {
    final m = (raw as Map).cast<String, Object?>();
    final area = Area.tryParse(m['area'] as String?);
    final subject = m['subject'] as String?;
    final count = (m['count'] as num?)?.toInt();
    if (area == null || subject == null || count == null) continue;
    counts.add(
      BankCount(
        area: area,
        subject: subject,
        difficulty: (m['difficulty'] as num?)?.toInt(),
        count: count,
      ),
    );
  }
  final shards = <BankShardRef>[];
  for (final raw in (root['shards'] as List? ?? const [])) {
    final m = (raw as Map).cast<String, Object?>();
    final area = Area.tryParse(m['area'] as String?);
    final path = m['path'] as String?;
    if (area == null || path == null) continue;
    shards.add(
      BankShardRef(
        area: area,
        path: path,
        count: (m['count'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return BankIndex(
    sources: _sourcesOf(root),
    summary: BankSummary(
      generatedAt: root['generatedAt'] as String? ?? '',
      counts: counts,
      taxonomy: taxonomy,
    ),
    shards: shards,
    generatedAt: _stampOf(root),
  );
}

/// Entrada de [parseBankShard] (um único argumento, para rodar em isolate).
class BankShardInput {
  const BankShardInput({
    required this.json,
    required this.sources,
    required this.generatedAt,
  });

  final String json;
  final List<BankSource> sources;
  final DateTime generatedAt;
}

/// Lê uma parte do v2 (`{área}.json`) e monta as cópias, como o v1. Questão
/// inválida ou de fonte não registrada é pulada.
List<Question> parseBankShard(BankShardInput input) {
  final root = jsonDecode(input.json) as Map<String, Object?>;
  final version = root['schemaVersion'];
  if (version != supportedBankSchemaVersionV2) {
    throw FormatException('schemaVersion $version não suportado');
  }
  return _questionsOf(root['questions'], input.sources, input.generatedAt);
}

List<BankSource> _sourcesOf(Map<String, Object?> root) => [
  for (final s in (root['sources'] as List? ?? const []))
    BankSource.fromMap((s as Map).cast<String, Object?>()),
];

DateTime _stampOf(Map<String, Object?> root) =>
    DateTime.tryParse(root['generatedAt'] as String? ?? '') ?? DateTime(2026);

List<Question> _questionsOf(
  Object? rawQuestions,
  List<BankSource> sources,
  DateTime stamp,
) {
  final byId = {for (final s in sources) s.id: s};
  final questions = <Question>[];
  for (final raw in (rawQuestions as List? ?? const [])) {
    final m = (raw as Map).cast<String, Object?>();
    final id = m['id'] as String?;
    final area = Area.tryParse(m['area'] as String?);
    final statement = m['statement'] as String?;
    final source = byId[m['source']];
    if (id == null || area == null || statement == null || source == null) {
      continue;
    }
    final classifiedBy = m['classifiedBy'];
    final difficulty = (m['difficulty'] as num?)?.toInt();
    final q = Question(
      id: 'bank_$id',
      statement: statement,
      type: QuestionType.objective,
      alternatives:
          (m['alternatives'] as List?)?.whereType<String>().toList() ??
          const [],
      area: area,
      subject: m['subject'] as String? ?? '',
      topic: m['topic'] as String? ?? '',
      platform: _platform(source, m['variant'], m['year']),
      sourceUrl: source.officialUrl.isEmpty ? null : source.officialUrl,
      createdAt: stamp,
      updatedAt: stamp,
      origin: QuestionOrigin.bank,
      bankId: id,
      bankDifficulty: difficulty != null && difficulty >= 1 && difficulty <= 3
          ? difficulty
          : null,
      autoClassified: classifiedBy == 'agent' || classifiedBy == 'model',
    );
    // Materializa os campos preguiçosos aqui, fora da thread da tela.
    q.searchText;
    q.topicKey;
    q.platformKey;
    questions.add(q);
  }
  return questions;
}

/// "{nome curto da fonte}{ variante}{ ano}": "ENEM PPL 2024".
String _platform(BankSource source, Object? variant, Object? year) {
  final label = [
    source.name.split(' (').first.trim(),
    if (variant is String && variant.isNotEmpty)
      bankVariantLabels[variant] ?? variant,
    if (year != null) '$year',
  ];
  return label.join(' ');
}
