import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../data/local/simulated_pilot.dart';
import '../../data/metrics_repository.dart';
import '../../data/providers.dart';
import '../../domain/metric_event.dart';
import '../../domain/pilot_metrics.dart';
import '../../domain/session.dart';

/// Linha de base do piloto real (minutos para montar uma lista de 10 ANTES do
/// IaGo). Valor provisório: o grupo deve trocar pelo número das entrevistas.
const PilotParameters realPilotParameters = PilotParameters(
  baselineListMinutes: 30,
);

/// Eventos de métrica do usuário atual: memória na demo; Firestore na conta.
/// Na conta, já marca o uso de hoje (no máximo um evento por dia, H1).
final metricsRepositoryProvider = Provider<MetricsRepository>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  final clock = ref.watch(clockProvider);
  if (owner case final String uid) {
    final repo = FirestoreMetricsRepository(
      db: FirebaseFirestore.instance,
      uid: uid,
      clock: clock,
    );
    unawaited(repo.markActiveToday().catchError((Object _) {}));
    return repo;
  }
  return MemoryMetricsRepository(clock: clock);
});

/// Registra eventos sem travar a tela (falha de rede não atrapalha o uso).
final metricsLoggerProvider = Provider<MetricsLogger>(MetricsLogger.new);

class MetricsLogger {
  MetricsLogger(this._ref);

  final Ref _ref;

  void log(MetricEventType type, [Map<String, Object?> data = const {}]) {
    final event = MetricEvent(
      type: type,
      at: _ref.read(clockProvider)(),
      data: data,
    );
    unawaited(
      _ref.read(metricsRepositoryProvider).log(event).catchError((Object _) {}),
    );
  }
}

/// Quem vê a tela "Métricas do piloto": na demo, todos (dados simulados);
/// nas contas, só quem tem `admins/{uid}` no Firestore.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final owner = ref.watch(dataOwnerProvider);
  if (owner is DemoSession) return true;
  if (owner case final String uid) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
  return false;
});

/// Relatório H1–H4 calculado na hora a partir dos eventos.
class PilotReport {
  const PilotReport({
    required this.simulated,
    required this.users,
    required this.baselineMinutes,
    required this.hypotheses,
  });

  final bool simulated;
  final int users;
  final double baselineMinutes;
  final List<Hypothesis> hypotheses;
}

final pilotReportProvider = FutureProvider<PilotReport>((ref) async {
  final repo = ref.watch(metricsRepositoryProvider);
  final events = await repo.loadPilotEvents();
  final parameters = repo.simulated
      ? simulatedPilotParameters
      : realPilotParameters;
  return PilotReport(
    simulated: repo.simulated,
    users: events.where((e) => e.type == MetricEventType.signedUp).length,
    baselineMinutes: parameters.baselineListMinutes,
    hypotheses: computePilotMetrics(
      events: events,
      now: ref.read(clockProvider)(),
      parameters: parameters,
    ),
  );
});
