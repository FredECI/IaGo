import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/clock.dart';
import '../domain/metric_event.dart';
import 'firebase/firestore_mapping.dart';
import 'local/simulated_pilot.dart';

/// Eventos de métrica do piloto. Implementações: memória (demo) e Firestore.
abstract interface class MetricsRepository {
  Future<void> log(MetricEvent event);

  /// Já respondeu (ou dispensou) a pesquisa de satisfação?
  Future<bool> surveyDone();

  /// Eventos de todos os usuários (só para administradores).
  Future<List<MetricEvent>> loadPilotEvents();

  /// `true` quando [loadPilotEvents] devolve dados simulados.
  bool get simulated;
}

/// Demonstração: guarda na memória e mostra o piloto simulado.
class MemoryMetricsRepository implements MetricsRepository {
  MemoryMetricsRepository({required this._clock});

  final Clock _clock;
  final List<MetricEvent> logged = [];

  @override
  bool get simulated => true;

  @override
  Future<void> log(MetricEvent event) async => logged.add(event);

  @override
  Future<bool> surveyDone() async => logged.any(
    (e) =>
        e.type == MetricEventType.satisfaction ||
        e.type == MetricEventType.satisfactionDismissed,
  );

  @override
  Future<List<MetricEvent>> loadPilotEvents() async =>
      simulatedPilotEvents(_clock());
}

/// Conta real: `users/{uid}/events`. A leitura de todos é por collection
/// group, liberada pelas regras só para quem tem `admins/{uid}`.
class FirestoreMetricsRepository implements MetricsRepository {
  FirestoreMetricsRepository({
    required this._db,
    required this._uid,
    required this._clock,
  });

  final FirebaseFirestore _db;
  final String _uid;
  final Clock _clock;

  CollectionReference<Map<String, dynamic>> get _events =>
      _db.collection('users').doc(_uid).collection('events');

  @override
  bool get simulated => false;

  @override
  Future<void> log(MetricEvent event) {
    final map = toFirestore(event.toMap());
    // "Ativo no dia" tem id fixo por data: no máximo um por dia.
    if (event.type == MetricEventType.active) {
      final day = event.at.toIso8601String().substring(0, 10);
      return commitOrQueue(_events.doc('active-$day').set(map));
    }
    return commitOrQueue(_events.add(map).then((_) {}));
  }

  /// Marca o uso de hoje (idempotente).
  Future<void> markActiveToday() =>
      log(MetricEvent(type: MetricEventType.active, at: _clock()));

  @override
  Future<bool> surveyDone() async {
    final snapshot = await _events
        .where(
          'type',
          whereIn: [
            MetricEventType.satisfaction.code,
            MetricEventType.satisfactionDismissed.code,
          ],
        )
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  @override
  Future<List<MetricEvent>> loadPilotEvents() async {
    final snapshot = await _db.collectionGroup('events').get();
    return [
      for (final doc in snapshot.docs)
        ?MetricEvent.fromMap(
          doc.reference.parent.parent?.id ?? '',
          fromFirestore(doc.data()),
        ),
    ];
  }
}
