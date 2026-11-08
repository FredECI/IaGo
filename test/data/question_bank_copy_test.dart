import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/repositories.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';

/// QA da F2: cópia do acervo (CA-B4, CA-B8), importação (CA-I11) e limites do
/// lote, contra a implementação em memória.
Question bankCopy({String statement = 'Enunciado do acervo'}) => Question(
  id: 'bank_enem-2022-136',
  statement: statement,
  type: QuestionType.objective,
  alternatives: const ['a', 'b', 'c', 'd', 'e'],
  area: Area.mathematics,
  subject: 'Matemática',
  platform: 'ENEM 2022',
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
  origin: QuestionOrigin.bank,
  bankId: 'enem-2022-136',
);

Question imported(String statement) => Question(
  id: '',
  statement: statement,
  type: QuestionType.discursive,
  area: Area.humanities,
  subject: 'História',
  platform: 'Apostila',
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
  origin: QuestionOrigin.import,
);

void main() {
  var now = DateTime(2026, 11, 7, 10);
  DateTime clock() => now;
  setUp(() => now = DateTime(2026, 11, 7, 10));

  group('cópia do acervo', () {
    test(
      'CA-B4: salvar de novo não duplica e mantém origem e bankId',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        await repo.createMany([bankCopy()]);
        await repo.createMany([bankCopy()]);
        expect(repo.current, hasLength(1));
        final q = repo.current.single;
        expect(q.id, 'bank_enem-2022-136');
        expect(q.origin, QuestionOrigin.bank);
        expect(q.bankId, 'enem-2022-136');
        expect(q.platform, 'ENEM 2022');
      },
    );

    test('CA-B8: recém-salva não é "editada"; depois de update, é', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      final saved = (await repo.createMany([bankCopy()])).single;
      expect(saved.isEdited, isFalse);
      expect(saved.createdAt, saved.updatedAt);

      now = now.add(const Duration(minutes: 5));
      final edited = await repo.update(saved.copyWith(statement: 'Meu ajuste'));
      expect(edited.isEdited, isTrue);
      expect(repo.current.single.statement, 'Meu ajuste');
      expect(repo.current.single.isEdited, isTrue);
    });

    test(
      'CA-B8: editar a cópia não afeta outra cópia nem o modelo do acervo',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final original = bankCopy();
        final saved = (await repo.createMany([original])).single;
        now = now.add(const Duration(minutes: 1));
        await repo.update(saved.copyWith(statement: 'Outro texto'));
        // O objeto de origem (o que o catálogo devolve) continua intacto.
        expect(original.statement, 'Enunciado do acervo');
        expect(original.isEdited, isFalse);
      },
    );

    test('questão manual e importada nunca aparecem como editadas', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      final saved = (await repo.createMany([imported('x')])).single;
      now = now.add(const Duration(hours: 1));
      final edited = await repo.update(saved.copyWith(statement: 'y'));
      expect(edited.updatedAt.isAfter(edited.createdAt), isTrue);
      expect(edited.isEdited, isFalse);
    });

    // DOCUMENTAÇÃO do risco apontado pelo implementador. Não é um teste de
    // comportamento desejado: registra o que createMany faz hoje.
    // Salvar de novo uma cópia já editada (mesmo id) NÃO duplica (CA-B4 ok),
    // mas regrava o documento inteiro: perde o texto editado, zera a marca de
    // "editada" (createdAt = updatedAt = agora) e apaga a data original de salvamento.
    // Na camada de dados, isso fere a intenção de CA-B8 (a edição some em silêncio).
    // A tela do acervo (A4) deve consultar o id antes de salvar, ou createMany
    // deve preservar documentos existentes.
    test(
      'DOCUMENTAÇÃO: salvar de novo uma cópia editada sobrescreve a edição',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final first = (await repo.createMany([bankCopy()])).single;
        now = now.add(const Duration(days: 2));
        await repo.update(first.copyWith(statement: 'Meu ajuste'));
        expect(repo.current.single.isEdited, isTrue);

        now = now.add(const Duration(days: 1));
        await repo.createMany([bankCopy()]);

        expect(repo.current, hasLength(1)); // CA-B4: sem duplicata
        final after = repo.current.single;
        expect(after.statement, 'Enunciado do acervo'); // edição perdida
        expect(after.isEdited, isFalse); // marca perdida
        expect(after.createdAt, now); // data original perdida
        expect(after.createdAt, isNot(first.createdAt));
      },
    );

    test('a avaliação privada (myDifficulty, myQuality) é regravada pelo mesmo motivo', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      final first = (await repo.createMany([bankCopy()])).single;
      await repo.update(first.copyWith(myDifficulty: 3, myQuality: 1));
      await repo.createMany([bankCopy()]);
      expect(repo.current.single.myDifficulty, isNull);
      expect(repo.current.single.myQuality, isNull);
    });
  });

  group('importação (CA-I11) e lote', () {
    test(
      'CA-I11: lote importado guarda origin=import, sem bankId, id novo',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final saved = await repo.createMany([imported('a'), imported('b')]);
        expect(saved.map((q) => q.origin), everyElement(QuestionOrigin.import));
        expect(saved.map((q) => q.bankId), everyElement(isNull));
        expect(saved.map((q) => q.id).toSet(), hasLength(2));
        expect(saved.every((q) => q.createdAt == now), isTrue);
        expect(
          repo.current.every((q) => q.origin == QuestionOrigin.import),
          isTrue,
        );
      },
    );

    test('lote de exatamente 400 passa e 401 lança, sem gravar nada', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      expect(QuestionRepository.maxCreateMany, 400);
      final ok = await repo.createMany([
        for (var i = 0; i < 400; i++) imported('q$i'),
      ]);
      expect(ok, hasLength(400));
      expect(repo.current, hasLength(400));
      await expectLater(
        repo.createMany([for (var i = 0; i < 401; i++) imported('z$i')]),
        throwsArgumentError,
      );
      expect(repo.current, hasLength(400));
    });

    test('createMany força hasImage=false (sem imagem em lote)', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      final saved = await repo.createMany([
        imported('a').copyWith(hasImage: true),
      ]);
      expect(saved.single.hasImage, isFalse);
    });

    test(
      'regressão: lote com o mesmo id repetido grava uma só questão',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        await repo.createMany([bankCopy(), bankCopy(statement: 'duplicada')]);
        expect(repo.current, hasLength(1));
      },
    );

    test(
      'createMany mistura acervo e import e mantém a lista ordenada e emitida',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final emissions = <int>[];
        final sub = repo.watchAll().listen((l) => emissions.add(l.length));
        await repo.createMany([bankCopy(), imported('a')]);
        await pumpEventQueue();
        expect(emissions.last, 2);
        await sub.cancel();
      },
    );
  });
}
