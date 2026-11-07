import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/direction_models.dart';
import 'package:iago/domain/direction_progress.dart';
import 'package:iago/domain/question.dart';
import 'package:iago/domain/question_list.dart';

final now = DateTime(2026, 11, 30, 12);

DateTime ago(int days, [int hour = 12]) =>
    DateTime(now.year, now.month, now.day - days, hour);

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
  createdAt: ago(20),
);

Question q(
  String id,
  Area area,
  String subject,
  DateTime at, {
  String topic = 'segredo-do-usuario',
}) => Question(
  id: id,
  statement: 'enunciado secreto $id',
  type: QuestionType.discursive,
  area: area,
  subject: subject,
  topic: topic,
  platform: 'plataforma-x',
  createdAt: at,
  updatedAt: at,
);

QuestionList list(String id, List<String> ids, DateTime? exported) =>
    QuestionList(
      id: id,
      name: 'lista',
      questionIds: ids,
      createdAt: ago(40),
      updatedAt: ago(40),
      lastExportedAt: exported,
    );

void main() {
  group('computeStepProgress (CA-D7)', () {
    test('conta N de M nos 14 dias e X de Y nos 14 anteriores', () {
      final steps = [
        // Últimos 14 dias: 3 de 4.
        step('a', dueAt: ago(2), status: StepStatus.done, doneAt: ago(3)),
        step('b', dueAt: ago(5), status: StepStatus.done, doneAt: ago(5)),
        step('c', dueAt: ago(9), status: StepStatus.done, doneAt: ago(10)),
        step('d', dueAt: ago(12), status: StepStatus.missed),
        // 14 anteriores: 1 de 3.
        step('e', dueAt: ago(16), status: StepStatus.done, doneAt: ago(17)),
        step('f', dueAt: ago(20), status: StepStatus.missed),
        step('g', dueAt: ago(27)),
        // Fora das duas janelas.
        step('h', dueAt: ago(40), status: StepStatus.done, doneAt: ago(40)),
      ];
      final p = computeStepProgress(steps, now);
      expect(
        (p.doneRecent, p.totalRecent, p.donePrevious, p.totalPrevious),
        (3, 4, 1, 3),
      );
      expect(
        p.sentence,
        'Você cumpriu 3 de 4 etapas nos últimos 14 dias; '
        'nos 14 anteriores, 1 de 3.',
      );
    });

    test('concluir uma etapa atualiza a comparação', () {
      final open = step('a', dueAt: ago(1));
      final before = computeStepProgress([open], now);
      expect((before.doneRecent, before.totalRecent), (0, 1));
      final after = computeStepProgress([completeStep(open, now)], now);
      expect((after.doneRecent, after.totalRecent), (1, 1));
    });

    test(
      'etapa em dia e ainda não vencida não conta; concluída antes conta',
      () {
        final future = step('a', dueAt: DateTime(2026, 12, 3));
        expect(computeStepProgress([future], now).isEmpty, isTrue);
        final early = completeStep(future, now);
        expect(computeStepProgress([early], now).doneRecent, 1);
      },
    );

    test('sem etapas, a frase é vazia (nada de número solto)', () {
      expect(computeStepProgress(const [], now).sentence, '');
    });

    test('sem janela anterior, a frase não inventa comparação', () {
      final p = computeStepProgress([
        step('a', dueAt: ago(1), status: StepStatus.done, doneAt: ago(1)),
      ], now);
      expect(p.sentence, 'Você cumpriu 1 de 1 etapas nos últimos 14 dias.');
    });

    test(
      'bordas: 14 dias exatos já é da janela anterior (aberta à esquerda)',
      () {
        final at14 = now.subtract(const Duration(days: 14));
        final p = computeStepProgress([
          step('a', dueAt: at14),
          step('b', dueAt: at14.subtract(const Duration(milliseconds: 1))),
        ], now);
        expect((p.totalRecent, p.totalPrevious), (0, 2));
        // Exatamente 14 dias atrás já é da janela anterior (aberta à esquerda).
      },
    );
  });

  group('adiar e concluir (CA-D8)', () {
    test('adia uma vez, por 2 dias, a partir do prazo', () {
      final s = step('a', dueAt: DateTime(2026, 12, 3, 23, 59, 59, 999));
      final first = postponeStep(s, now)!;
      expect(first.dueAt, DateTime(2026, 12, 5, 23, 59, 59, 999));
      expect(first.postponedAt, now);
      expect(canPostpone(first), isFalse);
      expect(postponeStep(first, now), isNull);
    });

    test('atrasada adia a partir de hoje', () {
      final s = step('a', dueAt: ago(5));
      expect(
        postponeStep(s, now)!.dueAt,
        DateTime(2026, 12, 2, 23, 59, 59, 999),
      );
    });

    test('concluída ou perdida não pode ser adiada', () {
      expect(
        canPostpone(step('a', dueAt: ago(1), status: StepStatus.done)),
        isFalse,
      );
      expect(
        canPostpone(step('a', dueAt: ago(1), status: StepStatus.missed)),
        isFalse,
      );
    });

    test('concluir grava a data e é idempotente', () {
      final s = step('a', dueAt: ago(1));
      final done = completeStep(s, now);
      expect(done.status, StepStatus.done);
      expect(done.doneAt, now);
      expect(completeStep(done, now.add(const Duration(days: 1))).doneAt, now);
    });

    test('atrasada é calculada na leitura', () {
      expect(isOverdue(step('a', dueAt: ago(1)), now), isTrue);
      expect(isOverdue(step('a', dueAt: DateTime(2026, 12, 1)), now), isFalse);
      expect(
        isOverdue(step('a', dueAt: ago(1), status: StepStatus.done), now),
        isFalse,
      );
    });
  });

  group('buildDirectionContext', () {
    final goal = StudyGoal(
      exam: ExamTarget.enem,
      weeklyHours: 6,
      createdAt: ago(30),
      updatedAt: ago(30),
    );

    test('só contagens por matéria do catálogo, sem texto livre', () {
      final questions = [
        q('1', Area.mathematics, 'Matemática', ago(2)),
        q('2', Area.mathematics, 'Matemática', ago(20)),
        q('3', Area.naturalSciences, 'Física', ago(1)),
        // Matéria fora do catálogo (tag livre): não pode chegar ao contexto.
        q('4', Area.naturalSciences, 'Astrologia', ago(1)),
      ];
      final lists = [
        list('a', ['1', '2', '3'], ago(3)), // conta em Matemática e Física
        list('b', ['1'], ago(30)), // fora da janela
        list('c', ['3'], null), // nunca exportada
      ];
      final c = buildDirectionContext(
        goal: goal,
        questions: questions,
        lists: lists,
        now: now,
      );
      SubjectCoverage of(String s) =>
          c.coverage.firstWhere((x) => x.subject == s);
      expect((of('Matemática').saved, of('Matemática').savedLast14d), (2, 1));
      expect(of('Matemática').listsExportedLast14d, 1);
      expect((of('Física').saved, of('Física').savedLast14d), (1, 1));
      expect(of('Física').listsExportedLast14d, 1);
      expect(c.coverage.any((x) => x.subject == 'Astrologia'), isFalse);

      final json = jsonEncode(c.toJson());
      for (final secret in [
        'enunciado secreto',
        'segredo-do-usuario',
        'plataforma-x',
        'Astrologia',
      ]) {
        expect(json.contains(secret), isFalse, reason: secret);
      }
    });

    test('histórico vem das etapas dos últimos 14 dias', () {
      final c = buildDirectionContext(
        goal: goal,
        questions: const [],
        lists: const [],
        steps: [
          step('a', dueAt: ago(2), status: StepStatus.done, doneAt: ago(2)),
          step('b', dueAt: ago(4), status: StepStatus.missed),
          step('c', dueAt: ago(20), status: StepStatus.done, doneAt: ago(20)),
        ],
        now: now,
      );
      expect(c.history.doneLast14d, 1);
      expect(c.history.missedLast14d, 1);
    });

    test('sem dados, a cobertura é vazia', () {
      final c = buildDirectionContext(
        goal: goal,
        questions: const [],
        lists: const [],
        now: now,
      );
      expect(c.coverage, isEmpty);
    });
  });
}
