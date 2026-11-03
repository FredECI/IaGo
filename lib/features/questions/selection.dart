import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';

import '../../data/providers.dart';
import '../../domain/list_builder.dart';
import '../lists/lists_providers.dart';

/// Seleção de questões para montar uma lista (na ordem dos toques).
class QuestionSelection {
  const QuestionSelection({this.active = false, this.ids = const []});

  final bool active;
  final List<String> ids;

  bool contains(String id) => ids.contains(id);
}

final questionSelectionProvider =
    NotifierProvider<QuestionSelectionController, QuestionSelection>(
      QuestionSelectionController.new,
    );

class QuestionSelectionController extends Notifier<QuestionSelection> {
  @override
  QuestionSelection build() {
    ref.watch(sessionProvider);
    return const QuestionSelection();
  }

  /// Entra no modo seleção (opcionalmente já com uma questão marcada).
  void start([String? firstId]) {
    ref.read(listAssemblyTimerProvider.notifier).markStart();
    state = QuestionSelection(active: true, ids: [?firstId]);
  }

  void toggle(String id) {
    final ids = state.contains(id)
        ? removeId(state.ids, id)
        : [...state.ids, id];
    state = QuestionSelection(active: true, ids: ids);
  }

  void addAll(Iterable<String> ids) =>
      state = QuestionSelection(active: true, ids: appendIds(state.ids, ids));

  void exit() => state = const QuestionSelection();
}

/// Atalho "Montar lista": vai para Questões já no modo seleção.
void startListBuilding(BuildContext context, WidgetRef ref) {
  ref.read(questionSelectionProvider.notifier).start();
  context.go(Routes.questions);
}
