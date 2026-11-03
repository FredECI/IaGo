import 'dart:typed_data';

import '../domain/question.dart';
import '../domain/question_list.dart';

/// Questões do usuário atual. Implementações: memória (demo) e Firestore.
abstract interface class QuestionRepository {
  /// Todas as questões, mais recentes primeiro; emite de novo a cada mudança.
  Stream<List<Question>> watchAll();

  /// Cria a questão (o repositório define id e datas) e, se houver, a imagem.
  Future<Question> create(Question question, {Uint8List? image});

  /// Atualiza a questão. [image] troca a imagem; [removeImage] apaga a atual.
  Future<Question> update(
    Question question, {
    Uint8List? image,
    bool removeImage = false,
  });

  Future<void> delete(String id);

  /// Imagem compactada da questão (carregada só no detalhe e no PDF).
  Future<Uint8List?> loadImage(String questionId);
}

/// Listas de questões do usuário atual.
abstract interface class ListRepository {
  /// Todas as listas, mais recentes primeiro; emite de novo a cada mudança.
  Stream<List<QuestionList>> watchAll();

  Future<QuestionList> create(QuestionList list);

  Future<QuestionList> update(QuestionList list);

  Future<void> delete(String id);

  /// Registra uma exportação em PDF (contador e data da última).
  Future<QuestionList> registerExport(String id);

  /// Retira a questão de todas as listas (usado quando ela é excluída).
  Future<void> removeQuestion(String questionId);
}
