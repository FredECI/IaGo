import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';
import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/user_profile.dart';
import 'terms_page.dart';

/// Quanto esperar o perfil antes de liberar o app (CA-T10: falha de rede não
/// impede o uso).
const Duration termsLookupTimeout = Duration(seconds: 6);

enum TermsGateState {
  /// Termos em dia (ou nada a conferir: demo, sem conta, sem rede).
  ok,

  /// Lendo a versão aceita.
  checking,

  /// Versão antiga ou ausente: só o novo aceite ou a exclusão da conta.
  needsAccept,
}

/// Versão dos termos gravada no perfil da conta. Sem conta, sem Firebase, com
/// erro ou sem resposta no prazo, vale a versão atual: a rede nunca prende a
/// pessoa do lado de fora, e o aceite continua valendo no próximo acesso.
final acceptedTermsVersionProvider = StreamProvider<String?>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  final auth = ref.watch(authRepositoryProvider);
  if (owner is! String || auth == null) {
    return Stream.value(AppInfo.termsVersion);
  }
  final controller = StreamController<String?>();
  var answered = false;
  void failOpen() {
    if (!answered && !controller.isClosed) {
      answered = true;
      controller.add(AppInfo.termsVersion);
    }
  }

  final timer = Timer(termsLookupTimeout, failOpen);
  final sub = auth.watchAcceptedTermsVersion().listen((version) {
    answered = true;
    if (!controller.isClosed) controller.add(version);
  }, onError: (Object _) => failOpen());
  ref.onDispose(() {
    timer.cancel();
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

final termsGateProvider = Provider<TermsGateState>((ref) {
  if (ref.watch(dataOwnerProvider) is! String) return TermsGateState.ok;
  final accepted = ref.watch(acceptedTermsVersionProvider);
  return switch (accepted) {
    AsyncData(:final value) =>
      value == AppInfo.termsVersion
          ? TermsGateState.ok
          : TermsGateState.needsAccept,
    AsyncError() => TermsGateState.ok,
    _ => TermsGateState.checking,
  };
});

/// Envolve o app: enquanto a conta estiver em termos antigos, mostra só o
/// novo aceite (com a opção de excluir a conta) no lugar das rotas.
class TermsGate extends ConsumerWidget {
  const TermsGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(termsGateProvider)) {
      TermsGateState.ok => child,
      TermsGateState.checking => _GateShell(
        child: Scaffold(
          body: Center(
            child: Semantics(
              label: 'Conferindo os termos',
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
      ),
      TermsGateState.needsAccept => const _GateShell(
        child: TermsReacceptPage(),
      ),
    };
  }
}

/// O gate fica acima do `Navigator`; campos de texto precisam de um `Overlay`.
class _GateShell extends StatelessWidget {
  const _GateShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]);
}

/// Novo aceite obrigatório dos termos. Quem não aceita (inclusive por ter
/// menos que a idade mínima) pode excluir a conta aqui mesmo (CA-T8).
class TermsReacceptPage extends ConsumerStatefulWidget {
  const TermsReacceptPage({super.key});

  @override
  ConsumerState<TermsReacceptPage> createState() => _TermsReacceptPageState();
}

class _TermsReacceptPageState extends ConsumerState<TermsReacceptPage> {
  final _password = TextEditingController();
  bool _accepted = false;
  bool _ageDeclared = false;
  bool _confirmingDelete = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    if (!_accepted || !_ageDeclared) {
      setState(
        () => _error =
            'Para continuar, aceite os termos e declare a idade mínima.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.acceptTerms(
        termsVersion: AppInfo.termsVersion,
        declaredMinAge: ref.read(accessPolicyProvider).minAge,
      );
      // O perfil muda e o gate libera sozinho.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Digite a senha para confirmar a exclusão.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.deleteAccount(password: _password.text);
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Novos termos de uso'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Atualizamos os termos e a política de privacidade. Para '
                  'continuar usando o IaGo, leia e aceite a versão nova.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 4),
                const TermsContent(),
                const SizedBox(height: 20),
                CheckboxListTile(
                  key: const Key('reaccept-terms'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _accepted,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _accepted = v ?? false),
                  title: const Text(
                    'Li e aceito os Termos de Uso e a Política de '
                    'Privacidade (LGPD).',
                  ),
                ),
                CheckboxListTile(
                  key: const Key('reaccept-age'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _ageDeclared,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _ageDeclared = v ?? false),
                  title: Text('Declaro ter $minAge anos ou mais.'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('reaccept-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('reaccept-submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _accept,
                  child: const Text('Aceitar e continuar'),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Não quer aceitar, ou tem menos de $minAge anos?',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Você pode excluir a conta. Suas questões, listas, '
                  'registros e o que você publicou no Conecta são apagados. '
                  'Uma denúncia sua que ainda está aberta continua até o '
                  'moderador resolver.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (!_confirmingDelete)
                  OutlinedButton(
                    key: const Key('reaccept-delete'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _confirmingDelete = true;
                            _error = null;
                          }),
                    child: const Text('Excluir minha conta'),
                  )
                else ...[
                  TextField(
                    key: const Key('reaccept-delete-password'),
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha para confirmar',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('reaccept-delete-confirm'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: _busy ? null : _delete,
                    child: const Text('Excluir tudo'),
                  ),
                  if (_busy)
                    const Padding(
                      key: Key('reaccept-deleting'),
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Apagando seus dados... Pode levar alguns '
                              'segundos. Denúncias suas ainda abertas '
                              'ficam até a moderação resolver.',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('reaccept-signout'),
                  onPressed: _busy
                      ? null
                      : () => ref.read(sessionProvider.notifier).signOut(),
                  child: const Text('Sair por enquanto'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
