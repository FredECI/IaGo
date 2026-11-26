import 'dart:convert';

import 'area.dart';
import 'direction_models.dart';
import 'question.dart';

/// Sugestão de lista do acervo para as etapas do Direciona. Dart puro,
/// determinístico e igual em todas as plataformas.

/// Faixa-alvo de dificuldade (1 a 3) a partir do histórico de etapas.
///
/// 1 se errou mais do que fez; 3 se fez 3 ou mais e não errou nenhuma;
/// 2 nos outros casos.
int targetDifficulty(DirectionHistory history) {
  if (history.missedLast14d > history.doneLast14d) return 1;
  if (history.doneLast14d >= 3 && history.missedLast14d == 0) return 3;
  return 2;
}

/// Questões do acervo da matéria que ainda estão disponíveis: o total do
/// catálogo menos as cópias já salvas, com mínimo de 0.
int bankAvailableFor({required int inCatalog, required int savedCopies}) {
  final value = inCatalog - savedCopies;
  return value < 0 ? 0 : value;
}

/// Liga o planejador ao acervo sem depender do `BankSummary`: [available]
/// devolve a contagem do catálogo por matéria (por exemplo,
/// `summary.available`) e [savedBankCopies] as cópias do acervo já salvas,
/// por matéria. Mantém as matérias de [coverage] e acrescenta as que só
/// existem no acervo. Matéria sem nada continua fora da lista.
List<SubjectCoverage> withBankAvailability(
  Iterable<SubjectCoverage> coverage, {
  required int Function(String subject) available,
  Map<String, int> savedBankCopies = const {},
}) {
  final out = <SubjectCoverage>[];
  final seen = <String>{};
  int bankOf(String subject) => bankAvailableFor(
    inCatalog: available(subject),
    savedCopies: savedBankCopies[subject] ?? 0,
  );
  for (final c in coverage) {
    seen.add('${c.area.name}|${c.subject}');
    out.add(
      SubjectCoverage(
        area: c.area,
        subject: c.subject,
        saved: c.saved,
        savedLast14d: c.savedLast14d,
        listsExportedLast14d: c.listsExportedLast14d,
        bankAvailable: bankOf(c.subject),
      ),
    );
  }
  for (final area in Area.values) {
    for (final subject in area.subjects) {
      if (seen.contains('${area.name}|$subject')) continue;
      final b = bankOf(subject);
      if (b > 0) {
        out.add(
          SubjectCoverage(area: area, subject: subject, bankAvailable: b),
        );
      }
    }
  }
  return out;
}

/// FNV-1a de 32 bits sobre os bytes UTF-8.
int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    // hash * 0x01000193 (mod 2^32) sem passar de 2^53, para dar o mesmo
    // resultado na web (inteiros de JS).
    hash = (hash * 0x193 + ((hash & 0xff) << 24)) & 0xffffffff;
  }
  return hash;
}

/// Até [count] ids (`bankId`) do acervo, os mesmos para a mesma entrada.
///
/// Ordem: distância da faixa ([targetBand]; sem faixa na questão conta 1; sem
/// alvo, todas empatam), depois rodízio de assuntos (primeiro o assunto com
/// menos escolhidas, desempatando pela [topicOrder]; assunto fora da ordem
/// depois dos conhecidos e "sem assunto" por último) e, por fim, FNV-1a de
/// `seed + bankId`.
List<String> suggestBankQuestions({
  required List<Question> candidates,
  required Set<String> excludeBankIds,
  required int count,
  required String seed,
  int? targetBand,
  int? Function(Question q)? difficultyOf,
  List<String> topicOrder = const [],
}) {
  if (count <= 0) return const [];
  final pool = <_Cand>[];
  final seenIds = <String>{};
  for (final q in candidates) {
    final id = q.bankId;
    if (id == null || excludeBankIds.contains(id) || !seenIds.add(id)) continue;
    final band = difficultyOf?.call(q);
    final distance = targetBand == null
        ? 0
        : (band == null ? 1 : (band - targetBand).abs());
    final topic = q.topic.trim();
    final known = topicOrder.indexOf(topic);
    final topicIndex = topic.isEmpty
        ? topicOrder.length + 1
        : (known < 0 ? topicOrder.length : known);
    pool.add(_Cand(id, distance, topic, topicIndex, fnv1a32('$seed$id')));
  }

  final picked = <String>[];
  final perTopic = <String, int>{};
  while (picked.length < count && pool.isNotEmpty) {
    var best = pool.first;
    for (final c in pool.skip(1)) {
      if (_compare(c, best, perTopic) < 0) best = c;
    }
    pool.remove(best);
    picked.add(best.id);
    perTopic[best.topic] = (perTopic[best.topic] ?? 0) + 1;
  }
  return picked;
}

int _compare(_Cand a, _Cand b, Map<String, int> perTopic) {
  var r = a.distance.compareTo(b.distance);
  if (r != 0) return r;
  // "Sem assunto" (índice maior) só entra quando os demais já têm o mesmo
  // número de escolhas e nenhum conhecido sobrou antes dele.
  r = (perTopic[a.topic] ?? 0).compareTo(perTopic[b.topic] ?? 0);
  if (r != 0) return r;
  r = a.topicIndex.compareTo(b.topicIndex);
  if (r != 0) return r;
  r = a.hash.compareTo(b.hash);
  if (r != 0) return r;
  return a.id.compareTo(b.id);
}

class _Cand {
  _Cand(this.id, this.distance, this.topic, this.topicIndex, this.hash);
  final String id;
  final int distance;
  final String topic;
  final int topicIndex;
  final int hash;
}
