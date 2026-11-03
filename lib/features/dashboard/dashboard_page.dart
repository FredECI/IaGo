import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../shared/brand.dart';
import '../questions/selection.dart';
import 'weekly_summary_card.dart';

/// Painel inicial: atalhos e o roteiro dos próximos pilares.
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
          Text('Em breve', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _ComingSoonCard(
            icon: Icons.flag_outlined,
            pillar: 'Direciona',
            description: 'Metas e prazos espaçados, propostos para você.',
          ),
          const SizedBox(height: 8),
          const _ComingSoonCard(
            icon: Icons.groups_outlined,
            pillar: 'Conecta',
            description:
                'Comunidades em que estudantes se ajudam e ganham reputação, '
                'nunca dinheiro.',
          ),
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

/// Card desabilitado que mostra o roteiro do produto na apresentação.
class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({
    required this.icon,
    required this.pillar,
    required this.description,
  });

  final IconData icon;
  final String pillar;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      enabled: false,
      label: 'Em breve: $pillar. $description',
      excludeSemantics: true,
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Em breve: $pillar',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.lock_clock_outlined, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
