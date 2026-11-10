import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../domain/community_models.dart';
import 'community_state.dart';
import 'personal_data.dart';

/// Mensagem em português para uma falha do Conecta.
String communityErrorMessage(
  CommunityFailure failure,
) => switch (failure.kind) {
  CommunityFailureKind.tooSoon =>
    'Aguarde ${failure.waitSeconds} s para publicar de novo.',
  CommunityFailureKind.invalidInput =>
    failure.message.isEmpty
        ? 'Confira o texto e tente de novo.'
        : failure.message,
  CommunityFailureKind.notMember => 'Você não pode escrever no Conecta agora.',
  CommunityFailureKind.alreadyReported => 'Você já denunciou este conteúdo.',
  CommunityFailureKind.ownReply =>
    'Não dá para marcar a própria resposta como "Ajudou".',
  CommunityFailureKind.denied => 'Sem permissão para esta ação.',
  CommunityFailureKind.notFound =>
    'Este conteúdo não existe mais ou foi removido.',
  CommunityFailureKind.unavailable =>
    'Sem conexão com o servidor. Tente de novo.',
};

/// Como [communityErrorMessage], mas aceita qualquer erro: o que não for uma
/// falha do Conecta (por exemplo, o Firebase indisponível) vale "sem conexão".
String communityErrorText(Object error) => communityErrorMessage(
  error is CommunityFailure
      ? error
      : const CommunityFailure(CommunityFailureKind.unavailable),
);

/// Rótulos dos motivos de denúncia (iguais aos das regras da comunidade).
String reportReasonLabel(ReportReason reason) => switch (reason) {
  ReportReason.offensive => 'Ofensivo',
  ReportReason.harassment => 'Assédio',
  ReportReason.personalData => 'Dado pessoal',
  ReportReason.sexualOrMinor => 'Conteúdo sexual ou envolvendo menor',
  ReportReason.copyright => 'Direitos autorais',
  ReportReason.spam => 'Spam',
  ReportReason.other => 'Outro',
};

/// "4 ajudas (média do grupo: 2,5)": o número nunca aparece solto (CA-C7).
String reputationLabel(Reputation r) {
  final avg = r.groupAverage.toStringAsFixed(1).replaceAll('.', ',');
  final n = r.helpful == 1 ? '1 ajuda' : '${r.helpful} ajudas';
  return '$n (média do grupo: $avg)';
}

/// Faixa no conteúdo em análise ou oculto, com o motivo e o contato para
/// contestar (CA-C5). [mine] = é do próprio usuário (a moderação também vê
/// o conteúdo dos outros, sem a parte da contestação).
class ModerationBand extends StatelessWidget {
  const ModerationBand({
    super.key,
    required this.status,
    required this.mine,
    this.reason,
  });

  final ContentStatus status;
  final bool mine;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    if (status == ContentStatus.visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final String text;
    if (status == ContentStatus.pending) {
      text = mine
          ? 'Em análise. Alguém denunciou este conteúdo: os outros membros '
                'não o veem até a moderação revisar (em até 24 horas). Para '
                'contestar, escreva para $communityContactEmail.'
          : 'Em análise: denunciado e escondido dos outros membros.';
    } else {
      final why = (reason == null || reason!.trim().isEmpty)
          ? 'não informado'
          : reason!.trim();
      text = mine
          ? 'Oculto pela moderação. Motivo: $why. Para contestar, escreva '
                'para $communityContactEmail.'
          : 'Oculto pela moderação. Motivo: $why.';
    }
    return Semantics(
      container: true,
      child: Container(
        key: const Key('moderation-band'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de banimento: quem foi banido não escreve (CA-C5).
class BannedNotice extends StatelessWidget {
  const BannedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Container(
        key: const Key('banned-notice'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Sua conta foi banida do Conecta. Você não pode publicar, '
          'responder, marcar "Ajudou" nem denunciar. Para contestar, escreva '
          'para $communityContactEmail.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

/// Apelido de quem escreveu e quando. Tocar no apelido mostra a reputação.
class AuthorLine extends ConsumerWidget {
  const AuthorLine({
    super.key,
    required this.nickname,
    required this.authorUid,
    required this.createdAt,
  });

  final String nickname;
  final String authorUid;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = Formatters.relativeDay(createdAt, ref.watch(clockProvider)());
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          key: Key('author-$authorUid'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => showReputationSheet(context, nickname, authorUid),
          child: Text(nickname),
        ),
        Text(
          '· $when',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Reputação de um membro: "N ajudas (média do grupo: M)" (CA-C7).
class ReputationText extends ConsumerWidget {
  const ReputationText({super.key, required this.uid, this.style});

  final String uid;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rep = ref.watch(reputationProvider(uid));
    return rep.when(
      data: (r) =>
          Text(reputationLabel(r), key: Key('reputation-$uid'), style: style),
      loading: () => Text('Carregando reputação...', style: style),
      error: (_, _) => Text('Reputação indisponível agora.', style: style),
    );
  }
}

Future<void> showReputationSheet(
  BuildContext context,
  String nickname,
  String uid,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nickname, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ReputationText(uid: uid),
          ],
        ),
      ),
    ),
  );
}

/// Avisa antes de publicar texto que pareça telefone, e-mail ou CPF (CA-C9).
/// Devolve `true` se pode publicar (nada suspeito ou o usuário insistiu).
Future<bool> confirmPersonalData(
  BuildContext context,
  List<String> texts,
) async {
  final kinds = <PersonalDataKind>{
    for (final t in texts) ...detectPersonalData(t),
  };
  if (kinds.isEmpty) return true;
  final names = kinds.map((k) => k.label).join(', ');
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('personal-data-dialog'),
      title: const Text('Dado pessoal no texto?'),
      content: Text(
        'O texto parece ter $names. As regras da comunidade não permitem '
        'dados pessoais, seus ou de outras pessoas, e todos os membros '
        'veriam. Quer revisar antes de publicar?',
      ),
      actions: [
        TextButton(
          key: const Key('personal-data-publish'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Publicar mesmo assim'),
        ),
        FilledButton(
          key: const Key('personal-data-review'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Revisar'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// Pede o motivo (e detalhes opcionais) da denúncia. `null` = cancelou.
Future<({ReportReason reason, String details})?> askReport(
  BuildContext context,
) {
  return showDialog<({ReportReason reason, String details})>(
    context: context,
    builder: (context) => const _ReportDialog(),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('report-dialog'),
      title: const Text('Denunciar'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O conteúdo some para os outros membros até a moderação revisar. '
            'Não dá para cancelar a denúncia.',
          ),
          const SizedBox(height: 8),
          for (final r in ReportReason.values)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: _reason == r,
              child: ListTile(
                key: Key('report-reason-${r.wireName}'),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                leading: Icon(
                  _reason == r
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(reportReasonLabel(r)),
                onTap: () => setState(() => _reason = r),
              ),
            ),
          TextField(
            key: const Key('report-details'),
            controller: _details,
            maxLength: reportDetailsMax,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('report-submit'),
          onPressed: _reason == null
              ? null
              : () => Navigator.pop(context, (
                  reason: _reason!,
                  details: _details.text,
                )),
          child: const Text('Denunciar'),
        ),
      ],
    );
  }
}
