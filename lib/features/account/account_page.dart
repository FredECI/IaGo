import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme_mode_controller.dart';
import '../../core/app_info.dart';
import '../../data/providers.dart';
import '../../shared/brand.dart';

/// Conta: perfil, aparência, sobre e saída.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final isDemo = session?.isDemo ?? false;
    final name = session?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(title: const PageTitle('Conta')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.isEmpty ? '?' : name.characters.first,
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            title: Text(isDemo ? '$name (demonstração)' : name),
            subtitle: Text(
              isDemo
                  ? 'Dados de exemplo, guardados só neste aparelho'
                  : 'Conta IaGo',
            ),
          ),
          const Divider(),
          const _SectionTitle('Aparência'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistema'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Claro'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Escuro'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).select(selection.first),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const _SectionTitle('Sobre'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Versão'),
            subtitle: Text('${AppInfo.name} ${AppInfo.versionLabel}'),
          ),
          const Divider(),
          ListTile(
            key: const Key('sign-out'),
            leading: const Icon(Icons.logout),
            title: Text(isDemo ? 'Sair da demonstração' : 'Sair'),
            subtitle: isDemo
                ? const Text('Os dados de exemplo voltam ao estado original')
                : null,
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
