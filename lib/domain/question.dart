import 'package:collection/collection.dart';

import '../core/text_normalizer.dart';
import 'area.dart';

enum QuestionType {
  objective('Objetiva', 'Objetivas'),
  discursive('Discursiva', 'Discursivas');

  const QuestionType(this.label, this.pluralLabel);

  final String label;
  final String pluralLabel;

  static QuestionType? tryParse(String? name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

const Object _unset = Object();
const ListEquality<String> _listEquality = ListEquality<String>();

/// Questão salva pelo estudante, vinda de qualquer plataforma.
///
/// O IaGo não guarda gabarito: só enunciado, alternativas, categoria e origem.
class Question {
  Question({
    required this.id,
    required this.statement,
    required this.type,
    List<String> alternatives = const [],
    required this.area,
    required this.subject,
    this.topic = '',
    required this.platform,
    this.sourceUrl,
    this.notes,
    this.hasImage = false,
    required this.createdAt,
    required this.updatedAt,
  }) : alternatives = List.unmodifiable(alternatives);

  /// Letras das alternativas das objetivas (até cinco, de A a E).
  static const List<String> letters = ['A', 'B', 'C', 'D', 'E'];

  final String id;
  final String statement;
  final QuestionType type;
  final List<String> alternatives;
  final Area area;

  /// Matéria, do catálogo fixo de [area].
  final String subject;

  /// Assunto: tag livre (pode ficar vazio).
  final String topic;

  /// Plataforma de origem (site, apostila, app...).
  final String platform;
  final String? sourceUrl;
  final String? notes;
  final bool hasImage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Texto normalizado usado na busca, calculado uma vez por instância.
  late final String searchText = buildSearchText([
    statement,
    ...alternatives,
    area.label,
    subject,
    topic,
    platform,
    notes ?? '',
  ]);

  late final String topicKey = tagKey(topic);
  late final String platformKey = tagKey(platform);

  bool get isObjective => type == QuestionType.objective;

  Question copyWith({
    String? id,
    String? statement,
    QuestionType? type,
    List<String>? alternatives,
    Area? area,
    String? subject,
    String? topic,
    String? platform,
    Object? sourceUrl = _unset,
    Object? notes = _unset,
    bool? hasImage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Question(
      id: id ?? this.id,
      statement: statement ?? this.statement,
      type: type ?? this.type,
      alternatives: alternatives ?? this.alternatives,
      area: area ?? this.area,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      platform: platform ?? this.platform,
      sourceUrl: identical(sourceUrl, _unset)
          ? this.sourceUrl
          : sourceUrl as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      hasImage: hasImage ?? this.hasImage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Mapa para persistência. Datas ficam como [DateTime]; cada repositório
  /// converte para o formato do seu armazenamento.
  Map<String, Object?> toMap() => {
    'statement': statement,
    'type': type.name,
    'alternatives': alternatives,
    'area': area.name,
    'subject': subject,
    'topic': topic,
    'platform': platform,
    'sourceUrl': sourceUrl,
    'notes': notes,
    'hasImage': hasImage,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory Question.fromMap(String id, Map<String, Object?> map) {
    final area = Area.tryParse(map['area'] as String?) ?? Area.languages;
    final created = map['createdAt'] as DateTime? ?? DateTime(2026);
    return Question(
      id: id,
      statement: map['statement'] as String? ?? '',
      type:
          QuestionType.tryParse(map['type'] as String?) ??
          QuestionType.discursive,
      alternatives:
          (map['alternatives'] as List?)?.whereType<String>().toList() ??
          const [],
      area: area,
      subject: map['subject'] as String? ?? area.subjects.first,
      topic: map['topic'] as String? ?? '',
      platform: map['platform'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String?,
      notes: map['notes'] as String?,
      hasImage: map['hasImage'] as bool? ?? false,
      createdAt: created,
      updatedAt: map['updatedAt'] as DateTime? ?? created,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          other.id == id &&
          other.statement == statement &&
          other.type == type &&
          _listEquality.equals(other.alternatives, alternatives) &&
          other.area == area &&
          other.subject == subject &&
          other.topic == topic &&
          other.platform == platform &&
          other.sourceUrl == sourceUrl &&
          other.notes == notes &&
          other.hasImage == hasImage &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    statement,
    type,
    _listEquality.hash(alternatives),
    area,
    subject,
    topic,
    platform,
    sourceUrl,
    notes,
    hasImage,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Question($id, ${area.name}/$subject/$topic)';
}
