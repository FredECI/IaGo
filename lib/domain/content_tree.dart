import '../core/text_normalizer.dart';
import 'area.dart';
import 'question.dart';

/// Acervo organizado por conteúdo: área → matéria → assunto, com contagens.
class AreaNode {
  const AreaNode({
    required this.area,
    required this.count,
    required this.subjects,
  });

  final Area area;
  final int count;
  final List<SubjectNode> subjects;
}

class SubjectNode {
  const SubjectNode({
    required this.subject,
    required this.count,
    required this.topics,
    required this.untagged,
  });

  final String subject;
  final int count;

  /// Assuntos do mais frequente ao menos.
  final List<TopicNode> topics;

  /// Questões da matéria sem assunto.
  final int untagged;
}

class TopicNode {
  const TopicNode({
    required this.key,
    required this.label,
    required this.count,
  });

  /// [tagKey] do assunto (o mesmo usado no filtro).
  final String key;
  final String label;
  final int count;
}

/// Monta a árvore. As quatro áreas sempre aparecem (na ordem do catálogo);
/// matérias só quando têm questões, na ordem do catálogo da área.
List<AreaNode> buildContentTree(Iterable<Question> questions) {
  final byArea = <Area, List<Question>>{};
  for (final q in questions) {
    byArea.putIfAbsent(q.area, () => []).add(q);
  }
  return [
    for (final area in Area.values)
      AreaNode(
        area: area,
        count: byArea[area]?.length ?? 0,
        subjects: _subjects(area, byArea[area] ?? const []),
      ),
  ];
}

List<SubjectNode> _subjects(Area area, List<Question> questions) {
  final bySubject = <String, List<Question>>{};
  for (final q in questions) {
    bySubject.putIfAbsent(q.subject, () => []).add(q);
  }
  final ordered = [
    ...area.subjects.where(bySubject.containsKey),
    // Matérias fora do catálogo (dados antigos) vão para o fim.
    ...bySubject.keys.where((s) => !area.subjects.contains(s)),
  ];
  return [
    for (final subject in ordered) _subjectNode(subject, bySubject[subject]!),
  ];
}

SubjectNode _subjectNode(String subject, List<Question> questions) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  var untagged = 0;
  for (final q in questions) {
    final key = tagKey(q.topic);
    if (key.isEmpty) {
      untagged++;
      continue;
    }
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    labels.putIfAbsent(key, () => q.topic.trim());
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : labels[a]!.compareTo(labels[b]!);
    });
  return SubjectNode(
    subject: subject,
    count: questions.length,
    untagged: untagged,
    topics: [
      for (final key in keys)
        TopicNode(key: key, label: labels[key]!, count: counts[key]!),
    ],
  );
}
