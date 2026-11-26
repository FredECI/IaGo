import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_bank.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_planner.dart';
import 'package:iago/domain/direction_tuning.dart';
import 'package:iago/domain/question.dart';

Question bq(String id, {String topic = ''}) => Question(
  id: 'bank_$id',
  statement: 'Enunciado $id',
  type: QuestionType.objective,
  area: Area.mathematics,
  subject: 'Matemática',
  topic: topic,
  platform: 'ENEM',
  origin: QuestionOrigin.bank,
  bankId: id,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

GoalSummary goal([List<Area> focus = const []]) =>
    GoalSummary(exam: ExamTarget.enem, weeklyHours: 6, focusAreas: focus);

List<String> pick(
  List<Question> candidates, {
  Set<String> exclude = const {},
  int count = 5,
  String seed = 's1',
  int? band,
  int? Function(Question q)? diff,
  List<String> topics = const [],
}) => suggestBankQuestions(
  candidates: candidates,
  excludeBankIds: exclude,
  count: count,
  seed: seed,
  targetBand: band,
  difficultyOf: diff,
  topicOrder: topics,
);

void main() {
  group('targetDifficulty', () {
    test('faixas', () {
      expect(
        targetDifficulty(
          const DirectionHistory(doneLast14d: 1, missedLast14d: 2),
        ),
        1,
      );
      expect(targetDifficulty(const DirectionHistory(doneLast14d: 3)), 3);
      expect(targetDifficulty(const DirectionHistory()), 2);
      expect(
        targetDifficulty(
          const DirectionHistory(doneLast14d: 5, missedLast14d: 1),
        ),
        2,
      );
      expect(targetDifficulty(const DirectionHistory(doneLast14d: 2)), 2);
    });
  });

  test('fnv1a32: valores de referência', () {
    expect(fnv1a32(''), 0x811c9dc5);
    expect(fnv1a32('a'), 0xe40c292c);
    expect(fnv1a32('foobar'), 0xbf9cf968);
  });

  group('suggestBankQuestions', () {
    final pool = [
      for (var i = 0; i < 12; i++) bq('q$i', topic: i.isEven ? 'A' : 'B'),
    ];

    test(
      'determinístico (mesmo com outra ordem de entrada) e respeita count',
      () {
        final a = pick(pool);
        final b = pick(pool.reversed.toList());
        expect(a, b);
        expect(a, hasLength(5));
        expect(a.toSet(), hasLength(5));
      },
    );

    test('seed diferente muda a escolha', () {
      expect(
        pick(pool, seed: 's1', count: 4),
        isNot(pick(pool, seed: 's2', count: 4)),
      );
    });

    test('nunca devolve excluídas', () {
      final all = pick(pool, count: 12);
      final excluded = all.take(6).toSet();
      final r = pick(pool, exclude: excluded, count: 12);
      expect(r, hasLength(6));
      expect(r.toSet().intersection(excluded), isEmpty);
    });

    test('menos candidatas devolve todas; nenhuma ou count 0, vazio', () {
      expect(pick(pool.take(3).toList(), count: 10), hasLength(3));
      expect(pick(const [], count: 10), isEmpty);
      expect(pick(pool, count: 0), isEmpty);
    });

    test('rodízio de assuntos pela taxonomia, sem assunto por último', () {
      final mixed = [
        bq('a1', topic: 'A'),
        bq('a2', topic: 'A'),
        bq('a3', topic: 'A'),
        bq('b1', topic: 'B'),
        bq('b2', topic: 'B'),
        bq('n1'),
        bq('n2'),
      ];
      final r = pick(mixed, count: 6, topics: const ['A', 'B']);
      String topicOf(String id) =>
          mixed.firstWhere((q) => q.bankId == id).topic;
      expect(r.take(3).map(topicOf).toList(), ['A', 'B', '']);
      expect(r.skip(3).take(2).map(topicOf).toSet(), {'A', 'B'});
    });

    test('faixa-alvo: prefere a mais próxima; sem faixa vale distância 1', () {
      final qs = [bq('f1'), bq('f2'), bq('f3'), bq('sem')];
      final bands = {'bank_f1': 1, 'bank_f2': 2, 'bank_f3': 3};
      final r = pick(qs, count: 4, band: 3, diff: (q) => bands[q.id]);
      expect(r.first, 'f3');
      expect(r.last, 'f1');
      expect(r.sublist(1, 3).toSet(), {'f2', 'sem'});
    });

    test('sem alvo, a dificuldade é ignorada', () {
      final qs = [bq('f1'), bq('f3')];
      final a = pick(qs, count: 2, diff: (q) => q.id == 'bank_f1' ? 1 : 3);
      expect(a, pick(qs, count: 2));
    });
  });

  group('withBankAvailability', () {
    test('subtrai as cópias, mínimo 0, e acrescenta matérias só do acervo', () {
      final r = withBankAvailability(
        const [
          SubjectCoverage(
            area: Area.mathematics,
            subject: 'Matemática',
            saved: 2,
          ),
        ],
        available: (s) => {'Matemática': 10, 'História': 5}[s] ?? 0,
        savedBankCopies: {'Matemática': 12},
      );
      expect(r.firstWhere((c) => c.subject == 'Matemática').bankAvailable, 0);
      expect(r.firstWhere((c) => c.subject == 'História').bankAvailable, 5);
      expect(r.any((c) => c.subject == 'Redação'), isFalse);
    });
  });

  test('merge de cobertura usa o maior bankAvailable e toJson o inclui', () {
    final ctx = DirectionContext(
      today: DateTime(2026, 11, 26),
      goal: goal(),
      coverage: const [
        SubjectCoverage(
          area: Area.mathematics,
          subject: 'Matemática',
          saved: 1,
          bankAvailable: 7,
        ),
        SubjectCoverage(
          area: Area.mathematics,
          subject: 'Matemática',
          saved: 2,
          bankAvailable: 9,
        ),
      ],
    );
    final c = ctx.coverage.single;
    expect(c.saved, 3);
    expect(c.bankAvailable, 9);
    expect(c.toJson()['bankAvailable'], 9);
  });

  group('planDirection com o acervo', () {
    DirectionContext ctx(
      List<SubjectCoverage> cov, [
      List<Area> focus = const [],
    ]) => DirectionContext(
      today: DateTime(2026, 11, 26),
      goal: goal(focus),
      coverage: cov,
    );

    List<SubjectCoverage> fullBank() => [
      for (final a in Area.values)
        for (final s in a.subjects)
          SubjectCoverage(
            area: a,
            subject: s,
            bankAvailable: s == 'Redação' ? 0 : 100,
          ),
    ];

    test('CA-BM10: conta nova sem foco não recebe matéria sem material', () {
      final steps = planDirection(ctx(fullBank()));
      expect(steps, isNotEmpty);
      expect(steps.map((s) => s.subject), isNot(contains('Redação')));
      for (final s in steps) {
        expect(s.bankAvailableAtProposal, 100);
      }
    });

    test(
      'CA-BM10: sem o rebaixamento, Redação aparece (o bug que isto corrige)',
      () {
        final steps = planDirection(
          ctx(fullBank()),
          tuning: const PlannerTuning(deprioritizeEmptySubjects: false),
        );
        expect(steps.map((s) => s.subject), contains('Redação'));
      },
    );

    test('acervo vazio: ordem do MVP', () {
      final on = planDirection(ctx(const []));
      final off = planDirection(
        ctx(const []),
        tuning: const PlannerTuning(deprioritizeEmptySubjects: false),
      );
      expect(on.map((s) => s.subject), off.map((s) => s.subject));
    });

    test('área de foco continua na frente', () {
      final steps = planDirection(ctx(fullBank(), [Area.languages]));
      expect(steps.first.area, Area.languages);
    });

    test('motivo cita o acervo e cabe em 140 caracteres', () {
      final collect = planDirection(ctx(fullBank())).first;
      expect(collect.action, StepAction.collect);
      expect(collect.rationale, contains('o acervo tem 100 para escolher'));
      expect(collect.rationale.length, lessThanOrEqualTo(140));

      final practice = planDirection(
        ctx(
          const [
            SubjectCoverage(
              area: Area.mathematics,
              subject: 'Matemática',
              saved: 20,
              savedLast14d: 3,
              listsExportedLast14d: 1,
              bankAvailable: 40,
            ),
          ],
          [Area.mathematics],
        ),
      ).first;
      expect(practice.action, StepAction.practice);
      expect(practice.rationale, contains('acervo'));
      expect(practice.rationale.length, lessThanOrEqualTo(140));
    });

    test('sem bankAvailable o motivo é o do MVP', () {
      final s = planDirection(
        ctx(
          const [
            SubjectCoverage(
              area: Area.mathematics,
              subject: 'Matemática',
              saved: 3,
            ),
          ],
          [Area.mathematics],
        ),
      ).first;
      expect(s.rationale, isNot(contains('acervo')));
    });
  });
}
