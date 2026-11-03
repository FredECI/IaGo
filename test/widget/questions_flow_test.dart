import 'package:flutter_test/flutter_test.dart';
import 'package:iago/features/questions/question_card.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Texto de uma objetiva como o Pedro colaria na demo.
const String pastedQuestion =
    'Considere a função f(x) = 4x - 3. O valor de f(5) é:\n'
    'A) 12\nB) 15\nC) 17\nD) 20\nE) 23';

Future<void> openQuestionsTab(WidgetTester tester) async {
  await tester.tap(find.text('Questões').last);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search-field')), text);
  await tester.pumpAndSettle();
}

/// Rola até o primeiro cartão (a 360 px os filtros ocupam o topo) e toca.
Future<void> openFirstCard(WidgetTester tester) async {
  final card = find.byType(QuestionCard).first;
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Finder formScrollable() => find
    .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
    .first;

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: formScrollable());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocale);

  testWidgets('busca e filtros com contadores seguem o roteiro da demo', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await openQuestionsTab(tester);
    expect(find.text('40 questões'), findsOneWidget);

    await search(tester, 'função');
    expect(find.text('13 de 40 questões'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-area-mathematics')));
    await tester.pumpAndSettle();
    expect(find.text('11 de 40 questões'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-type-objective')));
    await tester.pumpAndSettle();
    expect(find.text('9 de 40 questões'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-filters')));
    await tester.pumpAndSettle();
    expect(find.text('40 questões'), findsOneWidget);
  });

  testWidgets('filtro por plataforma abre a folha com contadores', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await openQuestionsTab(tester);

    await tester.tap(find.byKey(const Key('filter-platform')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canal de vídeo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pronto'));
    await tester.pumpAndSettle();
    expect(find.text('6 de 40 questões'), findsOneWidget);
    expect(find.text('Plataforma · 1'), findsOneWidget);
  });

  testWidgets('tela "Por conteúdo" leva ao assunto já filtrado', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await openQuestionsTab(tester);

    await tester.tap(find.byKey(const Key('open-content-tree')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-area-mathematics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-topic-Funções')));
    await tester.pumpAndSettle();

    expect(find.text('11 de 40 questões'), findsOneWidget);
    expect(find.text('Assunto · 1'), findsOneWidget);
  });

  testWidgets('salva questão colada em segundos e ela entra na busca', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);

    await tester.tap(find.byKey(const Key('shortcut-save-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('field-statement')),
      pastedQuestion,
    );
    await tester.pumpAndSettle();

    // As alternativas foram separadas sozinhas.
    expect(
      find.text('5 alternativas separadas do texto colado.'),
      findsOneWidget,
    );
    final altE = tester.widget<TextFormField>(
      find.byKey(const Key('field-alt-4')),
    );
    expect(altE.controller!.text, '23');

    // Matemática preenche a matéria; "Funções" vem das sugestões.
    await scrollTo(tester, find.byKey(const Key('area-mathematics')));
    await tester.tap(find.byKey(const Key('area-mathematics')));
    await tester.pumpAndSettle();
    final topic = find.byKey(const Key('topic-suggestion-Funções'));
    await scrollTo(tester, topic);
    await tester.tap(topic);
    await tester.pumpAndSettle();
    final platform = find.byKey(
      const Key('platform-suggestion-Site de questões'),
    );
    await scrollTo(tester, platform);
    await tester.tap(platform);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-question-top')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Questão salva em'), findsOneWidget);
    expect(find.textContaining('meta: menos de 30 s'), findsOneWidget);

    await openQuestionsTab(tester);
    expect(find.text('41 questões'), findsOneWidget);
    await search(tester, 'função');
    await tester.tap(find.byKey(const Key('filter-area-mathematics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-type-objective')));
    await tester.pumpAndSettle();
    expect(find.text('10 de 41 questões'), findsOneWidget);
  });

  testWidgets('desfazer a separação devolve o texto colado', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tester.tap(find.byKey(const Key('shortcut-save-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('field-statement')),
      pastedQuestion,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('split-notice')), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    final statement = tester.widget<TextFormField>(
      find.byKey(const Key('field-statement')),
    );
    expect(statement.controller!.text, pastedQuestion);
    expect(find.byKey(const Key('split-notice')), findsNothing);
    // O botão manual continua disponível.
    expect(find.byKey(const Key('split-alternatives')), findsOneWidget);
  });

  testWidgets('formulário aponta os campos obrigatórios', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tester.tap(find.byKey(const Key('shortcut-save-question')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-question-top')));
    await tester.pumpAndSettle();
    expect(find.text('Confira os campos destacados.'), findsOneWidget);
    expect(
      find.text('Cole ou digite o enunciado (ou anexe um print).'),
      findsOneWidget,
    );
    expect(find.text('41 questões'), findsNothing);
  });

  testWidgets('edita uma questão pelo detalhe', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await openQuestionsTab(tester);
    await search(tester, 'escada');

    await openFirstCard(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Uma escada de 5 m'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('field-statement')),
      'Uma escada de 10 m está apoiada em um muro.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-question-top')));
    await tester.pumpAndSettle();

    expect(find.text('Alterações salvas.'), findsOneWidget);
    expect(
      find.text('Uma escada de 10 m está apoiada em um muro.'),
      findsOneWidget,
    );
    expect(find.textContaining('Editada em'), findsOneWidget);
  });

  testWidgets('exclui questão e ela sai também das listas', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await openQuestionsTab(tester);
    await search(tester, 'escada');

    await openFirstCard(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-question')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Questão excluída.'), findsOneWidget);
    expect(find.text('0 de 39 questões'), findsOneWidget);

    // A lista de reforço tinha 6 questões; agora tem 5.
    await tester.tap(find.text('Listas').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('5 questões'), findsOneWidget);
  });
}
