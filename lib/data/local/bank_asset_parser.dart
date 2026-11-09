import 'dart:convert';

import '../../domain/area.dart';
import '../../domain/bank_source.dart';
import '../../domain/question.dart';

/// Resultado da leitura do asset do acervo.
class BankData {
  const BankData({required this.sources, required this.questions});

  final List<BankSource> sources;
  final List<Question> questions;
}

const int supportedBankSchemaVersion = 1;

/// Lê o JSON do acervo e monta as cópias prontas para salvar: `id` com prefixo
/// `bank_`, `origin = bank` e `platform = "ENEM {year}"` (nome da fonte, sem o
/// parêntese). Aceita matéria ausente (vira vazia) e ignora campos
/// desconhecidos. Roda em isolate: já calcula o texto de busca de cada questão.
BankData parseBankAsset(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final version = root['schemaVersion'];
  if (version != supportedBankSchemaVersion) {
    throw FormatException('schemaVersion $version não suportado');
  }
  final sources = [
    for (final s in (root['sources'] as List? ?? const []))
      BankSource.fromMap((s as Map).cast<String, Object?>()),
  ];
  final byId = {for (final s in sources) s.id: s};
  final stamp =
      DateTime.tryParse(root['generatedAt'] as String? ?? '') ?? DateTime(2026);

  final questions = <Question>[];
  for (final raw in (root['questions'] as List? ?? const [])) {
    final m = (raw as Map).cast<String, Object?>();
    final id = m['id'] as String?;
    final area = Area.tryParse(m['area'] as String?);
    final statement = m['statement'] as String?;
    final source = byId[m['source']];
    if (id == null || area == null || statement == null || source == null) {
      continue;
    }
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
      platform: _platform(source, m['year']),
      sourceUrl: source.officialUrl.isEmpty ? null : source.officialUrl,
      createdAt: stamp,
      updatedAt: stamp,
      origin: QuestionOrigin.bank,
      bankId: id,
    );
    // Materializa os campos preguiçosos aqui, fora da thread da tela.
    q.searchText;
    q.topicKey;
    q.platformKey;
    questions.add(q);
  }
  return BankData(sources: sources, questions: questions);
}

String _platform(BankSource source, Object? year) {
  final label = source.name.split(' (').first.trim();
  return year == null ? label : '$label $year';
}
