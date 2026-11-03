import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock.dart';
import '../domain/session.dart';
import '../domain/user_profile.dart';
import 'auth_repository.dart';
import 'firebase/firebase_auth_repository.dart';
import 'firebase/firebase_bootstrap.dart';
import 'firebase/firestore_list_repository.dart';
import 'firebase/firestore_question_repository.dart';
import 'local/demo_seed.dart';
import 'local/memory_list_repository.dart';
import 'local/memory_question_repository.dart';
import 'repositories.dart';

/// Autenticação real, disponível só quando o Firebase está pronto.
final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final status = ref.watch(firebaseStatusProvider).value;
  if (status != FirebaseStatus.ready) return null;
  return FirebaseAuthRepository(
    auth: FirebaseAuth.instance,
    db: FirebaseFirestore.instance,
    clock: ref.watch(clockProvider),
  );
});

/// Usuário logado no Firebase (`null` se ninguém ou se não houver Firebase).
final authUserProvider = StreamProvider<AuthUser?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return auth == null ? Stream.value(null) : auth.authStateChanges();
});

/// Sessão atual (`null` = ninguém entrou).
final sessionProvider = NotifierProvider<SessionController, Session?>(
  SessionController.new,
);

class SessionController extends Notifier<Session?> {
  @override
  Session? build() {
    // Escuta (não observa) o login: se o Firebase terminar de iniciar com o
    // Pedro já na demonstração, a sessão demo continua intacta.
    ref.listen(authUserProvider, (_, next) {
      if (state is DemoSession) return;
      final user = next.value;
      state = user == null
          ? null
          : AccountSession(
              uid: user.uid,
              email: user.email ?? '',
              name: user.displayName,
            );
    });
    return null;
  }

  /// Entra como Pedro, com os dados de exemplo recriados do zero.
  void enterDemo() => state = DemoSession(startedAt: ref.read(clockProvider)());

  Future<void> signOut() async {
    if (state is AccountSession) {
      await ref.read(authRepositoryProvider)?.signOut();
    }
    state = null;
  }
}

/// Dono dos dados: a própria sessão demo (cada entrada é nova) ou o `uid` da
/// conta. Mudar o nome da conta não recria os repositórios.
final dataOwnerProvider = Provider<Object?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is AccountSession ? session.uid : session;
});

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
  final session = ref.watch(dataOwnerProvider);
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
  final owner = ref.watch(dataOwnerProvider);
  final clock = ref.watch(clockProvider);
  if (owner case final String uid) {
    return FirestoreQuestionRepository(
      db: FirebaseFirestore.instance,
      uid: uid,
      clock: clock,
    );
  }
  final demo = ref.watch(demoStoreProvider);
  if (demo != null) return demo.questions;
  final empty = MemoryQuestionRepository(clock: clock);
  ref.onDispose(empty.dispose);
  return empty;
});

final listRepositoryProvider = Provider<ListRepository>((ref) {
  final owner = ref.watch(dataOwnerProvider);
  final clock = ref.watch(clockProvider);
  if (owner case final String uid) {
    return FirestoreListRepository(
      db: FirebaseFirestore.instance,
      uid: uid,
      clock: clock,
    );
  }
  final demo = ref.watch(demoStoreProvider);
  if (demo != null) return demo.lists;
  final empty = MemoryListRepository(clock: clock);
  ref.onDispose(empty.dispose);
  return empty;
});
