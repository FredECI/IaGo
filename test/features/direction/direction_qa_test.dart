import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/app/theme.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/local/direction_demo_data.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/direction/direction_pages.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

/// QA de DI4: falhas, toque duplo, prazo vencido e texto grande a 360 px.
class _NoWriteRepo extends MemoryDirectionRepository {
  _NoWriteRepo({super.goal});

  @override
  Future<void> updateSteps(List<StudyStep> steps) =>
      Future.error(StateError('sem rede'));
}

class _CountingRepo extends MemoryDirectionRepository {
  _CountingRepo({super.goal});

  int writes = 0;

  @override
  Future<void> updateSteps(List<StudyStep> steps) {
    writes++;
    return super.updateSteps(steps);
  }
}

Future<void> _pump(
  WidgetTester tester,
  MemoryDirectionRepository repo, {
  double textScale = 1,
  String initial = Routes.direction,
}) async {
  await initTestLocale();
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
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
        directionRepositoryProvider.overrideWith((ref) => repo),
        directionSimulatedProvider.overrideWithValue(false),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: const Locale('pt', 'BR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

StudyStep _overdue() => StudyStep(
  id: 'late',
  action: StepAction.practice,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: testNow.subtract(const Duration(days: 2)),
  source: StepSource.rules,
  rationale: 'Atrasada de propósito.',
  createdAt: testNow.subtract(const Duration(days: 9)),
);

StudyGoal get _goal => DirectionDemoData.build(testNow).goal;

void main() {
  testWidgets('CA-D5: falha ao gravar a proposta mostra mensagem, não erro', (
    tester,
  ) async {
    final repo = _NoWriteRepo(goal: _goal);
    await _pump(tester, repo);
    expect(find.byKey(const Key('direction-empty')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('direction-propose')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Não foi possível montar a proposta'),
      findsOneWidget,
    );
    // A tela continua útil: o botão volta e nenhuma tela de erro aparece.
    expect(find.byKey(const Key('direction-propose')), findsOneWidget);
    expect(find.byKey(const Key('direction-reload')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toque duplo em "Pedir nova proposta" grava uma vez só', (
    tester,
  ) async {
    final repo = _CountingRepo(goal: _goal);
    await _pump(tester, repo);
    await tester.runAsync(() async {
      final button = find.byKey(const Key('direction-propose'));
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.currentSteps.length, lessThanOrEqualTo(3));
  });

  testWidgets(
    'prazo vencido: avisa, sem "Aceitar prazo", e adiar sai do vencido',
    (tester) async {
      final repo = MemoryDirectionRepository(goal: _goal, steps: [_overdue()]);
      await _pump(tester, repo);
      expect(find.textContaining('Prazo vencido em'), findsOneWidget);
      expect(find.byKey(const Key('accept-late')), findsNothing);

      await tester.tap(find.byKey(const Key('postpone-late')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Prazo vencido'), findsNothing);
      expect(find.textContaining('(adiada)'), findsOneWidget);
      expect(find.byKey(const Key('postpone-late')), findsNothing);
    },
  );

  testWidgets('texto 2x a 360 px: Direciona e objetivo não estouram', (
    tester,
  ) async {
    final d = DirectionDemoData.build(testNow);
    final repo = MemoryDirectionRepository(goal: d.goal, steps: d.steps);
    await _pump(tester, repo, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pump(tester, repo, textScale: 2, initial: Routes.directionGoal);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'objetivo: sem horas, data e áreas ainda salva (campos opcionais)',
    (tester) async {
      final repo = MemoryDirectionRepository();
      await _pump(tester, repo, initial: Routes.directionGoal);
      await reveal(tester, find.byKey(const Key('goal-save')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('goal-save')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(repo.currentGoal, isNotNull);
      expect(repo.currentGoal!.targetDate, isNull);
      expect(repo.currentGoal!.focusAreas, isEmpty);
      expect(repo.currentSteps, isNotEmpty);
    },
  );
}
