import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../domain/bank_source.dart';
import '../../domain/question.dart';
import '../../shared/common_widgets.dart';
import '../rating/rating_panel.dart';
import 'bank_providers.dart';

/// Detalhe de uma questão do acervo: enunciado, alternativas, crédito e o
/// botão de salvar. Sem gabarito, de propósito.
class BankQuestionPage extends ConsumerStatefulWidget {
  const BankQuestionPage({super.key, required this.questionId});

  /// Id estável do acervo (`bankId`), não o id da cópia.
  final String questionId;

  @override
  ConsumerState<BankQuestionPage> createState() => _BankQuestionPageState();
}

class _BankQuestionPageState extends ConsumerState<BankQuestionPage> {
  bool _saving = false;

  Future<void> _save(Question question) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(bankActionsProvider).save(question);
      if (!mounted) return;
      showMessage(
        context,
        created
            ? 'Questão salva em Minhas questões.'
            : 'Esta questão já estava salva.',
      );
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Não foi possível salvar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bankQuestionProvider(widget.questionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Questão do acervo')),
      body: async.when(
        loading: () => Semantics(
          label: 'Carregando a questão',
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Não foi possível abrir a questão',
          action: OutlinedButton(
            key: const Key('bank-detail-retry'),
            onPressed: () =>
                ref.invalidate(bankQuestionProvider(widget.questionId)),
            child: const Text('Tentar de novo'),
          ),
        ),
        data: (question) => question == null
            ? EmptyState(
                icon: Icons.search_off,
                title: 'Questão não encontrada no acervo',
                action: OutlinedButton(
                  onPressed: () => context.go(Routes.bank),
                  child: const Text('Voltar ao acervo'),
                ),
              )
            : _Body(question: question, saving: _saving, onSave: _save),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.question,
    required this.saving,
    required this.onSave,
  });

  final Question question;
  final bool saving;
  final Future<void> Function(Question) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final saved = ref.watch(savedBankIdsProvider).contains(question.id);
    final sources = ref.watch(bankSourcesProvider).value ?? const [];
    final source = _sourceOf(question, sources);
    final category = [
      question.area.shortLabel,
      if (question.subject.isNotEmpty &&
          question.subject != question.area.shortLabel)
        question.subject,
      if (question.topic.trim().isNotEmpty) question.topic.trim(),
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            AreaAvatar(question.area, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            InfoTag(label: question.platform, icon: Icons.source_outlined),
            InfoTag(
              label: question.type.label,
              icon: Icons.radio_button_checked,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          question.statement.trim(),
          key: const Key('bank-statement'),
          style: theme.textTheme.bodyLarge,
        ),
        if (question.alternatives.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (var i = 0; i < question.alternatives.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.secondaryContainer,
                    child: Text(
                      i < Question.letters.length
                          ? Question.letters[i]
                          : '${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        question.alternatives[i],
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        if (saved)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                key: const Key('bank-already-saved'),
                style: _bigButton,
                onPressed: null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Já salva'),
              ),
              TextButton(
                key: const Key('bank-open-saved'),
                style: _bigText,
                onPressed: () => context.push(Routes.question(question.id)),
                child: const Text('Ver em Minhas questões'),
              ),
            ],
          )
        else
          FilledButton.icon(
            key: const Key('bank-save'),
            style: _bigButton,
            onPressed: saving ? null : () => onSave(question),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Salvar em Minhas questões'),
          ),
        const SizedBox(height: 16),
        _Credit(question: question, source: source),
        const SizedBox(height: 16),
        BankRatingPanel(question: question),
      ],
    );
  }

  static final ButtonStyle _bigButton = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  );
  static final ButtonStyle _bigText = TextButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
  );

  /// As fontes são prefixo do id estável (`enem-2022-5` vem de `enem`). Com
  /// uma fonte só, ela vale para todas as questões.
  static BankSource? _sourceOf(Question q, List<BankSource> sources) {
    final id = q.bankId ?? '';
    for (final s in sources) {
      if (id.startsWith('${s.id}-')) return s;
    }
    return sources.length == 1 ? sources.first : null;
  }
}

/// Crédito: só o que o asset declara. Nunca afirma licença (CA-B7).
class _Credit extends StatelessWidget {
  const _Credit({required this.question, required this.source});

  final Question question;
  final BankSource? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = source?.officialUrl.isNotEmpty == true
        ? source!.officialUrl
        : question.sourceUrl;
    return Card(
      key: const Key('bank-credit'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Origem e crédito', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Origem: ${question.platform}'),
            if (source != null && source!.attribution.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(source!.attribution),
            ],
            if (source != null && source!.notice.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                source!.notice,
                key: const Key('bank-notice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              children: [
                if (url != null && url.isNotEmpty)
                  TextButton.icon(
                    key: const Key('bank-official-link'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _open(context, url),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Conferir na fonte oficial'),
                  ),
                TextButton(
                  key: const Key('bank-credit-sources'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => context.push(Routes.bankSources),
                  child: const Text('Fontes e licenças'),
                ),
              ],
            ),
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
