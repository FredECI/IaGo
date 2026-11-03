import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/local/demo_seed.dart';
import 'package:iago/domain/list_builder.dart';
import 'package:iago/domain/question_list.dart';
import 'package:iago/features/export/list_pdf.dart';
import 'package:image/image.dart' as img;

import '../helpers/pdf_fonts.dart';
import '../helpers/test_app.dart';

void main() {
  setUpAll(initTestLocale);

  final now = DateTime(2026, 11, 6, 14);
  final seed = DemoSeed.build(now);
  final fonts = loadTestPdfFonts();

  QuestionList listOf(List<String> ids) => QuestionList(
    id: 'l',
    name: 'Reforço — Funções',
    questionIds: ids,
    createdAt: now,
    updatedAt: now,
  );

  test('gera um PDF válido para a lista de reforço (objetivas)', () async {
    final questions = resolveQuestions(
      seed.lists.last.questionIds,
      seed.questions,
    );
    final pdf = await buildListPdf(
      list: listOf(seed.lists.last.questionIds),
      questions: questions,
      fonts: fonts,
      generatedAt: now,
    );
    expect(ascii.decode(pdf.bytes.sublist(0, 5)), '%PDF-');
    expect(pdf.pages, greaterThanOrEqualTo(1));
  });

  test('as 40 questões ocupam várias páginas sem estourar', () async {
    final ids = [for (final q in seed.questions) q.id];
    final pdf = await buildListPdf(
      list: listOf(ids),
      questions: seed.questions,
      fonts: fonts,
      generatedAt: now,
    );
    expect(pdf.pages, greaterThan(5));
  });

  test('aceita imagem anexada e questão só com imagem', () async {
    final image = img.encodeJpg(img.Image(width: 300, height: 200));
    final question = seed.questions.first.copyWith(
      statement: '',
      hasImage: true,
    );
    final pdf = await buildListPdf(
      list: listOf([question.id]),
      questions: [question],
      images: {question.id: Uint8List.fromList(image)},
      fonts: fonts,
      generatedAt: now,
    );
    expect(pdf.bytes.length, greaterThan(image.length));
  });

  test('enunciado enorme não trava a geração (pode quebrar página)', () async {
    final huge = seed.questions.first.copyWith(
      statement: List.filled(400, 'Texto longo de enunciado.').join(' '),
    );
    final pdf = await buildListPdf(
      list: listOf([huge.id]),
      questions: [huge],
      fonts: fonts,
      generatedAt: now,
    );
    expect(pdf.pages, greaterThan(1));
  });

  test('nenhum gabarito: o modelo nem tem campo de resposta certa', () {
    // Guarda-chuva de escopo: se alguém incluir "gabarito" no modelo,
    // este teste lembra que o IaGo não corrige nem cria gabarito.
    final map = seed.questions.first.toMap();
    expect(map.keys.where((k) => k.toLowerCase().contains('answer')), isEmpty);
    expect(answerLines, greaterThanOrEqualTo(5));
  });
}
