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
    expect(hs.map((h) => h.code), ['H1', 'H2', 'H3', 'H4', 'H5', 'H6']);
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
    expect(activation.detail, startsWith('1 de 2 usuários'));
  });

  test('CA-M1: H1 soma manual e importado e não conta o acervo', () {
    final start = now.subtract(const Duration(days: 10));
    MetricEvent signup(String uid) =>
        MetricEvent(type: MetricEventType.signedUp, at: start, uid: uid);
    MetricEvent saved(String uid) => MetricEvent(
      type: MetricEventType.questionSaved,
      at: start.add(const Duration(days: 1)),
      uid: uid,
    );
    MetricEvent bulk(String uid, String origin, int count, {int day = 2}) =>
        MetricEvent(
          type: MetricEventType.questionsBulkSaved,
          at: start.add(Duration(days: day)),
          uid: uid,
          data: {'origin': origin, 'count': count},
        );
    PilotMetric activationOf(List<MetricEvent> events) => computePilotMetrics(
      events: events,
      now: now,
      parameters: params,
    ).first.metrics.first;

    final metric = activationOf([
      signup('manual-import'),
      for (var i = 0; i < 4; i++) saved('manual-import'),
      bulk('manual-import', 'import', 6), // 4 + 6 = 10: ativado
      signup('so-acervo'),
      bulk('so-acervo', 'bank', 30), // acervo não conta
      signup('acervo-mais-poucas'),
      for (var i = 0; i < 9; i++) saved('acervo-mais-poucas'),
      bulk('acervo-mais-poucas', 'bank', 30), // 9 próprias: não ativa
      signup('import-tardio'),
      bulk('import-tardio', 'import', 20, day: 8), // fora da 1ª semana
    ]);
    expect(metric.detail, startsWith('1 de 4 usuários'));
    expect(metric.value, '25%');
  });

  test('CA-M2: H5 e H6 mostram "meta provisória"', () {
    final hs = computePilotMetrics(
      events: simulatedPilotEvents(now),
      now: now,
      parameters: params,
    );
    final byCode = {for (final h in hs) h.code: h};
    final h5 = byCode['H5']!.metrics;
    final h6 = byCode['H6']!.metrics;
    expect(h5, hasLength(1));
    expect(h6, hasLength(2));
    for (final m in [...h5, ...h6]) {
      expect(m.target, startsWith('meta provisória'), reason: m.label);
      expect(m.status, isNot(MetricStatus.noData), reason: m.label);
    }
    expect(h5.first.target, 'meta provisória: 60%');
    expect(h6[0].target, 'meta provisória: 50%');
    expect(h6[1].target, 'meta provisória: 30%');
  });

  test('H5: só conta no prazo o que foi concluído até o prazo', () {
    MetricEvent done(bool onTime) => MetricEvent(
      type: MetricEventType.directionStepDone,
      at: now,
      uid: 'a',
      data: {'onTime': onTime},
    );
    final h5 = computePilotMetrics(
      events: [
        done(true),
        done(true),
        done(false), // concluída fora do prazo
        MetricEvent(
          type: MetricEventType.directionStepMissed,
          at: now,
          uid: 'a',
        ),
      ],
      now: now,
      parameters: params,
    ).firstWhere((h) => h.code == 'H5').metrics.single;
    expect(h5.value, '50%');
    expect(h5.status, MetricStatus.notMet);
    expect(h5.detail, '2 de 4 etapas');
  });

  test('H6: resposta de outra pessoa em até 48 h e membros com "Ajudou"', () {
    MetricEvent ev(
      MetricEventType type,
      String uid,
      Duration after,
      Map<String, Object?> data,
    ) => MetricEvent(
      type: type,
      at: now.subtract(const Duration(days: 10)).add(after),
      uid: uid,
      data: data,
    );
    final h6 = computePilotMetrics(
      events: [
        ev(MetricEventType.communityPost, 'a', Duration.zero, {'postId': 'p1'}),
        ev(MetricEventType.communityReply, 'b', const Duration(hours: 5), {
          'postId': 'p1',
          'replyId': 'r1',
        }),
        ev(MetricEventType.helpfulGiven, 'a', const Duration(hours: 6), {
          'replyId': 'r1',
        }),
        // Resposta tardia (72 h): o post conta como sem resposta rápida.
        ev(MetricEventType.communityPost, 'a', Duration.zero, {'postId': 'p2'}),
        ev(MetricEventType.communityReply, 'c', const Duration(hours: 72), {
          'postId': 'p2',
          'replyId': 'r2',
        }),
        // Resposta do próprio autor não vale.
        ev(MetricEventType.communityPost, 'a', Duration.zero, {'postId': 'p3'}),
        ev(MetricEventType.communityReply, 'a', const Duration(hours: 1), {
          'postId': 'p3',
          'replyId': 'r3',
        }),
        // Post recente e sem resposta ainda: não entra na conta.
        MetricEvent(
          type: MetricEventType.communityPost,
          at: now.subtract(const Duration(hours: 5)),
          uid: 'a',
          data: const {'postId': 'p4'},
        ),
      ],
      now: now,
      parameters: params,
    ).firstWhere((h) => h.code == 'H6').metrics;
    expect(h6[0].value, '33%');
    expect(h6[0].detail, '1 de 3 posts');
    // Participantes: a, b, c; só b teve resposta marcada como útil.
    expect(h6[1].value, '33%');
    expect(h6[1].status, MetricStatus.met);
  });

  test(
    'CA-M3: na demo, H1 a H4 mantêm os valores (H5 e H6 não interferem)',
    () {
      final all = simulatedPilotEvents(now);
      const newTypes = {
        MetricEventType.directionStepDone,
        MetricEventType.directionStepMissed,
        MetricEventType.communityPost,
        MetricEventType.communityReply,
        MetricEventType.helpfulGiven,
      };
      final base = all.where((e) => !newTypes.contains(e.type)).toList();
      expect(base.length, lessThan(all.length));

      List<PilotMetric> h1h4(List<MetricEvent> events) => [
        for (final h in computePilotMetrics(
          events: events,
          now: now,
          parameters: params,
        ).take(4))
          ...h.metrics,
      ];
      final withNew = h1h4(all);
      final without = h1h4(base);
      for (var i = 0; i < without.length; i++) {
        expect(withNew[i].value, without[i].value, reason: without[i].label);
        expect(withNew[i].detail, without[i].detail, reason: without[i].label);
        expect(withNew[i].status, without[i].status, reason: without[i].label);
      }
      final metrics = byLabel(
        computePilotMetrics(events: all, now: now, parameters: params),
      );
      expect(metrics['Retenção: ativos toda semana no 1º mês']!.value, '38%');
      expect(metrics['Listas baixadas por usuário por semana']!.value, '0,8');
    },
  );

  test(
    'H2 usa só listas sem questões do acervo; H3 mostra as com etapa aceita',
    () {
      MetricEvent export(Map<String, Object?> data) => MetricEvent(
        type: MetricEventType.listExported,
        at: now,
        uid: 'a',
        data: {'assemblySeconds': 600, 'questionCount': 10, ...data},
      );
      final hs = computePilotMetrics(
        events: [
          MetricEvent(type: MetricEventType.signedUp, at: now, uid: 'a'),
          export({'bankQuestionCount': 0, 'hadAcceptedListStep': false}),
          export({'bankQuestionCount': 4, 'assemblySeconds': 3000}),
          export({'bankQuestionCount': 0, 'hadAcceptedListStep': true}),
        ],
        now: now,
        parameters: params,
      );
      expect(hs[1].metrics[0].detail, '2 listas medidas');
      expect(
        hs[2].metrics[0].detail,
        '3 exportações (1 com etapa de montar lista aceita no momento)',
      );
    },
  );

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
