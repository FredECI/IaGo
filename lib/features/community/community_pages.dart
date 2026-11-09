import 'package:material_ui/material_ui.dart';

import '../../shared/placeholder_page.dart';

/// Provisória: a tela de verdade é a C2.
class CommunityHomePage extends StatelessWidget {
  const CommunityHomePage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Conecta',
    message: 'Comunidades em que estudantes se ajudam, em breve nesta tela.',
    icon: Icons.groups_outlined,
  );
}

/// Provisória: uma comunidade e suas conversas (C2).
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, required this.communityId});

  final String communityId;

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Comunidade',
    message: 'As conversas desta comunidade chegam em breve.',
    icon: Icons.groups_outlined,
  );
}

/// Provisória: uma conversa (C2).
class CommunityPostPage extends StatelessWidget {
  const CommunityPostPage({
    super.key,
    required this.communityId,
    required this.postId,
  });

  final String communityId;
  final String postId;

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Conversa',
    message: 'A conversa e as respostas chegam em breve.',
    icon: Icons.forum_outlined,
  );
}

/// Provisória: virar membro (F6).
class BecomeMemberPage extends StatelessWidget {
  const BecomeMemberPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Virar membro',
    message: 'Convite, idade e regras da comunidade, em breve nesta tela.',
    icon: Icons.how_to_reg_outlined,
  );
}

/// Provisória: fila de moderação (C3).
class ModerationPage extends StatelessWidget {
  const ModerationPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Moderação',
    message: 'A fila de denúncias chega em breve.',
    icon: Icons.shield_outlined,
  );
}
