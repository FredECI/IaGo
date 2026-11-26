import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/clock.dart';
import 'package:iago/data/bank_catalog.dart';
import 'package:iago/data/firebase/firestore_direction_repository.dart';
import 'package:iago/data/local/direction_memory_repository.dart';
import 'package:iago/data/local/memory_question_repository.dart';
import 'package:iago/data/metrics_repository.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/bank_source.dart';
import 'package:iago/domain/bank_summary.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/metric_event.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_filter.dart';
import 'package:iago/features/bank/bank_providers.dart';
import 'package:iago/features/direction/direction_providers.dart';
import 'package:iago/features/metrics/metrics_providers.dart';
import 'package:iago/features/questions/questions_providers.dart';

import '../helpers/fake_bank_catalog.dart';

/// BM8: Direciona com o acervo (resumo, `bankAvailable`, sugestão, interruptor,
/// timeouts) e `BankActions.createList(fromStepId)`.
final now = DateTime(2026, 11, 30, 12);

StudyGoal goal() => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: 8,
  focusAreas: const [Area.mathematics],
  createdAt: now,
  updatedAt: now,
);

/// Questões próprias de Matemática, salvas há 20 dias (sem lista exportada):
/// a etapa de Matemática vira "Montar lista".
List<Question> ownMath(int n) => [
  for (var i = 0; i < n; i++)
    Question(
      id: 'own-$i',
      statement: 'Questão $i',
      type: QuestionType.objective,
      area: Area.mathematics,
      subject: 'Matemática',
      platform: 'Apostila',
      createdAt: now.subtract(const Duration(days: 20)),
      updatedAt: now.subtract(const Duration(days: 20)),
    ),
];

/// Acervo falso que falha ou trava em chamadas escolhidas.
class _FlakyCatalog implements BankCatalog {
  _FlakyCatalog({this.failSummary = false, this.hangSearch = false});

  final bool failSummary;
  final bool hangSearch;
  final BankCatalog _inner = FakeBankCatalog(delay: Duration.zero);
  int searches = 0;

  @override
  Future<BankSummary> summary() =>
      failSummary ? Future.error(StateError('x')) : _inner.summary();

  @override
  Future<BankPage> search(
    QuestionFilter filter, {
    String? cursor,
    int limit = 50,
  }) {
    searches++;
    return hangSearch
        ? Completer<BankPage>().future
        : _inner.search(filter, cursor: cursor, limit: limit);
  }

  @override
  Future<QuestionFacets> facets(QuestionFilter filter) => _inner.facets(filter);

  @override
  Future<List<Question>> byIds(List<String> ids) => _inner.byIds(ids);

  @override
  Future<List<BankSource>> sources() => _inner.sources();
}

class Harness {
  Harness(this.container, this.repo, this.metrics);
  final ProviderContainer container;
  final MemoryDirectionRepository repo;
  final MemoryMetricsRepository metrics;

  DirectionActions get actions => container.read(directionActionsProvider);

  Future<List<StudyStep>> propose() => actions.proposeWithRules(goal());

  MetricEvent event(MetricEventType type) =>
      metrics.logged.firstWhere((e) => e.type == type);
}

Harness harness({
  BankCatalog? catalog,
  List<Question> questions = const [],
  Map<String, Object?>? runtime,
  List<StudyStep> steps = const [],
}) {
  final repo = MemoryDirectionRepository(goal: goal(), steps: steps);
  final metrics = MemoryMetricsRepository(clock: () => now);
  final container = ProviderContainer(
    overrides: <Override>[
      clockProvider.overrideWithValue(() => now),
      directionRepositoryProvider.overrideWithValue(repo),
      metricsRepositoryProvider.overrideWithValue(metrics),
      bankCatalogProvider.overrideWithValue(
        catalog ?? FakeBankCatalog(delay: Duration.zero),
      ),
      questionRepositoryProvider.overrideWithValue(
        MemoryQuestionRepository(clock: () => now, initial: questions),
      ),
      if (runtime != null)
        accessPolicyProvider.overrideWithValue(
          AccessPolicy.fromRuntime(runtime, termsMinAge: 18),
        ),
    ],
  );
  // As telas já ouvem as questões; sem ouvinte o stream fica pausado.
  container.listen(questionsProvider, (_, _) {});
  addTearDown(container.dispose);
  addTearDown(repo.dispose);
  return Harness(container, repo, metrics);
}

