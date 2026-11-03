import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/question_list.dart';

/// Todas as listas do usuário atual, mais recentes primeiro.
final listsProvider = StreamProvider<List<QuestionList>>(
  (ref) => ref.watch(listRepositoryProvider).watchAll(),
);

/// Uma lista pelo id (`null` se não existir ou ainda não carregou).
final listByIdProvider = Provider.family<QuestionList?, String>((ref, id) {
  final lists = ref.watch(listsProvider).value;
  return lists?.firstWhereOrNull((l) => l.id == id);
});
