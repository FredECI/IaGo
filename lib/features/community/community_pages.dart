import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/access_policy.dart';
import '../../domain/community_models.dart';
import '../../domain/community_validation.dart';
import '../../domain/user_profile.dart';
import '../../shared/common_widgets.dart';
import 'community_access.dart';
import 'community_providers.dart';

// As telas do Conecta moram em arquivos próprios; o roteador importa só este.
export 'community_home_page.dart';
export 'community_post_page.dart';
export 'community_room_page.dart';
export 'moderation_page.dart';

/// Resumo das regras da comunidade (a versão completa é o documento
/// `docs/conecta/regras-da-comunidade.md`, versão `communityRulesVersion`).
const List<String> communityRulesSummary = [
  'A comunidade é fechada: só entram pessoas convidadas, com e-mail '
      'verificado e a idade mínima do piloto.',
  'Os outros membros veem só o apelido, os posts, as respostas e a contagem '
      'de "Ajudou". A idade declarada, o convite e o e-mail são privados.',
  'Nada de ofensa, assédio, dado pessoal, spam, propaganda, cópia de '
      'material com direitos ou conteúdo sexual envolvendo menores.',
  'Sem mensagem direta, anexo ou link clicável. Um post ou resposta a cada '
      '30 segundos.',
  'Conteúdo denunciado some para os outros até a moderação revisar, em até '
      '24 horas. A moderação pode restaurar, ocultar ou banir.',
  'Ao excluir a conta, seus posts, respostas e "Ajudou" são apagados. Uma '
      'denúncia sua ainda aberta continua até a moderação resolver.',
];

/// Entrar no piloto do Conecta: e-mail verificado, convite (se a política
/// exigir), idade mínima, apelido e aceite das regras. A entrada grava
/// `memberships` e `profiles` no mesmo lote (`CommunityRepository.join`).
class BecomeMemberPage extends ConsumerStatefulWidget {
  const BecomeMemberPage({super.key});

  @override
  ConsumerState<BecomeMemberPage> createState() => _BecomeMemberPageState();
}

class _BecomeMemberPageState extends ConsumerState<BecomeMemberPage> {
  final _invite = TextEditingController();
  final _nickname = TextEditingController();
  bool _ageDeclared = false;
  bool _rulesAccepted = false;
  bool _busy = false;
  bool _verifiedNow = false;
  String? _error;
  String? _verifyInfo;

  @override
  void dispose() {
    _invite.dispose();
    _nickname.dispose();
    super.dispose();
  }

  bool get _emailVerified =>
      _verifiedNow ||
      (ref.read(authUserProvider).value?.emailVerified ?? false);

