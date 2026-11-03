import 'dart:math';

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
  for (var i = 0; i < simulatedPilotUsers; i++) {
    final uid = 'simulado-${(i + 1).toString().padLeft(2, '0')}';
    final daysAgo = 6 + (i * 36 ~/ (simulatedPilotUsers - 1));
    final signup = now.subtract(Duration(days: daysAgo, hours: 3 + i % 8));
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
    for (final w in activeWeeks) {
      add(MetricEventType.active, day(w * 7 + 1 + random.nextDouble() * 5));
    }

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
  return events;
}
