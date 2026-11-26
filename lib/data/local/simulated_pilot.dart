import 'dart:math';

import 'package:collection/collection.dart';

import '../../domain/direction_models.dart';
import '../../domain/metric_event.dart';
import '../../domain/pilot_metrics.dart';
import '../../domain/user_profile.dart';

/// Linha de base SIMULADA da H2 (minutos para montar uma lista de 10 antes do
/// IaGo). No piloto de verdade, o grupo troca pelo número das entrevistas.
const PilotParameters simulatedPilotParameters = PilotParameters(
  baselineListMinutes: 30,
);

const int simulatedPilotUsers = 20;

/// Eventos de 20 usuários FICTÍCIOS, para a tela "Métricas do piloto" na
/// demonstração (sempre rotulada como "dados simulados").
///
/// Determinístico (mesmo resultado em todo ensaio) e de propósito misto:
/// algumas metas batem e outras não, como num piloto real.
List<MetricEvent> simulatedPilotEvents(DateTime now) {
  final random = Random(2026);
  final events = <MetricEvent>[];
  const referrals = [
    ReferralSource.friend, ReferralSource.prepCourse, ReferralSource.social, //
    ReferralSource.prepCourse, ReferralSource.friend, ReferralSource.other, //
    ReferralSource.social, ReferralSource.prepCourse, ReferralSource.friend, //
    ReferralSource.social, ReferralSource.prepCourse, ReferralSource.other, //
    ReferralSource.friend, ReferralSource.social, ReferralSource.prepCourse, //
    ReferralSource.friend, ReferralSource.social, ReferralSource.other, //
    ReferralSource.prepCourse, ReferralSource.friend,
  ];
  // Quem fica ativo nas 4 primeiras semanas (entre os que já têm 4+ semanas).
  const retained = {12, 14, 17};
  const scores = [9, 8, 10, 7, 9, 8, 6, 9, 10, 8, 9, 7, 8];

  var answered = 0;
  final userActiveTimes = <String, List<DateTime>>{};
  final signupAt = <String, DateTime>{};
  for (var i = 0; i < simulatedPilotUsers; i++) {
    final uid = 'simulado-${(i + 1).toString().padLeft(2, '0')}';
    final daysAgo = 6 + (i * 36 ~/ (simulatedPilotUsers - 1));
    final signup = now.subtract(Duration(days: daysAgo, hours: 3 + i % 8));
    signupAt[uid] = signup;
    DateTime day(double offsetDays) =>
        signup.add(Duration(minutes: (offsetDays * 24 * 60).round()));
    void add(MetricEventType type, DateTime at, [Map<String, Object?>? data]) {
      if (at.isAfter(now)) return;
      events.add(MetricEvent(type: type, at: at, uid: uid, data: data ?? {}));
    }

    add(MetricEventType.signedUp, signup, {
      'referralSource': referrals[i].name,
      'platformsBefore': 2 + random.nextInt(4),
    });

    // H1, ativação: 13 de 20 salvam 10+ questões na 1ª semana.
    final firstWeekSaves = i < 13
        ? 10 + random.nextInt(7)
        : 3 + random.nextInt(5);
    for (var s = 0; s < firstWeekSaves; s++) {
      add(MetricEventType.questionSaved, day(random.nextDouble() * 6.5), {
        'seconds': 12 + random.nextInt(25),
      });
    }

    // Semanas com uso: os "retidos" usam toda semana; os outros, nas duas
    // primeiras e de vez em quando. Todo evento cai numa semana com uso.
    final weeks = (daysAgo / 7).ceil();
    final activeWeeks = [
      for (var w = 0; w < weeks; w++)
        if (retained.contains(i) || w < 2 || (i + w) % 4 == 0) w,
    ];
    final activeTimes = <DateTime>[];
    for (final w in activeWeeks) {
      final at = day(w * 7 + 1 + random.nextDouble() * 5);
      activeTimes.add(at);
      add(MetricEventType.active, at);
    }

    // H5 (sem Random: o fluxo de H1 a H4 não muda). Cada etapa cai no mesmo
    // instante de um dia de uso, então a retenção também não muda.
    for (var k = 0; k < 2 + i % 3; k++) {
      if (activeTimes.isEmpty) break;
      final at = activeTimes[k % activeTimes.length];
      final outcome = (i + k * 3) % 7;
      final data = {
        'source': k.isEven ? 'rules' : 'ai',
        'action': StepAction.values[(i + k) % StepAction.values.length].name,
      };
      if (outcome <= 4) {
        add(MetricEventType.directionStepDone, at, {
          ...data,
          'onTime': outcome <= 3,
        });
      } else {
        add(MetricEventType.directionStepMissed, at, data);
      }
    }
    userActiveTimes[uid] = activeTimes;

    // H2/H3: listas exportadas (cerca de 0,8 por usuário por semana).
    final rate = 0.4 + (i % 5) * 0.2;
    final exportsCount = max(1, (max(1, daysAgo / 7) * rate).round());
    for (var x = 0; x < exportsCount; x++) {
      final week = activeWeeks[x % activeWeeks.length];
      add(
        MetricEventType.listExported,
        day(week * 7 + random.nextDouble() * 6),
        {
          'questionCount': 8 + random.nextInt(5),
          'assemblySeconds': (8 + random.nextInt(12)) * 60 + random.nextInt(60),
          'exportIndex': x + 1,
        },
      );
    }

    // H4: pesquisa de satisfação para quem exportou 3+ listas.
    if (exportsCount >= 3 && answered < scores.length) {
      add(MetricEventType.satisfaction, day(activeWeeks.last * 7 + 3), {
        'score': scores[answered],
        'platformsNow': 1 + random.nextInt(3),
      });
      answered++;
    }
  }
  events.addAll(_simulatedCommunity(now, userActiveTimes, signupAt));
  return events;
}

