import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/demo_seed.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/content_tree.dart';

void main() {
  final tree = buildContentTree(
    DemoSeed.build(DateTime(2026, 11, 6)).questions,
  );

  test('as quatro áreas aparecem na ordem do catálogo, com as contagens', () {
    expect(tree.map((n) => n.area), Area.values);
    expect(
      {for (final n in tree) n.area: n.count},
      {
        Area.languages: 6,
        Area.humanities: 8,
        Area.naturalSciences: 10,
        Area.mathematics: 16,
      },
    );
  });

  test('matérias seguem o catálogo e somam o total da área', () {
    final nature = tree.firstWhere((n) => n.area == Area.naturalSciences);
    expect(nature.subjects.map((s) => s.subject), [
      'Biologia',
      'Física',
      'Química',
    ]);
    expect(nature.subjects.fold<int>(0, (sum, s) => sum + s.count), 10);
  });

  test('assuntos vêm do mais frequente ao menos', () {
    final math = tree.firstWhere((n) => n.area == Area.mathematics);
    final topics = math.subjects.single.topics;
    expect(topics.first.label, 'Funções');
    expect(topics.first.count, 11);
    expect(topics.map((t) => t.count), orderedEquals([11, 1, 1, 1, 1, 1]));
  });

  test('área sem questões fica vazia, sem matérias', () {
    final empty = buildContentTree(const []);
    expect(empty.every((n) => n.count == 0 && n.subjects.isEmpty), isTrue);
  });
}
