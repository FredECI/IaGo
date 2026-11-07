/// Contrato da resposta da IA de extração de questões (Dart puro).
///
/// Não depende de nenhum SDK de IA: quem chama o provedor entrega aqui o
/// texto JSON da resposta. Trocar de provedor não muda este arquivo.
///
/// O IaGo não guarda gabarito: qualquer campo fora do contrato (como
/// `correctAlternative` ou `answer`) é ignorado e nunca chega ao resultado.
library;

import 'dart:convert';

import '../core/text_normalizer.dart';
import 'area.dart';
import 'question.dart';

const int extractionSchemaVersion = 1;
const int maxExtractedStatementLength = 6000;
const int maxExtractedQuestions = 30;
const int minObjectiveAlternatives = 2;
const int maxObjectiveAlternatives = 5;
const int maxAlternativeLength = 1000;
const int maxAlternativesPerItem = 10;
const int _maxHintLength = 200;

/// Resposta sem condições de uso (versão do contrato diferente ou sem JSON
/// aproveitável). Equivale à falha `malformed`.
class MalformedExtractionException implements Exception {
  const MalformedExtractionException(this.message);
  final String message;

  @override
  String toString() => 'MalformedExtractionException: $message';
}

/// Rascunho de questão vindo da IA, ainda sem salvar.
class ExtractedQuestion {
  const ExtractedQuestion({
    required this.statement,
    required this.type,
    this.alternatives = const [],
    this.hasFigure = false,
    this.isComplete = true,
    this.page,
    this.sourceHint,
    this.suggestedArea,
    this.suggestedSubject,
    this.warnings = const [],
  });

  final String statement;
  final QuestionType type;
  final List<String> alternatives;

  /// Depende de figura, gráfico ou tabela que não virou texto.
  final bool hasFigure;

  /// `false` quando o enunciado está cortado.
  final bool isComplete;
  final int? page;
  final String? sourceHint;
  final Area? suggestedArea;
  final String? suggestedSubject;

  /// Avisos em português para a tela de revisão.
  final List<String> warnings;

  /// CA-I9: com figura, cortada ou com aviso, vem desmarcada.
  bool get needsAttention => hasFigure || !isComplete || warnings.isNotEmpty;
  bool get selectedByDefault => !needsAttention;
}

/// Resultado da validação de uma resposta inteira.
class ExtractionResult {
  const ExtractionResult({
    required this.questions,
    this.partial = false,
    this.containsPersonalData = false,
    this.notes,
    this.discardedCount = 0,
    this.warnings = const [],
  });

  final List<ExtractedQuestion> questions;

  /// O JSON veio cortado ou inválido e só os objetos completos foram mantidos.
  final bool partial;
  final bool containsPersonalData;
  final String? notes;

  /// Itens descartados (enunciado vazio ou grande demais, formato errado).
  final int discardedCount;

  /// Avisos do lote (repetidas, excesso, dados pessoais, resposta parcial).
  final List<String> warnings;
}

/// Recupera de um JSON cortado todos os objetos completos do array
/// `questions`, e nenhum inventado: um objeto só vale se as chaves fecharam e
/// ele é um JSON válido. Aceita texto cercado por ```json.
List<Map<String, dynamic>> salvageQuestions(String raw) => _scan(raw).questions;

class _Scan {
  _Scan(this.questions, this.schemaVersion, this.containsPersonalData);
  final List<Map<String, dynamic>> questions;
  final Object? schemaVersion;
  final bool? containsPersonalData;
}

