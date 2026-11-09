import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/bank_asset_catalog.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';

/// A3, casos-limite do QA: paginação, cópia pelo createMany, falhas e fontes.
void main() {
  final text = File('assets/acervo/acervo-v1.json').readAsStringSync();
  final data = parseBankAsset(text);
  final catalog = MemoryBankCatalog(data);

  group('paginação', () {
    test('último cursor devolve a página final sem nextCursor', () async {
      final total = data.questions.length;
      final page = await catalog.search(
        const QuestionFilter(),
        cursor: '${total - 3}',
        limit: 10,
      );
      expect(page.items, hasLength(3));
      expect(page.nextCursor, isNull);
      expect(page.total, total);
    });

    test('limit maior que o total devolve tudo em uma página', () async {
      final page = await catalog.search(
        const QuestionFilter(),
        limit: data.questions.length + 500,
      );
      expect(page.items, hasLength(data.questions.length));
      expect(page.nextCursor, isNull);
    });

    test('limit 0 e negativo não travam e o cursor avança', () async {
      for (final limit in [0, -5]) {
        final page = await catalog.search(const QuestionFilter(), limit: limit);
        expect(page.items.length, lessThanOrEqualTo(1));
        expect(page.nextCursor, isNotNull);
        expect(page.nextCursor, isNot('0'));
      }
    });

    test('cursor negativo é tratado como início', () async {
      final page = await catalog.search(const QuestionFilter(), cursor: '-4');
      expect(page.items.first.id, data.questions.first.id);
    });

    test('filtro sem resultado: página vazia, total 0, sem cursor', () async {
      final page = await catalog.search(
        const QuestionFilter(query: 'zzzxqwyk-inexistente'),
      );
      expect(page.items, isEmpty);
      expect(page.total, 0);
      expect(page.nextCursor, isNull);
    });

    test('percorrer todas as páginas cobre o acervo uma vez só', () async {
      final seen = <String>[];
      String? cursor;
      do {
        final p = await catalog.search(
          const QuestionFilter(),
          cursor: cursor,
          limit: 200,
        );
        seen.addAll(p.items.map((q) => q.id));
        cursor = p.nextCursor;
      } while (cursor != null);
      expect(seen, hasLength(data.questions.length));
      expect(seen.toSet(), hasLength(seen.length));
    });
  });

  group('filtros e busca', () {
    test('filtro por matéria nunca inclui questão de matéria vazia', () async {
      expect(data.questions.where((q) => q.subject.isEmpty), isNotEmpty);
      final page = await catalog.search(
        const QuestionFilter().toggleSubject('Matemática'),
        limit: 5000,
      );
      expect(page.items, isNotEmpty);
      expect(page.items.any((q) => q.subject.isEmpty), isFalse);
    });

    test('busca ignora acento e caixa', () async {
      final a = await catalog.search(const QuestionFilter(query: 'função'));
      final b = await catalog.search(const QuestionFilter(query: 'FUNCAO'));
      expect(a.total, greaterThan(0));
      expect(b.total, a.total);
    });

    test('plural -ões equivale a -ão', () async {
      final a = await catalog.search(const QuestionFilter(query: 'informação'));
      final b = await catalog.search(
        const QuestionFilter(query: 'informações'),
      );
      expect(a.total, greaterThan(0));
      expect(b.total, a.total);
    });

    test('byIds: vazio, só inexistentes e repetidos', () async {
      expect(await catalog.byIds(const []), isEmpty);
      expect(
        await catalog.byIds(['nao-existe', 'bank_enem-2009-141']),
        isEmpty,
      );
      final dup = await catalog.byIds(['enem-2009-141', 'enem-2009-141']);
      expect(dup.map((q) => q.id), everyElement('bank_enem-2009-141'));
    });

    test(
      'ids estáveis: duas instâncias resolvem o mesmo bankId igual',
      () async {
        final other = MemoryBankCatalog(parseBankAsset(text));
        final a = await catalog.byIds(['enem-2009-141']);
        final b = await other.byIds(['enem-2009-141']);
        expect(a.single.id, b.single.id);
        expect(a.single.statement, b.single.statement);
      },
    );
  });

  group('cópia para Minhas questões (CA-B4)', () {
    MemoryQuestionRepository repo() =>
        MemoryQuestionRepository(clock: () => DateTime(2026, 11, 8));

    test('salvar pelo createMany mantém id, origem e plataforma', () async {
      final r = repo();
      final q = (await catalog.byIds(['enem-2009-141'])).single;
      final saved = await r.createMany([q]);
      expect(saved.single.id, 'bank_enem-2009-141');
      expect(saved.single.origin, QuestionOrigin.bank);
      expect(saved.single.bankId, 'enem-2009-141');
      expect(saved.single.platform, 'ENEM 2009');
      expect(r.current, hasLength(1));
    });

    test(
      'salvar duas vezes (mesmo lote ou lotes seguidos) não duplica',
      () async {
        final r = repo();
        final q = (await catalog.byIds(['enem-2009-141'])).single;
        await r.createMany([q, q]);
        expect(r.current, hasLength(1));
        await r.createMany([q]);
        await r.createMany([q]);
        expect(r.current, hasLength(1));
      },
    );

    test(
      '30 do acervo viram 30 cópias, e salvar de novo não duplica',
      () async {
        final r = repo();
        final page = await catalog.search(const QuestionFilter(), limit: 30);
        await r.createMany(page.items);
        await r.createMany(page.items);
        expect(r.current, hasLength(30));
        expect(r.current.every((q) => q.origin == QuestionOrigin.bank), isTrue);
      },
    );

    test('editar a cópia não altera o objeto do acervo', () async {
      final r = repo();
      final q = (await catalog.byIds(['enem-2009-141'])).single;
      final saved = (await r.createMany([q])).single;
      await r.update(saved.copyWith(statement: 'editado'));
      final again = (await catalog.byIds(['enem-2009-141'])).single;
      expect(again.statement, q.statement);
    });
  });

  group('AssetBankCatalog: falhas', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('asset com schemaVersion 2 falha e permite nova tentativa', () async {
      final bundle = _SwitchBundle('{"schemaVersion": 2, "questions": []}');
      final asset = AssetBankCatalog(bundle: bundle);
      await expectLater(
        asset.search(const QuestionFilter()),
        throwsFormatException,
      );
      bundle.content = text;
      final page = await asset.search(const QuestionFilter(), limit: 3);
      expect(page.items, hasLength(3));
    });

    test('JSON corrompido falha sem travar o catálogo', () async {
      final bundle = _SwitchBundle('{nao e json');
      final asset = AssetBankCatalog(bundle: bundle);
      await expectLater(asset.sources(), throwsA(isA<FormatException>()));
      bundle.content = text;
      expect(await asset.sources(), isNotEmpty);
    });

    test('chamadas concorrentes carregam o asset uma vez só', () async {
      final bundle = _SwitchBundle(text);
      final asset = AssetBankCatalog(bundle: bundle);
      await Future.wait([
        asset.sources(),
        asset.facets(const QuestionFilter()),
        asset.search(const QuestionFilter()),
      ]);
      expect(bundle.loads, 1);
    });

    test('fonte não registrada: questão é descartada, não quebra', () {
      final parsed = parseBankAsset(
        '{"schemaVersion":1,"sources":[],"questions":[{"id":"zz-1",'
        '"source":"zz","area":"mathematics","statement":"s"}]}',
      );
      expect(parsed.questions, isEmpty);
    });

    test('asset sem a chave questions devolve acervo vazio', () async {
      final empty = MemoryBankCatalog(parseBankAsset('{"schemaVersion":1}'));
      final page = await empty.search(const QuestionFilter());
      expect(page.total, 0);
      expect(page.nextCursor, isNull);
      final f = await empty.facets(const QuestionFilter());
      expect(f.areas.fold<int>(0, (n, o) => n + o.count), 0);
    });
  });

  group('critérios estáticos', () {
    Iterable<File> dartFiles(String dir) =>
        Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));

    test('CA-F2: nenhum código do app cita api.enem.dev', () {
      for (final f in dartFiles('lib')) {
        expect(
          f.readAsStringSync(),
          isNot(contains('api.enem.dev')),
          reason: f.path,
        );
      }
    });

    test('CA-B6: o acervo não usa rede nem Firestore', () {
      for (final p in [
        'lib/data/bank_catalog.dart',
        'lib/data/bank_asset_catalog.dart',
        'lib/data/local/bank_asset_parser.dart',
        'lib/features/bank/bank_providers.dart',
      ]) {
        final s = File(p).readAsStringSync();
        expect(s, isNot(contains('cloud_firestore')), reason: p);
        expect(s, isNot(contains('firebase')), reason: p);
        expect(s, isNot(contains('dart:io')), reason: p);
        expect(s, isNot(contains('package:http')), reason: p);
        expect(s, isNot(contains('HttpClient')), reason: p);
      }
    });

    test('CA-R3: a interface não expõe tipos da implementação', () {
      final s = File('lib/data/bank_catalog.dart').readAsStringSync();
      expect(s, isNot(contains('bank_asset')));
      expect(s, isNot(contains('MemoryBankCatalog')));
    });

    test('CA-T5: nenhum arquivo de lib importa flutter/material.dart', () {
      for (final f in dartFiles('lib')) {
        expect(
          f.readAsStringSync(),
          isNot(contains('package:flutter/material.dart')),
          reason: f.path,
        );
      }
    });
  });
}

class _SwitchBundle extends CachingAssetBundle {
  _SwitchBundle(this.content);
  String content;
  int loads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loads++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return content;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}
