import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/community_repository.dart';
import '../../domain/community_models.dart';
import '../../domain/community_validation.dart';
import '../../shared/common_widgets.dart';
import 'community_providers.dart';
import 'community_state.dart';
import 'community_widgets.dart';

/// Posts de uma comunidade, do mais novo ao mais antigo, com "Carregar mais".
class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key, required this.communityId});

  final String communityId;

  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage> {
  static const int _pageSize = 20;

  final List<Post> _posts = [];
  Object? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  Community? get _community => communityById(widget.communityId);

  @override
  void initState() {
    super.initState();
    if (_community != null) _reload();
  }

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.posts(widget.communityId, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
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

  Future<void> _more() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.posts(
        widget.communityId,
        cursor: _cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
      });
    } catch (failure) {
      if (mounted) showMessage(context, communityErrorText(failure));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _write() async {
    final created = await showModalBottomSheet<Post>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PostSheet(communityId: widget.communityId),
    );
    if (created == null || !mounted) return;
    showMessage(context, 'Post publicado.');
    await _reload();
  }

  Future<void> _open(Post post) async {
    // O aviso "Post publicado" cobriria o campo de resposta.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await context.push(
      Routes.communityPost(widget.communityId, post.id),
      extra: post,
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final community = _community;
    if (community == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comunidade')),
        body: const EmptyState(
          icon: Icons.groups_outlined,
          title: 'Comunidade não encontrada',
          message: 'Volte ao Conecta e escolha uma das comunidades.',
        ),
      );
    }
    final banned = ref.watch(isBannedProvider).value ?? false;
    final uid = ref.watch(communityUidProvider);

    Widget body;
    if (banned) {
      body = const Padding(padding: EdgeInsets.all(16), child: BannedNotice());
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar',
        message: _error,
        action: FilledButton(
          key: const Key('room-retry'),
          onPressed: _reload,
          child: const Text('Tentar de novo'),
        ),
      );
    } else if (_posts.isEmpty) {
      body = const EmptyState(
        icon: Icons.forum_outlined,
        title: 'Ainda não há conversas aqui',
        message: 'Escreva o primeiro post desta comunidade.',
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          for (final post in _posts)
            _PostCard(
              post: post,
              mine: uid == null || post.authorUid == uid,
              onTap: () => _open(post),
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(
                key: const Key('room-more'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _loadingMore ? null : _more,
                child: _loadingMore
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Carregar mais'),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(community.name)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: body,
          ),
        ),
      ),
      floatingActionButton: banned
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-post'),
              heroTag: null,
              onPressed: _write,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Escrever post'),
            ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({
    required this.post,
    required this.mine,
    required this.onTap,
  });

  final Post post;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      key: Key('post-${post.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ModerationBand(
                status: post.status,
                mine: mine,
                reason: post.moderationReason,
              ),
              Text(post.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                post.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
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
    );
  }
}

/// Escrever um post (título e texto, sempre texto puro).
class _PostSheet extends ConsumerStatefulWidget {
  const _PostSheet({required this.communityId});

  final String communityId;

  @override
  ConsumerState<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends ConsumerState<_PostSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final NewPost input;
    try {
      input = validateNewPost(
        NewPost(
          communityId: widget.communityId,
          title: _title.text,
          body: _body.text,
        ),
      );
    } catch (failure) {
      setState(() => _error = communityErrorText(failure));
      return;
    }
    if (!await confirmPersonalData(context, [input.title, input.body])) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final post = await ref
          .read(communityRepositoryProvider)
          .createPost(input);
      if (mounted) Navigator.pop(context, post);
    } catch (failure) {
      if (mounted) {
        setState(() {
          _error = communityErrorText(failure);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escrever post', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Só texto. Não use dados pessoais. Links e marcações aparecem '
              'como texto comum.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('post-title'),
              controller: _title,
              maxLength: postTitleMax,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('post-body'),
              controller: _body,
              maxLength: contentBodyMax,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Texto'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  key: const Key('post-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('post-submit'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }
}
