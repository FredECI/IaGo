/// Eventos de uso que alimentam as hipóteses do piloto (H1–H4).
///
/// Guardados em `users/{uid}/events` (contas reais) ou na memória (demo).
/// Nada de conteúdo das questões: só tipo, data e números.
enum MetricEventType {
  /// Cadastro, com a origem (H4) e as plataformas usadas antes (H2).
  signedUp('signed_up'),

  /// Questão salva, com o tempo para salvar.
  questionSaved('question_saved'),

  /// Lista criada (pelo filtro ou por seleção).
  listCreated('list_created'),

  /// Lista exportada em PDF, com o tempo de montagem na 1ª exportação (H2/H3).
  listExported('list_exported'),

  /// Uso no dia (no máximo um por dia): base da retenção semanal (H1).
  active('active'),

  /// Pesquisa de satisfação de 0 a 10 (H4) e plataformas usadas agora (H2).
  satisfaction('satisfaction'),

  /// O estudante dispensou a pesquisa (não perguntar de novo).
  satisfactionDismissed('satisfaction_dismissed');

  const MetricEventType(this.code);

  /// Valor gravado no banco.
  final String code;

  static MetricEventType? tryParse(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

class MetricEvent {
  const MetricEvent({
    required this.type,
    required this.at,
    this.uid = '',
    this.data = const {},
  });

  final MetricEventType type;
  final DateTime at;

  /// Dono do evento (preenchido ao ler os eventos de todos, na visão admin).
  final String uid;
  final Map<String, Object?> data;

  int? intData(String key) => (data[key] as num?)?.toInt();

  String? stringData(String key) => data[key] as String?;

  /// `type` e `at` vêm por último: nenhum dado extra consegue sobrescrevê-los.
  Map<String, Object?> toMap() => {...data, 'type': type.code, 'at': at};

  static MetricEvent? fromMap(String uid, Map<String, Object?> map) {
    final type = MetricEventType.tryParse(map['type'] as String?);
    final at = map['at'];
    if (type == null || at is! DateTime) return null;
    return MetricEvent(
      type: type,
      at: at,
      uid: uid,
      data: {
        for (final entry in map.entries)
          if (entry.key != 'type' && entry.key != 'at') entry.key: entry.value,
      },
    );
  }
}
