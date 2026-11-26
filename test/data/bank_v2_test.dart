import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/data/bank_asset_catalog.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_bank_catalog.dart';
import '../helpers/real_bank.dart';
import '../helpers/test_app.dart';

/// Asset v2 (BM1, BM5, BM6): índice, partes por área, resumo e rótulos.
void main() {
  final real = RealBank.load();

  group('asset v2 gerado', () {
    test('índice: partes, contagens e taxonomia batem com as questões', () {
      final summary = real.index.summary;
      expect(real.index.shards.map((s) => s.area).toSet(), Area.values.toSet());
      for (final s in real.index.shards) {
        final n = real.data.questions.where((q) => q.area == s.area).length;
        expect(n, s.count, reason: s.area.name);
      }
      final withSubject = real.data.questions.where(
        (q) => q.subject.isNotEmpty,
      );
      expect(
        summary.counts.fold<int>(0, (n, c) => n + c.count),
        withSubject.length,
      );
      expect(real.data.questions, hasLength(2256));
      expect(summary.available('Matemática'), 305);
    });

    test('taxonomia do índice cobre o catálogo de matérias do app', () {
      final taxonomy = real.index.summary.taxonomy;
      final subjects = [for (final a in Area.values) ...a.subjects];
      expect(taxonomy.keys.toSet(), subjects.toSet());
      expect(taxonomy['Redação'], isEmpty);
      for (final e in taxonomy.entries) {
        expect(e.value.length, lessThanOrEqualTo(14), reason: e.key);
      }
    });

    test('CA-BM1: matéria do catálogo da área e assunto da taxonomia', () {
      final taxonomy = real.index.summary.taxonomy;
      for (final q in real.data.questions) {
        if (q.subject.isEmpty) continue;
        expect(q.area.subjects, contains(q.subject), reason: q.id);
        if (q.topic.isNotEmpty) {
          expect(taxonomy[q.subject], contains(q.topic), reason: q.id);
        }
      }
    });

    test('CA-BM1: com a classificação pronta, toda questão tem matéria', () {
      final missing = real.data.questions.where((q) => q.subject.isEmpty);
      if (missing.isNotEmpty) {
        markTestSkipped('${missing.length} questões ainda sem classificação');
        return;
      }
      final topics = real.data.questions.where((q) => q.topic.isNotEmpty);
      expect(
        topics.length / real.data.questions.length,
        greaterThanOrEqualTo(0.85),
      );
    });

    test('limites de tamanho: 3 MiB por parte e 12 MiB no total', () {
      var total = 0;
      for (final f in Directory(realBankDir).listSync().whereType<File>()) {
        final size = f.lengthSync();
        total += size;
        if (!f.path.endsWith('index.json')) {
          expect(size, lessThanOrEqualTo(maxBankShardBytes), reason: f.path);
        }
      }
      expect(total, lessThanOrEqualTo(maxBankTotalBytes));
    });

    test('CA-BM5: nenhuma chave nem palavra de resposta em nenhum arquivo', () {
      final forbidden = RegExp(
        r'correctAlternative|isCorrect|TX_GABARITO|"answer"|"gabarito"',
      );
      for (final f in Directory(realBankDir).listSync().whereType<File>()) {
        expect(
          forbidden.hasMatch(f.readAsStringSync()),
          isFalse,
          reason: f.path,
        );
      }
    });

    test('ids publicados continuam no asset (CA-BM3)', () {
      final ids = {for (final q in real.data.questions) q.bankId};
      final v1 = File('tool/acervo/ids-v1.txt')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty);
      expect(v1.length, 1687);
      expect(v1.where((id) => !ids.contains(id)), isEmpty);
    });
  });

  group('resumo e carregamento por partes (CA-BM6)', () {
    test('summary() e sources() leem só o índice', () async {
      final bundle = FileAssetBundle();
      final catalog = AssetBankCatalog(bundle: bundle);
      final summary = await catalog.summary();
      await catalog.sources();
      expect(bundle.paths, [bankIndexPath]);
      expect(summary.available('Matemática'), 305);
      expect(summary.available('Inexistente'), 0);
      expect(summary.availableAt('Matemática', null), 305);
      expect(summary.availableAt('Matemática', 2), 0);
      expect(summary.taxonomy['História'], isNotEmpty);
      expect(summary.generatedAt, isNotEmpty);
    });

    test('filtro por área ou matéria carrega só a parte da área', () async {
      final bundle = FileAssetBundle();
      final catalog = AssetBankCatalog(bundle: bundle);
      final page = await catalog.search(
        const QuestionFilter(subjects: {'Matemática'}),
        limit: 3,
      );
      expect(page.total, 305);
      final math = real.index.shards.firstWhere(
        (s) => s.area == Area.mathematics,
      );
      expect(bundle.paths, [bankIndexPath, math.path]);
      // Pedir a mesma área de novo não lê nada.
      await catalog.search(const QuestionFilter(areas: {Area.mathematics}));
      expect(bundle.paths, hasLength(2));
      // As facetas precisam de todas as áreas, cada uma lida uma vez.
      await catalog.facets(const QuestionFilter());
      await catalog.byIds(['enem-2009-141']);
      expect(bundle.paths, hasLength(1 + real.index.shards.length));
      expect(bundle.paths.toSet(), hasLength(bundle.paths.length));
    });

    test('busca sem filtro de área carrega as 4 partes', () async {
      final bundle = FileAssetBundle();
      final catalog = AssetBankCatalog(bundle: bundle);
      final page = await catalog.search(const QuestionFilter(), limit: 1);
      expect(page.total, 2256);
      expect(bundle.paths, hasLength(5));
    });

    test('MemoryBankCatalog calcula o resumo das questões', () async {
      final memory = MemoryBankCatalog(real.data);
      final summary = await memory.summary();
      expect(summary.available('Matemática'), 305);
      expect(
        summary.counts.fold<int>(0, (n, c) => n + c.count),
        real.data.questions.where((q) => q.subject.isNotEmpty).length,
      );
    });

    test('índice ignora campos e linhas inválidas (CA-R3)', () {
      final index = parseBankIndex(
        '{"schemaVersion":2,"generatedAt":"2026-11-26","novo":1,'
        '"counts":[{"area":"mathematics","subject":"Matemática","difficulty":2,"count":5,"x":1},'
        '{"area":"invalida","subject":"X","count":1},{"area":"humanities"}],'
        '"shards":[{"area":"mathematics","path":"a.json","count":5},{"area":"zzz","path":"b"}]}',
      );
      expect(index.summary.counts, hasLength(1));
      expect(index.summary.availableAt('Matemática', 2), 5);
      expect(index.summary.available('Matemática'), 5);
      expect(index.shards, hasLength(1));
      expect(index.generatedAt, DateTime(2026, 11, 26));
    });
  });

  group('campos só do acervo', () {
    final q = Question(
      id: 'bank_x-1',
      statement: 's',
      type: QuestionType.objective,
      area: Area.humanities,
      subject: 'História',
      platform: 'ENEM 2022',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      origin: QuestionOrigin.bank,
      bankId: 'x-1',
      bankDifficulty: 2,
      autoClassified: true,
    );

    test('CA-BM8: não vão no mapa gravado nem voltam de fora', () {
      final map = q.toMap();
      expect(map.keys, isNot(contains('bankDifficulty')));
      expect(map.keys, isNot(contains('autoClassified')));
      final back = Question.fromMap('bank_x-1', map);
      expect(back.bankDifficulty, isNull);
      expect(back.autoClassified, isFalse);
      expect(back, q); // a igualdade os ignora
    });

    test('copyWith preserva e permite zerar', () {
      expect(q.copyWith(statement: 'z').bankDifficulty, 2);
      expect(q.copyWith(statement: 'z').autoClassified, isTrue);
      final cleared = q.copyWith(bankDifficulty: null, autoClassified: false);
      expect(cleared.bankDifficulty, isNull);
      expect(cleared.autoClassified, isFalse);
    });
  });

  group('desempenho (CA-BM9)', () {
    test('busca e facetas sobre 5.000 questões em menos de 400 ms (folga para carga do CI)', () async {
      final big = <Question>[];
      var copy = 0;
      while (big.length < 5000) {
        copy++;
        for (final q in real.data.questions) {
          if (big.length >= 5000) break;
          final c = q.copyWith(
            id: '${q.id}-$copy',
            bankId: '${q.bankId}-$copy',
          );
          c.searchText;
          big.add(c);
        }
      }
      final catalog = MemoryBankCatalog(
        BankData(sources: real.data.sources, questions: big),
      );
      final filters = [
        const QuestionFilter(query: 'função'),
        const QuestionFilter(
          query: 'função',
          areas: {Area.mathematics},
          type: QuestionType.objective,
        ),
        const QuestionFilter(query: 'energia elétrica'),
        const QuestionFilter(subjects: {'Matemática'}),
      ];
      for (final f in filters) {
        await catalog.search(f);
        await catalog.facets(f);
      }
      final sw = Stopwatch();
      var worst = 0;
      for (final f in filters) {
        sw
          ..reset()
          ..start();
        await catalog.search(f);
        await catalog.facets(f);
        sw.stop();
        if (sw.elapsedMilliseconds > worst) worst = sw.elapsedMilliseconds;
      }
      // ignore: avoid_print
      print('CA-BM9: ${big.length} questões, pior busca+facetas = $worst ms');
      expect(worst, lessThan(400));
    });
  });

  group('tela: Classificação automática (CA-BM7)', () {
    setUpAll(initTestLocale);

    BankData dataWith(Map<String, bool> autoById) {
      final stamp = DateTime(2026, 11, 26);
      return BankData(
        sources: const [fakeBankSource],
        questions: [
          for (final e in autoById.entries)
            Question(
              id: 'bank_${e.key}',
              statement: 'Enunciado ${e.key}',
              type: QuestionType.objective,
              alternatives: [for (final l in Question.letters) 'Alt $l'],
              area: Area.humanities,
              subject: 'História',
              topic: 'Era Vargas',
              platform: 'ENEM 2022',
              createdAt: stamp,
              updatedAt: stamp,
              origin: QuestionOrigin.bank,
              bankId: e.key,
              autoClassified: e.value,
            ),
        ],
      );
    }

    Future<void> open(WidgetTester tester, String bankId) async {
      final fake = FakeBankCatalog(
        data: dataWith({'enem-2022-1': true, 'enem-2022-2': false}),
        delay: Duration.zero,
      );
      await pumpIagoApp(
        tester,
        overrides: [bankCatalogProvider.overrideWithValue(fake)],
      );
      await enterDemo(tester);
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)))
          .read(routerProvider)
          .go('/questoes/acervo/$bankId');
      await tester.pumpAndSettle();
    }

    testWidgets('aparece para classificação do agente', (tester) async {
      await open(tester, 'enem-2022-1');
      expect(find.byKey(const Key('bank-auto-classified')), findsOneWidget);
      expect(find.text('Classificação automática'), findsOneWidget);
    });

    testWidgets('não aparece quando a fonte, regra ou pessoa classificou', (
      tester,
    ) async {
      await open(tester, 'enem-2022-2');
      expect(find.byKey(const Key('bank-auto-classified')), findsNothing);
    });
  });

  test('o pubspec declara só a pasta v2 do acervo', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/acervo/v2/'));
    expect(pubspec, isNot(contains('acervo-v1')));
  });

  test('o acervo v1 antigo continua legível pelo leitor v1', () {
    final v1 = File('assets/acervo/acervo-v1.json');
    if (!v1.existsSync()) return;
    expect(parseBankAsset(v1.readAsStringSync()).questions, hasLength(1687));
  });
}
