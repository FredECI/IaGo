import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/app/app.dart';
import 'package:iago/app/router.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/community/community_access.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_bank_catalog.dart';
import '../../helpers/test_app.dart';

/// QA de AV2 com o repositório REAL da demo (memória + dados simulados),
/// sem repositório falso, a 360 px.
void main() {
  setUpAll(initTestLocale);

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IagoApp)));

  Future<void> openBank(WidgetTester tester, {bool member = true}) async {
    await pumpIagoApp(
      tester,
      overrides: [
        bankCatalogProvider.overrideWithValue(FakeBankCatalog()),
        isMemberProvider.overrideWithValue(member),
      ],
    );
    await enterDemo(tester);
    containerOf(tester).read(routerProvider).go('/questoes/acervo/enem-2022-3');
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('rating-panel')));
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tapVisible(tester, find.byKey(Key(key)));

  String panelText(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('rating-panel')),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .join(' | ');

  testWidgets('CA-A1/A7 demo real: avaliar, alterar e remover mantém uma só', (
    tester,
  ) async {
    await openBank(tester);
    // Demo: resumo simulado com selo.
    expect(find.text('Dados simulados'), findsOneWidget);

    await tapKey(tester, 'rate-difficulty-1');
    await tapKey(tester, 'rate-quality-1');
    await tapKey(tester, 'rate-submit');
    expect(find.text('Alterar avaliação'), findsOneWidget);
    expect(find.text('Sua avaliação (você já avaliou)'), findsOneWidget);

    // Alterar: continua uma avaliação por pessoa (botão volta a "alterar").
    await tapKey(tester, 'rate-difficulty-3');
    await tapKey(tester, 'rate-submit');
    expect(find.text('Alterar avaliação'), findsOneWidget);
    // Sem mudança, o botão fica desligado.
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('rate-submit')),
    );
    expect(submit.onPressed, isNull);

    // Sair e voltar mantém a avaliação.
    containerOf(tester).read(routerProvider).go(Routes.questions);
    await tester.pumpAndSettle();
    containerOf(tester).read(routerProvider).go('/questoes/acervo/enem-2022-3');
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('rate-remove')));
    await tapKey(tester, 'rate-remove');
    expect(find.text('Avaliar'), findsOneWidget);
    expect(find.byKey(const Key('rate-remove')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CA-A6: o painel não fala em alternativa correta nem acerto', (
    tester,
  ) async {
    await openBank(tester);
    final text = panelText(tester).toLowerCase();
    for (final bad in ['correta', 'acertei', 'gabarito', 'acerto', 'errei']) {
      expect(text.contains(bad), isFalse, reason: 'apareceu "$bad": $text');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('não membro: sem escalas e sem escrita, mas vê o resumo', (
    tester,
  ) async {
    await openBank(tester, member: false);
    expect(find.byKey(const Key('rate-members-only')), findsOneWidget);
    expect(find.byKey(const Key('rate-difficulty-2')), findsNothing);
    expect(find.byKey(const Key('rating-diff')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CA-A5: nota privada fica na questão própria e sobrevive à saída',
    (tester) async {
      await pumpIagoApp(tester);
      await enterDemo(tester);
      final c = containerOf(tester);
      final id = c.read(questionsProvider).value!.first.id;
      c.read(routerProvider).go(Routes.question(id));
      await tester.pumpAndSettle();
      await tapKey(tester, 'private-quality-1');
      expect(c.read(questionByIdProvider(id))!.myQuality, 1);

      c.read(routerProvider).go(Routes.questions);
      await tester.pumpAndSettle();
      c.read(routerProvider).go(Routes.question(id));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('private-quality-1')),
      );
      expect(chip.selected, isTrue);
      // Nenhum texto de "correta/acertei" na nota privada.
      final all = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('private-rating')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => (t.data ?? '').toLowerCase())
          .join(' ');
      expect(all.contains('correta'), isFalse);
      expect(all.contains('acertei'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
