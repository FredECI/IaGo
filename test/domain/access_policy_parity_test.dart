// ignore_for_file: subtype_of_sealed_class (fakes mínimos do Firestore)
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/data/firebase/firestore_runtime_config.dart';
import 'package:iago/data/policy_providers.dart';
import 'package:iago/data/providers.dart';
import 'package:iago/data/runtime_config_repository.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/session.dart';

// F5a, validação do QA: paridade com firestore.rules (mesmas entradas de
// firestore-tests/attacks.test.mjs e members.test.mjs), demo x IA, falhas do
// runtime e da IA simulada.

const _gemini = AiProviderInfo(name: 'Gemini', minUserAge: 18);

AccessPolicy _from(Map<String, Object?>? data) =>
    AccessPolicy.fromRuntime(data, termsMinAge: AppInfo.termsMinAge);

class _Case {
  const _Case(this.label, this.value, this.expected);
  final String label;
  final Object? value;
  final int expected;
}

// Resultado de minAge() nas regras: configured is int && > 18 ? configured : 18.
const _minAgeTable = <_Case>[
  _Case('string "21"', '21', 18),
  _Case('string "25"', '25', 18),
  _Case('decimal 21.5', 21.5, 18),
  _Case('bool true', true, 18),
  _Case('null', null, 18),
  _Case('negativo -5', -5, 18),
  _Case('zero', 0, 18),
  _Case('lista [21]', [21], 18),
  _Case('mapa {v: 21}', {'v': 21}, 18),
  _Case('16', 16, 18),
  _Case('17', 17, 18),
  _Case('18', 18, 18),
  _Case('19', 19, 19),
  _Case('21', 21, 21),
];

class _Absent {
  const _Absent();
}

typedef _Snap = DocumentSnapshot<Map<String, dynamic>>;

class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this._get);
  final Future<_Snap> Function() _get;
  @override
  Future<_Snap> get([GetOptions? options]) => _get();
}

class _FakeCol extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCol(this._get);
  final Future<_Snap> Function() _get;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _FakeDoc(_get);
}

class _FakeDb extends Fake implements FirebaseFirestore {
  _FakeDb(this._get);
  final Future<_Snap> Function() _get;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCol(_get);
}

class _FakeSnap extends Fake implements _Snap {
  _FakeSnap(this._data);
  final Map<String, dynamic>? _data;
  @override
  Map<String, dynamic>? data() => _data;
}

class _ThrowingDb extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw StateError('sem Firebase');
}

class _ThrowingConfig implements RuntimeConfigRepository {
  @override
  Future<Map<String, Object?>?> load() => throw StateError('quebrou');
}

