import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/memory_community_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/community_models.dart';
import 'package:iago/features/community/community_providers.dart';

/// CA-C10: na demo, o Conecta é em memória e some ao sair.
void main() {
  const post = NewPost(
    communityId: 'matematica',
    title: 'Dúvida da demo',
    body: 'Isso some ao sair.',
  );

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('demo: Pedro já é membro, com a versão atual das regras', () async {
    final c = container()..read(sessionProvider.notifier).enterDemo();
    final repo = c.read(communityRepositoryProvider);
    expect(repo, isA<MemoryCommunityRepository>());
    final m = await repo.myMembership();
    expect(m, isNotNull);
    expect(m!.rulesVersion, communityRulesVersion);
    expect(m.declaredMinAge, 18);
  });

  test('demo: postar em memória; sair e entrar apaga tudo', () async {
    final c = container()..read(sessionProvider.notifier).enterDemo();
    final first = c.read(communityRepositoryProvider);
    final created = await first.createPost(post);
    expect((await first.myFootprint()).postIds, [created.id]);
    expect(
      (await first.posts('matematica')).items.map((p) => p.id),
      contains(created.id),
    );

    await c.read(sessionProvider.notifier).signOut();
    c.read(sessionProvider.notifier).enterDemo();
    final second = c.read(communityRepositoryProvider);
    expect(identical(first, second), isFalse);
    expect((await second.myFootprint()).postIds, isEmpty);
    expect(
      (await second.posts('matematica')).items.map((p) => p.title),
      isNot(contains(post.title)),
    );
  });

  test('sem sessão, o repositório é vazio e não membro', () async {
    final repo = container().read(communityRepositoryProvider);
    expect(await repo.myMembership(), isNull);
    await expectLater(
      repo.createPost(post),
      throwsA(
        isA<CommunityFailure>().having(
          (e) => e.kind,
          'kind',
          CommunityFailureKind.notMember,
        ),
      ),
    );
  });
}
