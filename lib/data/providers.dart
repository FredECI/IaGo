import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock.dart';
import '../domain/session.dart';
import 'local/demo_seed.dart';
import 'local/memory_list_repository.dart';
import 'local/memory_question_repository.dart';
import 'repositories.dart';

/// Sessão atual (`null` = ninguém entrou).
final sessionProvider = NotifierProvider<SessionController, Session?>(
  SessionController.new,
);

class SessionController extends Notifier<Session?> {
  @override
  Session? build() => null;

  /// Entra como Pedro, com os dados de exemplo recriados do zero.
  void enterDemo() => state = DemoSession(startedAt: ref.read(clockProvider)());

  void signOut() => state = null;
}

/// Repositórios locais da demonstração.
class DemoStore {
  DemoStore({required this.questions, required this.lists});

  factory DemoStore.seeded({required Clock clock, required DateTime now}) {
    final seed = DemoSeed.build(now);
    return DemoStore(
      questions: MemoryQuestionRepository(
        clock: clock,
        initial: seed.questions,
      ),
      lists: MemoryListRepository(clock: clock, initial: seed.lists),
    );
  }

  final MemoryQuestionRepository questions;
  final MemoryListRepository lists;

  void dispose() {
    questions.dispose();
    lists.dispose();
  }
}

/// Dados da demo: existem só durante uma sessão demo e somem ao sair.
final demoStoreProvider = Provider<DemoStore?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session is! DemoSession) return null;
  final store = DemoStore.seeded(
    clock: ref.watch(clockProvider),
    now: session.startedAt,
  );
  ref.onDispose(store.dispose);
  return store;
});

/// Implementação trocada pela sessão: demo → memória; conta → Firestore.
final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  final demo = ref.watch(demoStoreProvider);
  if (demo != null) return demo.questions;
  final empty = MemoryQuestionRepository(clock: ref.watch(clockProvider));
  ref.onDispose(empty.dispose);
  return empty;
});

final listRepositoryProvider = Provider<ListRepository>((ref) {
  final demo = ref.watch(demoStoreProvider);
  if (demo != null) return demo.lists;
  final empty = MemoryListRepository(clock: ref.watch(clockProvider));
  ref.onDispose(empty.dispose);
  return empty;
});
