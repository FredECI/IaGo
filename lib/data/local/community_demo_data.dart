import '../../domain/community_models.dart';

/// Conteúdo simulado do Conecta na demo (sem emoji e sem dados pessoais).
/// Datas relativas a "agora". Os autores são membros fictícios.
class CommunityDemoData {
  const CommunityDemoData({
    required this.posts,
    required this.replies,
    required this.votes,
  });

  final List<Post> posts;
  final List<Reply> replies;

  /// Ajudas de membros fictícios: `replyId` -> quantos votaram.
  final Map<String, int> votes;

  /// Uid usado pelos membros fictícios.
  static String uidOf(String nickname) => 'demo-$nickname';

  static CommunityDemoData build(DateTime now) {
    Post post(
      String id,
      String community,
      String nick,
      String title,
      String body,
      Duration ago,
    ) => Post(
      id: id,
      communityId: community,
      authorUid: uidOf(nick),
      authorNickname: nick,
      title: title,
      body: body,
      status: ContentStatus.visible,
      createdAt: now.subtract(ago),
    );
    Reply reply(
      String id,
      String postId,
      String nick,
      String body,
      Duration ago,
    ) => Reply(
      id: id,
      postId: postId,
      authorUid: uidOf(nick),
      authorNickname: nick,
      body: body,
      status: ContentStatus.visible,
      createdAt: now.subtract(ago),
    );

    return CommunityDemoData(
      posts: [
        post(
          'demo-p1',
          'matematica',
          'ana_funcoes',
          'Como saber se uma função é injetora?',
          'Sempre me confundo entre injetora e sobrejetora. Alguém tem um '
              'jeito de lembrar a diferença?',
          const Duration(hours: 5),
        ),
        post(
          'demo-p2',
          'matematica',
          'caio_log',
          'Logaritmo: por onde começar?',
          'Vou revisar logaritmos esta semana. Que ordem de estudo vocês '
              'recomendam?',
          const Duration(days: 1, hours: 2),
        ),
        post(
          'demo-p3',
          'natureza',
          'bia_quimica',
          'Dica para decorar a tabela periódica',
          'Estou montando cartões por família de elementos. Funciona '
              'melhor do que decorar em ordem?',
          const Duration(days: 2),
        ),
        post(
          'demo-p4',
          'linguagens',
          'leo_redacao',
          'Rotina de redação com pouco tempo',
          'Consigo escrever só um texto por semana. Vale mais refazer o '
              'mesmo ou trocar de tema toda vez?',
          const Duration(days: 3),
        ),
        post(
          'demo-p5',
          'humanas',
          'duda_historia',
          'Resumos de História: papel ou tela?',
          'Quem usa resumo em papel e quem prefere o celular? Estou '
              'tentando decidir.',
          const Duration(days: 4),
        ),
        post(
          'demo-p6',
          'reforco',
          'rafa_aulas',
          'Aula de reforço de 1 hora: como organizar?',
          'Dou aula de matemática para um aluno do 9º ano. Como vocês '
              'dividem o tempo entre teoria e exercícios?',
          const Duration(hours: 20),
        ),
      ],
      replies: [
        reply(
          'demo-r1',
          'demo-p1',
          'caio_log',
          'Pense assim: injetora não repete resultado, e sobrejetora '
              'alcança todo o contradomínio.',
          const Duration(hours: 4),
        ),
        reply(
          'demo-r2',
          'demo-p1',
          'bia_quimica',
          'Eu desenho as setas entre dois conjuntos. Ajuda a enxergar.',
          const Duration(hours: 3),
        ),
        reply(
          'demo-r3',
          'demo-p6',
          'ana_funcoes',
          'Uns 15 minutos de conversa e o resto em exercícios, com um '
              'erro comentado no final.',
          const Duration(hours: 10),
        ),
      ],
      votes: const {'demo-r1': 3, 'demo-r2': 1, 'demo-r3': 2},
    );
  }
}
