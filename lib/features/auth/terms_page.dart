import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';

/// Marcador do e-mail de contato até a D6/P4. Trocar aqui quando existir.
const String projectEmailPlaceholder = '<e-mail do projeto>';

/// Termos de Uso e Política de Privacidade (LGPD), em linguagem simples.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termos e privacidade')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [TermsContent()],
      ),
    );
  }
}

/// O texto dos termos, sem moldura: a tela de termos e a de novo aceite usam
/// o mesmo conteúdo.
class TermsContent extends StatelessWidget {
  const TermsContent({super.key});

  static List<(String, String)> get sections => [
    (
      'O que é o IaGo',
      'Projeto acadêmico feito por estudantes da UFRJ para organizar questões '
          'de estudo, montar um plano de estudos e conversar com outros '
          'estudantes. É gratuito e não tem anúncios. A versão atual é um '
          'piloto fechado.',
    ),
    (
      'Quem pode usar',
      'O piloto é para pessoas com ${AppInfo.termsMinAge} anos ou mais. Ao '
          'criar a conta ou aceitar estes termos, você declara ter essa idade. '
          'Se você tem menos, não use o app: peça a exclusão da conta.',
    ),
    (
      'Quais dados guardamos',
      'Nome, e-mail, como você conheceu o IaGo, a idade mínima que você '
          'declarou, as questões, listas e etapas de estudo que você salvar e '
          'registros de uso (por exemplo, "questão salva" e "lista '
          'exportada"). Não pedimos documentos nem dados de pagamento.',
    ),
    (
      'Para que usamos',
      'Para o app funcionar e para avaliar, de forma agregada, as hipóteses '
          'do piloto (por exemplo, se centralizar as questões economiza '
          'tempo). Não vendemos nem compartilhamos seus dados.',
    ),
    (
      'Inteligência artificial e Google',
      'Alguns recursos usam inteligência artificial do Google (Gemini, pelo '
          'Firebase AI Logic) para extrair questões de um arquivo que você '
          'envia e para sugerir etapas de estudo. Só o que você manda para a '
          'IA, como o arquivo ou o seu objetivo, é enviado ao Google; nada '
          'mais da sua conta. Usamos a camada gratuita do serviço, e nela o '
          'Google pode usar o conteúdo enviado para melhorar os seus '
          'produtos, inclusive com revisão humana. Por isso, não envie '
          'dados pessoais seus nem de terceiros. A IA pode errar: confira '
          'sempre o resultado. A IA não resolve nem corrige questões e não '
          'conversa com você.',
    ),
    (
      'O que é público e o que é privado',
      'Privado, só seu: e-mail, idade declarada, código de convite, suas '
          'questões, listas, etapas e registros de uso. Público entre os '
          'membros do Conecta: o apelido, o que você publica e responde '
          'e a contagem de "Ajudou". Quem avalia uma questão do acervo não '
          'aparece na tela, mas o registro da avaliação guarda um '
          'identificador da pessoa, e membros do piloto podem lê-lo.',
    ),
    (
      'Moderação',
      'O Conecta tem moderação. Conteúdo denunciado some para os outros '
          'membros até a revisão, que acontece em até 24 horas. A moderação '
          'pode restaurar, ocultar com motivo ou banir. Quem for banido '
          'continua podendo excluir a conta, mas um registro mínimo do '
          'banimento (identificador, data e motivo) é guardado para a '
          'decisão não ser burlada com uma conta nova. As regras completas '
          'estão nas regras da comunidade.',
    ),
    (
      'Onde ficam',
      'No Firebase (Google), em servidores protegidos por regras que só '
          'deixam você ler e escrever os seus dados privados. Os PDFs são '
          'gerados no seu aparelho e não ficam guardados no servidor.',
    ),
    (
      'Seus direitos (LGPD, art. 18)',
      'Você pode ver, corrigir e excluir seus dados a qualquer momento. Para '
          'apagar tudo, vá em Conta → Excluir minha conta: as questões, as '
          'listas, os registros, o que você publicou no Conecta e a conta '
          'são removidos. Uma denúncia sua que ainda está aberta continua '
          'até o moderador resolver.',
    ),
    (
      'Contato',
      'Grupo do projeto IaGo: Caio Peixoto, Fred, João Ricardo, Luiz e '
          'Nicolas. Dúvidas, pedidos de remoção e contestações: '
          '$projectEmailPlaceholder.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Versão de ${AppInfo.termsVersion}',
          style: theme.textTheme.bodySmall,
        ),
        for (final (title, body) in sections) ...[
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