  Future<void> _resend() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    try {
      await auth.sendEmailVerification();
      if (mounted) {
        setState(
          () => _verifyInfo =
              'Enviamos o e-mail. Confira a caixa de '
              'entrada e o spam.',
        );
      }
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _verifyInfo = failure.message);
    }
  }

  Future<void> _recheck() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    try {
      final verified = await auth.refreshEmailVerified();
      if (!mounted) return;
      setState(() {
        _verifiedNow = verified;
        _verifyInfo = verified
            ? null
            : 'Ainda não consta como verificado. Abra o link do e-mail e '
                  'toque aqui de novo.';
      });
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _verifyInfo = failure.message);
    }
  }

  Future<void> _join() async {
    final policy = ref.read(accessPolicyProvider);
    final invite = _invite.text.trim();
    String? problem;
    if (!_emailVerified) {
      problem = 'Verifique o seu e-mail antes de entrar.';
    } else if (policy.inviteRequired && invite.isEmpty) {
      problem = 'Informe o código de convite.';
    } else if (!_ageDeclared) {
      problem = 'Declare a idade mínima para entrar.';
    } else if (!_rulesAccepted) {
      problem = 'Aceite as regras da comunidade para entrar.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      validateNickname(_nickname.text);
      await ref
          .read(communityRepositoryProvider)
          .join(
            nickname: _nickname.text,
            inviteCode: policy.inviteRequired ? invite : null,
            declaredMinAge: policy.minAge,
            rulesVersion: communityRulesVersion,
          );
      ref.invalidate(myMembershipProvider);
      await ref.read(myMembershipProvider.future);
      if (mounted) {
        // Conecta desligado: o fórum não abre, volta ao Painel.
        context.go(
          ref.read(conectaVisibleProvider)
              ? Routes.community
              : Routes.dashboard,
        );
      }
    } on CommunityFailure catch (failure) {
      if (mounted) setState(() => _error = _messageFor(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mensagem em português; "negado" no servidor é convite, e-mail ou idade.
  String _messageFor(CommunityFailure failure) => switch (failure.kind) {
    CommunityFailureKind.denied =>
      'Não foi possível entrar. Confira o código de convite. Se você acabou '
          'de verificar o e-mail, toque em "Já verifiquei" de novo ou saia e '
          'entre na conta.',
    CommunityFailureKind.unavailable =>
      'Sem conexão com o servidor. Tente de novo.',
    _ =>
      failure.message.isEmpty
          ? 'Não foi possível entrar agora. Tente de novo.'
          : failure.message,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = ref.watch(accessPolicyProvider);
    final membership = ref.watch(myMembershipProvider);
    final conectaOn = ref.watch(conectaVisibleProvider);
    ref.watch(authUserProvider);

    Widget body;
    if (membership.isLoading && !membership.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (membership.value case final Membership m) {
      body = EmptyState(
        icon: Icons.how_to_reg_outlined,
        title: 'Você já faz parte',
        message: conectaOn
            ? 'Você participa do Conecta como ${m.nickname}.'
            : 'Você é membro do piloto como ${m.nickname}. A IA e as '
                  'avaliações já estão liberadas.',
        action: FilledButton(
          key: const Key('join-open'),
          onPressed: () =>
              context.go(conectaOn ? Routes.community : Routes.dashboard),
          child: Text(conectaOn ? 'Abrir o Conecta' : 'Voltar ao Painel'),
        ),
      );
    } else {
      body = _form(theme, policy, conectaOn);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar no piloto')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme, AccessPolicy policy, bool conectaOn) {
    final verified = _emailVerified;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          conectaOn
              ? 'O Conecta é um espaço fechado para estudar junto. Para '
                    'entrar, precisamos de mais algumas coisas.'
              : 'O piloto é fechado: quem entra libera a IA (importar de '
                    'prints e PDF, proposta do Direciona) e as avaliações do '
                    'acervo. Para entrar, precisamos de mais algumas coisas.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Card(
          key: const Key('join-verify-card'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      verified ? Icons.check_circle : Icons.mail_outline,
                      color: verified
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        verified
                            ? 'E-mail verificado'
                            : 'Verifique o seu e-mail',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (!verified) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Enviamos um link de verificação para o seu e-mail. '
                    'Abra o link e volte aqui.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const Key('join-resend'),
                        onPressed: _resend,
                        child: const Text('Reenviar e-mail'),
                      ),
                      TextButton(
                        key: const Key('join-recheck'),
                        onPressed: _recheck,
                        child: const Text('Já verifiquei'),
                      ),
                    ],
                  ),
                  if (_verifyInfo != null)
                    Text(_verifyInfo!, key: const Key('join-verify-info')),
                ],
              ],
            ),
          ),
        ),
        if (policy.inviteRequired) ...[
          const SizedBox(height: 16),
          TextField(
            key: const Key('join-invite'),
            controller: _invite,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Código de convite',
              helperText: 'Quem convidou você passa o código.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('join-nickname'),
          controller: _nickname,
          decoration: InputDecoration(
            labelText: 'Apelido',
            helperText:
                'De $nicknameMin a $nicknameMax caracteres. Os outros membros '
                'veem só o apelido: não use o seu nome completo.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('join-age'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _ageDeclared,
          onChanged: _busy
              ? null
              : (v) => setState(() => _ageDeclared = v ?? false),
          title: Text('Declaro ter ${policy.minAge} anos ou mais.'),
        ),
        ExpansionTile(
          key: const Key('join-rules-summary'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Regras da comunidade (resumo)'),
          subtitle: Text('Versão $communityRulesVersion'),
          children: [
            for (final line in communityRulesSummary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
          ],
        ),
        CheckboxListTile(
          key: const Key('join-rules'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _rulesAccepted,
          onChanged: _busy
              ? null
              : (v) => setState(() => _rulesAccepted = v ?? false),
          title: const Text('Li e aceito as regras da comunidade.'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('join-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('join-submit'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _join,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Entrar no piloto'),
        ),
      ],
    );
  }
}
