import '../../core/live_value.dart';
import '../../domain/direction_models.dart';
import '../direction_repository.dart';

/// Direciona em memória: modo demonstração (offline) e testes.
class MemoryDirectionRepository implements DirectionRepository {
  MemoryDirectionRepository({
    StudyGoal? goal,
    Iterable<StudyStep> steps = const [],
  }) : _goal = LiveValue(goal),
       _steps = LiveValue(_sorted(steps));

  final LiveValue<StudyGoal?> _goal;
  final LiveValue<List<StudyStep>> _steps;

  static List<StudyStep> _sorted(Iterable<StudyStep> items) =>
      List<StudyStep>.unmodifiable(
        items.toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt)),
      );

  StudyGoal? get currentGoal => _goal.value;
  List<StudyStep> get currentSteps => _steps.value;

  @override
  Stream<StudyGoal?> watchGoal() => _goal.stream;

  @override
  Future<void> saveGoal(StudyGoal goal) async => _goal.value = goal;

  @override
  Stream<List<StudyStep>> watchSteps() => _steps.stream;

  @override
  Future<void> addSteps(List<StudyStep> steps) async {
    final ids = {for (final s in steps) s.id};
    _steps.value = _sorted([
      for (final s in _steps.value)
        if (!ids.contains(s.id)) s,
      ...steps,
    ]);
  }

  /// Grava a etapa; se o id não existir, cria (igual ao `set` do Firestore).
  @override
  Future<void> updateStep(StudyStep step) => updateSteps([step]);

  @override
  Future<void> updateSteps(List<StudyStep> steps) async {
    final items = [..._steps.value];
    for (final step in steps) {
      final index = items.indexWhere((s) => s.id == step.id);
      if (index < 0) {
        items.add(step);
      } else {
        items[index] = step;
      }
    }
    _steps.value = _sorted(items);
  }

  Future<void> dispose() async {
    await _goal.close();
    await _steps.close();
  }
}
