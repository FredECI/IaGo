import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';
import '../../data/providers.dart';
import '../../shared/brand.dart';
import 'account_section.dart';

/// Porta de entrada: demonstração em 1 toque ou conta com e-mail.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 72)),
                  const SizedBox(height: 16),
                  Text(
                    AppInfo.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(child: BetaBadge()),
                  const SizedBox(height: 12),
                  Text(
                    AppInfo.expandedName,
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppInfo.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const Key('enter-demo'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).enterDemo(),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Entrar como Pedro (demonstração)'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dados de exemplo, guardados só neste aparelho. '
                    'Funciona sem internet.',
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('ou', style: muted),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const AccountSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
