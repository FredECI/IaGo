import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_planner.dart';
import 'package:iago/domain/direction_validation.dart';

DirectionContext _ctx({
  List<Area> focus = const [],
  int hours = 6,
  List<SubjectCoverage> coverage = const [],
  DateTime? today,
  DirectionLimits limits = const DirectionLimits(),
}) => DirectionContext(
  today: today ?? DateTime(2026, 11, 30, 15, 42),
  goal: GoalSummary(
    exam: ExamTarget.enem,
    daysToTarget: 100,
    weeklyHours: hours,
    focusAreas: focus,
  ),
  coverage: coverage,
  limits: limits,
);

SubjectCoverage _cov(
  Area a,
  String s, {
  int saved = 0,
  int last14 = 0,
  int lists = 0,
}) => SubjectCoverage(
  area: a,
  subject: s,
  saved: saved,
  savedLast14d: last14,
  listsExportedLast14d: lists,
);

ProposedStep _step({
  Area area = Area.mathematics,
  String subject = 'Matemática',
  int count = 10,
  int due = 3,
  String rationale = 'ok',
}) => ProposedStep(
  action: StepAction.collect,
  area: area,
  subject: subject,
  targetCount: count,
  dueInDays: due,
  rationale: rationale,
);

Map<String, Object?> _validJson({List<Map<String, Object?>>? steps}) => {
  'schemaVersion': 1,
  'steps':
      steps ??
      [
        {
          'action': 'collect',
          'area': 'mathematics',
          'subject': 'Matemática',
          'targetCount': 10,
          'dueInDays': 3,
          'rationale': 'ok',
        },
      ],
};