bool _isWs(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09;

_Scan _scan(String raw) {
  final s = raw;
  final questions = <Map<String, dynamic>>[];
  Object? schemaVersion;
  bool? personal;

  // Começa no objeto do contrato, não numa chave de frase de abertura
  // ("Aqui vai {o JSON}: {"schemaVersion"..."); sem ele, no primeiro '{'.
  final root = RegExp(r'\{\s*"(?:schemaVersion|questions)"').firstMatch(s);
  var i = root?.start ?? s.indexOf('{');
  if (i < 0) return _Scan(questions, null, null);
  i++; // dentro do objeto raiz (profundidade 1)

  // Retorna o índice depois da string que começa em [from] (aspas de abertura)
  // ou -1 se ela não termina.
  int endOfString(int from) {
    var j = from + 1;
    while (j < s.length) {
      final c = s.codeUnitAt(j);
      if (c == 0x5C) {
        j += 2;
        continue;
      }
      if (c == 0x22) return j + 1;
      j++;
    }
    return -1;
  }

  int skipWs(int from) {
    var j = from;
    while (j < s.length && _isWs(s.codeUnitAt(j))) {
      j++;
    }
    return j;
  }

  // Pula um valor qualquer; devolve o índice depois dele, ou -1 se cortado.
  int skipValue(int from) {
    var j = skipWs(from);
    if (j >= s.length) return -1;
    final c = s.codeUnitAt(j);
    if (c == 0x22) return endOfString(j);
    if (c == 0x7B || c == 0x5B) {
      var depth = 0;
      while (j < s.length) {
        final ch = s.codeUnitAt(j);
        if (ch == 0x22) {
          j = endOfString(j);
          if (j < 0) return -1;
          continue;
        }
        if (ch == 0x7B || ch == 0x5B) depth++;
        if (ch == 0x7D || ch == 0x5D) {
          depth--;
          if (depth == 0) return j + 1;
        }
        j++;
      }
      return -1;
    }
    while (j < s.length) {
      final ch = s.codeUnitAt(j);
      if (ch == 0x2C || ch == 0x7D || ch == 0x5D || _isWs(ch)) break;
      j++;
    }
    return j;
  }

  while (i < s.length) {
    i = skipWs(i);
    if (i >= s.length) break;
    final c = s.codeUnitAt(i);
    if (c == 0x2C) {
      i++;
      continue;
    }
    if (c != 0x22) break; // fim do objeto raiz ou lixo
    final keyEnd = endOfString(i);
    if (keyEnd < 0) break;
    final key = s.substring(i + 1, keyEnd - 1);
    i = skipWs(keyEnd);
    if (i >= s.length || s.codeUnitAt(i) != 0x3A) break;
    i = skipWs(i + 1);

    if (key == 'questions' && i < s.length && s.codeUnitAt(i) == 0x5B) {
      i++;
      while (i < s.length) {
        i = skipWs(i);
        if (i >= s.length) break;
        final ch = s.codeUnitAt(i);
        if (ch == 0x2C) {
          i++;
          continue;
        }
        if (ch == 0x5D) {
          i++;
          break;
        }
        final end = skipValue(i);
        if (end < 0) {
          i = s.length; // item cortado: descartado
          break;
        }
        if (ch == 0x7B) {
          try {
            final decoded = jsonDecode(s.substring(i, end));
            if (decoded is Map<String, dynamic>) questions.add(decoded);
          } on FormatException {
            // objeto fechado mas inválido: não aproveitar
          }
        }
        i = end;
      }
      continue;
    }

    final end = skipValue(i);
    if (end < 0) break;
    if (key == 'schemaVersion' || key == 'containsPersonalData') {
      try {
        final v = jsonDecode(s.substring(i, end));
        if (key == 'schemaVersion') schemaVersion = v;
        if (key == 'containsPersonalData' && v is bool) personal = v;
      } on FormatException {
        // ignora valor ilegível
      }
    }
    i = end;
  }
  return _Scan(questions, schemaVersion, personal);
}

String _stripFences(String raw) {
  final t = raw.trim();
  if (!t.startsWith('```')) return t;
  final firstLine = t.indexOf('\n');
  var body = firstLine < 0 ? '' : t.substring(firstLine + 1);
  final close = body.lastIndexOf('```');
  if (close >= 0) body = body.substring(0, close);
  return body.trim();
}

/// Valida a resposta da IA conforme o contrato (tabela C.1 da spec).
///
/// Lança [MalformedExtractionException] se `schemaVersion` não for 1 ou se
/// não houver nada aproveitável. JSON cortado vira resultado com
/// `partial == true`.
ExtractionResult parseExtraction(String raw) {
  final text = _stripFences(raw);

  Object? schemaVersion;
  bool personal = false;
  String? notes;
  List<Object?> items;
  var partial = false;

  Object? decoded;
  var validJson = true;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    decoded = null;
    validJson = false;
    partial = true;
  }

  if (validJson &&
      !(decoded is Map<String, dynamic> && decoded['questions'] is List)) {
    // JSON íntegro, mas fora do formato do contrato: nada a salvar.
    throw const MalformedExtractionException('Resposta fora do formato.');
  }

  if (decoded is Map<String, dynamic> && decoded['questions'] is List) {
    schemaVersion = decoded['schemaVersion'];
    personal = decoded['containsPersonalData'] == true;
    final n = decoded['notes'];
    notes = n is String && n.trim().isNotEmpty ? n.trim() : null;
    items = List<Object?>.from(decoded['questions'] as List);
  } else {
    final scan = _scan(text);
    partial = true;
    schemaVersion = scan.schemaVersion;
    personal = scan.containsPersonalData ?? false;
    items = scan.questions;
    if (schemaVersion == null && items.isEmpty) {
      throw const MalformedExtractionException(
        'Resposta sem JSON aproveitável.',
      );
    }
  }

  if (schemaVersion != extractionSchemaVersion) {
    throw MalformedExtractionException(
      'schemaVersion $schemaVersion não é suportado.',
    );
  }

  final warnings = <String>[];
  var discarded = 0;
  var duplicates = 0;
  final seen = <String>{};
  final out = <ExtractedQuestion>[];
  var overflow = 0;

  for (final item in items) {
    final q = _validateItem(item);
    if (q == null) {
      discarded++;
      continue;
    }
    // Chave própria: preserva símbolos e dígitos ("3 + 4" difere de "3 - 4").
    final key = q.statement.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (!seen.add(key)) {
      duplicates++;
      continue;
    }
    if (out.length >= maxExtractedQuestions) {
      overflow++;
      continue;
    }
    out.add(q);
  }

  if (partial) {
    warnings.add(
      'Aproveitamos ${out.length} '
      '${out.length == 1 ? 'questão' : 'questões'}; confira se faltou alguma.',
    );
  }
  if (duplicates > 0) {
    warnings.add(
      duplicates == 1
          ? 'Uma questão repetida foi mantida só uma vez.'
          : '$duplicates questões repetidas foram mantidas só uma vez.',
    );
  }
  if (overflow > 0) {
    warnings.add(
      'Mantivemos as primeiras $maxExtractedQuestions questões; '
      'envie o restante em outro lote.',
    );
  }
  if (discarded > 0) {
    warnings.add(
      discarded == 1
          ? 'Um item inválido (sem enunciado utilizável ou grande demais) '
                'foi descartado.'
          : '$discarded itens inválidos (sem enunciado utilizável ou grandes '
                'demais) foram descartados.',
    );
  }
  if (personal) {
    warnings.add(
      'O arquivo pode ter dados pessoais. Confira e remova antes de salvar.',
    );
  }

  return ExtractionResult(
    questions: out,
    partial: partial,
    containsPersonalData: personal,
    notes: notes,
    discardedCount: discarded,
    warnings: warnings,
  );
}

