import '../domain/direction_models.dart';

/// Objetivo e etapas do Direciona do usuário atual (privados).
/// Implementações: memória (demo) e Firestore.
abstract interface class DirectionRepository {
  /// Objetivo atual; `null` se ainda não foi definido.
  Stream<StudyGoal?> watchGoal();

  /// Cria ou substitui o objetivo.
  Future<void> saveGoal(StudyGoal goal);

  /// Etapas, da mais próxima do prazo para a mais distante.
  Stream<List<StudyStep>> watchSteps();

  /// Grava etapas novas (o id da etapa é mantido).
  Future<void> addSteps(List<StudyStep> steps);

  /// Substitui a etapa de mesmo id (concluir, adiar, marcar como perdida). Id
  /// inexistente cria a etapa, nas duas implementações (upsert).
  Future<void> updateStep(StudyStep step);

  /// Vários `updateStep` numa escrita só (em lote), com a mesma regra de
  /// upsert.
  Future<void> updateSteps(List<StudyStep> steps);
}
