import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:iago/data/local/bank_asset_parser.dart';

/// Pasta do asset v2 (os testes rodam na raiz do repositório).
const String realBankDir = 'assets/acervo/v2';

/// O acervo real (v2) lido do disco, de forma síncrona e sem isolate.
class RealBank {
  RealBank._(this.index, this.indexJson, this.shardJson, this.data);

  factory RealBank.load() {
    final indexText = File('$realBankDir/index.json').readAsStringSync();
    final index = parseBankIndex(indexText);
    final shardJson = {
      for (final s in index.shards) s.path: File(s.path).readAsStringSync(),
    };
    final questions = [
      for (final s in index.shards)
        ...parseBankShard(
          BankShardInput(
            json: shardJson[s.path]!,
            sources: index.sources,
            generatedAt: index.generatedAt,
          ),
        ),
    ];
    return RealBank._(
      index,
      jsonDecode(indexText) as Map<String, Object?>,
      shardJson,
      BankData(
        sources: index.sources,
        questions: questions,
        taxonomy: index.summary.taxonomy,
        generatedAt: index.summary.generatedAt,
      ),
    );
  }

  final BankIndex index;

  /// `index.json` decodificado.
  final Map<String, Object?> indexJson;

  /// Texto de cada parte, pelo caminho declarado no índice.
  final Map<String, String> shardJson;
  final BankData data;

  /// Todas as questões, como mapas do JSON (sem o parse).
  List<Map<String, Object?>> get rawQuestions => [
    for (final text in shardJson.values)
      ...((jsonDecode(text) as Map)['questions'] as List)
          .cast<Map<String, Object?>>(),
  ];
}

/// Lê o asset direto do disco (a VM de teste não precisa do bundle).
class FileAssetBundle extends AssetBundle {
  /// Caminhos lidos, na ordem.
  final List<String> paths = [];

  @override
  Future<ByteData> load(String key) async {
    paths.add(key);
    return ByteData.sublistView(File(key).readAsBytesSync());
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    paths.add(key);
    return File(key).readAsStringSync();
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}
