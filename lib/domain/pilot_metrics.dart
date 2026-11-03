import 'dart:math' as math;

import 'metric_event.dart';
import 'user_profile.dart';

/// Situação de uma métrica em relação à meta do canvas.
enum MetricStatus { met, notMet, noData }

/// Uma métrica do piloto: valor medido, meta e situação (nunca número solto).
class PilotMetric {
  const PilotMetric({
    required this.label,
    required this.value,
    required this.target,
    required this.status,
    this.detail,
  });

  final String label;

  /// Valor medido, já formatado ("62%", "13 min").
  final String value;

  /// Meta do canvas, formatada ("meta: 60%").
  final String target;
  final MetricStatus status;

  /// Contexto do cálculo ("13 de 20 usuários").
  final String? detail;
}

class Hypothesis {
  const Hypothesis({
    required this.code,
    required this.title,
    required this.metrics,
  });

  final String code;
  final String title;
  final List<PilotMetric> metrics;
}

/// Parâmetros que não vêm dos eventos.
class PilotParameters {
  const PilotParameters({required this.baselineListMinutes});

  /// Tempo para montar uma lista de 10 questões ANTES do IaGo (linha de base
  /// das entrevistas). Meta da H2: cair pela metade.
  final double baselineListMinutes;
}

/// Calcula H1–H4 a partir dos eventos de todos os usuários do piloto.
List<Hypothesis> computePilotMetrics({
  required List<MetricEvent> events,
  required DateTime now,
  required PilotParameters parameters,
}) {
  final byUser = <String, List<MetricEvent>>{};
  for (final e in events) {
    byUser.putIfAbsent(e.uid, () => []).add(e);
  }
  final signups = <String, MetricEvent>{
    for (final e in events)
      if (e.type == MetricEventType.signedUp) e.uid: e,
  };

  String pct(num v) => '${v.round()}%';

  // ---- H1: ativação (10+ questões na 1ª semana) e retenção (4 semanas).
  var activated = 0;
  var eligibleRetention = 0;
  var retained = 0;
  for (final entry in signups.entries) {
    final start = entry.value.at;
    final mine = byUser[entry.key] ?? const [];
    final firstWeekSaves = mine.where(
      (e) =>
          e.type == MetricEventType.questionSaved &&
          !e.at.isBefore(start) &&
          e.at.isBefore(start.add(const Duration(days: 7))),
    );
    if (firstWeekSaves.length >= 10) activated++;
    if (now.difference(start).inDays >= 28) {
      eligibleRetention++;
      final activeEveryWeek = List.generate(4, (week) {
        final from = start.add(Duration(days: 7 * week));
        final to = from.add(const Duration(days: 7));
        return mine.any((e) => !e.at.isBefore(from) && e.at.isBefore(to));
      }).every((active) => active);
      if (activeEveryWeek) retained++;
    }
  }
  final users = signups.length;
  final activation = PilotMetric(
    label: 'Ativação: salvaram 10+ questões na 1ª semana',
    value: users == 0 ? '—' : pct(activated * 100 / users),
    target: 'meta: 60%',
    status: users == 0
        ? MetricStatus.noData
        : (activated * 100 / users >= 60
              ? MetricStatus.met
              : MetricStatus.notMet),
    detail: '$activated de $users usuários',
  );
  final retention = PilotMetric(
    label: 'Retenção: ativos toda semana no 1º mês',
    value: eligibleRetention == 0
        ? '—'
        : pct(retained * 100 / eligibleRetention),
    target: 'meta: 40%',
    status: eligibleRetention == 0
        ? MetricStatus.noData
        : (retained * 100 / eligibleRetention >= 40
              ? MetricStatus.met
              : MetricStatus.notMet),
    detail: eligibleRetention == 0
        ? 'ainda ninguém completou 4 semanas'
        : '$retained de $eligibleRetention com 4+ semanas de uso',
  );

  // ---- H2: tempo de montagem (listas de ~10) e plataformas antes × depois.
  final assembly =
      events
          .where(
            (e) =>
                e.type == MetricEventType.listExported &&
                (e.intData('assemblySeconds') ?? 0) > 0 &&
                ((e.intData('questionCount') ?? 0) - 10).abs() <= 3,
          )
          .map((e) => e.intData('assemblySeconds')! / 60)
          .toList()
        ..sort();
  final medianMinutes = assembly.isEmpty
      ? null
      : (assembly.length.isOdd
            ? assembly[assembly.length ~/ 2]
            : (assembly[assembly.length ~/ 2 - 1] +
                      assembly[assembly.length ~/ 2]) /
                  2);
  final goalMinutes = parameters.baselineListMinutes / 2;
  final assemblyTime = PilotMetric(
    label: 'Tempo para montar lista de ~10 questões (mediana)',
    value: medianMinutes == null ? '—' : '${medianMinutes.round()} min',
    target:
        'meta: até ${goalMinutes.round()} min (metade dos '
        '${parameters.baselineListMinutes.round()} min de antes)',
    status: medianMinutes == null
        ? MetricStatus.noData
        : (medianMinutes <= goalMinutes
              ? MetricStatus.met
              : MetricStatus.notMet),
    detail: '${assembly.length} listas medidas',
  );
  double? average(Iterable<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  final before = average([
    for (final e in signups.values) ?e.intData('platformsBefore'),
  ]);
  final after = average([
    for (final e in events)
      if (e.type == MetricEventType.satisfaction) ?e.intData('platformsNow'),
  ]);
  String one(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  final platforms = PilotMetric(
    label: 'Plataformas usadas em paralelo (média)',
    value: before == null || after == null
        ? '—'
        : '${one(before)} → ${one(after)}',
    target: 'meta: cair (antes × depois)',
    status: before == null || after == null
        ? MetricStatus.noData
        : (after < before ? MetricStatus.met : MetricStatus.notMet),
    detail: 'no cadastro × na pesquisa de satisfação',
  );

  // ---- H3: listas baixadas por usuário por semana.
  var userWeeks = 0.0;
  for (final signup in signups.values) {
    userWeeks += math.max(1, now.difference(signup.at).inDays / 7);
  }
  final exports = events
      .where((e) => e.type == MetricEventType.listExported)
      .length;
  final perWeek = userWeeks == 0 ? null : exports / userWeeks;
  final listsPerWeek = PilotMetric(
    label: 'Listas baixadas por usuário por semana',
    value: perWeek == null ? '—' : one(perWeek),
    target: 'meta: pelo menos 1',
    status: perWeek == null
        ? MetricStatus.noData
        : (perWeek >= 1 ? MetricStatus.met : MetricStatus.notMet),
    detail: '$exports exportações',
  );

  // ---- H4: indicação e satisfação.
  final referred = signups.values
      .where(
        (e) => e.stringData('referralSource') == ReferralSource.friend.name,
      )
      .length;
  final referral = PilotMetric(
    label: 'Cadastros vindos de indicação',
    value: users == 0 ? '—' : pct(referred * 100 / users),
    target: 'meta: 1 em 4 (25%)',
    status: users == 0
        ? MetricStatus.noData
        : (referred * 4 >= users ? MetricStatus.met : MetricStatus.notMet),
    detail: '$referred de $users cadastros',
  );
  final scores = [
    for (final e in events)
      if (e.type == MetricEventType.satisfaction) ?e.intData('score'),
  ];
  final meanScore = average(scores);
  final satisfaction = PilotMetric(
    label: 'Satisfação média (0 a 10)',
    value: meanScore == null ? '—' : one(meanScore),
    target: 'meta: 8 ou mais',
    status: meanScore == null
        ? MetricStatus.noData
        : (meanScore >= 8 ? MetricStatus.met : MetricStatus.notMet),
    detail: '${scores.length} respostas',
  );

  return [
    Hypothesis(
      code: 'H1',
      title: 'O estudante quer centralizar suas questões',
      metrics: [activation, retention],
    ),
    Hypothesis(
      code: 'H2',
      title: 'Centralizar economiza tempo',
      metrics: [assemblyTime, platforms],
    ),
    Hypothesis(
      code: 'H3',
      title: 'Ajuda quem dá aulas de reforço',
      metrics: [listsPerWeek],
    ),
    Hypothesis(
      code: 'H4',
      title: 'Grátis e boca a boca trazem usuários',
      metrics: [referral, satisfaction],
    ),
  ];
}
