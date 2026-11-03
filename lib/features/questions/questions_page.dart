import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../shared/brand.dart';
import '../../shared/common_widgets.dart';
import 'question_card.dart';
import 'questions_providers.dart';

/// Tela de questões: todas as questões salvas, num lugar só.
class QuestionsPage extends ConsumerWidget {
  const QuestionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(questionsProvider);
    return Scaffold(
      appBar: AppBar(title: const PageTitle('Questões')),
      body: questions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Não foi possível carregar as questões',
          message: '$error',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              title: 'Nenhuma questão salva ainda',
              message: 'Cole aqui as questões que você encontra por aí.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  Formatters.questions(items.length),
                  style: Theme.of(context).textTheme.labelLarge,
                );
              }
              return QuestionCard(question: items[index - 1]);
            },
          );
        },
      ),
    );
  }
}
