import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/firebase/firebase_auth_repository.dart';
import 'package:iago/data/firebase/firestore_direction_repository.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_progress.dart';
import 'package:iago/features/direction/direction_providers.dart';

final now = DateTime(2026, 11, 30, 12);

StudyGoal goal() => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: 8,
  createdAt: now,
  updatedAt: now,
);

StudyStep step(String id, DateTime due, {StepStatus? status}) => StudyStep(
  id: id,
  action: StepAction.collect,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: due,
  status: status ?? StepStatus.accepted,
  source: StepSource.rules,
  rationale: 'x',
  createdAt: now,
);

Future<void> settle(ProviderContainer c) async {
  c.listen(studyStepsProvider, (_, _) {});
  c.listen(studyGoalProvider, (_, _) {});
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer demoContainer() {
  final c = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(c.dispose);
  c.read(sessionProvider.notifier).enterDemo();
  return c;
}

Map<String, Object?> validStep() => {
  'action': 'collect',
  'area': 'mathematics',
  'subject': 'Matemática',
  'targetCount': 5,
  'dueAt': now,
  'status': 'accepted',
  'source': 'rules',
  'rationale': 'r',
  'createdAt': now,
};

Map<String, Object?> validGoal() => {
  'exam': 'enem',
  'weeklyHours': 5,
  'createdAt': now,
  'updatedAt': now,
};

void main() {
  group('exclusão de conta (CA-T7)', () {
    test('userCollections inclui as subcoleções novas, com direction/goal', () {
      expect(
        FirebaseAuthRepository.userCollections,
        containsAll(['direction', 'directionSteps']),
      );
      // Mantém as antigas.
      expect(
        FirebaseAuthRepository.userCollections,
        containsAll(['questions', 'questionImages', 'lists', 'events']),
      );
    });
  });

  group('mapeamento do Firestore: documentos inválidos viram null', () {
    test('etapa válida base é aceita (controle)', () {
      expect(stepFromMap('a', validStep()), isNotNull);
    });

    for (final key in [
      'action',
      'area',
      'status',
      'source',
      'subject',
      'targetCount',
      'dueAt',
      'createdAt',
    ]) {
      test('etapa sem "$key" vira null', () {
        expect(stepFromMap('a', {...validStep()}..remove(key)), isNull);
      });
    }

    test('etapa com enum desconhecido vira null', () {
      expect(stepFromMap('a', {...validStep(), 'status': 'pausada'}), isNull);
      expect(stepFromMap('a', {...validStep(), 'source': 'robo'}), isNull);
      expect(stepFromMap('a', {...validStep(), 'area': 'astrologia'}), isNull);
    });

    test('regressão: etapa com "area" de tipo errado não pode lançar', () {
      expect(stepFromMap('a', {...validStep(), 'area': 7}), isNull);
    });

    test(
      'regressão: etapa com "postponedAt" de tipo errado não pode lançar',
      () {
        expect(
          stepFromMap('a', {...validStep(), 'postponedAt': 'ontem'}),
          anyOf(isNull, isA<StudyStep>()),
        );
      },
    );

    test('regressão: etapa com "doneAt" de tipo errado não pode lançar', () {
      expect(
        stepFromMap('a', {...validStep(), 'doneAt': 123}),
        anyOf(isNull, isA<StudyStep>()),
      );
    });

    test('regressão: etapa com "rationale" de tipo errado não pode lançar', () {
      expect(
        stepFromMap('a', {...validStep(), 'rationale': 5}),
        anyOf(isNull, isA<StudyStep>()),
      );
    });

    test('etapa com tipo errado em subject, targetCount e dueAt vira null', () {
      expect(stepFromMap('a', {...validStep(), 'subject': 3}), isNull);
      expect(stepFromMap('a', {...validStep(), 'targetCount': '5'}), isNull);
      expect(stepFromMap('a', {...validStep(), 'dueAt': 'amanhã'}), isNull);
    });

    test('etapa com null em campo obrigatório vira null', () {
      expect(stepFromMap('a', {...validStep(), 'dueAt': null}), isNull);
      expect(stepFromMap('a', {...validStep(), 'action': null}), isNull);
    });

    test('etapa sem rationale usa texto vazio', () {
      final m = {...validStep()}..remove('rationale');
      expect(stepFromMap('a', m)!.rationale, '');
    });

    test('objetivo válido base é aceito (controle)', () {
      expect(goalFromMap(validGoal()), isNotNull);
    });

    test('objetivo sem exam, horas ou datas vira null', () {
      for (final key in ['exam', 'weeklyHours', 'createdAt', 'updatedAt']) {
        expect(goalFromMap({...validGoal()}..remove(key)), isNull, reason: key);
      }
    });

    test(
      'objetivo com exam desconhecido ou horas com tipo errado vira null',
      () {
        expect(goalFromMap({...validGoal(), 'exam': 'xyz'}), isNull);
        expect(goalFromMap({...validGoal(), 'weeklyHours': '5'}), isNull);
        expect(goalFromMap({...validGoal(), 'weeklyHours': 5.5}), isNull);
      },
    );

    test('objetivo ignora áreas desconhecidas na lista', () {
      final g = goalFromMap({
        ...validGoal(),
        'focusAreas': ['mathematics', 'astrologia'],
      })!;
      expect(g.focusAreas, [Area.mathematics]);
    });

    test('objetivo com focusAreas que não é lista usa lista vazia', () {
      final g = goalFromMap({...validGoal(), 'focusAreas': 'mathematics'})!;
      expect(g.focusAreas, isEmpty);
    });

    test('regressão: objetivo com elemento não-texto em focusAreas não pode lançar', () {
      expect(
        goalFromMap({
          ...validGoal(),
          'focusAreas': [1, 'mathematics'],
        }),
        anyOf(isNull, isA<StudyGoal>()),
      );
    });

    test('regressão: objetivo com "exam" de tipo errado não pode lançar', () {
      expect(goalFromMap({...validGoal(), 'exam': 3}), isNull);
    });

    test(
      'regressão: objetivo com "targetDate" de tipo errado não pode lançar',
      () {
        expect(
          goalFromMap({...validGoal(), 'targetDate': 'amanhã'}),
          anyOf(isNull, isA<StudyGoal>()),
        );
      },
    );

    test('objetivo ida e volta preserva a data-alvo e o lastAiAt', () {
      final g = StudyGoal(
        exam: ExamTarget.vestibular,
        targetDate: DateTime(2027, 1, 10),
        weeklyHours: 40,
        lastAiAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final back = goalFromMap(goalToMap(g))!;
      expect(back.targetDate, DateTime(2027, 1, 10));
      expect(back.lastAiAt, now);
      expect(back.weeklyHours, 40);
    });

    test('regressão: etapa com targetCount negativo ou zero é aceita', () {
      // O planejador limita a 1..30 (DirectionLimits); um documento
      // adulterado com 0 ou -5 não deveria virar etapa.
      expect(stepFromMap('a', {...validStep(), 'targetCount': -5}), isNull);
      expect(stepFromMap('a', {...validStep(), 'targetCount': 0}), isNull);
    });
  });

  group('MemoryDirectionRepository nos limites', () {
    test('addSteps com mesmo id substitui, não duplica', () async {
      final repo = MemoryDirectionRepository();
      await repo.addSteps([step('a', DateTime(2026, 12, 2))]);
      await repo.addSteps([step('a', DateTime(2026, 12, 9))]);
      expect(repo.currentSteps, hasLength(1));
      expect(repo.currentSteps.single.dueAt, DateTime(2026, 12, 9));
      await repo.dispose();
    });

    test('addSteps vazio não emite nem muda nada', () async {
      final repo = MemoryDirectionRepository();
      await repo.addSteps(const []);
      expect(repo.currentSteps, isEmpty);
      await repo.dispose();
    });

    test('lista exposta é imutável', () async {
      final repo = MemoryDirectionRepository(
        steps: [step('a', DateTime(2026, 12, 2))],
      );
      expect(
        () => repo.currentSteps.add(step('b', now)),
        throwsUnsupportedError,
      );
      await repo.dispose();
    });

    test('etapas com o mesmo prazo mantêm todas', () async {
      final repo = MemoryDirectionRepository();
      final due = DateTime(2026, 12, 2);
      await repo.addSteps([step('a', due), step('b', due), step('c', due)]);
      expect(repo.currentSteps, hasLength(3));
      await repo.dispose();
    });

    test('adiar reordena pela nova data', () async {
      final repo = MemoryDirectionRepository(
        steps: [
          step('a', DateTime(2026, 12, 1, 23, 59, 59, 999)),
          step('b', DateTime(2026, 12, 3, 23, 59, 59, 999)),
        ],
      );
      await repo.updateStep(postponeStep(repo.currentSteps.first, now)!);
      expect([for (final s in repo.currentSteps) s.id], ['a', 'b']);
      await repo.updateStep(
        postponeStep(repo.currentSteps.last, now.add(const Duration(days: 4)))!,
      );
      expect([
        for (final s in repo.currentSteps) s.id,
      ], unorderedEquals(['a', 'b']));
      await repo.dispose();
    });

    test('novo ouvinte recebe o estado atual na hora', () async {
      final repo = MemoryDirectionRepository(
        steps: [step('a', DateTime(2026, 12, 2))],
      );
      await repo.saveGoal(goal());
      expect(await repo.watchSteps().first, hasLength(1));
      expect(await repo.watchGoal().first, isNotNull);
      await repo.dispose();
    });
  });

  group('ações (provider) nos limites', () {
    test(
      'regressão: completar etapa que já não existe não pode lançar na tela',
      () async {
        // Ex.: etapa removida/substituída entre o toque e a gravação. O
        // repositório em memória lança StateError; a UI (DI3/DI4) chama
        // `complete` sem try/catch. O Firestore, ao contrário, recriaria o
        // documento (set). Comportamento inconsistente entre as implementações.
        final c = demoContainer();
        final actions = c.read(directionActionsProvider);
        final ghost = step('fantasma', now.add(const Duration(days: 1)));
        await expectLater(actions.complete(ghost), completes);
      },
    );

    test('regressão: adiar etapa que já não existe não pode lançar', () async {
      final c = demoContainer();
      final actions = c.read(directionActionsProvider);
      final ghost = step('fantasma', now.add(const Duration(days: 1)));
      await expectLater(actions.postpone(ghost), completes);
    });

    test(
      'duas propostas seguidas não duplicam: no máximo 3 pendentes',
      () async {
        final repo = MemoryDirectionRepository();
        final c = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            directionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        final actions = c.read(directionActionsProvider);
        final first = await actions.proposeWithRules(goal());
        final second = await actions.proposeWithRules(goal());
        expect(repo.currentSteps.where(isPending), hasLength(3));
        expect(
          [for (final s in second) s.id],
          [for (final s in first) s.id],
          reason: 'devolve as pendentes que já existem',
        );
      },
    );

    test(
      'proposeWithRules marca vencidas como perdidas e não as apaga',
      () async {
        final repo = MemoryDirectionRepository(
          steps: [
            step('vencida', now.subtract(const Duration(days: 2))),
            step('em-dia', now.add(const Duration(days: 2))),
          ],
        );
        final c = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            directionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        await c.read(directionActionsProvider).proposeWithRules(goal());
        final byId = {for (final s in repo.currentSteps) s.id: s};
        expect(byId['vencida']!.status, StepStatus.missed);
        expect(byId['em-dia']!.status, StepStatus.accepted);
      },
    );

    test('proposta nunca gera prazo no passado nem além de 14 dias', () async {
      final repo = MemoryDirectionRepository();
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          directionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      final created = await c
          .read(directionActionsProvider)
          .proposeWithRules(goal());
      for (final s in created) {
        expect(s.dueAt.isAfter(now), isTrue);
        expect(s.dueAt.isBefore(now.add(const Duration(days: 15))), isTrue);
      }
    });

    test(
      'setGoal com só etapas vencidas marca como perdidas e propõe novas',
      () async {
        final repo = MemoryDirectionRepository(
          steps: [step('vencida', now.subtract(const Duration(days: 2)))],
        );
        final c = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            directionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        // A vencida vira missed e entra uma proposta nova.
        await c.read(directionActionsProvider).setGoal(goal());
        final byId = {for (final s in repo.currentSteps) s.id: s};
        expect(byId['vencida']!.status, StepStatus.missed);
        expect(repo.currentSteps.where(isPending), hasLength(3));
      },
    );
  });

  group('demo: estado limpo a cada entrada', () {
    test('concluir na 1ª sessão não vaza para a 2ª DemoSession', () async {
      final c = demoContainer();
      final actions = c.read(directionActionsProvider);
      final repo1 = c.read(directionRepositoryProvider);
      final first = (await repo1.watchSteps().first).where(isPending).first;
      await actions.complete(first);
      expect((await repo1.watchSteps().first).where(isPending), hasLength(2));

      c.read(sessionProvider.notifier).enterDemo();
      final repo2 = c.read(directionRepositoryProvider);
      expect(identical(repo1, repo2), isFalse);
      expect((await repo2.watchSteps().first).where(isPending), hasLength(3));
      expect((await repo2.watchGoal().first), isNotNull);
    });

    test('sair da demo devolve repositório vazio e sem objetivo', () async {
      final c = demoContainer();
      await c.read(sessionProvider.notifier).signOut();
      final repo = c.read(directionRepositoryProvider);
      expect(await repo.watchGoal().first, isNull);
      expect(await repo.watchSteps().first, isEmpty);
      expect(c.read(directionSimulatedProvider), isFalse);
    });

    test('demo: nextStepProvider é a pendente de prazo mais próximo', () async {
      final c = demoContainer();
      await settle(c);
      final next = c.read(nextStepProvider)!;
      final pending = c.read(pendingStepsProvider);
      expect(pending, hasLength(3));
      expect(next.id, pending.first.id);
      for (final s in pending) {
        expect(!next.dueAt.isAfter(s.dueAt), isTrue);
      }
    });

    test(
      'demo: a frase da comparação aparece com os números simulados',
      () async {
        final c = demoContainer();
        await settle(c);
        expect(
          c.read(stepProgressProvider).sentence,
          'Você cumpriu 3 de 4 etapas nos últimos 14 dias; nos 14 anteriores, '
          '1 de 3.',
        );
      },
    );

    test('concluir uma pendente em dia melhora o "N de M" recente', () async {
      final c = demoContainer();
      await settle(c);
      final before = c.read(stepProgressProvider);
      await c
          .read(directionActionsProvider)
          .complete(c.read(nextStepProvider)!);
      await settle(c);
      final after = c.read(stepProgressProvider);
      expect(after.doneRecent, before.doneRecent + 1);
      expect(after.totalRecent, before.totalRecent + 1);
    });

    test('contexto do Direciona na demo sai sem texto livre', () async {
      final c = demoContainer();
      await settle(c);
      await settle(c);
      final ctx = c.read(directionContextProvider);
      expect(ctx, isNotNull);
      for (final cov in ctx!.coverage) {
        expect(cov.area.subjects, contains(cov.subject));
      }
    });
  });
}
