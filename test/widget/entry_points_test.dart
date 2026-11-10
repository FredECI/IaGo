import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_bank_catalog.dart';
import '../helpers/test_app.dart';

/// Pontos de entrada das trilhas do MVP (F7), na demo: cada um abre a sua
/// página provisória e "Voltar" retorna.
void main() {
  setUpAll(initTestLocale);

  testWidgets('Painel: card do Direciona mostra a próxima etapa simulada', (
    tester,
  ) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await reveal(tester, find.byKey(const Key('direction-card')));
    expect(find.text('Próxima etapa (simulada)'), findsOneWidget);
    expect(find.text('Ver etapas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('direction-card')));
    await tester.pumpAndSettle();
    expect(find.text('Direciona'), findsWidgets);
    expect(find.text('Demonstração: proposta simulada'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Demonstração: proposta simulada'), findsNothing);
    expect(find.byKey(const Key('direction-card')), findsOneWidget);
  });

  testWidgets('Painel: card do Conecta abre na demo', (tester) async {
    await pumpIagoApp(tester);
    await enterDemo(tester);
    await tapVisible(tester, find.byKey(const Key('conecta-card')));
    expect(find.text('Conecta'), findsWidgets);
    expect(find.byKey(const Key('community-simulated')), findsOneWidget);
    expect(find.byKey(const Key('community-matematica')), findsOneWidget);
  });

  testWidgets('Questões: Acervo e Importar abrem as páginas', (tester) async {
    await pumpIagoApp(
      tester,
      overrides: [bankCatalogProvider.overrideWithValue(FakeBankCatalog())],
    );
    await enterDemo(tester);
    await tester.tap(find.text('Questões').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-bank')));
    await tester.pumpAndSettle();
    // Tela de verdade do acervo (A4), com o botão de voltar da barra.
    expect(find.byKey(const Key('bank-search-field')), findsOneWidget);
    expect(find.text('1.250 questões'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bank-search-field')), findsNothing);
    expect(find.text('40 questões'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-import')));
    await tester.pumpAndSettle();
    expect(find.text('Importar questões'), findsWidgets);
    expect(find.byKey(const Key('import-paste-field')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-paste-field')), findsNothing);
    expect(find.text('40 questões'), findsOneWidget);
  });

  testWidgets('Painel: sem etapas a tempo, avisa e oferece tentar de novo', (
    tester,
  ) async {
    final never = StreamController<List<StudyStep>>.broadcast();
    addTearDown(never.close);
    await pumpIagoApp(
      tester,
      overrides: [
        studyStepsProvider.overrideWith((ref) => never.stream),
        directionReadTimeoutProvider.overrideWithValue(
          const Duration(seconds: 30),
        ),
      ],
    );
    await enterDemo(tester);
    await reveal(tester, find.byKey(const Key('direction-card')));
    expect(find.text('Carregando suas etapas...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Carregando suas etapas...'), findsNothing);
    expect(find.text('Tentar de novo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('direction-retry')));
    await tester.pump();
    expect(find.text('Tentar de novo'), findsNothing);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