/// Linha que começa com "Gabarito" ou "Resposta".
final RegExp _answerKeyLine = RegExp(
  r'^[ \t]*(?:gabarito|resposta)\b',
  caseSensitive: false,
  multiLine: true,
);

final RegExp _letterPrefix = RegExp(
  r'^\s*(?:\(([A-Ea-e])\)|([A-Ea-e])(?:\)|\.(?=\s)|[ \t]*[-–—](?=\s)))\s*',
);

String _stripLetter(String alt, int index) {
  final m = _letterPrefix.firstMatch(alt);
  if (m == null) return alt;
  final letter = (m.group(1) ?? m.group(2))!.toUpperCase();
  // Só tira se a letra é a esperada para a posição ("E. coli" na 1ª fica).
  if (letter.codeUnitAt(0) - 0x41 != index) return alt;
  return alt.substring(m.end).trim();
}

ExtractedQuestion? _validateItem(Object? item) {
  if (item is! Map) return null;
  final rawStatement = item['statement'];
  if (rawStatement is! String) return null;
  final statement = rawStatement.trim();
  if (statement.isEmpty || statement.length > maxExtractedStatementLength) {
    return null;
  }

  final warnings = <String>[];
  var alternatives = <String>[];
  final rawAlts = item['alternatives'];
  if (rawAlts is List) {
    // Acima do teto o item é descartado inteiro (nunca truncado em silêncio).
    if (rawAlts.length > maxAlternativesPerItem) return null;
    for (final a in rawAlts) {
      if (a is! String) continue;
      if (a.trim().length > maxAlternativeLength) return null;
      final cleaned = _stripLetter(a.trim(), alternatives.length);
      if (cleaned.isNotEmpty) alternatives.add(cleaned);
    }
  }

  var type = QuestionType.tryParse(
    item['type'] is String ? item['type'] as String : null,
  );
  if (type == null) {
    type = alternatives.isNotEmpty
        ? QuestionType.objective
        : QuestionType.discursive;
    warnings.add('O tipo da questão não veio claro. Confira.');
  }

  if (type == QuestionType.discursive) {
    alternatives = const [];
  } else if (alternatives.length < minObjectiveAlternatives ||
      alternatives.length > maxObjectiveAlternatives) {
    warnings.add(
      'Objetiva com ${alternatives.length} alternativas (o esperado é de '
      '$minObjectiveAlternatives a $maxObjectiveAlternatives). Confira.',
    );
  }

  final complete = item['isComplete'] == true;
  if (item['isComplete'] is! bool) {
    warnings.add('Não foi possível confirmar que a questão está completa.');
  }

  final area = Area.tryParse(
    item['suggestedArea'] is String ? item['suggestedArea'] as String : null,
  );
  String? subject;
  final rawSubject = item['suggestedSubject'];
  if (area != null && rawSubject is String) {
    final key = tagKey(rawSubject);
    for (final s in area.subjects) {
      if (tagKey(s) == key) subject = s;
    }
  }

  final rawPage = item['page'];
  final page = rawPage is int && rawPage > 0 ? rawPage : null;
  final rawHint = item['sourceHint'];
  var hint = rawHint is String ? rawHint.trim() : null;
  if (hint != null && hint.isEmpty) hint = null;
  if (hint != null && hint.length > _maxHintLength) {
    hint = hint.substring(0, _maxHintLength);
  }

  // Sem gabarito: texto de resposta dentro do conteúdo vira aviso (e desmarca).
  final texts = [statement, ...alternatives, ?hint];
  if (texts.any(_answerKeyLine.hasMatch)) {
    warnings.add(
      'O texto parece trazer gabarito ou resposta. O IaGo não guarda '
      'gabarito: apague essa parte antes de salvar.',
    );
  }

  return ExtractedQuestion(
    statement: statement,
    type: type,
    alternatives: alternatives,
    hasFigure: item['hasFigure'] == true,
    isComplete: complete,
    page: page,
    sourceHint: hint,
    suggestedArea: area,
    suggestedSubject: subject,
    warnings: warnings,
  );
}