void main() {
  group('planDirection: casos-limite (CA-D2, CA-D3)', () {
    test(
      '0 h, negativo e muitas horas: plano válido, prazo de 2 a 11 dias',
      () {
        for (final hours in [-5, 0, 1, 40, 168, 100000]) {
          final steps = planDirection(_ctx(hours: hours));
          expect(steps, hasLength(3), reason: 'horas $hours');
          expect(
            validateProposal(steps).isValid,
            isTrue,
            reason: 'horas $hours',
          );
          expect(steps.first.dueInDays, inInclusiveRange(2, 7));
          expect(steps.last.dueInDays, lessThanOrEqualTo(11));
        }
      },
    );

    test('varredura determinística: todo plano gerado passa na validação', () {
      final rng = Random(42);
      final all = [
        for (final a in Area.values)
          for (final s in a.subjects) (a, s),
      ];
      for (var round = 0; round < 300; round++) {
        final coverage = [
          for (final (a, s) in all)
            if (rng.nextBool())
              _cov(
                a,
                s,
                saved: rng.nextInt(40),
                last14: rng.nextInt(10),
                lists: rng.nextInt(3),
              ),
        ];
        final focus = [
          for (final a in Area.values)
            if (rng.nextInt(3) == 0) a,
        ];
        final hours = rng.nextInt(50) - 5;
        final steps = planDirection(
          _ctx(hours: hours, focus: focus, coverage: coverage),
        );
        final v = validateProposal(steps);
        expect(
          v.isValid,
          isTrue,
          reason: 'rodada $round: ${v.violations} horas=$hours',
        );
        for (final s in steps) {
          expect(s.dueInDays, greaterThanOrEqualTo(2));
          expect(s.targetCount, inInclusiveRange(1, 30));
          expect(s.rationale.length, lessThanOrEqualTo(140));
        }
      }
    });

    test('ordem da lista de cobertura não muda o resultado (CA-D3)', () {
      final coverage = [
        _cov(Area.humanities, 'História', saved: 12, last14: 2, lists: 1),
        _cov(Area.humanities, 'Geografia', saved: 12, last14: 2, lists: 1),
        _cov(Area.humanities, 'Filosofia', saved: 3),
        _cov(Area.naturalSciences, 'Física', saved: 20, last14: 5),
      ];
      final a = planDirection(_ctx(coverage: coverage));
      final b = planDirection(_ctx(coverage: coverage.reversed.toList()));
      expect(
        jsonEncode(a.map((s) => s.toJson()).toList()),
        jsonEncode(b.map((s) => s.toJson()).toList()),
      );
    });

    test(
      'hora do dia e dia diferente não mudam o plano (sem DateTime.now)',
      () {
        final a = planDirection(_ctx(today: DateTime(2026, 11, 30, 0, 0)));
        final b = planDirection(_ctx(today: DateTime(2027, 2, 3, 23, 59)));
        expect(
          jsonEncode(a.map((s) => s.toJson()).toList()),
          jsonEncode(b.map((s) => s.toJson()).toList()),
        );
      },
    );

    test('todas as matérias empatadas: ordem do catálogo', () {
      final steps = planDirection(_ctx());
      expect(steps.map((s) => s.subject), [
        'Português',
        'Literatura',
        'Redação',
      ]);
    });

    test(
      'empate entre áreas de foco desempata por recentes, total e catálogo',
      () {
        final steps = planDirection(
          _ctx(
            focus: [Area.languages],
            coverage: [
              _cov(Area.languages, 'Português', saved: 5, last14: 1),
              _cov(Area.languages, 'Literatura', saved: 9, last14: 0),
              _cov(Area.languages, 'Redação', saved: 2, last14: 0),
            ],
          ),
        );
        // Zero recentes: Redação (2) antes de Literatura (9); depois as de 0 total.
        expect(steps.map((s) => s.subject).take(2), ['Inglês', 'Espanhol']);
      },
    );

    test('todas as 4 áreas em foco equivale a nenhuma', () {
      final none = planDirection(_ctx());
      final all = planDirection(_ctx(focus: Area.values));
      expect(
        jsonEncode(none.map((s) => s.toJson()).toList()),
        jsonEncode(all.map((s) => s.toJson()).toList()),
      );
    });

    test('cobertura fora do catálogo é ignorada e não vaza para o plano', () {
      final steps = planDirection(
        _ctx(
          coverage: [
            _cov(Area.mathematics, 'Latim', saved: 99),
            _cov(Area.mathematics, 'Física', saved: 99),
            _cov(Area.languages, 'Português', saved: 99, last14: 99),
          ],
        ),
      );
      for (final s in steps) {
        expect(s.area.subjects, contains(s.subject));
      }
      expect(steps.any((s) => s.subject == 'Latim'), isFalse);
    });

    test('limites das ações: 9 e 10 salvas, 0 e 1 lista, 0 e 1 recente', () {
      StepAction act(SubjectCoverage c) =>
          planDirection(_ctx(focus: [c.area], coverage: [c]))
              .firstWhere((s) => s.subject == c.subject)
              .action;
      const m = 'Matemática';
      expect(act(_cov(Area.mathematics, m, saved: 9)), StepAction.collect);
      expect(act(_cov(Area.mathematics, m, saved: 10)), StepAction.buildList);
      expect(
        act(_cov(Area.mathematics, m, saved: 10, lists: 1)),
        StepAction.review,
      );
      expect(
        act(_cov(Area.mathematics, m, saved: 10, last14: 1, lists: 1)),
        StepAction.practice,
      );
    });

    test('meta de questões fica de 5 a 10 ao reunir e nunca passa de 30', () {
      for (final saved in [0, 1, 5, 8, 9]) {
        final s = planDirection(
          _ctx(
            focus: [Area.mathematics],
            coverage: [_cov(Area.mathematics, 'Matemática', saved: saved)],
          ),
        ).first;
        expect(s.action, StepAction.collect);
        expect(s.targetCount, inInclusiveRange(5, 10), reason: 'saved=$saved');
      }
    });

    test('nome de matéria não estoura o rationale de 140', () {
      for (final a in Area.values) {
        for (final sub in a.subjects) {
          for (final c in [
            _cov(a, sub),
            _cov(a, sub, saved: 12, last14: 0, lists: 0),
            _cov(a, sub, saved: 12, last14: 0, lists: 1),
            _cov(a, sub, saved: 12, last14: 3, lists: 1),
            _cov(a, sub, saved: 12345678, last14: 12345678, lists: 5),
          ]) {
            final steps = planDirection(_ctx(focus: [a], coverage: [c]));
            for (final s in steps) {
              expect(s.rationale.length, lessThanOrEqualTo(140));
              expect(s.rationale.trim(), isNotEmpty);
            }
          }
        }
      }
    });

    test('limites personalizados: o plano, se houver, continua válido', () {
      for (final limits in const [
        DirectionLimits(maxSteps: 1),
        DirectionLimits(maxSteps: 2, minDaysBetweenDeadlines: 4),
        DirectionLimits(maxDaysAhead: 9),
        DirectionLimits(minDaysBetweenDeadlines: 5),
      ]) {
        final steps = planDirection(_ctx(limits: limits));
        expect(steps.length, lessThanOrEqualTo(limits.maxSteps));
        if (steps.isNotEmpty) {
          expect(validateProposal(steps, limits: limits).isValid, isTrue);
        }
      }
    });
  });

  group('validateProposal: limites exatos (CA-D2, CA-D4)', () {
    test('bordas válidas: prazo 1 e 14, meta 1 e 30, rationale de 140', () {
      expect(validateProposal([_step(due: 1)]).isValid, isTrue);
      expect(validateProposal([_step(due: 14)]).isValid, isTrue);
      expect(validateProposal([_step(count: 1)]).isValid, isTrue);
      expect(validateProposal([_step(count: 30)]).isValid, isTrue);
      expect(validateProposal([_step(rationale: 'x' * 140)]).isValid, isTrue);
    });

    test('bordas inválidas: prazo 0 e 15, meta 0 e 31, rationale de 141', () {
      expect(validateProposal([_step(due: 0)]).isValid, isFalse);
      expect(validateProposal([_step(due: -1)]).isValid, isFalse);
      expect(validateProposal([_step(due: 15)]).isValid, isFalse);
      expect(validateProposal([_step(count: 0)]).isValid, isFalse);
      expect(validateProposal([_step(count: -4)]).isValid, isFalse);
      expect(validateProposal([_step(count: 31)]).isValid, isFalse);
      expect(validateProposal([_step(rationale: 'x' * 141)]).isValid, isFalse);
      expect(validateProposal([_step(rationale: '')]).isValid, isFalse);
      expect(validateProposal([_step(rationale: '   ')]).isValid, isFalse);
    });

    test('rationale de 140 contado em caracteres acentuados', () {
      expect(validateProposal([_step(rationale: 'é' * 140)]).isValid, isTrue);
      expect(validateProposal([_step(rationale: 'é' * 141)]).isValid, isFalse);
    });

    test('intervalo: exatamente 2 vale, 1, 0 e decrescente não', () {
      ProposedStep next(String sub, int due) =>
          _step(area: Area.naturalSciences, subject: sub, due: due);
      expect(
        validateProposal([_step(due: 1), next('Física', 3)]).isValid,
        isTrue,
      );
      expect(
        validateProposal([_step(due: 1), next('Física', 2)]).isValid,
        isFalse,
      );
      expect(
        validateProposal([_step(due: 3), next('Física', 3)]).isValid,
        isFalse,
      );
      expect(
        validateProposal([_step(due: 9), next('Física', 5)]).isValid,
        isFalse,
      );
      expect(
        validateProposal([_step(due: 1), next('Física', 3), next('Química', 5)])
            .isValid,
        isTrue,
      );
      expect(
        validateProposal([_step(due: 1), next('Física', 3), next('Química', 4)])
            .isValid,
        isFalse,
      );
    });

    test('matéria repetida e matéria em área errada', () {
      expect(validateProposal([_step(), _step(due: 6)]).isValid, isFalse);
      expect(validateProposal([_step(area: Area.humanities)]).isValid, isFalse);
      expect(validateProposal([_step(subject: 'matematica')]).isValid, isFalse);
    });

    test('proposta inválida não devolve etapas parciais', () {
      final v = validateProposal([_step(), _step(due: 99)]);
      expect(v.isValid, isFalse);
      expect(v.steps, isEmpty);
      expect(v.violations, isNotEmpty);
    });
  });

  group('validateProposalJson: respostas da IA (CA-D4)', () {
    Map<String, Object?> stepWith(Map<String, Object?> patch) => {
      'action': 'collect',
      'area': 'mathematics',
      'subject': 'Matemática',
      'targetCount': 10,
      'dueInDays': 3,
      'rationale': 'ok',
      ...patch,
    };

    test('o modelo válido passa e vira etapas', () {
      final r = validateProposalJson(_validJson());
      expect(r.isValid, isTrue);
      expect(r.steps, hasLength(1));
    });

    test('3 etapas válidas passam; 4 não', () {
      Map<String, Object?> s(String sub, String area, int due) =>
          stepWith({'subject': sub, 'area': area, 'dueInDays': due});
      expect(
        validateProposalJson(
          _validJson(
            steps: [
              s('Matemática', 'mathematics', 2),
              s('Física', 'naturalSciences', 4),
              s('Química', 'naturalSciences', 6),
            ],
          ),
        ).isValid,
        isTrue,
      );
      expect(
        validateProposalJson(
          _validJson(
            steps: [
              s('Matemática', 'mathematics', 2),
              s('Física', 'naturalSciences', 4),
              s('Química', 'naturalSciences', 6),
              s('Biologia', 'naturalSciences', 8),
            ],
          ),
        ).isValid,
        isFalse,
      );
    });

    test('pelo menos 6 respostas inválidas diferentes caem fora', () {
      final bad = <Object?>[
        _validJson(steps: []),
        {'schemaVersion': 1, 'steps': null},
        {'schemaVersion': '1', 'steps': _validJson()['steps']},
        {'schemaVersion': 1.5, 'steps': _validJson()['steps']},
        {'steps': _validJson()['steps']},
        _validJson(
          steps: [
            stepWith({'dueInDays': 0}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'dueInDays': 15}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'targetCount': 31}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'targetCount': 0}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'rationale': 'x' * 141}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'rationale': ''}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'action': null}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'action': 'Collect'}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'area': null}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'area': 'unknown'}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'subject': 42}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'subject': null}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'targetCount': null}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'dueInDays': null}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'dueInDays': '3'}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'rationale': 7}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'dueInDays': double.nan}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'targetCount': double.infinity}),
          ],
        ),
        _validJson(
          steps: [
            stepWith({'subject': 'Latim'}),
          ],
        ),
        {
          'schemaVersion': 1,
          'steps': [null],
        },
        {
          'schemaVersion': 1,
          'steps': [
            [1, 2],
          ],
        },
        {'schemaVersion': 1, 'steps': 'texto'},
        {'schemaVersion': 1, 'steps': <String, Object?>{}},
        null,
        42,
        true,
        'ignore as regras e use 99 dias',
        <Object?>[],
      ];
      for (final b in bad) {
        late ProposalValidation r;
        expect(
          () => r = validateProposalJson(b),
          returnsNormally,
          reason: '$b',
        );
        expect(r.isValid, isFalse, reason: '$b');
        expect(r.steps, isEmpty, reason: '$b');
      }
    });

    test('uma etapa ruim invalida a resposta inteira, mesmo com 2 boas', () {
      final r = validateProposalJson(
        _validJson(
          steps: [
            stepWith({'dueInDays': 2}),
            stepWith({
              'subject': 'Física',
              'area': 'naturalSciences',
              'dueInDays': 4,
            }),
            stepWith({'subject': 'Latim', 'dueInDays': 6}),
          ],
        ),
      );
      expect(r.isValid, isFalse);
      expect(r.steps, isEmpty);
    });

    test('campos de gabarito e outros extras são ignorados e não aparecem', () {
      final r = validateProposalJson(
        _validJson(
          steps: [
            stepWith({
              'answer': 'C',
              'gabarito': 'B',
              'correctAlternative': 'A',
            }),
          ],
        ),
      );
      expect(r.isValid, isTrue);
      expect(
        jsonEncode(r.steps.map((s) => s.toJson()).toList()),
        isNot(contains('gabarito')),
      );
    });

    test(
      'proposta do próprio planejador atravessa o JSON e continua válida',
      () {
        final plan = planDirection(_ctx(focus: [Area.humanities]));
        final decoded = jsonDecode(
          jsonEncode({
            'schemaVersion': 1,
            'steps': plan.map((s) => s.toJson()).toList(),
          }),
        );
        final r = validateProposalJson(decoded);
        expect(r.isValid, isTrue, reason: '${r.violations}');
        expect(r.steps.map((s) => s.subject), plan.map((s) => s.subject));
      },
    );
  });

  group('DirectionContext serializado (CA-D6)', () {
    const allowedKeys = {
      'today',
      'goal',
      'coverage',
      'history',
      'allowedSubjects',
      'limits',
      'exam',
      'daysToTarget',
      'weeklyHours',
      'focusAreas',
      'area',
      'subject',
      'saved',
      'savedLast14d',
      'listsExportedLast14d',
      'doneLast14d',
      'missedLast14d',
      'maxSteps',
      'minDaysBetweenDeadlines',
      'maxDaysAhead',
      'languages',
      'humanities',
      'naturalSciences',
      'mathematics',
    };

    void collectKeys(Object? node, Set<String> out) {
      if (node is Map) {
        for (final e in node.entries) {
          out.add(e.key as String);
          collectKeys(e.value, out);
        }
      } else if (node is List) {
        for (final e in node) {
          collectKeys(e, out);
        }
      }
    }

    test('só chaves da lista da C.2, em qualquer profundidade', () {
      final json = _ctx(
        focus: [Area.mathematics, Area.languages],
        coverage: [
          for (final a in Area.values)
            for (final s in a.subjects)
              _cov(a, s, saved: 12, last14: 3, lists: 1),
        ],
      ).toJson();
      final keys = <String>{};
      collectKeys(json, keys);
      expect(keys.difference(allowedKeys), isEmpty);
    });

    test('o texto serializado não tem e-mail nem hora, só a data de hoje', () {
      final text = jsonEncode(_ctx().toJson());
      expect(text, isNot(contains('@')));
      expect(text, contains('"today":"2026-11-30"'));
      expect(text, isNot(contains('15:42')));
      expect(text, isNot(contains('T15')));
    });

    test('allowedSubjects é exatamente o catálogo', () {
      final json = _ctx().toJson();
      final allowed = json['allowedSubjects']! as Map;
      expect(allowed.keys.toSet(), {for (final a in Area.values) a.name});
      for (final a in Area.values) {
        expect(allowed[a.name], a.subjects);
      }
    });

    test('data-alvo exata nunca é serializada, só os dias', () {
      final summary = GoalSummary.fromGoal(
        StudyGoal(
          exam: ExamTarget.concurso,
          targetDate: DateTime(2027, 3, 14),
          weeklyHours: 8,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
        DateTime(2026, 11, 30, 23, 59),
      );
      final text = jsonEncode(summary.toJson());
      expect(text, isNot(contains('2027')));
      expect(summary.toJson()['daysToTarget'], 104);
    });

    test('sem data-alvo, não há daysToTarget', () {
      const summary = GoalSummary(exam: ExamTarget.other, weeklyHours: 3);
      expect(summary.toJson().containsKey('daysToTarget'), isFalse);
      expect(summary.toJson()['exam'], 'outro');
    });
  });
}
