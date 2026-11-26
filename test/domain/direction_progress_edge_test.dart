import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_progress.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_list.dart';

final now = DateTime(2026, 11, 30, 12);

StudyStep step(
  String id, {
  required DateTime dueAt,
  StepStatus status = StepStatus.accepted,
  DateTime? doneAt,
  DateTime? postponedAt,
}) => StudyStep(
  id: id,
  action: StepAction.collect,
  area: Area.mathematics,
  subject: 'Matemática',
  targetCount: 10,
  dueAt: dueAt,
  status: status,
  doneAt: doneAt,
  postponedAt: postponedAt,
  source: StepSource.rules,
  rationale: 'x',
  createdAt: now,
);

Question q(String id, Area area, String subject, DateTime at) => Question(
  id: id,
  statement: 'enunciado $id',
  type: QuestionType.discursive,
  area: area,
  subject: subject,
  topic: 'tag-livre',
  platform: 'plataforma-x',
  createdAt: at,
  updatedAt: at,
);

QuestionList list(String id, List<String> ids, DateTime? exported) =>
    QuestionList(
      id: id,
      name: 'lista',
      questionIds: ids,
      createdAt: now,
      updatedAt: now,
      lastExportedAt: exported,
    );

StudyGoal goal() => StudyGoal(
  exam: ExamTarget.enem,
  weeklyHours: 5,
  createdAt: now,
  updatedAt: now,
);

