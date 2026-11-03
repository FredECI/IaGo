import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/simulated_pilot.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/domain/pilot_metrics.dart';

void main() {
  final now = DateTime(2026, 11, 6, 14);
  const params = PilotParameters(baselineListMinutes: 30);

  Map<String, PilotMetric> byLabel(List<Hypothesis> hs) => {
    for (final h in hs)
      for (final m in h.metrics) m.label: m,
  };

  test('piloto simulado: 20 usuários, resultados mistos e estáveis', () {
    final events = simulatedPilotEvents(now);
    final signups = events.where((e) => e.type == MetricEventType.signedUp);
    expect(signups, hasLength(20));
    expect(
      simulatedPilotEvents(now).length,
      events.length,
      reason: 'determinístico',
    );

    final hs = computePilotMetrics(
      events: events,
      now: now,
      parameters: params,
    );
    expect(hs.map((h) => h.code), ['H1', 'H2', 'H3', 'H4']);
    final statuses = [
      for (final h in hs)
        for (final m in h.metrics) m.status,
    ];
    expect(statuses, contains(MetricStatus.met));
    expect(statuses, contains(MetricStatus.notMet));
    expect(statuses, isNot(contains(MetricStatus.noData)));
    // Imprime para conferência no ensaio.
    for (final m in byLabel(hs).values) {
      // ignore: avoid_print
      print('${m.label}: ${m.value} (${m.target}) — ${m.status.name}');
    }
  });

  test('H1: ativação conta 10+ questões só na 1ª semana', () {
    final start = now.subtract(const Duration(days: 10));
    MetricEvent save(int day) => MetricEvent(
      type: MetricEventType.questionSaved,
      at: start.add(Duration(days: day)),
      uid: 'a',
    );
    final events = [
      MetricEvent(type: MetricEventType.signedUp, at: start, uid: 'a'),
      for (var i = 0; i < 9; i++) save(1),
      save(8), // fora da 1ª semana
      MetricEvent(type: MetricEventType.signedUp, at: start, uid: 'b'),
      for (var i = 0; i < 10; i++)
        MetricEvent(
          type: MetricEventType.questionSaved,
          at: start.add(const Duration(days: 2)),
          uid: 'b',
        ),
    ];
    final activation = computePilotMetrics(
      events: events,
      now: now,
      parameters: params,
    ).first.metrics.first;
    expect(activation.value, '50%');
    expect(activation.status, MetricStatus.notMet);
    expect(activation.detail, '1 de 2 usuários');
  });

  test('H2: mediana do tempo de montagem e comparação com a linha de base', () {
    MetricEvent export(int minutes, int count) => MetricEvent(
      type: MetricEventType.listExported,
      at: now,
      uid: 'a',
      data: {'assemblySeconds': minutes * 60, 'questionCount': count},
    );
    final hs = computePilotMetrics(
      events: [
        MetricEvent(
          type: MetricEventType.signedUp,
          at: now,
          uid: 'a',
          data: {'platformsBefore': 4},
        ),
        export(10, 10),
        export(14, 9),
        export(40, 10),
        export(99, 30), // lista grande: fora da conta de "~10 questões"
        MetricEvent(
          type: MetricEventType.satisfaction,
          at: now,
          uid: 'a',
          data: {'score': 9, 'platformsNow': 2},
        ),
      ],
      now: now,
      parameters: params,
    );
    final h2 = hs[1].metrics;
    expect(h2[0].value, '14 min');
    expect(h2[0].status, MetricStatus.met);
    expect(h2[1].value, '4,0 → 2,0');
    expect(h2[1].status, MetricStatus.met);
  });

  test('sem eventos, tudo aparece como "sem dados" (nada inventado)', () {
    final hs = computePilotMetrics(
      events: const [],
      now: now,
      parameters: params,
    );
    for (final h in hs) {
      for (final m in h.metrics) {
        expect(m.status, MetricStatus.noData, reason: m.label);
        expect(m.value, '—');
      }
    }
  });

  test('evento ida e volta pelo mapa', () {
    final e = MetricEvent(
      type: MetricEventType.listExported,
      at: now,
      data: {'questionCount': 10},
    );
    final back = MetricEvent.fromMap('u', e.toMap())!;
    expect(back.type, MetricEventType.listExported);
    expect(back.intData('questionCount'), 10);
    expect(back.uid, 'u');
    expect(MetricEvent.fromMap('u', const {'type': '???'}), isNull);
    // Um dado chamado "type" não pode trocar o tipo do evento.
    final tricky = MetricEvent(
      type: MetricEventType.questionSaved,
      at: now,
      data: const {'type': 'objective'},
    );
    expect(tricky.toMap()['type'], 'question_saved');
  });
}
