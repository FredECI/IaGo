import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/demo_seed.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:pdf/pdf.dart';

void main() {
  final now = DateTime(2026, 11, 6, 14);
  final seed = DemoSeed.build(now);
  final questions = seed.questions;

  test('tem 40 questões e 2 listas, com ids únicos', () {
    expect(questions, hasLength(40));
    expect(seed.lists, hasLength(2));
    expect(questions.map((q) => q.id).toSet(), hasLength(40));
  });

  test('cobre as 4 áreas, várias matérias e os dois tipos', () {
    expect(questions.map((q) => q.area).toSet(), Area.values.toSet());
    expect(questions.map((q) => q.subject).toSet().length, greaterThan(10));
    final types = questions.map((q) => q.type).toList();
    expect(types.where((t) => t == QuestionType.objective), hasLength(30));
    expect(types.where((t) => t == QuestionType.discursive), hasLength(10));
  });

  test('matérias pertencem ao catálogo da área', () {
    for (final q in questions) {
      expect(q.area.subjects, contains(q.subject), reason: q.id);
    }
  });

  test('objetivas têm 5 alternativas; discursivas, nenhuma', () {
    for (final q in questions) {
      expect(q.statement.trim(), isNotEmpty, reason: q.id);
      expect(q.alternatives, hasLength(q.isObjective ? 5 : 0), reason: q.id);
    }
  });

  test('listas só referenciam questões existentes', () {
    final ids = questions.map((q) => q.id).toSet();
    for (final list in seed.lists) {
      expect(ids.containsAll(list.questionIds), isTrue, reason: list.name);
    }
  });

  test('roteiro da demo: "função" + Matemática + Objetiva devolve 9', () {
    final filter = const QuestionFilter(query: 'função')
        .toggleArea(Area.mathematics)
        .toggleType(QuestionType.objective);
    expect(filter.apply(questions), hasLength(9));
    // Sem os filtros, a busca também traz Biologia e Linguagens.
    final all = const QuestionFilter(query: 'função').apply(questions);
    expect(all.map((q) => q.area).toSet(), {
      Area.mathematics,
      Area.naturalSciences,
      Area.languages,
    });
  });

  test('janelas do resumo: 8 nos últimos 7 dias e 5 nos 7 anteriores', () {
    final weekAgo = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));
    final recent = questions.where((q) => q.createdAt.isAfter(weekAgo));
    final previous = questions.where(
      (q) => q.createdAt.isAfter(twoWeeksAgo) && !q.createdAt.isAfter(weekAgo),
    );
    expect(recent, hasLength(8));
    expect(previous, hasLength(5));
  });

  test('nenhuma data fica no futuro', () {
    for (final q in questions) {
      expect(q.createdAt.isAfter(now), isFalse, reason: q.id);
    }
    for (final list in seed.lists) {
      expect(list.createdAt.isAfter(now), isFalse, reason: list.name);
    }
  });

  test('todo caractere tem glifo na fonte embutida (app e PDF offline)', () {
    final missing = <String>{};
    for (final file in ['Inter-Regular.ttf', 'Inter-Bold.ttf']) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      final font = TtfParser(ByteData.view(bytes.buffer));
      final texts = [
        for (final q in questions) ...[
          q.statement,
          ...q.alternatives,
          q.subject,
          q.topic,
          q.platform,
          q.notes ?? '',
        ],
        for (final l in seed.lists) l.name,
      ];
      for (final text in texts) {
        for (final rune in text.runes) {
          if (rune == 0x20) continue;
          if (!font.charToGlyphIndexMap.containsKey(rune)) {
            missing.add(
              '${String.fromCharCode(rune)} (U+${rune.toRadixString(16)}) em $file',
            );
          }
        }
      }
    }
    expect(missing, isEmpty);
  });
}
