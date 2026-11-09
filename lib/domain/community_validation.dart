import 'community_models.dart';

/// Validação das entradas do Conecta, no mesmo limite das regras do
/// Firestore. Lança [CommunityFailure] com `invalidInput` e mensagem em
/// português. Devolvem o texto já aparado.
String validateNickname(String raw) {
  final v = raw.trim();
  if (v.length < nicknameMin || v.length > nicknameMax) {
    throw const CommunityFailure(
      CommunityFailureKind.invalidInput,
      'O apelido precisa ter de $nicknameMin a $nicknameMax caracteres.',
    );
  }
  return v;
}

NewPost validateNewPost(NewPost post) {
  if (communityById(post.communityId) == null) {
    throw const CommunityFailure(
      CommunityFailureKind.invalidInput,
      'Comunidade desconhecida.',
    );
  }
  final title = post.title.trim();
  if (title.length < postTitleMin || title.length > postTitleMax) {
    throw const CommunityFailure(
      CommunityFailureKind.invalidInput,
      'O título precisa ter de $postTitleMin a $postTitleMax caracteres.',
    );
  }
  return NewPost(
    communityId: post.communityId,
    title: title,
    body: validateBody(post.body),
    bankId: post.bankId,
  );
}

String validateBody(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v.length > contentBodyMax) {
    throw const CommunityFailure(
      CommunityFailureKind.invalidInput,
      'O texto precisa ter de 1 a $contentBodyMax caracteres.',
    );
  }
  return v;
}

NewReport validateNewReport(NewReport report) {
  final details = report.details.trim();
  if (details.length > reportDetailsMax) {
    throw const CommunityFailure(
      CommunityFailureKind.invalidInput,
      'Os detalhes podem ter até $reportDetailsMax caracteres.',
    );
  }
  return NewReport(
    targetType: report.targetType,
    targetId: report.targetId,
    postId: report.postId,
    reason: report.reason,
    details: details,
  );
}

/// Segundos que faltam para a próxima escrita, ou 0 se já pode.
int cooldownRemainingSeconds(DateTime? lastWriteAt, DateTime now) {
  if (lastWriteAt == null) return 0;
  final left = lastWriteAt.add(communityCooldown).difference(now);
  if (left <= Duration.zero) return 0;
  return (left.inMilliseconds / 1000).ceil();
}