void main() {
  group('paridade com as regras: minAge', () {
    for (final c in _minAgeTable) {
      test('minAge ${c.label} -> ${c.expected}', () {
        final p = _from({'minAge': c.value});
        expect(p.minAge, c.expected);
        expect(p.acceptsDeclaredAge(c.expected - 1), isFalse);
        expect(p.acceptsDeclaredAge(c.expected), isTrue);
      });
    }

    test('minAge ausente -> 18 (17 nega, 18 e 30 aceitam)', () {
      final p = _from({});
      expect(p.minAge, 18);
      expect(p.acceptsDeclaredAge(17), isFalse);
      expect(p.acceptsDeclaredAge(18), isTrue);
      expect(p.acceptsDeclaredAge(30), isTrue);
    });
  });

  group('paridade com as regras: inviteRequired', () {
    // Regras: inviteRequired == false dispensa; qualquer outra coisa exige.
    final table = <String, (Object?, bool)>{
      'ausente': (const _Absent(), true),
      'true': (true, true),
      'false': (false, false),
      '"false"': ('false', true),
      'null': (null, true),
      '0': (0, true),
      '[false]': ([false], true),
    };
    table.forEach((label, row) {
      test('inviteRequired $label -> exigir=${row.$2}', () {
        final data = <String, Object?>{
          if (row.$1 is! _Absent) 'inviteRequired': row.$1,
        };
        expect(_from(data).inviteRequired, row.$2);
      });
    });
  });

  group('paridade com as regras: flags', () {
    // Regras: conectaWritesEnabled == true abre; qualquer outra coisa fecha.
    for (final key in ['aiEnabled', 'conectaEnabled', 'conectaWritesEnabled']) {
      final values = <Object?>[
        'true',
        1,
        null,
        [true],
        'yes',
      ];
      for (final v in values) {
        test('$key = ${v.runtimeType}($v) vale false', () {
          final p = _from({key: v});
          expect(p.aiEnabled, isFalse);
          expect(p.conectaEnabled, isFalse);
          expect(p.conectaWritesEnabled, isFalse);
        });
      }
    }

    test('flag true isolada não liga as outras', () {
      final p = _from({'conectaEnabled': true});
      expect(p.conectaEnabled, isTrue);
      expect(p.aiEnabled, isFalse);
      expect(p.conectaWritesEnabled, isFalse);
    });

    test('campos desconhecidos são ignorados', () {
      expect(_from({'foo': 1, 'minAge': 21}).minAge, 21);
    });
  });

  group('CA-T9: demo, IA e Conecta', () {
    test('canUseAi falso com aiEnabled=false, mesmo membro', () {
      final p = _from({'aiEnabled': false, 'conectaEnabled': true});
      expect(p.canUseAi(isMember: true, provider: _gemini), isFalse);
      expect(p.canUseAi(isMember: true, provider: fakeAiProvider), isFalse);
    });

    test('demo vê o Conecta com tudo desligado; IA continua falsa', () {
      final p = _from(null);
      expect(p.canSeeConecta(isDemo: true, isMember: false), isTrue);
      expect(p.canSeeConecta(isDemo: true, isMember: true), isTrue);
      expect(p.canUseAi(isMember: false, provider: fakeAiProvider), isFalse);
      expect(p.canUseAi(isMember: true, provider: fakeAiProvider), isFalse);
    });

    test('conta real sem conectaEnabled não vê o Conecta', () {
      final p = _from({'conectaWritesEnabled': true});
      expect(p.canSeeConecta(isDemo: false, isMember: true), isFalse);
    });

    test('AccessPolicy exige minAge >= termsMinAge (assert)', () {
      expect(
        () => AccessPolicy(termsMinAge: 18, minAge: 17),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('providers: demo x conta', () {
    ProviderContainer container(Object? owner) {
      final c = ProviderContainer(
        overrides: [dataOwnerProvider.overrideWithValue(owner)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('demo recebe IA simulada', () {
      final c = container(DemoSession(startedAt: DateTime(2026, 11, 8)));
      expect(c.read(questionExtractorProvider), isA<FakeQuestionExtractor>());
      expect(c.read(stepProposerProvider), isA<FakeStepProposer>());
    });

    test('conta real recebe null (IA indisponível)', () {
      final c = container('uid-1');
      expect(c.read(questionExtractorProvider), isNull);
      expect(c.read(stepProposerProvider), isNull);
    });

    test('sem sessão recebe null', () {
      final c = container(null);
      expect(c.read(questionExtractorProvider), isNull);
      expect(c.read(stepProposerProvider), isNull);
    });

    test('demo: política é o padrão seguro e IA fica bloqueada', () async {
      final c = container(DemoSession(startedAt: DateTime(2026, 11, 8)));
      final p = await c.read(accessPolicyAsyncProvider.future);
      expect(p, const AccessPolicy.safeDefault(termsMinAge: 18));
      await c.read(accessPolicyAsyncProvider.future);
      expect(
        c
            .read(accessPolicyProvider)
            .canUseAi(isMember: true, provider: fakeAiProvider),
        isFalse,
      );
    });

    test('accessPolicyProvider síncrono começa no padrão seguro', () {
      final c = container(null);
      expect(
        c.read(accessPolicyProvider),
        const AccessPolicy.safeDefault(termsMinAge: 18),
      );
    });

    test(
      'repositório que viola o contrato e lança: o síncrono segue seguro',
      () async {
        final c = ProviderContainer(
          overrides: [
            runtimeConfigRepositoryProvider.overrideWithValue(
              _ThrowingConfig(),
            ),
          ],
        );
        addTearDown(c.dispose);
        await c
            .read(accessPolicyAsyncProvider.future)
            .then((_) {}, onError: (_) {});
        expect(
          c.read(accessPolicyProvider),
          const AccessPolicy.safeDefault(termsMinAge: 18),
        );
      },
    );
  });

  group('CA-T10: runtime sem rede cai no padrão seguro sem lançar', () {
    test('get() lança', () async {
      final repo = FirestoreRuntimeConfig(
        db: _FakeDb(() => Future.error(StateError('sem rede'))),
      );
      expect(await repo.load(), isNull);
      expect(
        _from(await repo.load()),
        const AccessPolicy.safeDefault(termsMinAge: 18),
      );
    });

    test('collection() lança de forma síncrona', () async {
      final repo = FirestoreRuntimeConfig(db: _ThrowingDb());
      expect(await repo.load(), isNull);
    });

    test('get() pendurado estoura o timeout e devolve null', () async {
      final never = Completer<_Snap>();
      final repo = FirestoreRuntimeConfig(
        db: _FakeDb(() => never.future),
        timeout: const Duration(milliseconds: 20),
      );
      expect(await repo.load(), isNull);
    });

    test('permission-denied vira null', () async {
      final repo = FirestoreRuntimeConfig(
        db: _FakeDb(
          () => Future.error(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          ),
        ),
      );
      expect(await repo.load(), isNull);
    });

    test('documento inexistente vira null; existente é lido', () async {
      expect(
        await FirestoreRuntimeConfig(db: _FakeDb(() async => _FakeSnap(null)))
            .load(),
        isNull,
      );
      final data = await FirestoreRuntimeConfig(
        db: _FakeDb(() async => _FakeSnap({'minAge': 21})),
      ).load();
      expect(_from(data).minAge, 21);
    });

    test('timeout padrão é de 4 s', () {
      expect(
        FirestoreRuntimeConfig(db: _ThrowingDb()).timeout,
        const Duration(seconds: 4),
      );
    });
  });

  group('IA simulada: falhas', () {
    final file = ImportFile(
      name: 'p.png',
      mimeType: 'image/png',
      bytes: Uint8List(0),
    );

    for (final f in AiFailure.values) {
      test('extrator com ${f.name}: "on AiException" captura', () async {
        final ex = FakeQuestionExtractor(failure: f);
        AiFailure? caught;
        try {
          await ex.extract(file);
        } on AiException catch (e) {
          caught = e.failure;
        }
        expect(caught, f);
        expect(ex.calls, 1);
      });
    }

    test('falha não deixa estado quebrado', () async {
      final ok = FakeQuestionExtractor();
      await ok.extract(file);
      await ok.extract(file);
      expect(ok.calls, 2);
    });
  });
}
