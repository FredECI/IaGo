import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/firebase/firebase_bootstrap.dart';
import '../../data/providers.dart';
import '../../domain/user_profile.dart';
import '../../shared/common_widgets.dart';

/// Entrada com e-mail e senha. Só aparece ativa com o Firebase pronto; sem
/// internet, avisa e deixa a demonstração como caminho principal.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Preencha e-mail e senha.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.signIn(email: _email.text, password: _password.text);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    final email = await showDialog<String>(
      context: context,
      builder: (context) => _ResetDialog(initial: _email.text.trim()),
    );
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await auth.sendPasswordReset(email);
    } on AuthFailure {
      // Não revela se o e-mail existe: a resposta é a mesma.
    }
    if (mounted) {
      showMessage(
        context,
        'Se houver conta com esse e-mail, enviamos um link para criar uma '
        'nova senha.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final status = ref.watch(firebaseStatusProvider);

    return switch (status) {
      AsyncData(value: FirebaseStatus.ready) => _form(theme),
      AsyncData(value: FirebaseStatus.notConfigured) => Text(
        'Contas com e-mail estão desligadas nesta versão. Use a '
        'demonstração.',
        key: const Key('accounts-off'),
        textAlign: TextAlign.center,
        style: muted,
      ),
      AsyncData(value: FirebaseStatus.unavailable) || AsyncError() => Column(
        key: const Key('accounts-unavailable'),
        children: [
          Text(
            'Sem conexão com o servidor de contas. A demonstração funciona '
            'normalmente.',
            textAlign: TextAlign.center,
            style: muted,
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(firebaseStatusProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
      _ => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Conectando ao servidor de contas…', style: muted),
          ),
        ],
      ),
    };
  }

  Widget _form(ThemeData theme) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('login-password'),
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Mostrar senha' : 'Esconder senha',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('login-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('login-submit'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Entrar'),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _resetPassword,
                child: const Text('Esqueci minha senha'),
              ),
              TextButton(
                key: const Key('go-sign-up'),
                onPressed: () => context.push(Routes.signUp),
                child: const Text('Criar conta grátis'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.initial});

  final String initial;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar senha'),
      content: TextField(
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail da conta'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_email.text.trim()),
          child: const Text('Enviar link'),
        ),
      ],
    );
  }
}
