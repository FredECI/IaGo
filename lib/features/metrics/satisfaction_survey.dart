import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../domain/metric_event.dart';
import 'metrics_providers.dart';

/// Exportações a partir das quais a pesquisa aparece (canvas: "após a 3ª").
const int surveyAfterExports = 3;

/// Mostra a pesquisa de satisfação (0 a 10) uma única vez, depois da 3ª lista
/// exportada. Responder ou dispensar fica registrado (H4 e H2).
Future<void> maybeAskSatisfaction(
  BuildContext context,
  WidgetRef ref, {
  required int totalExports,
}) async {
  if (totalExports < surveyAfterExports) return;
  final metrics = ref.read(metricsRepositoryProvider);
  if (await metrics.surveyDone()) return;
  if (!context.mounted) return;
  final answer = await showModalBottomSheet<_SurveyAnswer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SurveySheet(),
  );
  final now = ref.read(clockProvider)();
  if (answer == null) {
    await metrics.log(
      MetricEvent(type: MetricEventType.satisfactionDismissed, at: now),
    );
    return;
  }
  await metrics.log(
    MetricEvent(
      type: MetricEventType.satisfaction,
      at: now,
      data: {'score': answer.score, 'platformsNow': ?answer.platforms},
    ),
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Obrigado! Isso ajuda a melhorar o IaGo.')),
    );
  }
}

class _SurveyAnswer {
  const _SurveyAnswer(this.score, this.platforms);

  final int score;
  final int? platforms;
}

class _SurveySheet extends StatefulWidget {
  const _SurveySheet();

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  int? _score;
  int? _platforms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Uma pergunta rápida', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'De 0 a 10, quanto o IaGo ajudou a organizar suas questões?',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = 0; n <= 10; n++)
                  ChoiceChip(
                    key: Key('score-$n'),
                    label: Text('$n'),
                    selected: _score == n,
                    onSelected: (_) => setState(() => _score = n),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Hoje, em quantas plataformas você estuda? (opcional)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final n in [1, 2, 3, 4, 5])
                  ChoiceChip(
                    label: Text(n == 5 ? '5 ou mais' : '$n'),
                    selected: _platforms == n,
                    onSelected: (selected) =>
                        setState(() => _platforms = selected ? n : null),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Agora não'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('survey-send'),
                  onPressed: _score == null
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop(_SurveyAnswer(_score!, _platforms)),
                  child: const Text('Enviar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
