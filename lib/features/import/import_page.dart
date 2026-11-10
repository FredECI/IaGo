import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../core/clock.dart';
import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/ai_ports.dart';
import '../../domain/area.dart';
import '../../domain/metric_event.dart';
import '../../domain/paste_parser.dart';
import '../../shared/common_widgets.dart';
import '../community/community_access.dart';
import '../metrics/metrics_providers.dart';
import '../questions/questions_providers.dart';
import 'import_draft_card.dart';
import 'import_models.dart';
import 'import_providers.dart';

/// Importação em lote (I4): colar texto, ou enviar prints/PDF à IA, revisar
/// e salvar. Nada é gravado antes de "Salvar" (CA-I4).
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportSummary {
  const _ImportSummary({
    required this.saved,
    required this.before,
    required this.leftOut,
    required this.bySubject,
  });

  final int saved;
  final int before;
  final int leftOut;
  final Map<String, int> bySubject;
  int get after => before + saved;
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _paste = TextEditingController();
  final _bulkPlatform = TextEditingController();
  final List<ImportDraft> _drafts = [];
  final List<FileJob> _jobs = [];
  int _nextId = 1;
  DateTime? _startedAt;
  bool _showErrors = false;
  bool _saving = false;
  bool _running = false;

  /// Cota do provedor ou limite diário do usuário: o restante fica pendente.
  AiFailure? _limitHit;

  /// Cada execução tem um número; cancelar muda o número e o resultado da
  /// execução antiga é ignorado.
  int _runId = 0;
  String? _notice;
  String? _capNotice;
  List<String> _refusals = const [];
  Area? _bulkArea;
  String? _bulkSubject;
  _ImportSummary? _summary;

  @override
  void initState() {
    super.initState();
    // Falha passageira do App Check numa abertura anterior não pode valer a
    // sessão toda: ao reabrir a tela, a checagem é refeita.
    Future.microtask(_refreshAvailability);
  }

  /// Só para conta real: na demo o App Check nunca é tocado.
  Future<void> _refreshAvailability() async {
    if (!mounted || ref.read(dataOwnerProvider) is! String) return;
    if (!aiAvailabilityNeedsRetry(ref.read(aiAvailabilityProvider))) return;
    ref.invalidate(aiAvailabilityProvider);
    try {
      await ref.read(aiAvailabilityProvider.future);
    } catch (_) {
      // O erro já fica no provider; a tela mostra "indisponível".
    }
  }

  @override
  void dispose() {
    _paste.dispose();
    _bulkPlatform.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- rascunhos

  /// Acrescenta rascunhos respeitando o teto do lote. Devolve quantos entraram.
  int _addDrafts(List<ImportDraft Function(int id)> makers) {
    final room = maxImportQuestions - _drafts.length;
    final take = makers.length > room ? room : makers.length;
    for (var i = 0; i < take; i++) {
      _drafts.add(makers[i](_nextId++));
    }
    if (makers.length > take) {
      _capNotice =
          'O lote tem no máximo $maxImportQuestions questões: mantivemos as '
          'primeiras. Salve estas e importe o restante depois.';
    }
    if (take > 0) _startedAt ??= ref.read(clockProvider)();
    return take;
  }

  void _splitPaste() {
    final text = _paste.text.trim();
    if (text.isEmpty) {
      showMessage(context, 'Cole o texto com as questões primeiro.');
      return;
    }
    final parsed = splitPastedQuestions(text);
    if (parsed.isEmpty) {
      setState(() => _notice = 'Não encontramos questões nesse texto.');
      return;
    }
    var added = 0;
    final room = maxImportQuestions - _drafts.length;
    setState(() {
      _summary = null;
      _notice = null;
      added = _addDrafts([
        for (final p in parsed) (id) => ImportDraft.fromPasted(id, p),
      ]);
      // Passou do teto: o que sobrou fica no campo para o próximo lote.
      _paste.text = parsed.length > added && added == room
          ? _leftover(text, parsed[added].statement)
          : '';
    });
    // Lote cheio: nada foi extraído, então não há execução a registrar.
    if (added == 0) return;
    ref.read(metricsLoggerProvider).log(MetricEventType.importRun, {
      'source': 'paste',
      'files': 0,
      'extracted': added,
      'failedFiles': 0,
      'partial': false,
    });
  }

  /// Trecho do texto a partir da questão que não coube (com a linha do
  /// cabeçalho, se estiver logo acima). Sem achar, devolve o texto todo.
  String _leftover(String text, String firstStatement) {
    final index = text.indexOf(firstStatement.trim());
    if (index < 0) return text;
    var start = text.lastIndexOf('\n', index - 1) + 1;
    if (start > 1) {
      final prevStart = text.lastIndexOf('\n', start - 2) + 1;
      final prev = text.substring(prevStart, start - 1).trim();
      if (prev.isNotEmpty && prev.length <= 30) start = prevStart;
    }
    return text.substring(start).trim();
  }

  int get _selectedCount => _drafts.where((d) => d.selected).length;

  void _applyToAll() {
    setState(() {
      for (final d in _drafts) {
        final area = _bulkArea;
        if (area != null) {
          d.area = area;
          d.subject = _bulkSubject ?? area.defaultSubject;
        }
        final platform = _bulkPlatform.text.trim();
        if (platform.isNotEmpty) d.platform = platform;
      }
    });
  }

  // ------------------------------------------------------------------ arquivos

  Future<bool> _confirmNotice() async {
    if (ref.read(aiNoticeAcceptedProvider) == aiNoticeVersion) return true;
    final isDemo = ref.read(importAiModeProvider) == ImportAiMode.simulated;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('ai-notice'),
        title: const Text('Antes de enviar arquivos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDemo)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Na demonstração, nada sai do aparelho: o resultado é um '
                    'exemplo simulado. Em uma conta real, vale o aviso abaixo.',
                  ),
                ),
              const Text(
                'O arquivo vai para o Google, que pode usá-lo para melhorar '
                'produtos, e pessoas podem revisá-lo.\n\n'
                'Não envie dados pessoais; recorte o print antes.\n\n'
                'Envie só material a que você tem direito.\n\n'
                'A colagem de texto continua disponível e não envia nada.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('ai-notice-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('ai-notice-accept'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entendi, continuar'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    ref.read(aiNoticeAcceptedProvider.notifier).accept();
    return true;
  }

  Future<void> _pickFiles() async {
    if (_running) return;
    if (!await _confirmNotice() || !mounted) return;
    final List<ImportFile> picked;
    try {
      picked = await ref.read(pickFilesProvider)();
    } catch (_) {
      if (mounted) showMessage(context, 'Não foi possível abrir os arquivos.');
      return;
    }
    if (!mounted || picked.isEmpty) return;
    final check = checkImportFiles(picked, alreadyChosen: _jobs.length);
    final jobs = [for (final f in check.accepted) FileJob(f)];
    setState(() {
      _summary = null;
      _refusals = check.refusals;
      _jobs.addAll(jobs);
    });
    if (jobs.isNotEmpty) await _runJobs(jobs);
  }

  Future<void> _runJobs(List<FileJob> jobs) async {
    if (_running) return;
    // Marca já: toque duplo durante a checagem não roda duas vezes.
    final runId = ++_runId;
    bool cancelled() => !mounted || runId != _runId;
    setState(() {
      _running = true;
      _limitHit = null;
    });
    // "Tentar de novo" refaz a checagem da IA se ela falhou antes.
    await _refreshAvailability();
    // Cancelou (e talvez retomou) enquanto checava: esta execução morre.
    if (!mounted || runId != _runId) return;
    final extractor = ref.read(questionExtractorProvider);
    if (extractor == null) {
      setState(() => _running = false);
      showMessage(context, aiFailureMessage(_unavailableFailure()));
      return;
    }
    var ran = 0;
    var failed = 0;
    var extracted = 0;
    var partial = false;
    for (final job in jobs) {
      if (cancelled()) return;
      ran++;
      setState(() {
        job.status = FileJobStatus.running;
        job.failure = null;
      });
      try {
        final result = await extractor.extract(job.file);
        if (cancelled()) return;
        setState(() {
          job.status = FileJobStatus.done;
          job.extracted = result.questions.length;
          job.notes = result.warnings;
          extracted += _addDrafts([
            for (final q in result.questions)
              (id) => ImportDraft.fromExtracted(id, q),
          ]);
        });
        partial = partial || result.partial;
      } on AiException catch (e) {
        if (cancelled()) return;
        if (e.failure == AiFailure.quotaExhausted ||
            e.failure == AiFailure.dailyLimit) {
          // Cota ou limite diário: este e os próximos ficam pendentes; o que
          // já veio fica.
          setState(() {
            job.status = FileJobStatus.pending;
            _limitHit = e.failure;
          });
          ran--;
          break;
        }
        failed++;
        if (e.failure == AiFailure.appCheckDenied) {
          ref.read(metricsLoggerProvider).log(MetricEventType.aiFallback, {
            'feature': 'import',
            'reason': e.failure.name,
          });
        }
        setState(() {
          job.status = FileJobStatus.failed;
          job.failure = e.failure;
        });
      } catch (_) {
        if (cancelled()) return;
        failed++;
        setState(() {
          job.status = FileJobStatus.failed;
          job.failure = AiFailure.unknown;
        });
      }
    }
    if (cancelled()) return;
    setState(() => _running = false);
    if (ran > 0) {
      ref.read(metricsLoggerProvider).log(MetricEventType.importRun, {
        'source': 'files',
        'files': ran,
        'extracted': extracted,
        'failedFiles': failed,
        'partial': partial,
      });
    }
  }

  /// Por que a IA não está disponível (para a mensagem): App Check ou o resto.
  AiFailure _unavailableFailure() =>
      aiUnavailableReason(ref.read(aiAvailabilityProvider));

  /// Cancelar: o que está em andamento volta a "pendente" e o resultado que
  /// chegar depois é ignorado. Nada já extraído se perde.
  void _cancelRun() {
    setState(() {
      _runId++;
      _running = false;
      for (final job in _jobs) {
        if (job.status == FileJobStatus.running) {
          job.status = FileJobStatus.pending;
        }
      }
    });
  }

  void _removeJob(FileJob job) => setState(() => _jobs.remove(job));

  // -------------------------------------------------------------------- salvar

  Future<void> _save() async {
    final selected = _drafts.where((d) => d.selected).toList();
    if (selected.isEmpty) {
      showMessage(context, 'Marque pelo menos uma questão para salvar.');
      return;
    }
    final invalid = selected.where((d) => d.problems.isNotEmpty).toList();
    if (invalid.isNotEmpty) {
      setState(() {
        _showErrors = true;
        for (final d in invalid) {
          d.expanded = true;
        }
      });
      showMessage(
        context,
        invalid.length == 1
            ? '1 questão precisa de ajuste antes de salvar.'
            : '${invalid.length} questões precisam de ajuste antes de salvar.',
      );
      return;
    }
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    final before = (ref.read(questionsProvider).value ?? const []).length;
    try {
      await ref.read(questionRepositoryProvider).createMany([
        for (final d in selected) d.toQuestion(now),
      ]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Não foi possível salvar. Tente de novo.');
      return;
    }
    if (!mounted) return;
    final bySubject = <String, int>{};
    for (final d in selected) {
      bySubject.update(d.subject!, (n) => n + 1, ifAbsent: () => 1);
    }
    final leftOut = _drafts.length - selected.length;
    // Sem conteúdo de questão (CA-I14): só contagens.
    ref.read(metricsLoggerProvider).log(MetricEventType.questionsBulkSaved, {
      'origin': 'import',
      'count': selected.length,
      'seconds': now.difference(_startedAt ?? now).inSeconds,
      'discardedCount': leftOut,
    });
    setState(() {
      _saving = false;
      _summary = _ImportSummary(
        saved: selected.length,
        before: before,
        leftOut: leftOut,
        bySubject: bySubject,
      );
      _drafts.clear();
      _jobs.clear();
      _showErrors = false;
      _capNotice = null;
      _startedAt = null;
    });
  }

  // ---------------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = ref.watch(importAiModeProvider);
    final summary = _summary;
    // Só conta real: a demo não toca no App Check.
    // Conta real, fora do piloto, com a IA ligada: o caminho é virar membro.
    final offerJoin =
        ref.watch(canOfferJoinProvider) &&
        ref.watch(accessPolicyProvider).aiEnabled;
    final retryable =
        ref.watch(dataOwnerProvider) is String &&
        aiAvailabilityNeedsRetry(ref.watch(aiAvailabilityProvider));

    return Scaffold(
      appBar: AppBar(title: const Text('Importar questões')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (summary != null) _SummaryCard(summary: summary),
          Text(
            'Cole várias questões de uma vez ou envie prints. Você revisa tudo '
            'antes de salvar: nada é gravado sem o seu toque em "Salvar".',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Colar texto'),
          TextField(
            key: const Key('import-paste-field'),
            controller: _paste,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Cole aqui o texto com as questões',
              helperText:
                  'Funciona sem internet e não envia nada para fora do app.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('import-split'),
              onPressed: _splitPaste,
              icon: const Icon(Icons.call_split),
              label: const Text('Separar questões'),
            ),
          ),
          if (_notice case final notice?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                notice,
                key: const Key('import-notice'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Prints e PDF'),
          if (mode == ImportAiMode.unavailable)
            Container(
              key: const Key('import-files-unavailable'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Importar de prints e PDF não está disponível para esta '
                    'conta agora. A colagem de texto funciona normalmente.',
                  ),
                  if (offerJoin)
                    TextButton(
                      key: const Key('import-join'),
                      onPressed: () => context.push(Routes.becomeMember),
                      child: const Text('Entrar no piloto'),
                    ),
                  if (retryable)
                    TextButton(
                      key: const Key('import-retry-availability'),
                      onPressed: _refreshAvailability,
                      child: const Text('Tentar de novo'),
                    ),
                ],
              ),
            )
          else
            _filesSection(theme, mode),
          if (_drafts.isNotEmpty) ..._reviewSection(theme),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _filesSection(ThemeData theme, ImportAiMode mode) {
    final pending = _jobs.where((j) => j.status == FileJobStatus.pending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mode == ImportAiMode.simulated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Exemplo simulado: na demonstração a IA não lê o arquivo, '
              'devolve questões de exemplo.',
              key: const Key('import-simulated-note'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        Text(
          'Até $maxImportFiles arquivos de ${maxImportFileBytes ~/ (1024 * 1024)} '
          'MB (PNG, JPEG, WebP ou PDF de até $maxImportPdfPages páginas). '
          'A IA só copia o texto; você revisa.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('import-pick'),
            onPressed: _running ? null : _pickFiles,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Escolher arquivos'),
          ),
        ),
        for (final refusal in _refusals)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              refusal,
              key: const Key('import-refusal'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_limitHit case final hit?)
          Container(
            key: const Key('import-quota'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              aiFailureMessage(hit),
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        for (final job in _jobs) _jobTile(theme, job),
        if (_running)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('import-cancel'),
              onPressed: _cancelRun,
              icon: const Icon(Icons.close),
              label: const Text('Cancelar leitura'),
            ),
          ),
        if (pending.isNotEmpty && !_running)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('import-resume'),
              onPressed: () => _runJobs(pending.toList()),
              child: const Text('Tentar os arquivos pendentes'),
            ),
          ),
      ],
    );
  }

  Widget _jobTile(ThemeData theme, FileJob job) {
    final name = job.file.name;
    final (IconData icon, String text) = switch (job.status) {
      FileJobStatus.pending => (Icons.schedule, 'Pendente'),
      FileJobStatus.running => (Icons.hourglass_top, 'Lendo o arquivo…'),
      FileJobStatus.done => (
        Icons.check_circle_outline,
        job.extracted == 1
            ? '1 questão encontrada'
            : '${job.extracted} questões encontradas',
      ),
      FileJobStatus.failed => (
        Icons.error_outline,
        aiFailureMessage(job.failure ?? AiFailure.unknown),
      ),
    };
    final failed = job.status == FileJobStatus.failed;
    return Padding(
      key: ObjectKey(job),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          job.status == FileJobStatus.running
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  icon,
                  size: 20,
                  color: failed ? theme.colorScheme.error : null,
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis),
                Text(text, style: theme.textTheme.bodySmall),
                for (final note in job.notes)
                  Text(note, style: theme.textTheme.bodySmall),
                if (failed)
                  Wrap(
                    children: [
                      TextButton(
                        key: Key('job-retry-$name'),
                        onPressed: _running ? null : () => _runJobs([job]),
                        child: const Text('Tentar de novo só este'),
                      ),
                      TextButton(
                        onPressed: _running ? null : () => _removeJob(job),
                        child: const Text('Remover'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _reviewSection(ThemeData theme) {
    final selected = _selectedCount;
    return [
      const SizedBox(height: 24),
      _sectionLabel(theme, 'Revisão'),
      Text(
        '$selected de ${_drafts.length} marcadas para salvar '
        '(limite de $maxImportQuestions por lote).',
        key: const Key('import-count'),
        style: theme.textTheme.bodyMedium,
      ),
      if (_capNotice case final cap?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            cap,
            key: const Key('import-cap-notice'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 12),
      _bulkPanel(theme),
      const SizedBox(height: 12),
      for (var i = 0; i < _drafts.length; i++)
        ImportDraftCard(
          key: ValueKey(_drafts[i].id),
          draft: _drafts[i],
          number: i + 1,
          showErrors: _showErrors,
          onChanged: () => setState(() {}),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('import-save'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(
          selected == 1 ? 'Salvar 1 questão' : 'Salvar $selected questões',
        ),
      ),
    ];
  }

  Widget _bulkPanel(ThemeData theme) {
    final area = _bulkArea;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aplicar a todas', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in Area.values)
                ChoiceChip(
                  key: Key('bulk-area-${a.name}'),
                  label: Text(a.shortLabel),
                  selected: area == a,
                  onSelected: (_) => setState(() {
                    _bulkArea = a;
                    _bulkSubject = a.defaultSubject;
                  }),
                ),
            ],
          ),
          if (area != null && area.subjects.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in area.subjects)
                  ChoiceChip(
                    key: Key('bulk-subject-$s'),
                    label: Text(s),
                    selected: _bulkSubject == s,
                    onSelected: (_) => setState(() => _bulkSubject = s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const Key('bulk-platform'),
            controller: _bulkPlatform,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Plataforma de origem',
              hintText: 'Ex.: site, app, apostila, professor',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('import-apply-all'),
              onPressed: _applyToAll,
              child: const Text('Aplicar a todas'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.summary});

  final _ImportSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subjects = summary.bySubject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      key: const Key('import-summary'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onSecondaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.saved == 1
                  ? '1 questão salva'
                  : '${summary.saved} questões salvas',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Minhas questões: de ${summary.before} para ${summary.after}.',
            ),
            Text(
              'Por matéria: '
              '${subjects.map((e) => '${e.key} ${e.value}').join(', ')}.',
            ),
            if (summary.leftOut > 0)
              Text(
                summary.leftOut == 1
                    ? '1 rascunho ficou de fora (não estava marcado).'
                    : '${summary.leftOut} rascunhos ficaram de fora '
                          '(não estavam marcados).',
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const Key('import-see-questions'),
                  onPressed: () {
                    // Busca e filtros antigos esconderiam as importadas.
                    ref.read(questionFilterProvider.notifier).clearAll();
                    context.go(Routes.questions);
                  },
                  child: const Text('Ver minhas questões'),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.dashboard),
                  child: const Text('Voltar ao Painel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
