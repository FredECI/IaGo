import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/memory_list_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_list.dart';

Question draft({String statement = 'Nova questão'}) => Question(
  id: '',
  statement: statement,
  type: QuestionType.discursive,
  area: Area.humanities,
  subject: 'História',
  platform: 'Livro',
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
);

void main() {
  var now = DateTime(2026, 11, 3, 10);
  DateTime clock() => now;

  group('MemoryQuestionRepository', () {
    test(
      'create define id e datas pelo relógio e emite a lista nova',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final emissions = <List<Question>>[];
        final sub = repo.watchAll().listen(emissions.add);

        final saved = await repo.create(draft());
        await pumpEventQueue();

        expect(saved.id, hasLength(20));
        expect(saved.createdAt, now);
        expect(emissions.first, isEmpty);
        expect(emissions.last.single.id, saved.id);
        await sub.cancel();
      },
    );

    test('lista fica do mais recente para o mais antigo', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      await repo.create(draft(statement: 'antiga'));
      now = now.add(const Duration(hours: 1));
      await repo.create(draft(statement: 'nova'));
      expect(repo.current.map((q) => q.statement), ['nova', 'antiga']);
    });

    test(
      'update preserva a criação, muda a atualização e guarda imagem',
      () async {
        final repo = MemoryQuestionRepository(clock: clock);
        final saved = await repo.create(draft());
        now = now.add(const Duration(minutes: 5));
        final image = Uint8List.fromList([1, 2, 3]);
        final updated = await repo.update(
          saved.copyWith(statement: 'editada'),
          image: image,
        );
        expect(updated.createdAt, saved.createdAt);
        expect(updated.updatedAt, now);
        expect(updated.hasImage, isTrue);
        expect(await repo.loadImage(saved.id), image);

        final withoutImage = await repo.update(updated, removeImage: true);
        expect(withoutImage.hasImage, isFalse);
        expect(await repo.loadImage(saved.id), isNull);
      },
    );

    test('delete remove a questão e a imagem', () async {
      final repo = MemoryQuestionRepository(clock: clock);
      final saved = await repo.create(draft(), image: Uint8List(1));
      await repo.delete(saved.id);
      expect(repo.current, isEmpty);
      expect(await repo.loadImage(saved.id), isNull);
    });
  });

  group('MemoryListRepository', () {
    test('create, update e registerExport', () async {
      final repo = MemoryListRepository(clock: clock);
      final list = await repo.create(
        QuestionList(
          id: '',
          name: 'Reforço',
          questionIds: const ['a', 'b'],
          createdAt: DateTime(2000),
          updatedAt: DateTime(2000),
        ),
      );
      expect(list.createdAt, now);

      final renamed = await repo.update(list.copyWith(name: 'Reforço 2'));
      expect(repo.current.single.name, 'Reforço 2');

      final exported = await repo.registerExport(renamed.id);
      expect(exported.exportCount, 1);
      expect(exported.lastExportedAt, now);

      await repo.delete(list.id);
      expect(repo.current, isEmpty);
    });

    test('removeQuestion tira a questão de todas as listas', () async {
      QuestionList list(String name, List<String> ids) => QuestionList(
        id: '',
        name: name,
        questionIds: ids,
        createdAt: DateTime(2000),
        updatedAt: DateTime(2000),
      );
      final repo = MemoryListRepository(clock: clock);
      await repo.create(list('A', ['x', 'y']));
      await repo.create(list('B', ['y', 'z']));
      await repo.create(list('C', ['z']));

      await repo.removeQuestion('y');

      final byName = {for (final l in repo.current) l.name: l.questionIds};
      expect(byName, {
        'A': ['x'],
        'B': ['z'],
        'C': ['z'],
      });
    });
  });
}
