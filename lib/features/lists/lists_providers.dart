import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../data/providers.dart';
import '../../domain/direction_models.dart';
import '../../domain/list_builder.dart';
import '../../domain/metric_event.dart';
import '../../domain/question.dart';
import '../../domain/question_list.dart';
import '../direction/direction_providers.dart';
import '../metrics/metrics_providers.dart';
import '../questions/questions_providers.dart';

/// Todas as listas do usuário atual, mais recentes primeiro.
final listsProvider = StreamProvider<List<QuestionList>>(
  (ref) => ref.watch(listRepositoryProvider).watchAll(),
);

/// Uma lista pelo id (`null` se não existir ou ainda não carregou).
final listByIdProvider = Provider.family<QuestionList?, String>((ref, id) {
  final lists = ref.watch(listsProvider).value;
  return lists?.firstWhereOrNull((l) => l.id == id);
});

/// Cronômetro da montagem de lista (H2: "tempo para montar uma lista").
/// Começa na primeira busca, filtro ou seleção e zera quando a lista é criada
/// ou quando o estudante limpa tudo.
final listAssemblyTimerProvider =
    NotifierProvider<ListAssemblyTimer, DateTime?>(ListAssemblyTimer.new);

class ListAssemblyTimer extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.watch(sessionProvider);
    return null;
  }

  void markStart() => state ??= ref.read(clockProvider)();

  void reset() => state = null;
}

/// Operações de lista usadas pelas telas.
final listActionsProvider = Provider<ListActions>(ListActions.new);

class ListActions {
  ListActions(this._ref);

  final Ref _ref;

  Future<QuestionList> create({
    required String name,
    required List<String> questionIds,
  }) async {
    final now = _ref.read(clockProvider)();
    final startedAt = _ref.read(listAssemblyTimerProvider) ?? now;
    final list = await _ref
        .read(listRepositoryProvider)
        .create(
          QuestionList(
            id: '',
            name: name.trim(),
            questionIds: questionIds,
            createdAt: now,
            updatedAt: now,
            assemblyStartedAt: startedAt,
          ),
        );
    _ref.read(listAssemblyTimerProvider.notifier).reset();
    _ref.read(metricsLoggerProvider).log(MetricEventType.listCreated, {
      'questionCount': list.length,
    });
    return list;
  }

  Future<void> rename(QuestionList list, String name) => _ref
      .read(listRepositoryProvider)
      .update(list.copyWith(name: name.trim()));

  Future<void> reorder(QuestionList list, int oldIndex, int newIndex) => _ref
      .read(listRepositoryProvider)
      .update(
        list.copyWith(
          questionIds: reorderIds(list.questionIds, oldIndex, newIndex),
        ),
      );

  Future<void> remove(QuestionList list, String questionId) => _ref
      .read(listRepositoryProvider)
      .update(
        list.copyWith(questionIds: removeId(list.questionIds, questionId)),
      );

  Future<void> add(QuestionList list, Iterable<String> questionIds) => _ref
      .read(listRepositoryProvider)
      .update(
        list.copyWith(questionIds: appendIds(list.questionIds, questionIds)),
      );

  Future<void> delete(QuestionList list) =>
      _ref.read(listRepositoryProvider).delete(list.id);

  /// Conta uma exportação (o PDF em si não é guardado em lugar nenhum). Na
  /// 1ª exportação, registra o tempo de montagem da lista (H2).
  Future<QuestionList> registerExport(QuestionList list) async {
    final now = _ref.read(clockProvider)();
    final startedAt = list.assemblyStartedAt;
    final assemblySeconds = list.exportCount == 0 && startedAt != null
        ? now.difference(startedAt).inSeconds
        : null;
    final saved = await _ref
        .read(listRepositoryProvider)
        .registerExport(list.id);
    final origin = _exportOrigin(list);
    _ref.read(metricsLoggerProvider).log(MetricEventType.listExported, {
      'questionCount': list.length,
      'exportIndex': list.exportCount + 1,
      'assemblySeconds': ?assemblySeconds,
      'bankQuestionCount': origin.bankCount,
      'hadAcceptedListStep': origin.hadAcceptedListStep,
    });
    return saved;
  }

  /// Quantas questões da lista vêm do acervo (H2) e se há uma etapa
  /// `buildList` aceita e pendente (H3). Só contagens, lidas do que já está
  /// carregado (sem esperar rede): se ainda não carregou, vale 0 e `false`.
  ({int bankCount, bool hadAcceptedListStep}) _exportOrigin(QuestionList list) {
    final questions = _ref.read(questionsProvider).value ?? const <Question>[];
    final ids = list.questionIds.toSet();
    final bankCount = questions
        .where((q) => ids.contains(q.id) && q.origin == QuestionOrigin.bank)
        .length;
    final steps = _ref.read(studyStepsProvider).value ?? const <StudyStep>[];
    final hadAcceptedListStep = steps.any(
      (s) =>
          s.action == StepAction.buildList && s.status == StepStatus.accepted,
    );
    return (bankCount: bankCount, hadAcceptedListStep: hadAcceptedListStep);
  }
}
