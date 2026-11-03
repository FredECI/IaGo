import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/app_info.dart';
import '../../core/clock.dart';
import '../../core/image_compressor.dart';
import '../../data/providers.dart';
import '../../domain/area.dart';
import '../../domain/metric_event.dart';
import '../../domain/paste_parser.dart';
import '../../domain/question.dart';
import '../../domain/suggestions.dart';
import '../../shared/common_widgets.dart';
import '../metrics/metrics_providers.dart';
import 'questions_providers.dart';

/// Salvar (ou editar) uma questão vinda de qualquer plataforma.
///
/// Pensado para levar menos de 30 s: colar o texto separa as alternativas
/// sozinho, Matemática já preenche a matéria e assunto/plataforma têm
/// sugestões com o que o estudante já usou.
class QuestionFormPage extends ConsumerStatefulWidget {
  const QuestionFormPage({super.key, this.questionId});

  /// `null` para uma questão nova.
  final String? questionId;

  @override
  ConsumerState<QuestionFormPage> createState() => _QuestionFormPageState();
}

class _QuestionFormPageState extends ConsumerState<QuestionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _statement = TextEditingController();
  final _alternatives = List.generate(5, (_) => TextEditingController());
  final _topic = TextEditingController();
  final _platform = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();

  QuestionType _type = QuestionType.objective;
  Area? _area;
  String? _subject;
  Uint8List? _image;
  bool _imageChanged = false;
  bool _processingImage = false;
  bool _saving = false;
  bool _loaded = false;
  int _lastStatementLength = 0;
  Question? _existing;

  /// Aviso (no próprio formulário) depois de separar as alternativas, com o
  /// necessário para desfazer. Some quando o enunciado é editado de novo.
  _SplitNotice? _splitNotice;

  /// Início do cronômetro de "salvar em menos de 30 s".
  late final DateTime _openedAt;

  bool get _isEditing => widget.questionId != null;

  @override
  void initState() {
    super.initState();
    _openedAt = ref.read(clockProvider)();
    final id = widget.questionId;
    if (id == null) {
      _loaded = true;
    } else {
      final existing = ref.read(questionByIdProvider(id));
      if (existing != null) _load(existing);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _statement,
      ..._alternatives,
      _topic,
      _platform,
      _url,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Question q) {
    _existing = q;
    _loaded = true;
    _statement.text = q.statement;
    _lastStatementLength = q.statement.length;
    _type = q.type;
    for (var i = 0; i < _alternatives.length; i++) {
      _alternatives[i].text = i < q.alternatives.length
          ? q.alternatives[i]
          : '';
    }
    _area = q.area;
    _subject = q.subject;
    _topic.text = q.topic;
    _platform.text = q.platform;
    _url.text = q.sourceUrl ?? '';
    _notes.text = q.notes ?? '';
    if (q.hasImage) {
      unawaited(
        ref.read(questionRepositoryProvider).loadImage(q.id).then((bytes) {
          if (mounted && !_imageChanged) setState(() => _image = bytes);
        }),
      );
    }
  }

  // ------------------------------------------------------------ colagem

  void _onStatementChanged(String text) {
    final grew = text.length - _lastStatementLength;
    _lastStatementLength = text.length;
    // Um salto grande de texto é colagem: tenta separar as alternativas.
    if (grew >= 20 && parsePastedQuestion(text).hasAlternatives) {
      _splitAlternatives();
    } else {
      setState(() => _splitNotice = null);
    }
  }

  void _splitAlternatives() {
    final raw = _statement.text;
    final parsed = parsePastedQuestion(raw);
    if (!parsed.hasAlternatives) return;
    final notice = _SplitNotice(
      count: parsed.alternatives.length,
      rawText: raw,
      previousType: _type,
      previousAlternatives: [for (final c in _alternatives) c.text],
    );
    setState(() {
      _splitNotice = notice;
      _statement.text = parsed.statement;
      _lastStatementLength = parsed.statement.length;
      _type = QuestionType.objective;
      for (var i = 0; i < _alternatives.length; i++) {
        _alternatives[i].text = i < parsed.alternatives.length
            ? parsed.alternatives[i]
            : '';
      }
    });
  }

  void _undoSplit() {
    final notice = _splitNotice;
    if (notice == null) return;
    setState(() {
      _splitNotice = null;
      _statement.text = notice.rawText;
      _lastStatementLength = notice.rawText.length;
      _type = notice.previousType;
      for (var i = 0; i < _alternatives.length; i++) {
        _alternatives[i].text = notice.previousAlternatives[i];
      }
    });
  }

  // ------------------------------------------------------------- imagem

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
      );
      if (file == null) return;
      setState(() => _processingImage = true);
      final raw = await file.readAsBytes();
      // Dá um quadro para o indicador aparecer antes do trabalho pesado.
      await Future<void>.delayed(const Duration(milliseconds: 32));
      final compressed = await compute(compressImage, raw);
      if (!mounted) return;
      setState(() {
        _image = compressed;
        _imageChanged = true;
        _processingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _processingImage = false);
      showMessage(context, 'Não foi possível usar essa imagem.');
    }
  }

  void _removeImage() => setState(() {
    _image = null;
    _imageChanged = true;
  });

  // --------------------------------------------------------------- salvar

  String? _normalizedUrl() {
    final text = _url.text.trim();
    if (text.isEmpty) return null;
    return text.contains('://') ? text : 'https://$text';
  }

  String? _validateUrl(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    final ok =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.contains('.');
    return ok ? null : 'Link inválido (ex.: https://site.com/questao)';
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      showMessage(context, 'Confira os campos destacados.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(questionRepositoryProvider);
    final now = ref.read(clockProvider)();
    final existing = _existing;
    final question = Question(
      id: existing?.id ?? '',
      statement: _statement.text.trim(),
      type: _type,
      alternatives: _type == QuestionType.objective
          ? [
              for (final c in _alternatives)
                if (c.text.trim().isNotEmpty) c.text.trim(),
            ]
          : const [],
      area: _area!,
      subject: _subject!,
      topic: _topic.text.trim(),
      platform: _platform.text.trim(),
      sourceUrl: _normalizedUrl(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      hasImage: _image != null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      if (existing == null) {
        await repo.create(question, image: _image);
      } else {
        await repo.update(
          question,
          image: _imageChanged ? _image : null,
          removeImage: _imageChanged && _image == null,
        );
        ref.invalidate(questionImageProvider(question.id));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Não foi possível salvar: $error');
      return;
    }
    if (!mounted) return;
    final seconds = now.difference(_openedAt).inSeconds;
    final goal = AppInfo.saveQuestionGoal.inSeconds;
    if (existing == null) {
      ref.read(metricsLoggerProvider).log(MetricEventType.questionSaved, {
        'seconds': seconds,
        'questionType': question.type.name,
        'hasImage': question.hasImage,
      });
    }
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Questão salva em $seconds s (meta: menos de $goal s).'
                : 'Alterações salvas.',
          ),
        ),
      );
  }

  // ---------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final id = widget.questionId;
    if (id != null && !_loaded) {
      // Aberto por link direto: espera as questões carregarem.
      final question = ref.watch(questionByIdProvider(id));
      if (question != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loaded) setState(() => _load(question));
        });
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Editar questão')),
        body: ref.watch(questionsProvider).isLoading || question != null
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.search_off,
                title: 'Questão não encontrada',
              ),
      );
    }

    final theme = Theme.of(context);
    final canSplit =
        _statement.text.isNotEmpty &&
        parsePastedQuestion(_statement.text).hasAlternatives;
    final topics = matchSuggestions(
      ref.watch(topicSuggestionsProvider(_subject)),
      _topic.text,
    );
    final platforms = matchSuggestions(
      ref.watch(platformSuggestionsProvider),
      _platform.text,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar questão' : 'Salvar questão'),
        actions: [
          TextButton(
            key: const Key('save-question-top'),
            onPressed: _saving ? null : _save,
            child: const Text('Salvar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _SectionLabel('Enunciado'),
            TextFormField(
              key: const Key('field-statement'),
              controller: _statement,
              minLines: 4,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onStatementChanged,
              decoration: const InputDecoration(
                hintText: 'Cole aqui o texto da questão',
                helperText:
                    'Se o texto tiver alternativas A) a E), o IaGo separa '
                    'sozinho.',
                helperMaxLines: 2,
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty && _image == null
                  ? 'Cole ou digite o enunciado (ou anexe um print).'
                  : null,
            ),
            if (_splitNotice case final notice?)
              _SplitNoticeBanner(notice: notice, onUndo: _undoSplit)
            else if (canSplit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('split-alternatives'),
                  onPressed: _splitAlternatives,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Separar alternativas'),
                ),
              ),
            const SizedBox(height: 16),
            const _SectionLabel('Tipo'),
            SegmentedButton<QuestionType>(
              segments: const [
                ButtonSegment(
                  value: QuestionType.objective,
                  label: Text('Objetiva'),
                  icon: Icon(Icons.radio_button_checked),
                ),
                ButtonSegment(
                  value: QuestionType.discursive,
                  label: Text('Discursiva'),
                  icon: Icon(Icons.edit_note),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == QuestionType.objective) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < _alternatives.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: Key('field-alt-$i'),
                    controller: _alternatives[i],
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Alternativa ${Question.letters[i]}',
                      isDense: true,
                    ),
                  ),
                ),
              FormField<void>(
                validator: (_) {
                  final filled = _alternatives
                      .where((c) => c.text.trim().isNotEmpty)
                      .length;
                  return filled < 2 && _image == null
                      ? 'Preencha pelo menos duas alternativas (ou anexe o '
                            'print).'
                      : null;
                },
                builder: (state) => state.hasError
                    ? _ErrorText(state.errorText!)
                    : const SizedBox.shrink(),
              ),
            ],
            const SizedBox(height: 16),
            const _SectionLabel('Categoria'),
            FormField<Area>(
              validator: (_) => _area == null ? 'Escolha a área.' : null,
              builder: (state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final area in Area.values)
                        ChoiceChip(
                          key: Key('area-${area.name}'),
                          avatar: Icon(AppIcons.area(area), size: 18),
                          label: Text(area.shortLabel),
                          selected: _area == area,
                          onSelected: (_) => setState(() {
                            _area = area;
                            if (!area.subjects.contains(_subject)) {
                              _subject = area.defaultSubject;
                            }
                          }),
                        ),
                    ],
                  ),
                  if (state.hasError) _ErrorText(state.errorText!),
                ],
              ),
            ),
            if (_area != null && _area!.subjects.length > 1) ...[
              const SizedBox(height: 12),
              Text('Matéria', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              FormField<String>(
                validator: (_) =>
                    _subject == null ? 'Escolha a matéria.' : null,
                builder: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final subject in _area!.subjects)
                          ChoiceChip(
                            key: Key('subject-$subject'),
                            label: Text(subject),
                            selected: _subject == subject,
                            onSelected: (_) =>
                                setState(() => _subject = subject),
                          ),
                      ],
                    ),
                    if (state.hasError) _ErrorText(state.errorText!),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-topic'),
              controller: _topic,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Assunto (opcional)',
                hintText: 'Ex.: Funções',
              ),
            ),
            _SuggestionChips(
              keyPrefix: 'topic',
              options: topics,
              onSelected: (value) => setState(() => _topic.text = value),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Origem'),
            TextFormField(
              key: const Key('field-platform'),
              controller: _platform,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Plataforma de origem',
                hintText: 'Ex.: site, app, apostila, professor',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Informe de onde veio a questão.'
                  : null,
            ),
            _SuggestionChips(
              keyPrefix: 'platform',
              options: platforms,
              onSelected: (value) => setState(() => _platform.text = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link de origem (opcional)',
                hintText: 'https://...',
              ),
              validator: _validateUrl,
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Imagem ou print (opcional)'),
            _buildImageField(theme),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('field-notes'),
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('save-question'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Salvar alterações' : 'Salvar questão'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageField(ThemeData theme) {
    if (_processingImage) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Compactando a imagem…'),
        ],
      );
    }
    final image = _image;
    if (image != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Image.memory(image, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'Compactada: ${(image.length / 1024).ceil()} KB',
                style: theme.textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trocar'),
              ),
              TextButton.icon(
                onPressed: _removeImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover'),
              ),
            ],
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('attach-image'),
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Anexar imagem ou print'),
        ),
        if (!kIsWeb)
          OutlinedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Tirar foto'),
          ),
      ],
    );
  }
}

/// O que é preciso para desfazer a separação automática das alternativas.
class _SplitNotice {
  const _SplitNotice({
    required this.count,
    required this.rawText,
    required this.previousType,
    required this.previousAlternatives,
  });

  final int count;
  final String rawText;
  final QuestionType previousType;
  final List<String> previousAlternatives;
}

/// Aviso no próprio formulário (não cobre os campos como um snackbar).
class _SplitNoticeBanner extends StatelessWidget {
  const _SplitNoticeBanner({required this.notice, required this.onUndo});

  final _SplitNotice notice;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('split-notice'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${notice.count} alternativas separadas do texto colado.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onUndo, child: const Text('Desfazer')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

/// Sugestões tocáveis logo abaixo do campo (autocompletar).
class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({
    required this.keyPrefix,
    required this.options,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final option in options)
            ActionChip(
              key: Key('$keyPrefix-suggestion-$option'),
              avatar: const Icon(Icons.history, size: 16),
              label: Text(option),
              onPressed: () => onSelected(option),
            ),
        ],
      ),
    );
  }
}
