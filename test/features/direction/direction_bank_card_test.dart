import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iago/app/router.dart';
import 'package:iago/app/theme.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/direction/direction_pages.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/domain/question_list.dart';
import 'package:iago/features/lists/lists_providers.dart';
import 'package:iago/features/questions/questions_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/fake_bank_catalog.dart';
import '../../helpers/test_app.dart';

/// BM9: botões do card, linha "Sugestão do acervo" e o interruptor, a 360 px.
StudyStep step(
  String id,
  StepAction action, {
  String subject = 'Matemática',
  Area area = Area.mathematics,
  List<String> ids = const [],
  int? band,
  int? available,
  String? listId,
}) => StudyStep(
  id: id,
  action: action,
  area: area,
  subject: subject,
  targetCount: 10,
  dueAt: DateTime(2026, 11, 12, 23, 59),
  source: StepSource.rules,
  rationale: 'Motivo da etapa.',
  createdAt: testNow,
  bankIds: ids,
  difficultyTarget: band,
  bankAvailableAtProposal: available,
  bankListId: listId,
);

late GoRouter router;
late ProviderContainer container;

Future<MemoryDirectionRepository> pumpCard(
  WidgetTester tester,
  List<StudyStep> steps, {
  bool bankEnabled = true,
  List<QuestionList> lists = const [],
}) async {
  await initTestLocale();
  tester.view.physicalSize = const Size(360 * 3, 1500 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = MemoryDirectionRepository(
    goal: StudyGoal(
      exam: ExamTarget.enem,
      weeklyHours: 8,
      createdAt: testNow,
      updatedAt: testNow,
    ),
    steps: steps,
  );
  router = GoRouter(
    initialLocation: Routes.direction,
    routes: [
      GoRoute(path: Routes.direction, builder: (_, _) => const DirectionPage()),
      GoRoute(
        path: Routes.bank,
        builder: (_, _) => const Scaffold(body: Text('TELA ACERVO')),
      ),
      GoRoute(
        path: Routes.questions,
        builder: (_, _) => const Scaffold(body: Text('TELA MINHAS')),
      ),
      GoRoute(
        path: '${Routes.lists}/:id',
        builder: (_, state) =>
            Scaffold(body: Text('TELA LISTA ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final app = ProviderScope(
    overrides: <Override>[
      clockProvider.overrideWithValue(() => testNow),
      bankCatalogProvider.overrideWithValue(
        FakeBankCatalog(delay: Duration.zero),
      ),
      directionRepositoryProvider.overrideWithValue(repo),
      if (lists.isNotEmpty)
        listsProvider.overrideWith((ref) => Stream.value(lists)),
      if (!bankEnabled)
        accessPolicyProvider.overrideWithValue(
          AccessPolicy.fromRuntime({
            'directionBankEnabled': false,
          }, termsMinAge: 18),
        ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      locale: const Locale('pt', 'BR'),
    ),
  );
  await tester.pumpWidget(app);
  container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  await tester.pumpAndSettle();
  return repo;
}

String get location => router.state.uri.toString();

void main() {
  testWidgets(
    'Montar lista: linha da sugestão, cria a lista e vira Abrir lista',
    (tester) async {
      final repo = await pumpCard(tester, [
        step(
          's1',
          StepAction.buildList,
          ids: ['enem-2022-0', 'enem-2022-1', 'enem-2022-2'],
          band: 2,
          available: 50,
        ),
      ]);
      expect(
        find.text(
          'Sugestão do acervo: 3 questões de Matemática, dificuldade Média',
        ),
        findsOneWidget,
      );
      final build = find.byKey(const Key('bank-build-s1'));
      expect(find.text('Montar lista com 3 do acervo'), findsOneWidget);
      expect(tester.getSize(build).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(build).width, lessThanOrEqualTo(360));
      expect(find.byKey(const Key('bank-open-s1')), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(build);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      final stored = (await tester.runAsync(() => repo.watchSteps().first))!
          .single;
      expect(stored.bankListId, isNotNull);
      expect(location, Routes.list(stored.bankListId!));
      expect(find.textContaining('TELA LISTA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lista já montada: o botão é Abrir lista; excluída, volta a montar',
    (tester) async {
      final withLink = step(
        's1',
        StepAction.practice,
        ids: ['enem-2022-0'],
        available: 50,
        listId: 'L1',
      );
      await pumpCard(
        tester,
        [withLink],
        lists: [
          QuestionList(
            id: 'L1',
            name: 'x',
            questionIds: const ['bank_enem-2022-0'],
            createdAt: testNow,
            updatedAt: testNow,
          ),
        ],
      );
      // Sem band, a linha omite a dificuldade.
      expect(
        find.text('Sugestão do acervo: 1 questão de Matemática'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('bank-build-s1')), findsNothing);
      await tester.tap(find.byKey(const Key('bank-open-list-s1')));
      await tester.pumpAndSettle();
      expect(location, Routes.list('L1'));
    },
  );

  testWidgets('lista excluída: o botão volta a montar', (tester) async {
    await pumpCard(tester, [
      step(
        's1',
        StepAction.practice,
        ids: ['enem-2022-0'],
        available: 50,
        listId: 'L1',
      ),
    ]);
    expect(find.byKey(const Key('bank-open-list-s1')), findsNothing);
    expect(find.byKey(const Key('bank-build-s1')), findsOneWidget);
  });

  testWidgets('Escolher no acervo filtra por área e matéria', (tester) async {
    await pumpCard(tester, [step('s1', StepAction.collect, available: 50)]);
    expect(find.byKey(const Key('bank-build-s1')), findsNothing);
    await tester.tap(find.byKey(const Key('bank-choose-s1')));
    await tester.pumpAndSettle();
    expect(location, Routes.bank);
    final filter = container.read(bankFilterProvider);
    expect(filter.areas, {Area.mathematics});
    expect(filter.subjects, {'Matemática'});
    // CA-BM13a: o filtro de "Minhas questões" não muda.
    expect(container.read(questionFilterProvider).isEmpty, isTrue);
  });

  testWidgets('Revisar: Ver minhas questões filtra Minhas questões', (
    tester,
  ) async {
    await pumpCard(tester, [
      step(
        's1',
        StepAction.review,
        subject: 'Biologia',
        area: Area.naturalSciences,
      ),
    ]);
    await tester.tap(find.byKey(const Key('bank-mine-s1')));
    await tester.pumpAndSettle();
    expect(location, Routes.questions);
    final filter = container.read(questionFilterProvider);
    expect(filter.subjects, {'Biologia'});
    expect(container.read(bankFilterProvider).isEmpty, isTrue);
  });

  testWidgets('sem acervo na matéria, o card fica como no MVP', (tester) async {
    await pumpCard(tester, [
      step('s1', StepAction.collect, subject: 'Redação', area: Area.languages),
    ]);
    expect(find.byKey(const Key('bank-choose-s1')), findsNothing);
    expect(find.byKey(const Key('complete-s1')), findsOneWidget);
  });

  testWidgets('directionBankEnabled=false desliga botões e linha', (
    tester,
  ) async {
    await pumpCard(tester, [
      step(
        's1',
        StepAction.buildList,
        ids: ['enem-2022-0'],
        band: 1,
        available: 50,
      ),
      step('s2', StepAction.collect, available: 50),
      step('s3', StepAction.review),
    ], bankEnabled: false);
    expect(find.textContaining('Sugestão do acervo'), findsNothing);
    expect(find.byKey(const Key('bank-build-s1')), findsNothing);
    expect(find.byKey(const Key('bank-choose-s2')), findsNothing);
    expect(find.byKey(const Key('bank-mine-s3')), findsNothing);
    expect(find.byKey(const Key('complete-s1')), findsOneWidget);
  });

  testWidgets('ids que sumiram do acervo: mensagem e botão some', (
    tester,
  ) async {
    await pumpCard(tester, [
      step('s1', StepAction.buildList, ids: ['enem-2099-1'], available: 50),
    ]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('bank-build-s1')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      find.text('As questões sugeridas não estão mais no acervo.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bank-build-s1')), findsNothing);
  });
}
