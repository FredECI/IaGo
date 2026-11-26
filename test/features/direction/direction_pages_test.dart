import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/app/theme.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/local/direction_demo_data.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/direction/direction_pages.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

/// Repositório cujas escritas de etapa falham.
class _FailingRepo extends MemoryDirectionRepository {
  _FailingRepo({super.goal, super.steps});

  @override
  Future<void> updateStep(StudyStep step) => Future.error(StateError('x'));
}

Future<void> _pump(
  WidgetTester tester, {
  MemoryDirectionRepository? repo,
  bool simulated = false,
  List<Uri>? opened,
}) async {
  await initTestLocale();
  tester.view.physicalSize = const Size(360 * 3, 1500 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: Routes.direction,
    routes: [
      GoRoute(
        path: Routes.direction,
        builder: (_, _) => const DirectionPage(),
        routes: [
          GoRoute(path: 'objetivo', builder: (_, _) => const GoalPage()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        clockProvider.overrideWithValue(() => testNow),
        directionRepositoryProvider.overrideWith(
          (ref) => repo ?? MemoryDirectionRepository(),
        ),
        directionSimulatedProvider.overrideWithValue(simulated),
        if (opened != null)
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: const Locale('pt', 'BR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MemoryDirectionRepository _demoRepo({bool failing = false}) {
  final d = DirectionDemoData.build(testNow);
  return failing
      ? _FailingRepo(goal: d.goal, steps: d.steps)
      : MemoryDirectionRepository(goal: d.goal, steps: d.steps);
}

Finder get _stepCards => find.byWidgetPredicate(
  (w) => w.key is Key && w.key.toString().contains("'step-demo-pending-"),
);

void main() {
  testWidgets('sem objetivo: define e recebe 3 etapas pelas regras', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Defina seu objetivo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('direction-define-goal')));
    await tester.pumpAndSettle();
    expect(find.text('Objetivo de estudo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-exam-vestibular')));
    await tester.tap(find.byKey(const Key('goal-area-mathematics')));
    await tester.pump();
    // As leituras das regras usam fluxos reais: precisam de tempo real.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('goal-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('direction-goal-summary')), findsOneWidget);
    expect(find.textContaining('Vestibular'), findsOneWidget);
    expect(find.text('Proposta automática'), findsNWidgets(3));
    expect(find.text('Concluir'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('concluir atualiza a comparação (CA-D7)', (tester) async {
    await _pump(tester, repo: _demoRepo());
    expect(
      find.text(
        'Você cumpriu 3 de 4 etapas nos últimos 14 dias; nos 14 anteriores, '
        '1 de 3.',
      ),
      findsOneWidget,
    );
    expect(_stepCards, findsNWidgets(3));

    await tester.tap(find.byKey(const Key('complete-demo-pending-0')));
    await tester.pumpAndSettle();

    expect(_stepCards, findsNWidgets(2));
    expect(find.textContaining('4 de 5 etapas'), findsOneWidget);
    expect(find.textContaining('nos 14 anteriores, 1 de 3'), findsOneWidget);
  });

  testWidgets('adiar vale uma vez: depois a opção some (CA-D8)', (
    tester,
  ) async {
    await _pump(tester, repo: _demoRepo());
    final postpone = find.byKey(const Key('postpone-demo-pending-0'));
    expect(postpone, findsOneWidget);
    expect(find.textContaining('(adiada)'), findsNothing);

    await tester.tap(postpone);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('postpone-demo-pending-0')), findsNothing);
    expect(find.textContaining('(adiada)'), findsOneWidget);
    // As outras etapas ainda podem ser adiadas.
    expect(find.byKey(const Key('postpone-demo-pending-1')), findsOneWidget);
  });

  testWidgets('demo mostra o aviso de proposta simulada (CA-D10)', (
    tester,
  ) async {
    await _pump(tester, repo: _demoRepo(), simulated: true);
    expect(find.text('Demonstração: proposta simulada'), findsOneWidget);
    expect(find.text('Proposta automática'), findsNWidgets(3));
  });

  testWidgets('adicionar à agenda abre a URL com título e data (CA-D9)', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pump(tester, repo: _demoRepo(), opened: opened);
    await tester.tap(find.byKey(const Key('calendar-demo-pending-0')));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.host, 'calendar.google.com');
    expect(opened.single.queryParameters['text'], startsWith('IaGo: '));
    expect(opened.single.queryParameters['dates'], matches(r'^\d{8}/\d{8}$'));
  });

  testWidgets('falha ao gravar mostra mensagem, não tela de erro', (
    tester,
  ) async {
    await _pump(tester, repo: _demoRepo(failing: true));
    await tester.tap(find.byKey(const Key('complete-demo-pending-0')));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível concluir a etapa. Tente de novo.'),
      findsOneWidget,
    );
    expect(_stepCards, findsNWidgets(3));
  });

  testWidgets('sem pendentes: estado vazio e "Pedir nova proposta"', (
    tester,
  ) async {
    final d = DirectionDemoData.build(testNow);
    final repo = MemoryDirectionRepository(
      goal: d.goal,
      steps: [
        for (final s in d.steps)
          if (!isPendingStatus(s)) s,
      ],
    );
    await _pump(tester, repo: repo);
    expect(find.byKey(const Key('direction-empty')), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('direction-propose')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('direction-empty')), findsNothing);
    expect(find.text('Proposta automática'), findsWidgets);
  });

  testWidgets('a 360 px a página das etapas não estoura', (tester) async {
    await _pump(tester, repo: _demoRepo());
    expect(tester.takeException(), isNull);
    expect(find.text('Adicionar à agenda'), findsWidgets);
  });
}

bool isPendingStatus(StudyStep s) =>
    s.status == StepStatus.proposed || s.status == StepStatus.accepted;
