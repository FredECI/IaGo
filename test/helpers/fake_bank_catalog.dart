import 'package:iago/data/bank_catalog.dart';
import 'package:iago/data/bank_asset_catalog.dart';
import 'package:iago/data/local/bank_asset_parser.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/bank_source.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';

const BankSource fakeBankSource = BankSource(
  id: 'enem',
  name: 'ENEM (INEP)',
  officialUrl: 'https://exemplo.gov.br/enem',
  attribution: 'Provas do ENEM, INEP.',
  notice: 'Reproduzido para uso educacional. Confira o original.',
  via: 'api.exemplo.dev',
);

/// 1.250 questões falsas: 0 a 49 de Matemática com "função"; 100 a 111 com
/// "reforço"; metade das de Humanas e Linguagens ainda sem matéria.
BankData fakeBankData() {
  final stamp = DateTime(2026, 11, 7);
  final areas = Area.values; // 0 a 2: sem Matemática
  final questions = <Question>[];
  for (var i = 0; i < 1250; i++) {
    final area = i < 50 ? Area.mathematics : areas[i % 3];
    final subject = area == Area.mathematics
        ? 'Matemática'
        : (i.isEven ? '' : area.subjects.first);
    final extra = i < 50
        ? 'Qual é a função do item $i?'
        : (i >= 100 && i < 112 ? 'Plano de reforço $i.' : 'Texto $i.');
    questions.add(
      Question(
        id: 'bank_enem-2022-$i',
        statement: 'Questão $i. $extra',
        type: QuestionType.objective,
        alternatives: [
          for (final l in Question.letters) 'Alternativa $l do $i',
        ],
        area: area,
        subject: subject,
        platform: 'ENEM ${2022 + i % 2}',
        sourceUrl: fakeBankSource.officialUrl,
        createdAt: stamp,
        updatedAt: stamp,
        origin: QuestionOrigin.bank,
        bankId: 'enem-2022-$i',
      ),
    );
  }
  return BankData(sources: const [fakeBankSource], questions: questions);
}

/// Catálogo em memória com atraso e falhas programáveis.
class FakeBankCatalog implements BankCatalog {
  FakeBankCatalog({
    BankData? data,
    this.delay = const Duration(milliseconds: 150),
  }) : _inner = MemoryBankCatalog(data ?? fakeBankData());

  final MemoryBankCatalog _inner;
  final Duration delay;

  /// Quantas das próximas buscas devem falhar.
  int failSearches = 0;
  final List<String?> cursors = [];

  @override
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  }) async {
    await Future<void>.delayed(delay);
    if (failSearches > 0) {
      failSearches--;
      throw StateError('falha simulada');
    }
    cursors.add(cursor);
    return _inner.search(filter, cursor: cursor, limit: limit);
  }

  @override
  Future<QuestionFacets> facets(QuestionFilter filter) async {
    await Future<void>.delayed(delay);
    return _inner.facets(filter);
  }

  @override
  Future<List<Question>> byIds(List<String> bankIds) async {
    await Future<void>.delayed(delay);
    return _inner.byIds(bankIds);
  }

  @override
  Future<List<BankSource>> sources() async {
    await Future<void>.delayed(delay);
    return _inner.sources();
  }
}
