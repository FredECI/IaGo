import 'dart:typed_data';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/live_value.dart';
import '../../domain/question.dart';
import '../../domain/rating_models.dart';
import '../repositories.dart';

/// Questões em memória: usadas no modo demonstração (offline) e nos testes.
class MemoryQuestionRepository implements QuestionRepository {
  MemoryQuestionRepository({
    required this._clock,
    Iterable<Question> initial = const [],
    Map<String, Uint8List> images = const {},
  }) : _images = {...images},
       _store = LiveValue(_sorted(initial));

  final Clock _clock;
  final Map<String, Uint8List> _images;
  final LiveValue<List<Question>> _store;

  static List<Question> _sorted(Iterable<Question> items) =>
      List<Question>.unmodifiable(
        items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  /// Estado atual, para testes e para o seed.
  List<Question> get current => _store.value;

  @override
  Stream<List<Question>> watchAll() => _store.stream;

  @override
  Future<Question> create(Question question, {Uint8List? image}) async {
    final now = _clock();
    final saved = question.copyWith(
      id: newId(),
      createdAt: now,
      updatedAt: now,
      hasImage: image != null,
    );
    if (image != null) _images[saved.id] = image;
    _store.value = _sorted([..._store.value, saved]);
    return saved;
  }

  @override
  Future<List<Question>> createMany(List<Question> questions) async {
    if (questions.length > QuestionRepository.maxCreateMany) {
      throw ArgumentError.value(questions.length, 'questions', 'lote grande');
    }
    if (questions.isEmpty) return const [];
    final now = _clock();
    final saved = [
      for (final q in QuestionRepository.dedupeById(questions))
        q.copyWith(
          id: q.id.isEmpty ? newId() : q.id,
          createdAt: now,
          updatedAt: now,
          hasImage: false,
        ),
    ];
    final ids = {for (final q in saved) q.id};
    _store.value = _sorted([
      ..._store.value.where((q) => !ids.contains(q.id)),
      ...saved,
    ]);
    return saved;
  }

  @override
  Future<Question> update(
    Question question, {
    Uint8List? image,
    bool removeImage = false,
  }) async {
    final items = [..._store.value];
    final index = items.indexWhere((q) => q.id == question.id);
    if (index < 0) {
      throw StateError('Questão não encontrada: ${question.id}');
    }
    if (removeImage) _images.remove(question.id);
    if (image != null) _images[question.id] = image;
    final saved = question.copyWith(
      updatedAt: _clock(),
      hasImage: _images.containsKey(question.id),
    );
    items[index] = saved;
    _store.value = _sorted(items);
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    _images.remove(id);
    _store.value = List<Question>.unmodifiable(
      _store.value.where((q) => q.id != id),
    );
  }

  @override
  Future<void> setPrivateRating(
    String id, {
    int? difficulty,
    int? quality,
  }) async {
    if (difficulty != null && !isValidScore(difficulty) ||
        quality != null && !isValidScore(quality)) {
      throw const RatingFailure(
        RatingFailureKind.invalid,
        'A nota deve ser de 1 a 3.',
      );
    }
    final items = [..._store.value];
    final index = items.indexWhere((q) => q.id == id);
    if (index < 0) {
      throw const RatingFailure(
        RatingFailureKind.invalid,
        'Questão não encontrada.',
      );
    }
    // Sem tocar em updatedAt.
    items[index] = items[index].copyWith(
      myDifficulty: difficulty,
      myQuality: quality,
    );
    _store.value = _sorted(items);
  }

  @override
  Future<Uint8List?> loadImage(String questionId) async => _images[questionId];

  Future<void> dispose() => _store.close();
}
