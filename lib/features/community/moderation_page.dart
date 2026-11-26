import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../domain/community_models.dart';
import '../../shared/common_widgets.dart';
import 'community_providers.dart';
import 'community_state.dart';
import 'community_widgets.dart';

/// Fila de denúncias abertas, só para moderador: restaurar, ocultar com
/// motivo, ocultar e banir. Denúncia de conteúdo apagado só se dispensa.
class ModerationPage extends ConsumerStatefulWidget {
  const ModerationPage({super.key});

  @override
  ConsumerState<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends ConsumerState<ModerationPage> {
  List<ModerationItem> _items = const [];
  bool _loading = true;
  bool _started = false;
  String? _error;
  String? _busyId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(communityRepositoryProvider).openReports();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = communityErrorText(failure);
        _loading = false;
      });
    }
  }

  Future<void> _decide(ModerationItem item, ModerationDecision decision) async {
    setState(() => _busyId = item.report.id);
    try {
      await ref
          .read(communityRepositoryProvider)
          .resolve(item.report.id, decision);
      if (!mounted) return;
      showMessage(context, 'Denúncia resolvida.');
      await _load();
    } catch (failure) {
      if (mounted) showMessage(context, communityErrorText(failure));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _hide(ModerationItem item, {required bool ban}) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(ban: ban),
    );
    if (reason == null || !mounted) return;
    await _decide(
      item,
      ModerationDecision(
        ban ? ModerationKind.hideAndBan : ModerationKind.hide,
        reason: reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moderator = ref.watch(isModeratorProvider);
    Widget body;
    if (moderator.isLoading && !moderator.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (moderator.value != true) {
      body = const EmptyState(
        key: Key('moderation-denied'),
        icon: Icons.lock_outline,
        title: 'Sem acesso',
        message: 'A moderação é só para quem está na escala de moderadores.',
      );
    } else {
      if (!_started) {
        _started = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
      body = _queue();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Moderação')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _queue() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar a fila',
        message: _error,
        action: FilledButton(
          key: const Key('moderation-retry'),
          onPressed: _load,
          child: const Text('Tentar de novo'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.task_alt_outlined,
        title: 'Nenhuma denúncia aberta',
        message: 'A fila está em dia.',
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          _items.length == 1
              ? '1 denúncia aberta (revisar em até 24 horas)'
              : '${_items.length} denúncias abertas (revisar em até 24 horas)',
          key: const Key('moderation-count'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final item in _items)
          _ReportCard(
            item: item,
            busy: _busyId == item.report.id,
            onRestore: () =>
                _decide(item, const ModerationDecision(ModerationKind.restore)),
            onHide: () => _hide(item, ban: false),
            onBan: () => _hide(item, ban: true),
          ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.busy,
    required this.onRestore,
    required this.onHide,
    required this.onBan,
  });

  final ModerationItem item;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onHide;
  final VoidCallback onBan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = item.report;
    final kind = report.targetType == ReportTarget.post
        ? 'Post denunciado'
        : 'Resposta denunciada';
    return Card(
      key: Key('report-${report.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$kind: ${reportReasonLabel(report.reason)}',
              style: theme.textTheme.titleSmall,
            ),
            Text(
              'Denunciado por ${report.reporterUid} em '
              '${Formatters.dateTime(report.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (report.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Detalhes: ${report.details}'),
            ],
            const Divider(),
            if (item.targetDeleted)
              Text(
                'Conteúdo apagado',
                key: Key('deleted-${report.id}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              Text(
                'Autor: ${item.authorNickname}',
                style: theme.textTheme.bodySmall,
              ),
              if (item.title != null)
                Text(item.title!, style: theme.textTheme.titleMedium),
              // Texto puro, como no fórum (CA-C8).
              Text(item.body),
            ],
            const SizedBox(height: 8),
            if (busy)
              const LinearProgressIndicator()
            else if (item.targetDeleted)
              OutlinedButton(
                key: Key('dismiss-${report.id}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: onRestore,
                child: const Text('Dispensar'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: Key('restore-${report.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: onRestore,
                    child: const Text('Restaurar'),
                  ),
                  OutlinedButton(
                    key: Key('hide-${report.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: onHide,
                    child: const Text('Ocultar'),
                  ),
                  FilledButton(
                    key: Key('ban-${report.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: onBan,
                    child: const Text('Ocultar e banir'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Pede o motivo (obrigatório) mostrado ao autor.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.ban});

  final bool ban;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _reason.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Escreva o motivo: o autor vai ler.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('reason-dialog'),
      scrollable: true,
      title: Text(widget.ban ? 'Ocultar e banir' : 'Ocultar com motivo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.ban)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'A pessoa autora será banida: não publica, responde, marca '
                '"Ajudou" nem denuncia.',
              ),
            ),
          TextField(
            key: const Key('reason-field'),
            controller: _reason,
            maxLength: 200,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Motivo (o autor vê)',
              helperText: 'Uma frase curta e neutra, sem dados pessoais.',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('reason-confirm'),
          onPressed: _confirm,
          child: Text(widget.ban ? 'Ocultar e banir' : 'Ocultar'),
        ),
      ],
    );
  }
}
