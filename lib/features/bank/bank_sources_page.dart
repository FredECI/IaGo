import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../domain/bank_source.dart';
import '../../shared/common_widgets.dart';
import 'bank_format.dart';
import 'bank_providers.dart';

/// Contato para pedir a remoção de uma questão. Marcador até a D6/P4 definir o
/// e-mail do projeto: trocar aqui, uma vez só.
const String bankRemovalContact = AppInfo.projectContactEmail;

/// "Fontes e licenças": de onde vem cada questão, o link oficial, como pedir
/// a remoção e o que o acervo não tem (CA-B7). Nunca afirma licença.
class BankSourcesPage extends ConsumerWidget {
  const BankSourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(bankSourcesProvider);
    final unclassified = ref.watch(bankUnclassifiedProvider).value ?? 0;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fontes e licenças')),
      body: sources.when(
        loading: () => Semantics(
          label: 'Carregando as fontes',
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Não foi possível carregar as fontes',
          action: OutlinedButton(
            key: const Key('sources-retry'),
            onPressed: () => ref.invalidate(bankSourcesProvider),
            child: const Text('Tentar de novo'),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'De onde vêm as questões do acervo. Confira sempre o original.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Text('Nenhuma fonte registrada.')
            else
              for (final source in list) _SourceCard(source: source),
            const SizedBox(height: 8),
            _Notice(
              key: const Key('sources-removal'),
              icon: Icons.mail_outline,
              title: 'Pedir a remoção de uma questão',
              body: SelectableText(
                'Se uma questão ou um texto de terceiros não deveria estar '
                'aqui, escreva para $bankRemovalContact informando a questão '
                '(por exemplo, ENEM 2022). Se for o caso, ela sai na versão '
                'seguinte do app.',
              ),
            ),
            const _Notice(
              key: Key('sources-images'),
              icon: Icons.image_not_supported_outlined,
              title: 'Questões com imagem',
              body: Text(
                'O acervo traz só o texto. Questões que dependem de imagem, '
                'gráfico ou tabela em figura não estão aqui.',
              ),
            ),
            _Notice(
              key: const Key('sources-unclassified'),
              icon: Icons.category_outlined,
              title: 'Matérias ainda sem classificação',
              body: Text(
                unclassified > 0
                    ? '${bankQuestions(unclassified)} ainda estão sem matéria. '
                          'Elas aparecem na busca e no filtro por área, mas '
                          'não no filtro por matéria.'
                    : 'Questões sem matéria aparecem na busca e no filtro '
                          'por área, mas não no filtro por matéria.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final BankSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source.name, style: theme.textTheme.titleMedium),
            if (source.attribution.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(source.attribution),
            ],
            if (source.notice.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                source.notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (source.via.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Texto obtido por ${source.via}, só na preparação do acervo; '
                'o app não acessa esse endereço.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (source.officialUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: Key('source-link-${source.id}'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _open(context, source.officialUrl),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir o site oficial'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showMessage(context, 'Não foi possível abrir o link.');
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                body,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