void main() {
  group('proposta com o acervo', () {
    test('Matemática vira "Montar lista" com ids do acervo e faixa', () async {
      final h = harness(questions: ownMath(12));
      final steps = await h.propose();

      final math = steps.firstWhere((s) => s.subject == 'Matemática');
      expect(math.action, StepAction.buildList);
      expect(math.bankAvailableAtProposal, 50);
      expect(math.bankIds, isNotEmpty);
      expect(math.bankIds.length, lessThanOrEqualTo(math.targetCount));
      expect(math.bankIds.toSet(), hasLength(math.bankIds.length));
      for (final id in math.bankIds) {
        expect(id, matches(bankIdFormat));
      }
      // O acervo falso não tem faixa de dificuldade: nada de faixa-alvo.
      expect(math.difficultyTarget, isNull);
      expect(math.rationale, isNot(isEmpty));

      final plan = h.event(MetricEventType.directionPlanCreated);
      expect(plan.data['bankSuggestedSteps'], 1);
      expect(plan.data['catalogGeneratedAt'], isA<String>());
    });

    test('etapa "Reunir" não leva ids, só o bankAvailable', () async {
      final h = harness(); // conta nova: tudo é "collect"
      final steps = await h.propose();
      expect(steps, isNotEmpty);
      for (final s in steps) {
        expect(s.action, StepAction.collect);
        expect(s.bankIds, isEmpty);
      }
      final math = steps.firstWhere((s) => s.subject == 'Matemática');
      expect(math.bankAvailableAtProposal, 50);
    });

    test('cópias já salvas saem do bankAvailable e das sugestões', () async {
      final copies = [
        for (var i = 0; i < 5; i++)
          Question(
            id: 'bank_enem-2022-$i',
            statement: 'x',
            type: QuestionType.objective,
            area: Area.mathematics,
            subject: 'Matemática',
            platform: 'ENEM 2022',
            createdAt: now.subtract(const Duration(days: 20)),
            updatedAt: now.subtract(const Duration(days: 20)),
            origin: QuestionOrigin.bank,
            bankId: 'enem-2022-$i',
          ),
      ];
      final h = harness(questions: [...ownMath(12), ...copies]);
      final math = (await h.propose()).firstWhere(
        (s) => s.subject == 'Matemática',
      );
      expect(math.bankAvailableAtProposal, 45);
      for (final c in copies) {
        expect(math.bankIds, isNot(contains(c.bankId)));
      }
    });
  });

  group('o acervo nunca derruba a proposta (CA-BM13)', () {
    test('directionBankEnabled=false: Direciona do MVP', () async {
      final h = harness(
        questions: ownMath(12),
        runtime: {'directionBankEnabled': false},
      );
      final steps = await h.propose();
      expect(steps, hasLength(3));
      for (final s in steps) {
        expect(s.bankIds, isEmpty);
        expect(s.bankAvailableAtProposal ?? 0, 0);
      }
      final plan = h.event(MetricEventType.directionPlanCreated);
      expect(plan.data.containsKey('bankSuggestedSteps'), isFalse);
    });

    test('resumo indisponível: etapas sem sugestão e sem erro', () async {
      final h = harness(
        questions: ownMath(12),
        catalog: _FlakyCatalog(failSummary: true),
      );
      final steps = await h.propose();
      expect(steps, hasLength(3));
      expect(steps.every((s) => s.bankIds.isEmpty), isTrue);
      expect(steps.every((s) => (s.bankAvailableAtProposal ?? 0) == 0), isTrue);
    });

    test('parte da área trava: etapas saem sem ids, no tempo', () async {
      final h = harness(
        questions: ownMath(12),
        catalog: _FlakyCatalog(hangSearch: true),
      );
      final watch = Stopwatch()..start();
      final steps = await h.propose();
      watch.stop();
      expect(steps, hasLength(3));
      expect(steps.every((s) => s.bankIds.isEmpty), isTrue);
      // O bankAvailable sai do índice e continua anotado.
      expect(
        steps
            .firstWhere((s) => s.subject == 'Matemática')
            .bankAvailableAtProposal,
        50,
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('BankActions.createList(fromStepId)', () {
    test('grava bankListId na etapa e registra o evento', () async {
      final h = harness(questions: ownMath(12));
      final steps = await h.propose();
      final math = steps.firstWhere((s) => s.subject == 'Matemática');
      final found = await h.container
          .read(bankCatalogProvider)
          .byIds(math.bankIds);
      expect(found, hasLength(math.bankIds.length));

      final list = await h.container
          .read(bankActionsProvider)
          .createList(
            name: 'Direciona: Matemática até 02/12',
            questions: found,
            fromStepId: math.id,
          );

      final stored = (await h.repo.watchSteps().first).firstWhere(
        (s) => s.id == math.id,
      );
      expect(stored.bankListId, list.id);
      expect(stored.bankIds, math.bankIds, reason: 'preservados');
      final created = h.event(MetricEventType.directionBankListCreated);
      expect(created.data['stepId'], math.id);
      expect(created.data['questionCount'], found.length);
      expect(created.data.values.whereType<String>().toList(), [math.id]);
      expect(list.length, found.length);
    });

    test('sem fromStepId nada é gravado na etapa', () async {
      final h = harness(questions: ownMath(12));
      final steps = await h.propose();
      final math = steps.firstWhere((s) => s.subject == 'Matemática');
      final found = await h.container
          .read(bankCatalogProvider)
          .byIds(math.bankIds);
      await h.container
          .read(bankActionsProvider)
          .createList(name: 'x', questions: found);
      final stored = (await h.repo.watchSteps().first).firstWhere(
        (s) => s.id == math.id,
      );
      expect(stored.bankListId, isNull);
      expect(
        h.metrics.logged.where(
          (e) => e.type == MetricEventType.directionBankListCreated,
        ),
        isEmpty,
      );
    });
  });

  group('etapas simuladas da demo', () {
    test(
      'attachBankToPendingSteps anexa sem mudar matéria nem prazo',
      () async {
        final base = StudyStep(
          id: 'demo-pending-0',
          action: StepAction.buildList,
          area: Area.mathematics,
          subject: 'Matemática',
          targetCount: 10,
          dueAt: now.add(const Duration(days: 3)),
          source: StepSource.rules,
          rationale: 'x',
          createdAt: now,
        );
        final h = harness(questions: ownMath(12), steps: [base]);
        await h.actions.attachBankToPendingSteps();
        final stored = (await h.repo.watchSteps().first).single;
        expect(stored.subject, 'Matemática');
        expect(stored.dueAt, base.dueAt);
        expect(stored.bankAvailableAtProposal, 50);
        expect(stored.bankIds, isNotEmpty);
        // Idempotente: uma 2ª chamada não muda nada.
        await h.actions.attachBankToPendingSteps();
        final again = (await h.repo.watchSteps().first).single;
        expect(again.bankIds, stored.bankIds);
      },
    );
  });
}
