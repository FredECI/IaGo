import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../domain/community_models.dart';
import 'community_state.dart';
import 'community_widgets.dart';

/// Conecta: as cinco comunidades fixas, a reputação de quem está lendo e,
/// para moderadores, a entrada da fila de denúncias.
class CommunityHomePage extends ConsumerWidget {
  const CommunityHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(communityUidProvider);
    final banned = ref.watch(isBannedProvider).value ?? false;
    final moderator = ref.watch(isModeratorProvider).value ?? false;
    final isDemo = ref.watch(sessionProvider)?.isDemo ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Conecta')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Comunidades em que estudantes se ajudam. Escolha uma para '
                  'ver as conversas.',
                  style: theme.textTheme.bodyLarge,
                ),
                if (isDemo) ...[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      key: Key('community-simulated'),
                      label: Text('Comunidade simulada'),
                    ),
                  ),
                ],
                if (banned) ...[
                  const SizedBox(height: 12),
                  const BannedNotice(),
                ],
                const SizedBox(height: 12),
                if (uid != null && !banned)
                  Card(
                    key: const Key('my-reputation'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sua reputação',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          ReputationText(uid: uid),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final c in communities)
                  Card(
                    child: ListTile(
                      key: Key('community-${c.id}'),
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(c.name),
                      subtitle: Text(c.description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.communityRoom(c.id)),
                    ),
                  ),
                if (isDemo)
                  SwitchListTile(
                    key: const Key('demo-moderator-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ver como moderador (demonstração)'),
                    subtitle: const Text(
                      'Só na demo: abre a fila de denúncias simulada.',
                    ),
                    value: ref.watch(demoModeratorModeProvider),
                    onChanged: (v) =>
                        ref.read(demoModeratorModeProvider.notifier).set(v),
                  ),
                if (moderator && !banned)
                  Card(
                    child: ListTile(
                      key: const Key('open-moderation'),
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Moderação'),
                      subtitle: const Text('Fila de denúncias abertas.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.moderation),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
