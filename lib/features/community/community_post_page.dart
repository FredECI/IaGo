import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../data/community_repository.dart';
import '../../domain/community_models.dart';
import '../../domain/community_validation.dart';
import '../../shared/common_widgets.dart';
import 'community_providers.dart';
import 'community_state.dart';
import 'community_widgets.dart';

/// Conversa: o post, as respostas em ordem cronológica e "Ajudou".
class CommunityPostPage extends ConsumerStatefulWidget {
  const CommunityPostPage({
    super.key,
    required this.communityId,
    required this.postId,
  });

  final String communityId;
  final String postId;

  @override
  ConsumerState<CommunityPostPage> createState() => _CommunityPostPageState();
}

class _CommunityPostPageState extends ConsumerState<CommunityPostPage> {
  static const int _maxSearchPages = 10;

  Post? _post;
  List<Reply> _replies = const [];
  Map<String, int> _counts = const {};
  Set<String> _myVotes = const {};
  bool _loading = true;
  String? _error;
  bool _started = false;

  final _reply = TextEditingController();
  bool _sending = false;
  String? _replyError;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Object? extra;
    try {
      extra = GoRouterState.of(context).extra;
    } catch (_) {
      extra = null;
    }
    if (extra is Post && extra.id == widget.postId) _post = extra;
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  /// Sem o post vindo da lista (link direto), procura nas primeiras páginas.
  Future<Post?> _find() async {
    Object? cursor;
    for (var i = 0; i < _maxSearchPages; i++) {
      final page = await _repo.posts(widget.communityId, cursor: cursor);
      for (final p in page.items) {
        if (p.id == widget.postId) return p;
      }
      cursor = page.nextCursor;
      if (cursor == null) break;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _post ??= await _find();
      if (_post == null) {
        throw const CommunityFailure(CommunityFailureKind.notFound);
      }
      final results = await Future.wait<Object>([
        _repo.replies(widget.postId),
        _repo.helpfulCounts(widget.postId),
        _repo.myHelpfulVotes(widget.postId),
      ]);
      if (!mounted) return;
      setState(() {
        _replies = results[0] as List<Reply>;
        _counts = results[1] as Map<String, int>;
        _myVotes = results[2] as Set<String>;
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

  Future<void> _toggleHelpful(Reply reply) async {
    final marked = _myVotes.contains(reply.id);
    try {
      await _repo.setHelpful(reply, helpful: !marked);
      if (!mounted) return;
      setState(() {
        final votes = {..._myVotes};
        final counts = {..._counts};
        final now = counts[reply.id] ?? 0;
        if (marked) {
          votes.remove(reply.id);
          counts[reply.id] = now > 0 ? now - 1 : 0;
        } else {
          votes.add(reply.id);
          counts[reply.id] = now + 1;
        }
        _myVotes = votes;
        _counts = counts;
      });
    } catch (failure) {
      if (mounted) showMessage(context, communityErrorText(failure));
    }
  }

  Future<void> _send() async {
    final String text;
    try {
      text = validateBody(_reply.text);
    } catch (failure) {
      setState(() => _replyError = communityErrorText(failure));
      return;
    }
    if (!await confirmPersonalData(context, [text])) return;
    if (!mounted) return;
    setState(() {
      _sending = true;
      _replyError = null;
    });
    try {
      await _repo.reply(widget.postId, text);
      if (!mounted) return;
      _reply.clear();
      await _load();
    } catch (failure) {
      if (mounted) setState(() => _replyError = communityErrorText(failure));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report({
    required ReportTarget target,
    required String id,
  }) async {
    final answer = await askReport(context);
    if (answer == null || !mounted) return;
    try {
      await _repo.report(
        NewReport(
          targetType: target,
          targetId: id,
          postId: widget.postId,
          reason: answer.reason,
          details: answer.details,
        ),
      );
    } catch (failure) {
      if (mounted) showMessage(context, communityErrorText(failure));
      return;
    }
    if (!mounted) return;
    if (target == ReportTarget.post) {
      showMessage(
        context,
        'Denúncia enviada. O post some para os outros membros até a '
        'moderação revisar.',
      );
      _leave();
    } else {
      showMessage(
        context,
        'Denúncia enviada. A resposta some para os outros membros até a '
        'moderação revisar.',
      );
      await _load();
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.communityRoom(widget.communityId));
    }
  }

  Future<void> _delete({
    required ReportTarget target,
    required String id,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          target == ReportTarget.post ? 'Apagar o post?' : 'Apagar a resposta?',
        ),
        content: const Text('Não dá para desfazer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (target == ReportTarget.post) {
        await _repo.deletePost(id);
        if (mounted) _leave();
      } else {
        await _repo.deleteReply(id);
        if (mounted) await _load();
      }
    } catch (failure) {
      if (mounted) showMessage(context, communityErrorText(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final banned = ref.watch(isBannedProvider).value ?? false;
    final uid = ref.watch(communityUidProvider);

    Widget body;
    if (banned) {
      body = const Padding(padding: EdgeInsets.all(16), child: BannedNotice());
    } else if (_loading && _post == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar',
        message: _error,
        action: FilledButton(
          key: const Key('conversation-retry'),
          onPressed: _load,
          child: const Text('Tentar de novo'),
        ),
      );
    } else {
      body = Column(
        children: [
          Expanded(child: _conversation(uid)),
          _composer(),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conversa')),
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

  bool _isMine(String authorUid, String? uid) =>
      uid == null || authorUid == uid;

  Widget _conversation(String? uid) {
    final theme = Theme.of(context);
    final post = _post!;
    final mine = _isMine(post.authorUid, uid);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Card(
          key: const Key('conversation-post'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ModerationBand(
                    status: post.status,
                    mine: mine,
                    reason: post.moderationReason,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _MoreMenu(
                      keyPrefix: 'post',
                      mine: mine,
                      onReport: () =>
                          _report(target: ReportTarget.post, id: post.id),
                      onDelete: () =>
                          _delete(target: ReportTarget.post, id: post.id),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // Texto puro: nada de link clicável, HTML ou imagem (CA-C8).
                  child: Text(post.body, style: theme.textTheme.bodyMedium),
                ),
                AuthorLine(
                  nickname: post.authorNickname,
                  authorUid: post.authorUid,
                  createdAt: post.createdAt,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _replies.isEmpty
              ? 'Respostas'
              : Formatters.count(_replies.length, 'resposta', 'respostas'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (_replies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Ainda sem respostas. Seja o primeiro a ajudar.',
              key: const Key('no-replies'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final reply in _replies) _replyCard(reply, uid),
      ],
    );
  }

  Widget _replyCard(Reply reply, String? uid) {
    final theme = Theme.of(context);
    final mine = _isMine(reply.authorUid, uid);
    final count = _counts[reply.id] ?? 0;
    final marked = _myVotes.contains(reply.id);
    return Card(
      key: Key('reply-${reply.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ModerationBand(
                status: reply.status,
                mine: mine,
                reason: reply.moderationReason,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(reply.body, style: theme.textTheme.bodyMedium),
                ),
                _MoreMenu(
                  keyPrefix: 'reply-${reply.id}',
                  mine: mine,
                  onReport: () =>
                      _report(target: ReportTarget.reply, id: reply.id),
                  onDelete: () =>
                      _delete(target: ReportTarget.reply, id: reply.id),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AuthorLine(
                  nickname: reply.authorNickname,
                  authorUid: reply.authorUid,
                  createdAt: reply.createdAt,
                ),
                // Na própria resposta não há como marcar (CA-C6).
                TextButton.icon(
                  key: Key('helpful-${reply.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: mine || reply.status != ContentStatus.visible
                      ? null
                      : () => _toggleHelpful(reply),
                  icon: Icon(
                    marked ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                  ),
                  label: Text(
                    marked
                        ? 'Ajudou ($count) - você marcou'
                        : 'Ajudou ($count)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final theme = Theme.of(context);
    final post = _post;
    if (post == null) return const SizedBox.shrink();
    if (post.status != ContentStatus.visible) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Este post está escondido pela moderação: não dá para responder.',
          key: const Key('reply-closed'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _replyError!,
                  key: const Key('reply-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('reply-field'),
                    controller: _reply,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: contentBodyMax,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    decoration: const InputDecoration(
                      labelText: 'Sua resposta',
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('reply-send'),
                  tooltip: 'Enviar resposta',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Menu de ações do post ou da resposta: denunciar (dos outros) ou apagar
/// (do próprio).
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.keyPrefix,
    required this.mine,
    required this.onReport,
    required this.onDelete,
  });

  final String keyPrefix;
  final bool mine;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: Key('more-$keyPrefix'),
      tooltip: 'Mais ações',
      onSelected: (v) => v == 'report' ? onReport() : onDelete(),
      itemBuilder: (_) => [
        if (mine)
          PopupMenuItem(
            key: Key('delete-$keyPrefix'),
            value: 'delete',
            child: const Text('Apagar'),
          )
        else
          PopupMenuItem(
            key: Key('report-$keyPrefix'),
            value: 'report',
            child: const Text('Denunciar'),
          ),
      ],
    );
  }
}
