import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../domain/pilot_metrics.dart';
import '../../shared/common_widgets.dart';
import 'metrics_providers.dart';

/// "Métricas do piloto": H1–H6 do canvas calculadas na hora, cada número ao
/// lado da sua meta. Restrita a administradores; na demo, dados simulados.
class MetricsPage extends ConsumerWidget {
  const MetricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(isAdminProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Métricas do piloto')),
      body: switch (admin) {
        AsyncData(value: false) || AsyncError() => const EmptyState(
          icon: Icons.lock_outline,
          title: 'Área restrita',
          message: 'Só administradores do piloto veem esta tela.',
        ),
        AsyncData(value: true) => const _Report(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Report extends ConsumerWidget {
  const _Report();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(pilotReportProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'Não foi possível calcular as métricas',
            message: '$error',
          ),
          data: (report) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (report.simulated) const _SimulatedBanner(),
              const SizedBox(height: 12),
              Text(
                '${Formatters.count(report.users, 'usuário', 'usuários')}'
                '${report.simulated ? ' fictícios' : ''}'
                ' · calculado agora a partir dos eventos de uso',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final hypothesis in report.hypotheses) ...[
                _HypothesisCard(hypothesis: hypothesis),
                const SizedBox(height: 12),
              ],
              Text(
                'Como medimos: ativação = 10+ questões próprias (à mão ou '
                'importadas, sem o acervo) nos 7 dias após o '
                'cadastro; H5 e H6 têm meta provisória, a confirmar pelo '
                'grupo; retenção = uso em cada uma das 4 primeiras semanas; '
                'tempo de montagem = da primeira busca/seleção até a 1ª '
                'exportação, em listas de 7 a 13 questões, comparado com a '
                'linha de base de ${report.baselineMinutes.round()} min.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
  }
}

class _SimulatedBanner extends StatelessWidget {
  const _SimulatedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('simulated-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE68A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB45309), width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, color: Color(0xFF451A03)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'DADOS SIMULADOS: 20 usuários fictícios, só para mostrar o '
              'cálculo. Não são resultados do piloto.',
              style: TextStyle(
                color: Color(0xFF451A03),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HypothesisCard extends StatelessWidget {
  const _HypothesisCard({required this.hypothesis});

  final Hypothesis hypothesis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('hypothesis-${hypothesis.code}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${hypothesis.code} · ${hypothesis.title}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final metric in hypothesis.metrics) ...[
              const Divider(height: 24),
              _MetricRow(metric: metric),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric});

  final PilotMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metric.label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              metric.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                metric.target,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(status: metric.status),
            if (metric.detail != null)
              Text(
                metric.detail!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MetricStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Verde e vermelho-tijolo escuros: texto branco com contraste ≥ 4,5:1.
    final (label, icon, background, foreground) = switch (status) {
      MetricStatus.met => (
        'Meta atingida',
        Icons.check_circle,
        const Color(0xFF2E7D32),
        Colors.white,
      ),
      MetricStatus.notMet => (
        'Abaixo da meta',
        Icons.error_outline,
        const Color(0xFFB23C17),
        Colors.white,
      ),
      MetricStatus.noData => (
        'Sem dados ainda',
        Icons.hourglass_empty,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
