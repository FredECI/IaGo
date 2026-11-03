import 'package:collection/collection.dart';

const Object _unset = Object();
const ListEquality<String> _listEquality = ListEquality<String>();

/// Lista de questões montada pelo estudante (para estudar ou levar ao reforço).
///
/// Guarda só a ordem dos ids; o PDF é gerado na hora e não fica no servidor.
class QuestionList {
  QuestionList({
    required this.id,
    required this.name,
    List<String> questionIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.exportCount = 0,
    this.lastExportedAt,
  }) : questionIds = List.unmodifiable(questionIds);

  final String id;
  final String name;
  final List<String> questionIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int exportCount;
  final DateTime? lastExportedAt;

  int get length => questionIds.length;

  QuestionList copyWith({
    String? id,
    String? name,
    List<String>? questionIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? exportCount,
    Object? lastExportedAt = _unset,
  }) {
    return QuestionList(
      id: id ?? this.id,
      name: name ?? this.name,
      questionIds: questionIds ?? this.questionIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      exportCount: exportCount ?? this.exportCount,
      lastExportedAt: identical(lastExportedAt, _unset)
          ? this.lastExportedAt
          : lastExportedAt as DateTime?,
    );
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'questionIds': questionIds,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'exportCount': exportCount,
    'lastExportedAt': lastExportedAt,
  };

  factory QuestionList.fromMap(String id, Map<String, Object?> map) {
    final created = map['createdAt'] as DateTime? ?? DateTime(2026);
    return QuestionList(
      id: id,
      name: map['name'] as String? ?? 'Lista',
      questionIds:
          (map['questionIds'] as List?)?.whereType<String>().toList() ??
          const [],
      createdAt: created,
      updatedAt: map['updatedAt'] as DateTime? ?? created,
      exportCount: (map['exportCount'] as num?)?.toInt() ?? 0,
      lastExportedAt: map['lastExportedAt'] as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionList &&
          other.id == id &&
          other.name == name &&
          _listEquality.equals(other.questionIds, questionIds) &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.exportCount == exportCount &&
          other.lastExportedAt == lastExportedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    _listEquality.hash(questionIds),
    createdAt,
    updatedAt,
    exportCount,
    lastExportedAt,
  );

  @override
  String toString() => 'QuestionList($id, $name, ${questionIds.length})';
}
