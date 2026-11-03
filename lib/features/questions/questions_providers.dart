import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/question.dart';

/// Todas as questões do usuário atual, mais recentes primeiro.
final questionsProvider = StreamProvider<List<Question>>(
  (ref) => ref.watch(questionRepositoryProvider).watchAll(),
);

/// Uma questão pelo id (`null` se não existir ou ainda não carregou).
final questionByIdProvider = Provider.family<Question?, String>((ref, id) {
  final questions = ref.watch(questionsProvider).value;
  return questions?.firstWhereOrNull((q) => q.id == id);
});