/// H6 simulada: 10 pessoas postam; 3 que usam toda semana respondem. Posts e
/// "Ajudou" caem em instantes de uso (a retenção não muda). Sem Random.
List<MetricEvent> _simulatedCommunity(
  DateTime now,
  Map<String, List<DateTime>> activeTimes,
  Map<String, DateTime> signupAt,
) {
  String uidOf(int i) => 'simulado-${(i + 1).toString().padLeft(2, '0')}';
  final events = <MetricEvent>[];
  final repliers = [12, 14, 17].map(uidOf).toList();
  var n = 0;
  for (final poster in [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]) {
    final uid = uidOf(poster);
    final times = activeTimes[uid] ?? const <DateTime>[];
    for (var k = 0; k < 2 && k < times.length; k++, n++) {
      final postAt = times[k];
      if (postAt.isAfter(now)) continue;
      events.add(
        MetricEvent(
          type: MetricEventType.communityPost,
          at: postAt,
          uid: uid,
          data: {'communityId': 'enem-geral', 'postId': 'sim-p$n'},
        ),
      );
      // Ordem fixa: 4 em 7 posts recebem resposta rápida, 1 em 7 demora.
      final kind = n % 7;
      if (kind >= 5) continue;
      final replier = repliers[n % repliers.length];
      final replyAt = postAt.add(
        Duration(hours: kind <= 3 ? 3 + kind * 5 : 60),
      );
      if (replier == uid ||
          replyAt.isAfter(now) ||
          signupAt[replier]!.isAfter(postAt)) {
        continue;
      }
      events.add(
        MetricEvent(
          type: MetricEventType.communityReply,
          at: replyAt,
          uid: replier,
          data: {
            'communityId': 'enem-geral',
            'postId': 'sim-p$n',
            'replyId': 'sim-r$n',
          },
        ),
      );
      // Só a resposta rápida de n múltiplo de 4 vira "Ajudou". O instante é o
      // do próximo dia de uso de quem agradece, para não mexer na retenção.
      final later = times.where((t) => t.isAfter(replyAt)).firstOrNull;
      if (n % 4 == 0 && kind <= 3 && later != null && !later.isAfter(now)) {
        events.add(
          MetricEvent(
            type: MetricEventType.helpfulGiven,
            at: later,
            uid: uid,
            data: {
              'communityId': 'enem-geral',
              'postId': 'sim-p$n',
              'replyId': 'sim-r$n',
            },
          ),
        );
      }
    }
  }
  return events;
}
