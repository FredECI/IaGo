import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../data/providers.dart';
import '../../shared/brand.dart';
import '../community/community_access.dart';
import '../direction/direction_providers.dart';
import '../questions/selection.dart';
import 'weekly_summary_card.dart';

/// Painel inicial: resumo, atalhos e a entrada dos pilares.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const PageTitle('IaGo', showBrand: true)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Olá, ${session?.displayName ?? 'estudante'}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (session?.isDemo ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Modo demonstração · dados locais',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          const WeeklySummaryCard(),
          const SizedBox(height: 20),
          Text('Atalhos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ShortcutCard(
                  key: const Key('shortcut-save-question'),
                  icon: Icons.add_circle_outline,
                  label: 'Salvar questão',
                  onTap: () => context.push(Routes.newQuestion),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ShortcutCard(
                  key: const Key('shortcut-build-list'),
                  icon: Icons.playlist_add,
                  label: 'Montar lista',
                  onTap: () => startListBuilding(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Seus pilares', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _DirectionCard(),
          if (ref.watch(conectaVisibleProvider)) ...const [
            SizedBox(height: 8),
            _ConectaCard(),
          ],
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primary,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: scheme.onPrimary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Direciona: a próxima etapa (com prazo e motivo) ou o convite para criar o
/// objetivo. Na demo, as etapas são simuladas e o card diz isso. Se as etapas
/// não chegarem em `directionReadTimeoutProvider`, vira um aviso neutro com
/// "Tentar de novo" (nunca "Carregando..." sem fim).
class _DirectionCard extends ConsumerStatefulWidget {
  const _DirectionCard();

  @override
  ConsumerState<_DirectionCard> createState() => _DirectionCardState();
}

class _DirectionCardState extends ConsumerState<_DirectionCard> {
  Timer? _timer;
  bool _timedOut = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(ref.read(directionReadTimeoutProvider), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  void _retry() {
    setState(() => _timedOut = false);
    ref.invalidate(studyStepsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(nextStepProvider);
    final loading = ref.watch(studyStepsProvider).isLoading;
    final simulated = ref.watch(directionSimulatedProvider);
    if (loading && step == null) {
      if (_timer == null || !(_timer?.isActive ?? false)) {
        if (!_timedOut) _startTimer();
      }
    } else {
      _timer?.cancel();
      _timedOut = false;
    }
    if (loading && step == null && _timedOut) {
      final theme = Theme.of(context);
      return Card(
        key: const Key('direction-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direciona',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Não foi possível carregar suas etapas agora.',
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      key: const Key('direction-retry'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _retry,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (step == null) {
      return _PillarCard(
        key: const Key('direction-card'),
        icon: Icons.flag_outlined,
        title: 'Direciona',
        description: loading
            ? 'Carregando suas etapas...'
            : 'Defina seu objetivo e receba as próximas etapas de estudo.',
        actionLabel: 'Definir objetivo',
        route: Routes.direction,
      );
    }
    // O número é a meta da etapa e vem com ação, matéria e prazo (CA-T11).
    return _PillarCard(
      key: const Key('direction-card'),
      icon: Icons.flag_outlined,
      title: 'Próxima etapa${simulated ? ' (simulada)' : ''}',
      description:
          '${step.action.label}: ${step.targetCount} · ${step.subject}, '
          'até ${Formatters.date(step.dueAt)}. ${step.rationale}',
      actionLabel: 'Ver etapas',
      route: Routes.direction,
    );
  }
}

/// Conecta: só aparece para quem a política libera (`conectaVisibleProvider`).
class _ConectaCard extends StatelessWidget {
  const _ConectaCard();

  @override
  Widget build(BuildContext context) => const _PillarCard(
    key: Key('conecta-card'),
    icon: Icons.groups_outlined,
    title: 'Conecta',
    description: 'Comunidades em que estudantes se ajudam e ganham reputação.',
    actionLabel: 'Abrir comunidades',
    route: Routes.community,
  );
}

class _PillarCard extends StatelessWidget {
  const _PillarCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '$title. $description. $actionLabel',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text(
                        actionLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
