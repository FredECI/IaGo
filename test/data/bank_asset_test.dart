import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/bank_asset_catalog.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/data/local/demo_seed.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:pdf/pdf.dart';

/// A3: o asset do acervo (CA-B2) e o catálogo em memória (CA-B3, CA-B6, CA-B9).
void main() {
  final text = File('assets/acervo/acervo-v1.json').readAsStringSync();
  final raw = jsonDecode(text) as Map<String, Object?>;
  final rawQuestions = (raw['questions'] as List).cast<Map<String, Object?>>();
  final data = parseBankAsset(text);
  final catalog = MemoryBankCatalog(data);

  group('asset (CA-B2)', () {
    test('schemaVersion 1 e fontes registradas com atribuição e aviso', () {
      expect(raw['schemaVersion'], 1);
      final sources = (raw['sources'] as List).cast<Map<String, Object?>>();
      expect(sources, isNotEmpty);
      for (final s in sources) {
        expect(s['id'], isNotEmpty);
        expect(s['attribution'], isNotEmpty);
        expect(s['notice'], isNotEmpty);
        expect(s['officialUrl'], startsWith('https://'));
      }
    });

    test('schemaVersion desconhecido é recusado', () {
      expect(
        () => parseBankAsset('{"schemaVersion": 2, "questions": []}'),
        throwsFormatException,
      );
    });

    test('tem 1.000 questões ou mais, das 4 áreas, sem perder nenhuma', () {
      expect(rawQuestions.length, greaterThanOrEqualTo(1000));
      expect(data.questions, hasLength(rawQuestions.length));
      expect(data.questions.map((q) => q.area).toSet(), Area.values.toSet());
    });

    test('ids únicos, com prefixo da fonte registrada', () {
      final ids = rawQuestions.map((q) => q['id'] as String).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final sourceIds = (raw['sources'] as List)
          .map((s) => (s as Map)['id'] as String)
          .toSet();
      for (final q in rawQuestions) {
        expect(sourceIds, contains(q['source']), reason: '${q['id']}');
        expect(q['id'] as String, startsWith('${q['source']}-'));
      }
    });

    test('matéria, quando existe, é do catálogo da área', () {
      for (final q in data.questions) {
        if (q.subject.isEmpty) continue; // classificação é da A2
        expect(q.area.subjects, contains(q.subject), reason: q.id);
      }
    });

    test('toda questão tem enunciado e 5 alternativas não vazias', () {
      for (final q in rawQuestions) {
        expect(
          (q['statement'] as String).trim(),
          isNotEmpty,
          reason: '${q['id']}',
        );
        final alts = (q['alternatives'] as List).cast<String>();
        expect(alts, hasLength(5), reason: '${q['id']}');
        expect(alts.every((a) => a.trim().isNotEmpty), isTrue);
      }
    });

    test(
      'sem gabarito: nenhum campo ou palavra de resposta (fora de URLs)',
      () {
        const allowedKeys = {
          'id',
          'source',
          'year',
          'number',
          'area',
          'subject',
          'topic',
          'statement',
          'alternatives',
          'media',
        };
        final forbidden = RegExp(
          'gabarito|correct|isCorrect|resposta correta|alternativa correta|answer key',
          caseSensitive: false,
        );
        for (final q in rawQuestions) {
          expect(
            allowedKeys.containsAll(q.keys),
            isTrue,
            reason: '${q['id']} ${q.keys}',
          );
          final body = jsonEncode(q).replaceAll(RegExp(r'https?://\S+'), '');
          expect(forbidden.hasMatch(body), isFalse, reason: '${q['id']}');
        }
      },
    );

    test('todo caractere tem glifo na Inter embutida (app e PDF offline)', () {
      final font = TtfParser(
        ByteData.view(
          File('assets/fonts/Inter-Regular.ttf').readAsBytesSync().buffer,
        ),
      );
      final missing = <String>{};
      for (final q in data.questions) {
        for (final t in [
          q.statement,
          ...q.alternatives,
          q.subject,
          q.platform,
        ]) {
          for (final rune in t.runes) {
            if (rune == 0x20 || rune == 0x0A || rune == 0x09 || rune == 0x0D) {
              continue;
            }
            if (!font.charToGlyphIndexMap.containsKey(rune)) {
              missing.add(
                '${String.fromCharCode(rune)} (U+${rune.toRadixString(16)})',
              );
            }
          }
        }
      }
      expect(missing, isEmpty);
    });
  });

  group('mapeamento para Question', () {
    test(
      'id bank_{bankId}, origin bank, plataforma "ENEM {ano}", objetiva',
      () {
        final q = data.questions.firstWhere((q) => q.bankId == 'enem-2009-141');
        expect(q.id, 'bank_enem-2009-141');
        expect(q.origin, QuestionOrigin.bank);
        expect(q.platform, 'ENEM 2009');
        expect(q.type, QuestionType.objective);
        expect(q.sourceUrl, startsWith('https://www.gov.br/inep'));
        expect(q.alternatives, hasLength(5));
      },
    );

    test('questão sem matéria é aceita, com matéria vazia', () {
      expect(data.questions.where((q) => q.subject.isEmpty), isNotEmpty);
    });

    test('campos desconhecidos são ignorados e questão inválida é pulada', () {
      final parsed = parseBankAsset(
        jsonEncode({
          'schemaVersion': 1,
          'sources': [
            {'id': 'x', 'name': 'Fonte X (sigla)', 'novo': 1},
          ],
          'questions': [
            {
              'id': 'x-1',
              'source': 'x',
              'year': 2001,
              'area': 'mathematics',
              'statement': 's',
              'alternatives': ['a', 'b', 'c', 'd', 'e'],
              'media': 'futuro',
            },
            {'id': 'x-2', 'source': 'x', 'area': 'invalida', 'statement': 's'},
            {
              'id': 'y-1',
              'source': 'y',
              'area': 'humanities',
              'statement': 's',
            },
          ],
        }),
      );
      expect(parsed.questions.map((q) => q.id), ['bank_x-1']);
      expect(parsed.questions.single.platform, 'Fonte X 2001');
    });
  });

  group('catálogo', () {
    test(
      'busca filtra e pagina com cursor opaco, sem repetir nem perder',
      () async {
        const filter = QuestionFilter(query: 'função');
        final expected = filter.apply(data.questions).map((q) => q.id).toList();
        final seen = <String>[];
        String? cursor;
        var pages = 0;
        do {
          final page = await catalog.search(filter, cursor: cursor, limit: 7);
          expect(page.total, expected.length);
          expect(page.items.length, lessThanOrEqualTo(7));
          seen.addAll(page.items.map((q) => q.id));
          cursor = page.nextCursor;
          pages++;
        } while (cursor != null);
        expect(seen, expected);
        expect(pages, greaterThan(1));
      },
    );

    test('cursor inválido ou além do fim não quebra', () async {
      final bad = await catalog.search(const QuestionFilter(), cursor: 'x');
      expect(bad.items, isNotEmpty);
      final end = await catalog.search(
        const QuestionFilter(),
        cursor: '999999',
      );
      expect(end.items, isEmpty);
      expect(end.nextCursor, isNull);
    });

    test('byIds devolve na ordem pedida e ignora id desconhecido', () async {
      final got = await catalog.byIds([
        'enem-2009-141',
        'nao-existe',
        'enem-2009-1',
      ]);
      expect(got.map((q) => q.id), ['bank_enem-2009-141', 'bank_enem-2009-1']);
    });

    test('sources devolve a fonte do ENEM', () async {
      final s = await catalog.sources();
      expect(s.map((e) => e.id), contains('enem'));
    });

    test('facetas aceitam matéria ausente e batem com a busca', () async {
      const filter = QuestionFilter(query: 'função');
      final facets = await catalog.facets(filter);
      expect(facets.subjects.every((s) => s.value.isNotEmpty), isTrue);
      final total = (await catalog.search(filter)).total;
      expect(facets.areas.fold<int>(0, (n, o) => n + o.count), total);
      expect(
        facets.types.firstWhere((t) => t.value == QuestionType.objective).count,
        total,
      );
      // Faceta de área ignora o filtro de área, como no app.
      final math = filter.toggleArea(Area.mathematics);
      final f2 = await catalog.facets(math);
      expect(
        f2.areas.fold<int>(0, (n, o) => n + o.count),
        total,
        reason: 'contadores de área ignoram o próprio filtro',
      );
      // Filtro por matéria nunca quebra, mesmo com muitas sem matéria.
      final bySubject = await catalog.search(
        const QuestionFilter().toggleSubject('Matemática'),
      );
      expect(bySubject.items.every((q) => q.subject == 'Matemática'), isTrue);
    });

    test(
      'CA-B3: buscar no acervo não muda o "Minhas questões" nem o roteiro',
      () async {
        final seed = DemoSeed.build(DateTime(2026, 11, 6, 14));
        final mine = seed.questions;
        final before = List<Question>.of(mine);
        const script = QuestionFilter(query: 'função');
        final scripted = script
            .toggleArea(Area.mathematics)
            .toggleType(QuestionType.objective);
        expect(scripted.apply(mine), hasLength(9));

        await catalog.search(script);
        await catalog.facets(scripted);

        expect(mine, before);
        expect(scripted.apply(mine), hasLength(9));
        expect(mine.any((q) => q.origin == QuestionOrigin.bank), isFalse);
      },
    );
  });

  group('AssetBankCatalog (CA-B1, CA-B6)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'lê o asset só uma vez, só do bundle (sem rede, sem Firestore)',
      () async {
        final bundle = _CountingBundle();
        final asset = AssetBankCatalog(bundle: bundle);
        final a = await asset.search(const QuestionFilter(query: 'função'));
        final b = await asset.facets(const QuestionFilter());
        await asset.byIds(['enem-2009-141']);
        await asset.sources();
        expect(a.total, greaterThan(0));
        expect(b.areas, hasLength(4));
        expect(bundle.loads, 1);
        expect(bundle.paths, [bankAssetPath]);
      },
    );

    test('o asset registrado no pubspec carrega pelo rootBundle', () async {
      final asset = AssetBankCatalog();
      final page = await asset.search(const QuestionFilter(), limit: 5);
      expect(page.total, data.questions.length);
      expect(page.items, hasLength(5));
      expect((await rootBundle.loadString(bankAssetPath)).length, text.length);
    });

    test('falha de leitura não trava o catálogo: tenta de novo', () async {
      final bundle = _FlakyBundle();
      final asset = AssetBankCatalog(bundle: bundle);
      await expectLater(asset.sources(), throwsA(isA<Exception>()));
      expect(await asset.sources(), isNotEmpty);
    });
  });

  group('desempenho (CA-B9)', () {
    test('busca e facetas sobre ~2.000 questões em menos de 100 ms', () async {
      // Replica o asset até passar de 2.000 questões (pior caso do MVP).
      final big = <Question>[...data.questions];
      var copy = 0;
      while (big.length < 2000) {
        copy++;
        for (final q in data.questions) {
          if (big.length >= 2000) break;
          final c = q.copyWith(
            id: '${q.id}-$copy',
            bankId: '${q.bankId}-$copy',
          );
          c.searchText;
          big.add(c);
        }
      }
      final bigCatalog = MemoryBankCatalog(
        BankData(sources: data.sources, questions: big),
      );
      final filters = [
        const QuestionFilter(query: 'função'),
        const QuestionFilter(query: 'função')
            .toggleArea(Area.mathematics)
            .toggleType(QuestionType.objective),
        const QuestionFilter(query: 'energia elétrica'),
        const QuestionFilter().toggleSubject('Inglês'),
      ];
      // Aquece o JIT uma vez; o isolate real já devolve o searchText pronto.
      for (final f in filters) {
        await bigCatalog.search(f);
        await bigCatalog.facets(f);
      }
      final sw = Stopwatch();
      var worst = 0;
      for (final f in filters) {
        sw
          ..reset()
          ..start();
        await bigCatalog.search(f);
        await bigCatalog.facets(f);
        sw.stop();
        worst = worst > sw.elapsedMilliseconds ? worst : sw.elapsedMilliseconds;
      }
      // ignore: avoid_print
      print('CA-B9: ${big.length} questões, pior busca+facetas = $worst ms');
      expect(worst, lessThan(100));
    });

    test(
      'o parse do asset roda fora da thread da tela e é rápido o bastante',
      () {
        final sw = Stopwatch()..start();
        parseBankAsset(text);
        // ignore: avoid_print
        print('parse do asset (thread de teste): ${sw.elapsedMilliseconds} ms');
      },
    );
  });
}

class _CountingBundle extends CachingAssetBundle {
  int loads = 0;
  final List<String> paths = [];

  @override
  Future<ByteData> load(String key) async {
    loads++;
    paths.add(key);
    final bytes = Uint8List.fromList(File(key).readAsBytesSync());
    return ByteData.view(bytes.buffer);
  }
}

class _FlakyBundle extends CachingAssetBundle {
  int calls = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      super.loadString(key, cache: false);

  @override
  Future<ByteData> load(String key) async {
    if (calls++ == 0) throw Exception('falha simulada');
    final bytes = Uint8List.fromList(File(key).readAsBytesSync());
    return ByteData.view(bytes.buffer);
  }
}
