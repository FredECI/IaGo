import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/bank_source.dart';
import '../domain/question.dart';
import '../domain/question_filter.dart';
import 'bank_catalog.dart';
import 'local/bank_asset_parser.dart';

const String bankAssetPath = 'assets/acervo/acervo-v1.json';

/// Acervo em memória: filtra com o mesmo [QuestionFilter] do app. Não toca
/// em rede nem em Firestore (CA-B6).
class MemoryBankCatalog implements BankCatalog {
  MemoryBankCatalog(this._data)
    : _byBankId = {
        for (final q in _data.questions)
          if (q.bankId != null) q.bankId!: q,
      };

  final BankData _data;
  final Map<String, Question> _byBankId;

  @override
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  }) async {
    final all = filter.isEmpty
        ? _data.questions
        : filter.apply(_data.questions);
    final start = (int.tryParse(cursor ?? '') ?? 0).clamp(0, all.length);
    final end = (start + (limit < 1 ? 1 : limit)).clamp(0, all.length);
    return BankPage(
      items: all.sublist(start, end),
      total: all.length,
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  @override
  Future<QuestionFacets> facets(QuestionFilter filter) async {
    final f = QuestionFacets.compute(_data.questions, filter);
    // Questão ainda sem matéria (classificação pendente) não vira opção.
    return QuestionFacets(
      areas: f.areas,
      subjects: [
        for (final s in f.subjects)
          if (s.value.isNotEmpty) s,
      ],
      topics: f.topics,
      types: f.types,
      platforms: f.platforms,
    );
  }

  @override
  Future<List<Question>> byIds(List<String> bankIds) async => [
    for (final id in bankIds)
      if (_byBankId[id] case final Question q) q,
  ];

  @override
  Future<List<BankSource>> sources() async => _data.sources;
}

/// Lê o asset uma única vez por sessão, no primeiro uso, e faz o parse num
/// isolate para não travar a tela.
class AssetBankCatalog implements BankCatalog {
  AssetBankCatalog({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<MemoryBankCatalog>? _loading;

  Future<MemoryBankCatalog> _catalog() => _loading ??= _load();

  Future<MemoryBankCatalog> _load() async {
    try {
      final text = await _bundle.loadString(bankAssetPath);
      return MemoryBankCatalog(await compute(parseBankAsset, text));
    } catch (_) {
      _loading = null; // permite tentar de novo
      rethrow;
    }
  }

  @override
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  }) async => (await _catalog()).search(filter, cursor: cursor, limit: limit);

  @override
  Future<QuestionFacets> facets(QuestionFilter filter) async =>
      (await _catalog()).facets(filter);

  @override
  Future<List<Question>> byIds(List<String> bankIds) async =>
      (await _catalog()).byIds(bankIds);

  @override
  Future<List<BankSource>> sources() async => (await _catalog()).sources();
}
