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

  /// Avaliação privada (1 a 3) da questão: grava só `myDifficulty` e
  /// `myQuality`, **sem mudar `updatedAt`** (mudar marcaria a cópia do acervo
  /// como "editada"). `null` apaga a nota. Nota fora de 1 a 3 lança
  /// `RatingFailure`; questão inexistente lança `RatingFailure` (invalid).
  Future<void> setPrivateRating(String id, {int? difficulty, int? quality});

  /// Cria várias questões em lote (importação e acervo). Id não vazio é
  /// mantido, o que torna salvar do acervo idempotente (mesmo id, mesmo
  /// documento). Lote vazio não faz nada; mais de [maxCreateMany] lança
  /// [ArgumentError]. Id repetido no mesmo lote vira uma só questão (vale a
  /// última ocorrência). Ser idempotente por id significa que salvar de novo
  /// substitui o documento, inclusive edições: quem chama (a tela do acervo)
  /// deve evitar regravar uma questão do acervo que já foi salva.
  Future<List<Question>> createMany(List<Question> questions);

  /// Tamanho máximo de um lote de [createMany].
  static const int maxCreateMany = 400;

  /// Remove ids repetidos mantendo a última ocorrência (ids vazios ficam).
  static List<Question> dedupeById(List<Question> questions) {
    final lastIndex = <String, int>{
      for (var i = 0; i < questions.length; i++) questions[i].id: i,
    };
    return [
      for (var i = 0; i < questions.length; i++)
        if (questions[i].id.isEmpty || lastIndex[questions[i].id] == i)
          questions[i],
    ];
  }

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
