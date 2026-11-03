import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/clock.dart';
import '../../data/providers.dart';
import '../../domain/list_builder.dart';
import '../lists/lists_providers.dart';
import '../metrics/satisfaction_survey.dart';
import '../questions/questions_providers.dart';
import 'list_pdf.dart';
import 'pdf_exporter.dart';

/// Abre a folha de exportação: gera o PDF na hora e oferece abrir ou baixar.
Future<void> showExportSheet(BuildContext context, {required String listId}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ExportSheet(listId: listId),
  );
}

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  GeneratedPdf? _pdf;
  Object? _error;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final list = ref.read(listByIdProvider(widget.listId));
      if (list == null) throw StateError('Lista não encontrada');
      final questions = resolveQuestions(
        list.questionIds,
        ref.read(questionsProvider).value ?? const [],
      );
      final repo = ref.read(questionRepositoryProvider);
      final images = <String, Uint8List>{};
      for (final q in questions.where((q) => q.hasImage)) {
        final bytes = await repo.loadImage(q.id);
        if (bytes != null) images[q.id] = bytes;
      }
      final fonts = await ref.read(pdfFontsProvider.future);
      final pdf = await buildListPdf(
        list: list,
        questions: questions,
        images: images,
        fonts: fonts,
        generatedAt: ref.read(clockProvider)(),
      );
      if (mounted) setState(() => _pdf = pdf);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _deliver({required bool open}) async {
    final pdf = _pdf;
    final list = ref.read(listByIdProvider(widget.listId));
    if (pdf == null || list == null) return;
    final exporter = ref.read(pdfExporterProvider);
    final actions = ref.read(listActionsProvider);
    final filename = pdfFileName(list.name);
    // Sem `await` antes de abrir: o navegador só deixa abrir aba no toque.
    final delivered = open
        ? await exporter.open(pdf.bytes, filename)
        : await exporter.share(pdf.bytes, filename);
    if (delivered && !_counted) {
      _counted = true;
      final exportsBefore = (ref.read(listsProvider).value ?? const [])
          .fold<int>(0, (sum, l) => sum + l.exportCount);
      await actions.registerExport(list);
      if (mounted) {
        await maybeAskSatisfaction(
          context,
          ref,
          totalExports: exportsBefore + 1,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(listByIdProvider(widget.listId));
    final questions = resolveQuestions(
      list?.questionIds ?? const [],
      ref.watch(questionsProvider).value ?? const [],
    );
    final exporter = ref.watch(pdfExporterProvider);
    final pdf = _pdf;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Exportar PDF', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              list?.name ?? '',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(describeComposition(questions)),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                'Não foi possível gerar o PDF: $_error',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (pdf == null)
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Gerando o PDF no aparelho…')),
                ],
              )
            else ...[
              Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PDF pronto: ${pdf.pages} '
                      '${pdf.pages == 1 ? 'página' : 'páginas'}, '
                      '${(pdf.bytes.length / 1024).ceil()} KB.',
                      key: const Key('pdf-ready'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Gerado agora, neste aparelho. Nada fica guardado no servidor. '
                'Sem gabarito.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pdf-open'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => _deliver(open: true),
                icon: const Icon(Icons.open_in_new),
                label: Text(exporter.openLabel),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('pdf-share'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _deliver(open: false),
                icon: Icon(kIsWeb ? Icons.download : Icons.share),
                label: Text(exporter.shareLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
