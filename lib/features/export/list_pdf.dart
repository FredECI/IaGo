import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/app_info.dart';
import '../../domain/list_builder.dart';
import '../../domain/question.dart';
import '../../domain/question_list.dart';

/// Fontes do PDF: as mesmas do app, embutidas (acentos e símbolos offline).
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static Future<PdfFonts> load() async {
    final regular = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    return PdfFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }
}

/// PDF pronto para entregar: os bytes e o número de páginas.
typedef GeneratedPdf = ({Uint8List bytes, int pages});

/// Linhas para a resposta de cada discursiva.
const int answerLines = 7;

/// Gera o PDF da lista na hora, no próprio aparelho: nada vai para o servidor.
///
/// Limpo e pronto para imprimir: nome da lista, numeração, espaço para
/// resposta nas discursivas e **nenhum gabarito**.
Future<GeneratedPdf> buildListPdf({
  required QuestionList list,
  required List<Question> questions,
  required PdfFonts fonts,
  required DateTime generatedAt,
  Map<String, Uint8List> images = const {},
}) async {
  try {
    return await _build(list, questions, fonts, generatedAt, images, true);
  } on PdfException {
    // Alguma questão não coube inteira numa página: refaz deixando quebrar.
    return _build(list, questions, fonts, generatedAt, images, false);
  }
}

Future<GeneratedPdf> _build(
  QuestionList list,
  List<Question> questions,
  PdfFonts fonts,
  DateTime generatedAt,
  Map<String, Uint8List> images,
  bool keepTogether,
) async {
  final doc = pw.Document(
    title: list.name,
    author: AppInfo.name,
    creator: '${AppInfo.name} ${AppInfo.versionLabel}',
    subject: describeComposition(questions),
  );
  final muted = PdfColors.grey700;
  final small = pw.TextStyle(fontSize: 8.5, color: muted);
  final body = const pw.TextStyle(fontSize: 11, lineSpacing: 2.5);
  final date = DateFormat('dd/MM/yyyy', 'pt_BR').format(generatedAt);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(54, 46, 54, 46),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      ),
      maxPages: 200,
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(list.name, style: small),
            ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Gerado pelo ${AppInfo.name} (${AppInfo.versionLabel}) em $date',
              style: small,
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: small,
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Text(
          list.name,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          describeComposition(questions),
          style: pw.TextStyle(fontSize: 10, color: muted),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Nome: ____________________________________',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.Text(
              'Data: ____/____/______',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey400, thickness: 0.8),
        pw.SizedBox(height: 6),
        for (var i = 0; i < questions.length; i++)
          ..._questionBlock(
            keepTogether: keepTogether,
            number: i + 1,
            question: questions[i],
            image: images[questions[i].id],
            body: body,
            small: small,
          ),
      ],
    ),
  );

  final bytes = await doc.save();
  return (bytes: bytes, pages: doc.document.pdfPageList.pages.length);
}

List<pw.Widget> _questionBlock({
  required bool keepTogether,
  required int number,
  required Question question,
  required Uint8List? image,
  required pw.TextStyle body,
  required pw.TextStyle small,
}) {
  const indent = pw.EdgeInsets.only(left: 18);
  final category = [
    question.subject,
    if (question.topic.trim().isNotEmpty) question.topic.trim(),
    'origem: ${question.platform}',
  ].join(' · ');
  final block = <pw.Widget>[
    // Número e enunciado num RichText que pode continuar na página seguinte
    // (só divide com `TextOverflow.span`; sem isso, texto longo quebra o PDF).
    pw.RichText(
      overflow: pw.TextOverflow.span,
      text: pw.TextSpan(
        style: body,
        children: [
          pw.TextSpan(
            text: '$number.  ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: question.statement.trim().isEmpty
                ? '(questão em imagem)'
                : question.statement.trim(),
          ),
        ],
      ),
    ),
    if (image != null)
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(18, 8, 0, 0),
        child: pw.Container(
          alignment: pw.Alignment.centerLeft,
          constraints: const pw.BoxConstraints(maxHeight: 240),
          child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
        ),
      ),
    if (question.isObjective)
      for (var i = 0; i < question.alternatives.length; i++)
        pw.Padding(
          padding: indent.copyWith(top: 5),
          child: pw.RichText(
            text: pw.TextSpan(
              style: body,
              children: [
                pw.TextSpan(
                  text: '(${Question.letters[i]})  ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: question.alternatives[i]),
              ],
            ),
          ),
        )
    else
      pw.Padding(
        padding: indent.copyWith(top: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Resposta:', style: small),
            for (var line = 0; line < answerLines; line++)
              pw.Container(
                height: 22,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    pw.Padding(
      padding: indent.copyWith(top: 6),
      child: pw.Text(category, style: small),
    ),
    pw.SizedBox(height: 16),
  ];
  // Questão inteira na mesma página quando cabe (não separa as alternativas
  // do enunciado). As muito longas ficam livres para continuar na próxima.
  final size =
      question.statement.length +
      question.alternatives.fold<int>(0, (sum, a) => sum + a.length);
  if (!keepTogether || size > (image == null ? 1400 : 900)) return block;
  return [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: block,
      ),
    ),
  ];
}
