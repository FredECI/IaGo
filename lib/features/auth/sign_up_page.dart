import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/app_info.dart';
import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/user_profile.dart';

/// Cadastro seguro: e-mail e senha, origem (H4) e aceite dos termos (LGPD).
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  ReferralSource? _referral;
  int? _platforms;
  bool _acceptedTerms = false;
  bool _ageDeclared = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// Senha mínima do beta (o Firebase aceitaria 6).
  static const int minPasswordLength = 8;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) {
      setState(() => _error = 'Sem conexão com o servidor de contas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.signUp(
        SignUpData(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          referralSource: _referral!,
          platformsBefore: _platforms,
          termsVersion: AppInfo.termsVersion,
          declaredMinAge: ref.read(accessPolicyProvider).minAge,
        ),
      );
      // A sessão muda sozinha e o roteador leva ao painel.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minAge = ref.watch(accessPolicyProvider).minAge;
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta grátis')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextFormField(
                    key: const Key('signup-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Informe seu nome.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('signup-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(text);
                      return ok ? null : 'Informe um e-mail válido.';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('signup-password'),
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      helperText: 'Pelo menos $minPasswordLength caracteres.',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar senha' : 'Esconder senha',
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v ?? '').length < minPasswordLength
                        ? 'A senha precisa ter pelo menos $minPasswordLength '
                              'caracteres.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Como você conheceu o IaGo?',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  FormField<ReferralSource>(
                    validator: (_) =>
                        _referral == null ? 'Escolha uma opção.' : null,
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final source in ReferralSource.values)
                              ChoiceChip(
                                key: Key('referral-${source.name}'),
                                label: Text(source.label),
                                selected: _referral == source,
                                onSelected: (_) =>
                                    setState(() => _referral = source),
                              ),
                          ],
                        ),
                        if (state.hasError) _ErrorLine(state.errorText!),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Hoje, em quantas plataformas você estuda? (opcional)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final n in [1, 2, 3, 4, 5])
                        ChoiceChip(
                          label: Text(n == 5 ? '5 ou mais' : '$n'),
                          selected: _platforms == n,
                          onSelected: (selected) =>
                              setState(() => _platforms = selected ? n : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FormField<bool>(
                    validator: (_) => _acceptedTerms
                        ? null
                        : 'É preciso aceitar os termos para criar a conta.',
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          key: const Key('signup-terms'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _acceptedTerms,
                          onChanged: (v) =>
                              setState(() => _acceptedTerms = v ?? false),
                          title: const Text(
                            'Li e aceito os Termos de Uso e a Política de '
                            'Privacidade (LGPD).',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => context.push(Routes.terms),
                            child: const Text('Ler os termos'),
                          ),
                        ),
                        if (state.hasError) _ErrorLine(state.errorText!),
                      ],
                    ),
                  ),
                  FormField<bool>(
                    validator: (_) => _ageDeclared
                        ? null
                        : 'É preciso declarar a idade mínima para criar a '
                              'conta.',
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          key: const Key('signup-age'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _ageDeclared,
                          onChanged: (v) =>
                              setState(() => _ageDeclared = v ?? false),
                          title: Text('Declaro ter $minAge anos ou mais.'),
                        ),
                        if (state.hasError) _ErrorLine(state.errorText!),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const Key('signup-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('signup-submit'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Criar conta'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grátis. Seus dados ficam só na sua conta e você pode '
                    'excluí-los quando quiser.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 12),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
