import '../domain/community_models.dart';

/// Conecta (fórum). Nenhuma regra de idade ou convite mora aqui: quem decide
/// se o usuário pode ver ou entrar é a `AccessPolicy`, na camada de cima.
/// Falhas esperadas lançam [CommunityFailure]. Implementações: memória (demo)
/// e Firestore.
abstract interface class CommunityRepository {
  /// `null` se ainda não entrou.
  Future<Membership?> myMembership();

  /// Entra: cria a participação e o perfil público no mesmo lote.
  Future<void> join({
    required String nickname,
    String? inviteCode,
    required int declaredMinAge,
    required String rulesVersion,
  });

  /// Troca o apelido (nas duas coleções, no mesmo lote). Os posts antigos
  /// mantêm o apelido de quando foram escritos.
  Future<void> rename(String nickname);

  /// Sai da comunidade (apaga participação e perfil público).
  Future<void> leave();

  /// Posts da comunidade, do mais novo ao mais antigo. Os visíveis de todos;
  /// na 1ª página, também os do próprio autor que estão em análise ou ocultos.
  Future<PostPage> posts(String communityId, {Object? cursor, int limit = 20});

  Future<Post> createPost(NewPost post);

  /// Conversa em ordem cronológica (visíveis e as próprias).
  Future<List<Reply>> replies(String postId);

  Future<Reply> reply(String postId, String body);

  /// Ids das respostas do post que o usuário marcou como "Ajudou".
  Future<Set<String>> myHelpfulVotes(String postId);

  Future<int> helpfulCount(String replyId);

  /// Ajudas de todas as respostas do post, numa consulta só.
  Future<Map<String, int>> helpfulCounts(String postId);

  /// Marca ou desmarca. Na própria resposta lança `ownReply`.
  Future<void> setHelpful(Reply reply, {required bool helpful});

  /// Ajudas recebidas e a média do grupo.
  Future<Reputation> reputation(String uid);

  /// Lança `alreadyReported` se o usuário já denunciou esse conteúdo.
  Future<void> report(NewReport report);

  Future<void> deletePost(String id);
  Future<void> deleteReply(String id);

  Future<bool> isModerator();
  Future<bool> isBanned();

  /// Fila de moderação (só moderador).
  Future<List<ModerationItem>> openReports();

  /// Decide a denúncia (só moderador); a denúncia fica `resolved`.
  Future<void> resolve(String reportId, ModerationDecision decision);

  /// Tudo o que o usuário tem no Conecta, para a exclusão de conta (C5).
  Future<CommunityFootprint> myFootprint();
}
