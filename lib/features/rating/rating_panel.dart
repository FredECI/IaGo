import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../data/providers.dart';
import '../../domain/question.dart';
import '../../domain/rating_models.dart';
import '../../domain/metric_event.dart';
import '../../shared/common_widgets.dart';
import '../metrics/metrics_providers.dart';
import '../community/community_access.dart';
import 'rating_providers.dart';

/// Escala de 3 níveis (um chip por nível). Tocar no nível já escolhido chama
/// [onChanged] com `null` quando [clearable] (usado na nota privada).
class ScoreScale extends StatelessWidget {
  const ScoreScale({
    super.key,
    required this.title,
    required this.labels,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.clearable = false,
  });

  final String title;
  final List<String> labels;
  final int? value;
  final ValueChanged<int?>? onChanged;
  final String keyPrefix;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < labels.length; i++)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  widthFactor: 1,
                  child: ChoiceChip(
                    key: Key('$keyPrefix-${i + 1}'),
                    label: Text(labels[i]),
                    selected: value == i + 1,
                    onSelected: onChanged == null
                        ? null
                        : (_) => onChanged!(
                            clearable && value == i + 1 ? null : i + 1,
                          ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Selo "Dados simulados" (CA-A7).
class SimulatedBadge extends StatelessWidget {
  const SimulatedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('rating-simulated'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Dados simulados',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Painel de avaliação no detalhe do acervo: resumo relativo para todos e
/// avaliar/alterar/remover só para membro (nunca mostra resultado de prova).
class BankRatingPanel extends ConsumerStatefulWidget {
  const BankRatingPanel({super.key, required this.question});

  final Question question;

  @override
  ConsumerState<BankRatingPanel> createState() => _BankRatingPanelState();
}

class _BankRatingPanelState extends ConsumerState<BankRatingPanel> {
  int? _difficulty;
  int? _quality;
  bool _busy = false;

  late final RatingTarget _target = RatingTarget(
    bankId: widget.question.bankId ?? widget.question.id,
    area: widget.question.area,
    subject: widget.question.subject,
  );

  String _errorText(Object e) => e is RatingFailure && e.message.isNotEmpty
      ? e.message
      : 'Não foi possível salvar a avaliação. Tente de novo.';

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _difficulty = null;
      _quality = null;
      ref.invalidate(myRatingProvider(_target.bankId));
      ref.invalidate(ratingSummaryProvider(_target));
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMember = ref.watch(isMemberProvider);
    final joinable = ref.watch(conectaJoinableProvider);
    // As regras só deixam membros lerem as avaliações; fora da demo, quem
    // não é membro nem tenta ler (evita leitura negada e erro na tela).
    final canRead = isMember || (ref.watch(sessionProvider)?.isDemo ?? false);
    final summary = canRead
        ? ref.watch(ratingSummaryProvider(_target))
        : const AsyncValue<RatingSummary>.loading();
    final mine = isMember
        ? ref.watch(myRatingProvider(_target.bankId)).value
        : null;

    return Card(
      key: const Key('rating-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Avaliações da comunidade',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (summary.value?.simulated ?? false) const SimulatedBadge(),
              ],
            ),
            const SizedBox(height: 8),
            if (!canRead)
              const Text(
                'As avaliações ficam visíveis para quem entrou no piloto.',
                key: Key('rating-members-note'),
              )
            else
              summary.when(
                loading: () => Semantics(
                  label: 'Carregando avaliações',
                  child: const LinearProgressIndicator(),
                ),
                error: (e, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        e is RatingFailure &&
                                e.kind == RatingFailureKind.unavailable
                            ? RatingFailure.offlineMessage
                            : 'Não foi possível carregar as avaliações.',
                        key: const Key('rating-error'),
                      ),
                    ),
                    TextButton(
                      key: const Key('rating-retry'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () =>
                          ref.invalidate(ratingSummaryProvider(_target)),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
                data: (s) => s.isEnough
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.difficultyText!,
                            key: const Key('rating-diff'),
                          ),
                          const SizedBox(height: 4),
                          Text(s.qualityText!, key: const Key('rating-qual')),
                        ],
                      )
                    : const Text(
                        RatingSummary.fewMessage,
                        key: Key('rating-few'),
                      ),
              ),
            const Divider(height: 24),
            if (isMember) ..._memberControls(mine) else ..._guestNote(joinable),
          ],
        ),
      ),
    );
  }

  List<Widget> _memberControls(RatingValue? mine) {
    final d = _difficulty ?? mine?.difficulty;
    final q = _quality ?? mine?.quality;
    final ready = d != null && q != null;
    final changed = mine == null || d != mine.difficulty || q != mine.quality;
    return [
      Text(
        mine == null ? 'Sua avaliação' : 'Sua avaliação (você já avaliou)',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      ScoreScale(
        title: 'Dificuldade',
        labels: difficultyLabels,
        value: d,
        keyPrefix: 'rate-difficulty',
        onChanged: _busy ? null : (v) => setState(() => _difficulty = v),
      ),
      const SizedBox(height: 8),
      ScoreScale(
        title: 'Qualidade',
        labels: qualityLabels,
        value: q,
        keyPrefix: 'rate-quality',
        onChanged: _busy ? null : (v) => setState(() => _quality = v),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('rate-submit'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _busy || !ready || !changed
            ? null
            : () => _run(() async {
                await ref
                    .read(ratingRepositoryProvider)
                    .rate(_target, RatingValue(difficulty: d, quality: q));
                // Só id e notas: nenhum conteúdo da questão.
                ref.read(metricsLoggerProvider).log(
                  MetricEventType.ratingSaved,
                  {'bankId': _target.bankId, 'difficulty': d, 'quality': q},
                );
              }, mine == null ? 'Avaliação enviada.' : 'Avaliação alterada.'),
        child: Text(mine == null ? 'Avaliar' : 'Alterar avaliação'),
      ),
      if (mine != null)
        TextButton(
          key: const Key('rate-remove'),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy
              ? null
              : () => _run(
                  () =>
                      ref.read(ratingRepositoryProvider).remove(_target.bankId),
                  'Avaliação removida.',
                ),
          child: const Text('Remover minha avaliação'),
        ),
    ];
  }

  List<Widget> _guestNote(bool joinable) => [
    const Text(
      'Só quem entrou no piloto da comunidade pode avaliar.',
      key: Key('rate-members-only'),
    ),
    if (joinable)
      TextButton(
        key: const Key('rate-join'),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () => context.push(Routes.becomeMember),
        child: const Text('Entrar no piloto'),
      ),
  ];
}

/// Avaliação privada de uma questão própria (só você vê). Grava na própria
/// questão, sem marcá-la como editada. Tocar no nível escolhido apaga a nota.
class PrivateRatingPanel extends ConsumerStatefulWidget {
  const PrivateRatingPanel({super.key, required this.question});

  final Question question;

  @override
  ConsumerState<PrivateRatingPanel> createState() => _PrivateRatingPanelState();
}

class _PrivateRatingPanelState extends ConsumerState<PrivateRatingPanel> {
  bool _busy = false;

  Future<void> _save({int? difficulty, int? quality}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ratingRepositoryProvider)
          .setPrivateRating(
            widget.question.id,
            difficulty: difficulty,
            quality: quality,
          );
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Não foi possível salvar a avaliação.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Column(
      key: const Key('private-rating'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Minha avaliação (só você vê)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ScoreScale(
          title: 'Dificuldade',
          labels: difficultyLabels,
          value: q.myDifficulty,
          keyPrefix: 'private-difficulty',
          clearable: true,
          onChanged: _busy
              ? null
              : (v) => _save(difficulty: v, quality: q.myQuality),
        ),
        const SizedBox(height: 8),
        ScoreScale(
          title: 'Qualidade',
          labels: qualityLabels,
          value: q.myQuality,
          keyPrefix: 'private-quality',
          clearable: true,
          onChanged: _busy
              ? null
              : (v) => _save(difficulty: q.myDifficulty, quality: v),
        ),
      ],
    );
  }
}
