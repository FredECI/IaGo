import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'questions_providers.dart';

/// Imagem anexada à questão; toque para ver em tela cheia com zoom.
class QuestionImage extends ConsumerWidget {
  const QuestionImage({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(questionImageProvider(questionId));
    return image.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const Text('Não foi possível carregar a imagem.'),
      data: (bytes) {
        if (bytes == null) return const SizedBox.shrink();
        return Semantics(
          label: 'Imagem da questão. Toque para ampliar.',
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      },
    );
  }
}
