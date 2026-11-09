import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/firebase/community_write_plans.dart';
import 'package:iago/data/firebase/rating_write_plans.dart';
import 'package:iago/domain/area.dart';
import 'package:iago/domain/rating_models.dart';

/// Exporta os planos de escrita das avaliações para
/// `firestore-tests/fixtures/rating_plans.json`, que o teste de regras
/// (`firestore-tests/rating-plans.test.mjs`) executa no emulador. Falha se o
/// arquivo estiver desatualizado; para regenerar:
/// `UPDATE_PLANS=1 flutter test test/data/rating_rules_fixture_test.dart`.
const _file = 'firestore-tests/fixtures/rating_plans.json';

Object? _value(Object? v) {
  if (v == null || v is String || v is num || v is bool) return v;
  if (v is FieldValue) {
    if (v == FieldValue.serverTimestamp()) return {r'$': 'serverTimestamp'};
    if (v == FieldValue.delete()) return {r'$': 'delete'};
    throw StateError('FieldValue desconhecido');
  }
  throw StateError('Tipo não serializável: ${v.runtimeType}');
}

List<Map<String, Object?>> _plan(List<PlannedWrite> plan) => [
  for (final w in plan)
    {
      'kind': w.kind.name,
      'path': w.path,
      if (w.data != null)
        'data': {for (final e in w.data!.entries) e.key: _value(e.value)},
    },
];

void main() {
  const math = RatingTarget(
    bankId: 'enem-2022-136',
    area: Area.mathematics,
    subject: 'Matemática',
  );
  final value = RatingValue(difficulty: 2, quality: 3);

  final scenarios = <String, List<PlannedWrite>>{
    'rate': ratePlan(uid: 'ana', target: math, value: value),
    'rateChange': ratePlan(
      uid: 'ana',
      target: math,
      value: RatingValue(difficulty: 3, quality: 1),
    ),
    // Questão sem matéria: o grupo vira o rótulo da área.
    'rateNoSubject': ratePlan(
      uid: 'ana',
      target: const RatingTarget(
        bankId: 'enem-2022-12',
        area: Area.naturalSciences,
        subject: '',
      ),
      value: value,
    ),
    'rateLongSubject': ratePlan(
      uid: 'ana',
      target: RatingTarget(
        bankId: 'enem-2022-12',
        area: Area.languages,
        subject: 'x' * 90,
      ),
      value: value,
    ),
    'rateOtherSource': ratePlan(
      uid: 'ana',
      target: const RatingTarget(
        bankId: 'obmep-2019-12',
        area: Area.mathematics,
        subject: 'Matemática',
      ),
      value: value,
    ),
    'remove': removeRatingPlan(uid: 'ana', bankId: 'enem-2022-136'),
    'privateRate': privateRatingPlan(
      uid: 'ana',
      questionId: 'bank_enem-2022-136',
      difficulty: 2,
      quality: 3,
    ),
    'privateClear': privateRatingPlan(uid: 'ana', questionId: 'q1'),
  };

  final json = const JsonEncoder.withIndent('  ')
      .convert({for (final e in scenarios.entries) e.key: _plan(e.value)});

  test('planos de avaliação batem com o fixture usado no teste de regras', () {
    final file = File(_file);
    if (Platform.environment['UPDATE_PLANS'] == '1') {
      file.writeAsStringSync('$json\n');
    }
    expect(file.existsSync(), isTrue, reason: 'rode com UPDATE_PLANS=1');
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n').trim(),
      json,
      reason: 'fixture desatualizado: UPDATE_PLANS=1 flutter test $_file',
    );
  });

  test('CA-A3: nota privada fora de 1 a 3 não gera plano', () {
    for (final bad in [0, 4, -2]) {
      expect(
        () => privateRatingPlan(uid: 'a', questionId: 'q', difficulty: bad),
        throwsA(isA<RatingFailure>()),
      );
      expect(
        () => privateRatingPlan(uid: 'a', questionId: 'q', quality: bad),
        throwsA(isA<RatingFailure>()),
      );
    }
  });

  test('o plano da avaliação pública nunca grava nota inválida (CA-A3)', () {
    for (final plan in scenarios.entries.where(
      (e) => e.key.startsWith('rate'),
    )) {
      final data = plan.value.single.data!;
      expect(data['difficulty'], inInclusiveRange(1, 3), reason: plan.key);
      expect(data['quality'], inInclusiveRange(1, 3), reason: plan.key);
    }
  });
}
