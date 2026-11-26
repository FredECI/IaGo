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

/// De onde a questão veio. Documento antigo, sem o campo, vale [manual].
enum QuestionOrigin {
  /// Digitada ou colada pelo estudante.
  manual,

  /// Extraída de um arquivo ou texto importado e revisada.
  import,

  /// Cópia de uma questão do acervo.
  bank;

  static QuestionOrigin parse(String? name) {
    for (final origin in values) {
      if (origin.name == name) return origin;
    }
    return manual;
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
    this.origin = QuestionOrigin.manual,
    this.bankId,
    this.myDifficulty,
    this.myQuality,
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

  /// Origem da questão (nas métricas, separa "minhas" de "do acervo").
  final QuestionOrigin origin;

  /// Id estável do acervo, só repassado (nunca interpretado). Só com
  /// `origin == bank`; o id do documento é `bank_{bankId}`.
  final String? bankId;

  /// Avaliação privada de dificuldade (1 a 3).
  final int? myDifficulty;

  /// Avaliação privada de qualidade (1 a 3).
  final int? myQuality;

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

  /// Cópia do acervo que o estudante alterou depois de salvar (CA-B8). Derivado
  /// de `updatedAt > createdAt`, sem campo próprio gravado.
  bool get isEdited =>
      origin == QuestionOrigin.bank && updatedAt.isAfter(createdAt);

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
    QuestionOrigin? origin,
    Object? bankId = _unset,
    Object? myDifficulty = _unset,
    Object? myQuality = _unset,
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
      origin: origin ?? this.origin,
      bankId: identical(bankId, _unset) ? this.bankId : bankId as String?,
      myDifficulty: identical(myDifficulty, _unset)
          ? this.myDifficulty
          : myDifficulty as int?,
      myQuality: identical(myQuality, _unset)
          ? this.myQuality
          : myQuality as int?,
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
    'origin': origin.name,
    'bankId': bankId,
    'myDifficulty': myDifficulty,
    'myQuality': myQuality,
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
      origin: QuestionOrigin.parse(map['origin'] as String?),
      bankId: map['bankId'] as String?,
      myDifficulty: (map['myDifficulty'] as num?)?.toInt(),
      myQuality: (map['myQuality'] as num?)?.toInt(),
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
          other.updatedAt == updatedAt &&
          other.origin == origin &&
          other.bankId == bankId &&
          other.myDifficulty == myDifficulty &&
          other.myQuality == myQuality;

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
    origin,
    bankId,
    myDifficulty,
    myQuality,
  );

  @override
  String toString() => 'Question($id, ${area.name}/$subject/$topic)';
}
