/// Sugestões de autocompletar a partir do que o próprio usuário já usou.
library;

import '../core/text_normalizer.dart';
import 'question.dart';

/// Plataformas comuns, oferecidas enquanto o usuário ainda não tem as suas.
const List<String> defaultPlatforms = [
  'Site de questões',
  'App de simulados',
  'Apostila do cursinho',
  'Livro didático',
  'Canal de vídeo',
  'Lista do professor',
  'Prova antiga',
];

/// Assuntos já usados, do mais frequente ao menos. [subject] restringe à
/// matéria (as sugestões de "Funções" só aparecem em Matemática).
List<String> usedTopics(Iterable<Question> questions, {String? subject}) =>
    _ranked([
      for (final q in questions)
        if (subject == null || q.subject == subject) q.topic,
    ]);

/// Plataformas já usadas (mais frequentes primeiro), completadas com as comuns.
List<String> usedPlatforms(Iterable<Question> questions) {
  final used = _ranked([for (final q in questions) q.platform]);
  final keys = {for (final p in used) tagKey(p)};
  return [...used, ...defaultPlatforms.where((p) => !keys.contains(tagKey(p)))];
}

/// Filtra as opções pelo que já foi digitado (sem acentos), sem repetir o
/// texto que já está no campo.
List<String> matchSuggestions(
  List<String> options,
  String typed, {
  int limit = 6,
}) {
  final key = tagKey(typed);
  return options
      .where((option) {
        final optionKey = tagKey(option);
        return optionKey != key && (key.isEmpty || optionKey.contains(key));
      })
      .take(limit)
      .toList();
}

List<String> _ranked(Iterable<String> values) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final value in values) {
    final label = value.trim();
    final key = tagKey(label);
    if (key.isEmpty) continue;
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    labels.putIfAbsent(key, () => label);
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : labels[a]!.compareTo(labels[b]!);
    });
  return [for (final key in keys) labels[key]!];
}
