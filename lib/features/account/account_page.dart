import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/theme_mode_controller.dart';
import '../../core/app_info.dart';
import '../../data/providers.dart';
import '../../domain/session.dart';
import '../../domain/user_profile.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import '../community/community_access.dart';
import '../metrics/metrics_providers.dart';

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
            subtitle: Text(switch (session) {
              DemoSession() => 'Dados de exemplo, guardados só neste aparelho',
              AccountSession(:final email) => email,
              null => '',
            }),
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
          if (ref.watch(canOfferJoinProvider)) ...[
            const Divider(),
            const _SectionTitle('Piloto'),
            ListTile(
              key: const Key('account-join'),
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Entrar no piloto'),
              subtitle: const Text(
                'Libera a IA e as avaliações do acervo. Precisa de convite.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.becomeMember),
            ),
          ],
          if (ref.watch(isAdminProvider).value ?? false) ...[
            const Divider(),
            const _SectionTitle('Piloto'),
            ListTile(
              key: const Key('open-metrics'),
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Métricas do piloto'),
              subtitle: Text(
                isDemo
                    ? 'H1–H6 com dados simulados'
                    : 'H1–H6 com os dados reais (administrador)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.metrics),
            ),
          ],
          const Divider(),
          const _SectionTitle('Sobre'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Versão'),
            subtitle: Text('${AppInfo.name} ${AppInfo.versionLabel}'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Termos e privacidade'),
            subtitle: const Text('O que guardamos e como excluir'),
            onTap: () => context.push(Routes.terms),
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
          if (session is AccountSession)
            ListTile(
              key: const Key('delete-account'),
              leading: Icon(
                Icons.delete_forever_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Excluir minha conta',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text(
                'Apaga questões, listas, registros e a conta',
              ),
              onTap: () => _deleteAccount(context, ref),
            ),
        ],
      ),
    );
  }
}

/// LGPD: confirma com a senha e apaga tudo (dados e conta).
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(authRepositoryProvider);
  if (auth == null) {
    showMessage(context, 'Sem conexão com o servidor de contas.');
    return;
  }
  final password = await showDialog<String>(
    context: context,
    builder: (context) => const _DeleteAccountDialog(),
  );
  if (password == null || password.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  // A exclusão pode levar vários segundos: mostra a espera, sem fechar.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          key: Key('deleting-account'),
          content: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Apagando seus dados...')),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    await auth.deleteAccount(password: password);
    messenger.showSnackBar(
      const SnackBar(content: Text('Conta e dados excluídos.')),
    );
  } on AuthFailure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  } finally {
    if (navigator.mounted) navigator.pop();
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excluir conta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Suas questões, listas, registros e o que você publicou no Conecta '
            'serão apagados para sempre. Uma denúncia sua ainda aberta '
            'continua até a moderação resolver. Digite sua senha para '
            'confirmar.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('delete-account-password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('delete-account-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: const Text('Excluir tudo'),
        ),
      ],
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
