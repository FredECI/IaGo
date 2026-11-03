/// Regras puras de montagem de listas (testáveis sem tela).
library;

import 'package:intl/intl.dart';

import 'question.dart';

/// Move o item de [oldIndex] para [newIndex], já como posição final (a
/// convenção do `onReorderItem` do `ReorderableListView`).
List<String> reorderIds(List<String> ids, int oldIndex, int newIndex) {
  final result = [...ids];
  if (oldIndex < 0 || oldIndex >= result.length) return result;
  final moved = result.removeAt(oldIndex);
  result.insert(newIndex.clamp(0, result.length), moved);
  return result;
}

/// Acrescenta ids ao fim, sem repetir os que já estão na lista.
List<String> appendIds(List<String> ids, Iterable<String> extra) {
  final seen = {...ids};
  return [
    ...ids,
    for (final id in extra)
      if (seen.add(id)) id,
  ];
}

/// Tira um id da lista.
List<String> removeId(List<String> ids, String id) => [
  for (final existing in ids)
    if (existing != id) existing,
];

/// Resolve os ids em questões, na ordem da lista, ignorando as excluídas.
List<Question> resolveQuestions(
  List<String> ids,
  Iterable<Question> questions,
) {
  final byId = {for (final q in questions) q.id: q};
  return [for (final id in ids) ?byId[id]];
}

/// Composição da lista: "10 questões · 8 objetivas e 2 discursivas".
String describeComposition(List<Question> questions) {
  final total = questions.length;
  final objective = questions.where((q) => q.isObjective).length;
  final discursive = total - objective;
  final head = '$total ${total == 1 ? 'questão' : 'questões'}';
  if (total == 0) return head;
  if (discursive == 0) return '$head · todas objetivas';
  if (objective == 0) return '$head · todas discursivas';
  final obj = '$objective ${objective == 1 ? 'objetiva' : 'objetivas'}';
  final dis = '$discursive ${discursive == 1 ? 'discursiva' : 'discursivas'}';
  return '$head · $obj e $dis';
}

/// Nome sugerido para uma lista nova (o usuário troca na hora).
String suggestListName(DateTime now) =>
    'Lista de ${DateFormat('dd/MM', 'pt_BR').format(now)}';

/// Nome de arquivo seguro para o PDF ("Reforço — Funções" vira
/// "Reforço - Funções.pdf").
String pdfFileName(String listName) {
  final cleaned = listName
      .replaceAll(RegExp(r'[—–]'), '-')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${cleaned.isEmpty ? 'lista' : cleaned}.pdf';
}