void main() {
  const ms = Duration(milliseconds: 1);
  final d14 = now.subtract(const Duration(days: 14));
  final d28 = now.subtract(const Duration(days: 28));

  group('bordas exatas das janelas (CA-D7)', () {
    StepProgress of(DateTime done) => computeStepProgress([
      step('a', dueAt: done, status: StepStatus.done, doneAt: done),
    ], now);

    test('agora entra na janela recente', () {
      expect(of(now).totalRecent, 1);
    });

    test('agora-14d exato pertence à janela anterior, não à recente', () {
      final p = of(d14);
      expect((p.totalRecent, p.totalPrevious), (0, 1));
    });

    test('1 ms depois de agora-14d ainda é recente', () {
      expect(of(d14.add(ms)).totalRecent, 1);
    });

    test('agora-28d exato fica fora das duas janelas', () {
      final p = of(d28);
      expect((p.totalRecent, p.totalPrevious), (0, 0));
      expect(p.isEmpty, isTrue);
    });

    test('1 ms depois de agora-28d entra na anterior', () {
      expect(of(d28.add(ms)).totalPrevious, 1);
    });

    test('concluída no futuro (relógio adiantado) não conta', () {
      expect(of(now.add(ms)).isEmpty, isTrue);
    });

    test(
      'etapa pendente com prazo exatamente agora já conta como não feita',
      () {
        final p = computeStepProgress([step('a', dueAt: now)], now);
        expect((p.doneRecent, p.totalRecent), (0, 1));
      },
    );

    test('pendente com prazo 1 ms no futuro não conta ainda', () {
      expect(
        computeStepProgress([step('a', dueAt: now.add(ms))], now).isEmpty,
        isTrue,
      );
    });

    test('concluída sem doneAt cai no prazo', () {
      final p = computeStepProgress([
        step(
          'a',
          dueAt: now.subtract(const Duration(days: 3)),
          status: StepStatus.done,
        ),
      ], now);
      expect((p.doneRecent, p.totalRecent), (1, 1));
    });

    test('doneAt manda mais que o prazo: prazo antigo, concluída agora', () {
      final p = computeStepProgress([
        step(
          'a',
          dueAt: now.subtract(const Duration(days: 20)),
          status: StepStatus.done,
          doneAt: now.subtract(const Duration(days: 1)),
        ),
      ], now);
      expect((p.doneRecent, p.totalRecent, p.totalPrevious), (1, 1, 0));
    });

    test('perdida com prazo no futuro (status incoerente) é ignorada', () {
      final p = computeStepProgress([
        step(
          'a',
          dueAt: now.add(const Duration(days: 1)),
          status: StepStatus.missed,
        ),
      ], now);
      expect(p.isEmpty, isTrue);
    });

    test('lista vazia e frase vazia', () {
      expect(computeStepProgress(const [], now).sentence, '');
    });

    test('frase com anterior zerado mostra "0 de N"', () {
      final p = computeStepProgress([
        step('a', dueAt: d14.subtract(const Duration(days: 1))),
        step('b', dueAt: d14.add(const Duration(days: 1))),
      ], now);
      expect(
        p.sentence,
        'Você cumpriu 0 de 1 etapas nos últimos 14 dias; nos 14 anteriores, '
        '0 de 1.',
      );
    });

    test('só janela anterior: frase mostra recente 0 de 0', () {
      final p = computeStepProgress([
        step('a', dueAt: d14.subtract(const Duration(days: 1))),
      ], now);
      expect(p.sentence, contains('0 de 0 etapas'));
      expect(p.sentence, contains('nos 14 anteriores, 0 de 1'));
    });
  });

  group('adiar (CA-D8) nos limites', () {
    test('prazo no fim do mês transborda para o mês seguinte', () {
      final s = step('a', dueAt: DateTime(2026, 12, 31, 23, 59, 59, 999));
      final p = postponeStep(s, now)!;
      expect(p.dueAt, DateTime(2027, 1, 2, 23, 59, 59, 999));
    });

    test(
      'etapa vencida há muito tempo adia a partir de hoje, não do prazo',
      () {
        final s = step('a', dueAt: DateTime(2026, 10, 1, 23, 59, 59, 999));
        final p = postponeStep(s, now)!;
        expect(p.dueAt, DateTime(2026, 12, 2, 23, 59, 59, 999));
        expect(p.dueAt.isAfter(now), isTrue);
        expect(isOverdue(p, now), isFalse);
      },
    );

    test('vencida ontem, adiada, deixa de contar na comparação', () {
      final s = step('a', dueAt: now.subtract(const Duration(days: 1)));
      expect(computeStepProgress([s], now).totalRecent, 1);
      final p = postponeStep(s, now)!;
      expect(computeStepProgress([p], now).isEmpty, isTrue);
    });

    test('hoje às 23:59:59.999, adiar vai para depois de amanhã', () {
      final late = DateTime(2026, 11, 30, 23, 59, 59, 999);
      final p = postponeStep(step('a', dueAt: late), late)!;
      expect(p.dueAt, DateTime(2026, 12, 2, 23, 59, 59, 999));
    });

    test(
      'adiar preserva status e demais campos; só prazo e postponedAt mudam',
      () {
        final s = step(
          'a',
          dueAt: DateTime(2026, 12, 3, 23, 59, 59, 999),
          status: StepStatus.proposed,
        );
        final p = postponeStep(s, now)!;
        expect(p.status, StepStatus.proposed);
        expect(p.postponedAt, now);
        expect(p.id, s.id);
        expect(p.targetCount, s.targetCount);
        expect(p.createdAt, s.createdAt);
      },
    );

    test('concluir depois de adiar mantém postponedAt e grava doneAt', () {
      final s = step('a', dueAt: DateTime(2026, 12, 3, 23, 59, 59, 999));
      final done = completeStep(postponeStep(s, now)!, now);
      expect(done.status, StepStatus.done);
      expect(done.postponedAt, now);
      expect(done.doneAt, now);
      expect(canPostpone(done), isFalse);
    });

    test('concluir etapa já concluída preserva a primeira doneAt', () {
      final first = completeStep(step('a', dueAt: now), d14);
      expect(completeStep(first, now).doneAt, d14);
    });

    test('concluir etapa perdida é permitido e vira concluída', () {
      final s = step('a', dueAt: d14, status: StepStatus.missed);
      expect(completeStep(s, now).status, StepStatus.done);
    });

    test('markMissed não mexe em concluída nem em perdida', () {
      final done = step('a', dueAt: d14, status: StepStatus.done);
      expect(markMissed(done), same(done));
      final lost = step('b', dueAt: d14, status: StepStatus.missed);
      expect(markMissed(lost), same(lost));
    });

    test('acceptStep só aceita proposta', () {
      final done = step('a', dueAt: d14, status: StepStatus.done);
      expect(acceptStep(done).status, StepStatus.done);
      final missed = step('b', dueAt: d14, status: StepStatus.missed);
      expect(acceptStep(missed).status, StepStatus.missed);
    });
  });

  group('buildDirectionContext nos limites', () {
    test(
      'lista exportada exatamente em agora-14d fica fora; em agora entra',
      () {
        final qs = [q('1', Area.mathematics, 'Matemática', now)];
        final c = buildDirectionContext(
          goal: goal(),
          questions: qs,
          lists: [
            list('a', ['1'], d14),
            list('b', ['1'], now),
          ],
          now: now,
        );
        expect(c.coverage.single.listsExportedLast14d, 1);
      },
    );

    test('lista exportada no futuro não conta', () {
      final qs = [q('1', Area.mathematics, 'Matemática', now)];
      final c = buildDirectionContext(
        goal: goal(),
        questions: qs,
        lists: [
          list('a', ['1'], now.add(ms)),
        ],
        now: now,
      );
      expect(c.coverage.single.listsExportedLast14d, 0);
    });

    test('lista com duas questões da mesma matéria conta uma vez', () {
      final qs = [
        q('1', Area.mathematics, 'Matemática', now),
        q('2', Area.mathematics, 'Matemática', now),
      ];
      final c = buildDirectionContext(
        goal: goal(),
        questions: qs,
        lists: [
          list('a', ['1', '2'], now),
        ],
        now: now,
      );
      expect(c.coverage.single.listsExportedLast14d, 1);
    });

    test('lista com ids inexistentes é ignorada sem erro', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: const [],
        lists: [
          list('a', ['fantasma'], now),
        ],
        now: now,
      );
      expect(c.coverage, isEmpty);
    });

    test('questão salva exatamente em agora-14d não é recente', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: [q('1', Area.mathematics, 'Matemática', d14)],
        lists: const [],
        now: now,
      );
      expect(c.coverage.single.savedLast14d, 0);
      expect(c.coverage.single.saved, 1);
    });

    test(
      'regressão: questão com createdAt no futuro não deve contar como recente',
      () {
        // Coerente com listsExportedLast14d, que descarta datas no futuro.
        final c = buildDirectionContext(
          goal: goal(),
          questions: [
            q(
              '1',
              Area.mathematics,
              'Matemática',
              now.add(const Duration(days: 3)),
            ),
          ],
          lists: const [],
          now: now,
        );
        expect(c.coverage.single.savedLast14d, 0);
      },
    );

    test('matéria de outra área (par inválido) não vaza', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: [q('1', Area.mathematics, 'Física', now)],
        lists: const [],
        now: now,
      );
      expect(c.coverage, isEmpty);
    });

    test('JSON não contém enunciado, tag livre, plataforma, id nem datas', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: [
          q('id-secreto', Area.mathematics, 'Matemática', now),
          q('id-2', Area.naturalSciences, 'Astrologia', now),
        ],
        lists: [
          list('lista-id', ['id-secreto'], now),
        ],
        steps: [step('etapa-id', dueAt: now.subtract(const Duration(days: 1)))],
        now: now,
      );
      final json = jsonEncode(c.toJson());
      for (final s in [
        'enunciado',
        'tag-livre',
        'plataforma-x',
        'id-secreto',
        'lista-id',
        'etapa-id',
        'Astrologia',
      ]) {
        expect(json.contains(s), isFalse, reason: s);
      }
      expect(json.contains('rationale'), isFalse);
      expect(json.contains('2026-11-30T'), isFalse);
    });

    test('pendente vencida sem status gravado entra em missedLast14d', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: const [],
        lists: const [],
        steps: [
          step('a', dueAt: now.subtract(const Duration(days: 2))),
          step('b', dueAt: now.add(const Duration(days: 2))),
        ],
        now: now,
      );
      expect(c.history.missedLast14d, 1);
      expect(c.history.doneLast14d, 0);
    });

    test('histórico não conta etapas da janela anterior', () {
      final c = buildDirectionContext(
        goal: goal(),
        questions: const [],
        lists: const [],
        steps: [step('a', dueAt: d14, status: StepStatus.missed)],
        now: now,
      );
      expect(c.history.missedLast14d, 0);
    });
  });
}
