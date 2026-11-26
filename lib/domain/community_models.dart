/// Modelos do Conecta (fórum). Dart puro: sem Flutter nem Firebase.
library;

/// Intervalo mínimo entre duas escritas (post ou resposta), igual a
/// `conectaCooldown()` nas regras (CA-R7).
const Duration communityCooldown = Duration(seconds: 30);

/// Limites iguais aos das regras do Firestore.
const int nicknameMin = 3;
const int nicknameMax = 24;
const int postTitleMin = 5;
const int postTitleMax = 120;
const int contentBodyMax = 2000;
const int reportDetailsMax = 500;

/// Uma das cinco comunidades fixas (as quatro áreas e o reforço).
class Community {
  const Community({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

const List<Community> communities = [
  Community(
    id: 'linguagens',
    name: 'Linguagens',
    description: 'Português, literatura, redação e línguas.',
  ),
  Community(
    id: 'humanas',
    name: 'Humanas',
    description: 'História, geografia, filosofia e sociologia.',
  ),
  Community(
    id: 'natureza',
    name: 'Natureza',
    description: 'Física, química e biologia.',
  ),
  Community(
    id: 'matematica',
    name: 'Matemática',
    description: 'Álgebra, funções, geometria e estatística.',
  ),
  Community(
    id: 'reforco',
    name: 'Reforço',
    description: 'Para quem dá aula de reforço: trocar ideias e materiais.',
  ),
];

Community? communityById(String id) {
  for (final c in communities) {
    if (c.id == id) return c;
  }
  return null;
}

enum ContentStatus {
  visible,
  pending,
  hidden;

  static ContentStatus? tryParse(Object? value) =>
      ContentStatus.values.asNameMap()[value];
}

class Membership {
  const Membership({
    required this.nickname,
    required this.declaredMinAge,
    required this.rulesVersion,
    required this.joinedAt,
    this.inviteCode,
  });

  final String nickname;
  final int declaredMinAge;
  final String rulesVersion;
  final DateTime joinedAt;
  final String? inviteCode;
}

class Post {
  const Post({
    required this.id,
    required this.communityId,
    required this.authorUid,
    required this.authorNickname,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.bankId,
    this.moderationReason,
  });

  final String id;
  final String communityId;
  final String authorUid;
  final String authorNickname;
  final String title;
  final String body;
  final String? bankId;
  final ContentStatus status;
  final String? moderationReason;
  final DateTime createdAt;

  Post copyWith({ContentStatus? status, String? moderationReason}) => Post(
    id: id,
    communityId: communityId,
    authorUid: authorUid,
    authorNickname: authorNickname,
    title: title,
    body: body,
    bankId: bankId,
    status: status ?? this.status,
    moderationReason: moderationReason ?? this.moderationReason,
    createdAt: createdAt,
  );
}

class Reply {
  const Reply({
    required this.id,
    required this.postId,
    required this.authorUid,
    required this.authorNickname,
    required this.body,
    required this.status,
    required this.createdAt,
    this.moderationReason,
  });

  final String id;
  final String postId;
  final String authorUid;
  final String authorNickname;
  final String body;
  final ContentStatus status;
  final String? moderationReason;
  final DateTime createdAt;

  Reply copyWith({ContentStatus? status, String? moderationReason}) => Reply(
    id: id,
    postId: postId,
    authorUid: authorUid,
    authorNickname: authorNickname,
    body: body,
    status: status ?? this.status,
    moderationReason: moderationReason ?? this.moderationReason,
    createdAt: createdAt,
  );
}

class NewPost {
  const NewPost({
    required this.communityId,
    required this.title,
    required this.body,
    this.bankId,
  });

  final String communityId;
  final String title;
  final String body;
  final String? bankId;
}

/// Página de posts. O cursor é opaco: só a implementação o entende.
class PostPage {
  const PostPage({required this.items, this.nextCursor});

  final List<Post> items;

  /// `null` = última página.
  final Object? nextCursor;
}

class Reputation {
  const Reputation({required this.helpful, required this.groupAverage});

  /// Ajudas recebidas.
  final int helpful;

  /// Média de ajudas por membro (o número nunca aparece solto, CA-C7).
  final double groupAverage;
}

enum ReportTarget { post, reply }

enum ReportReason {
  offensive('offensive'),
  harassment('harassment'),
  personalData('personal_data'),
  sexualOrMinor('sexual_or_minor'),
  copyright('copyright'),
  spam('spam'),
  other('other');

  const ReportReason(this.wireName);
  final String wireName;

  static ReportReason? tryParse(Object? value) {
    for (final r in ReportReason.values) {
      if (r.wireName == value) return r;
    }
    return null;
  }
}

class NewReport {
  const NewReport({
    required this.targetType,
    required this.targetId,
    required this.postId,
    required this.reason,
    this.details = '',
  });

  final ReportTarget targetType;
  final String targetId;

  /// Para post, o próprio id do post; para resposta, o post da conversa.
  final String postId;
  final ReportReason reason;
  final String details;
}

/// Denúncia como o moderador a vê.
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.postId,
    required this.reason,
    required this.details,
    required this.reporterUid,
    required this.open,
    required this.createdAt,
  });

  final String id;
  final ReportTarget targetType;
  final String targetId;
  final String postId;
  final ReportReason reason;
  final String details;
  final String reporterUid;
  final bool open;
  final DateTime createdAt;
}

/// Item da fila de moderação: a denúncia e o conteúdo denunciado.
class ModerationItem {
  const ModerationItem({
    required this.report,
    required this.authorUid,
    required this.authorNickname,
    required this.body,
    required this.status,
    this.title,
    this.targetDeleted = false,
  });

  /// Denúncia cujo conteúdo já foi apagado: o moderador só a dispensa (os
  /// demais campos vêm vazios).
  const ModerationItem.deleted(this.report)
    : authorUid = '',
      authorNickname = '',
      title = null,
      body = '',
      status = ContentStatus.hidden,
      targetDeleted = true;

  final bool targetDeleted;
  final ReportRecord report;
  final String authorUid;
  final String authorNickname;
  final String? title; // só posts
  final String body;
  final ContentStatus status;
}

enum ModerationKind {
  restore('restored'),
  hide('hidden'),
  hideAndBan('hidden_banned');

  const ModerationKind(this.wireName);
  final String wireName;
}

class ModerationDecision {
  const ModerationDecision(this.kind, {this.reason = ''});

  final ModerationKind kind;

  /// Motivo mostrado ao autor (obrigatório ao ocultar).
  final String reason;
}

/// Ids dos documentos do Conecta que pertencem ao usuário. Insumo da
/// exclusão de conta em cascata (C5).
class CommunityFootprint {
  const CommunityFootprint({
    this.postIds = const [],
    this.replyIds = const [],
    this.votesGiven = const [],
    this.votesReceived = const [],
    this.openReportIds = const [],
    this.resolvedReportIds = const [],
  });

  final List<String> postIds;
  final List<String> replyIds;
  final List<String> votesGiven;
  final List<String> votesReceived;
  final List<String> openReportIds;
  final List<String> resolvedReportIds;
}

enum CommunityFailureKind {
  invalidInput,
  notMember,
  tooSoon,
  alreadyReported,
  ownReply,
  denied,
  notFound,
  unavailable,
}

class CommunityFailure implements Exception {
  const CommunityFailure(this.kind, [this.message = '', this.waitSeconds = 0]);

  final CommunityFailureKind kind;
  final String message;

  /// Só em `tooSoon`: quanto falta para poder escrever de novo.
  final int waitSeconds;

  @override
  String toString() => 'CommunityFailure(${kind.name}): $message';
}
