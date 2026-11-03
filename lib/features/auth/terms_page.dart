import 'package:material_ui/material_ui.dart';

import '../../core/app_info.dart';

/// Termos de Uso e Política de Privacidade (LGPD), em linguagem simples.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const List<(String, String)> _sections = [
    (
      'O que é o IaGo',
      'Protótipo acadêmico (Beta 0.1) feito por estudantes da UFRJ para '
          'organizar questões de estudo. É gratuito e não tem anúncios.',
    ),
    (
      'Quais dados guardamos',
      'Nome, e-mail, como você conheceu o IaGo, as questões e listas que você '
          'salvar e registros de uso (por exemplo, "questão salva" e "lista '
          'exportada"). Não pedimos documentos nem dados de pagamento.',
    ),
    (
      'Para que usamos',
      'Para o app funcionar e para avaliar, de forma agregada, as hipóteses '
          'do piloto (por exemplo, se centralizar as questões economiza '
          'tempo). Não vendemos nem compartilhamos seus dados.',
    ),
    (
      'Onde ficam',
      'No Firebase (Google), em servidores protegidos por regras que só deixam '
          'você ler e escrever os seus dados. Os PDFs são gerados no seu '
          'aparelho e não ficam guardados no servidor.',
    ),
    (
      'Seus direitos (LGPD, art. 18)',
      'Você pode ver, corrigir e excluir seus dados a qualquer momento. Para '
          'apagar tudo, vá em Conta → Excluir minha conta: as questões, as '
          'listas, os registros e a conta são removidos.',
    ),
    (
      'Contato',
      'Grupo do projeto IaGo: Caio Peixoto, Fred, João Ricardo, Luiz e '
          'Nicolas.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Termos e privacidade')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Versão de ${AppInfo.termsVersion}',
            style: theme.textTheme.bodySmall,
          ),
          for (final (title, body) in _sections) ...[
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
      ),
    );
  }
}
