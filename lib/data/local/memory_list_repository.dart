import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/live_value.dart';
import '../../domain/question_list.dart';
import '../repositories.dart';

/// Listas em memória: usadas no modo demonstração (offline) e nos testes.
class MemoryListRepository implements ListRepository {
  MemoryListRepository({
    required this._clock,
    Iterable<QuestionList> initial = const [],
  }) : _store = LiveValue(_sorted(initial));

  final Clock _clock;
  final LiveValue<List<QuestionList>> _store;

  static List<QuestionList> _sorted(Iterable<QuestionList> items) =>
      List<QuestionList>.unmodifiable(
        items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  List<QuestionList> get current => _store.value;

  @override
  Stream<List<QuestionList>> watchAll() => _store.stream;

  @override
  Future<QuestionList> create(QuestionList list) async {
    final now = _clock();
    final saved = list.copyWith(id: newId(), createdAt: now, updatedAt: now);
    _store.value = _sorted([..._store.value, saved]);
    return saved;
  }

  @override
  Future<QuestionList> update(QuestionList list) async {
    final saved = list.copyWith(updatedAt: _clock());
    _replace(saved);
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    _store.value = List<QuestionList>.unmodifiable(
      _store.value.where((l) => l.id != id),
    );
  }

  @override
  Future<QuestionList> registerExport(String id) async {
    final list = _store.value.firstWhere(
      (l) => l.id == id,
      orElse: () => throw StateError('Lista não encontrada: $id'),
    );
    final saved = list.copyWith(
      exportCount: list.exportCount + 1,
      lastExportedAt: _clock(),
    );
    _replace(saved);
    return saved;
  }

  @override
  Future<void> removeQuestion(String questionId) async {
    final now = _clock();
    _store.value = _sorted([
      for (final list in _store.value)
        list.questionIds.contains(questionId)
            ? list.copyWith(
                questionIds: [
                  for (final id in list.questionIds)
                    if (id != questionId) id,
                ],
                updatedAt: now,
              )
            : list,
    ]);
  }

  void _replace(QuestionList saved) {
    final items = [..._store.value];
    final index = items.indexWhere((l) => l.id == saved.id);
    if (index < 0) throw StateError('Lista não encontrada: ${saved.id}');
    items[index] = saved;
    _store.value = _sorted(items);
  }

  Future<void> dispose() => _store.close();
}
