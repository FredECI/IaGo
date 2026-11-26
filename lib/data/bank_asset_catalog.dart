import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/area.dart';
import '../domain/bank_source.dart';
import '../domain/bank_summary.dart';
import '../domain/question.dart';
import '../domain/question_filter.dart';
import 'bank_catalog.dart';
import 'local/bank_asset_parser.dart';

/// Índice do acervo v2 (as partes vêm do campo `shards`).
const String bankIndexPath = 'assets/acervo/v2/index.json';

/// Limites do asset (CA-R7), conferidos por teste e pelo script.
const int maxBankShardBytes = 3 * 1024 * 1024;
const int maxBankTotalBytes = 12 * 1024 * 1024;

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

  /// Calculado das questões (o catálogo real lê o índice).
  @override
  Future<BankSummary> summary() async {
    final tally = <(Area, String, int?), int>{};
    for (final q in _data.questions) {
      if (q.subject.isEmpty) continue;
      final key = (q.area, q.subject, q.bankDifficulty);
      tally[key] = (tally[key] ?? 0) + 1;
    }
    return BankSummary.fromTally(
      generatedAt: _data.generatedAt,
      tally: tally,
      taxonomy: _data.taxonomy,
    );
  }
}

/// Lê o índice e as partes do asset (uma por área) sob demanda, cada uma uma
/// única vez por sessão, e faz o parse num isolate para não travar a tela.
///
/// | Chamada | O que carrega |
/// | --- | --- |
/// | `summary()` e `sources()` | só o índice |
/// | `search(filter)` | as áreas do filtro e as das suas matérias; sem área, todas |
/// | `facets(filter)` e `byIds(ids)` | todas as áreas |
class AssetBankCatalog implements BankCatalog {
  AssetBankCatalog({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<BankIndex>? _index;
  final Map<Area, Future<List<Question>>> _shards = {};
  final Map<String, Future<MemoryBankCatalog>> _catalogs = {};

  Future<BankIndex> _loadIndex() => _index ??= _readIndex();

  Future<BankIndex> _readIndex() async {
    try {
      final text = await _bundle.loadString(bankIndexPath);
      return await compute(parseBankIndex, text);
    } catch (_) {
      _index = null; // permite tentar de novo
      rethrow;
    }
  }

  Future<List<Question>> _loadShard(BankIndex index, Area area) =>
      _shards[area] ??= _readShard(index, area);

  Future<List<Question>> _readShard(BankIndex index, Area area) async {
    try {
      final refs = index.shards.where((s) => s.area == area);
      if (refs.isEmpty) return const <Question>[];
      final text = await _bundle.loadString(refs.first.path);
      return await compute(
        parseBankShard,
        BankShardInput(
          json: text,
          sources: index.sources,
          generatedAt: index.generatedAt,
        ),
      );
    } catch (_) {
      unawaited(_shards.remove(area)); // permite tentar de novo
      rethrow;
    }
  }

  /// Catálogo em memória sobre as partes das [areas] (todas, se `null`).
  Future<MemoryBankCatalog> _catalog(Set<Area>? areas) {
    final wanted = [
      for (final a in Area.values)
        if (areas == null || areas.contains(a)) a,
    ];
    final key = wanted.map((a) => a.name).join(',');
    return _catalogs[key] ??= _readCatalog(key, wanted);
  }

  Future<MemoryBankCatalog> _readCatalog(String key, List<Area> wanted) async {
    try {
      final index = await _loadIndex();
      final parts = await Future.wait([
        for (final a in wanted) _loadShard(index, a),
      ]);
      return MemoryBankCatalog(
        BankData(
          sources: index.sources,
          questions: [for (final p in parts) ...p],
          taxonomy: index.summary.taxonomy,
          generatedAt: index.summary.generatedAt,
        ),
      );
    } catch (_) {
      unawaited(_catalogs.remove(key));
      rethrow;
    }
  }

  /// Áreas que a busca precisa: as do filtro mais as das matérias filtradas.
  /// Sem nenhuma (ou com matéria desconhecida), `null`: todas.
  static Set<Area>? _areasFor(QuestionFilter filter) {
    final areas = <Area>{...filter.areas};
    for (final subject in filter.subjects) {
      for (final a in Area.values) {
        if (a.subjects.contains(subject)) areas.add(a);
      }
    }
    return areas.isEmpty ? null : areas;
  }

  @override
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  }) async =>
      (await _catalog(_areasFor(filter)))
          .search(filter, cursor: cursor, limit: limit);

  @override
  Future<QuestionFacets> facets(QuestionFilter filter) async =>
      (await _catalog(null)).facets(filter);

  @override
  Future<List<Question>> byIds(List<String> bankIds) async =>
      (await _catalog(null)).byIds(bankIds);

  @override
  Future<List<BankSource>> sources() async => (await _loadIndex()).sources;

  @override
  Future<BankSummary> summary() async => (await _loadIndex()).summary;
}
