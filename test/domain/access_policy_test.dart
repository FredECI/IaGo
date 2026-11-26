import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/data/ai/fake_ai.dart';
import 'package:iago/data/local/memory_runtime_config.dart';
import 'package:iago/domain/access_policy.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/domain/direction_models.dart';

const _gemini = AiProviderInfo(name: 'Gemini', minUserAge: 18);

AccessPolicy _from(Map<String, Object?>? data) =>
    AccessPolicy.fromRuntime(data, termsMinAge: AppInfo.termsMinAge);

void main() {
  group('fromRuntime: padrão seguro', () {
    for (final data in <Map<String, Object?>?>[null, <String, Object?>{}]) {
      test('documento ${data == null ? 'ausente' : 'vazio'}', () {
        final p = _from(data);
        expect(p.minAge, AppInfo.termsMinAge);
        expect(p.inviteRequired, isTrue);
        expect(p.aiEnabled, isFalse);
        expect(p.conectaEnabled, isFalse);
        expect(p.conectaWritesEnabled, isFalse);
        expect(p.aiModel, defaultAiModel);
        expect(p.aiDailyPerUser, defaultAiDailyPerUser);
        expect(p, const AccessPolicy.safeDefault(termsMinAge: 18));
      });
    }

    test('tipo errado vale o padrão', () {
      final p = _from({
        'minAge': '21',
        'inviteRequired': 'false',
        'aiEnabled': 1,
        'conectaEnabled': 'true',
        'conectaWritesEnabled': null,
        'aiModel': 7,
        'aiDailyPerUser': 'muitos',
      });
      expect(p.minAge, 18);
      expect(p.inviteRequired, isTrue);
      expect(p.aiEnabled, isFalse);
      expect(p.conectaEnabled, isFalse);
      expect(p.conectaWritesEnabled, isFalse);
      expect(p.aiModel, defaultAiModel);
      expect(p.aiDailyPerUser, defaultAiDailyPerUser);
    });

    test('minAge só sobe: abaixo ou igual aos termos vale a dos termos', () {
      expect(_from({'minAge': 13}).minAge, 18);
      expect(_from({'minAge': 0}).minAge, 18);
      expect(_from({'minAge': -5}).minAge, 18);
      expect(_from({'minAge': 18}).minAge, 18);
      expect(_from({'minAge': 21}).minAge, 21);
      expect(_from({'minAge': 21.5}).minAge, 18);
    });

    test('valores válidos são lidos', () {
      final p = _from({
        'inviteRequired': false,
        'aiEnabled': true,
        'conectaEnabled': true,
        'conectaWritesEnabled': true,
        'aiModel': ' outro-modelo ',
        'aiDailyPerUser': 5,
      });
      expect(p.inviteRequired, isFalse);
      expect(p.aiEnabled, isTrue);
      expect(p.conectaEnabled, isTrue);
      expect(p.conectaWritesEnabled, isTrue);
      expect(p.aiModel, 'outro-modelo');
      expect(p.aiDailyPerUser, 5);
    });

    test('aiDailyPerUser zero ou negativo vale o padrão', () {
      expect(_from({'aiDailyPerUser': 0}).aiDailyPerUser, 12);
      expect(_from({'aiDailyPerUser': -1}).aiDailyPerUser, 12);
    });
  });

  group('acceptsDeclaredAge', () {
    test('compara com minAge', () {
      final p = _from(null);
      expect(p.acceptsDeclaredAge(17), isFalse);
      expect(p.acceptsDeclaredAge(18), isTrue);
      expect(p.acceptsDeclaredAge(30), isTrue);
    });
  });

  group('canUseAi', () {
    test('exige IA ligada e membro', () {
      final on = _from({'aiEnabled': true});
      expect(on.canUseAi(isMember: true, provider: _gemini), isTrue);
      expect(on.canUseAi(isMember: false, provider: _gemini), isFalse);
      expect(_from(null).canUseAi(isMember: true, provider: _gemini), isFalse);
    });

    test('respeita a idade mínima do provedor (CA-R5)', () {
      final p = _from({'aiEnabled': true});
      const strict = AiProviderInfo(name: 'Outro', minUserAge: 21);
      const open = AiProviderInfo(name: 'Aberto', minUserAge: 13);
      expect(p.canUseAi(isMember: true, provider: strict), isFalse);
      expect(p.canUseAi(isMember: true, provider: open), isTrue);
    });

    test('termos abaixo do provedor bloqueiam, mesmo com minAge alto', () {
      const p = AccessPolicy(termsMinAge: 16, minAge: 21, aiEnabled: true);
      expect(p.canUseAi(isMember: true, provider: _gemini), isFalse);
    });

    test('minAge abaixo do provedor bloqueia, mesmo com termos altos', () {
      const p = AccessPolicy(termsMinAge: 18, minAge: 18, aiEnabled: true);
      const strict = AiProviderInfo(name: 'X', minUserAge: 19);
      expect(p.canUseAi(isMember: true, provider: strict), isFalse);
    });
  });

  group('canSeeConecta', () {
    test('demo vê o simulado; conta exige flag e membro', () {
      final off = _from(null);
      expect(off.canSeeConecta(isDemo: true, isMember: false), isTrue);
      expect(off.canSeeConecta(isDemo: false, isMember: true), isFalse);
      final on = _from({'conectaEnabled': true});
      expect(on.canSeeConecta(isDemo: false, isMember: true), isTrue);
      expect(on.canSeeConecta(isDemo: false, isMember: false), isFalse);
    });
  });

  // CA-R1: mudar a política muda o comportamento sem tocar em tela. As
  // perguntas abaixo são as únicas que a interface faz.
  group('CA-R1: configuração muda o comportamento', () {
    test('minAge 21 recusa quem declara 18 e aceita 21', () async {
      final repo = MemoryRuntimeConfig({});
      var p = _from(await repo.load());
      expect(p.acceptsDeclaredAge(18), isTrue);
      repo.data = {'minAge': 21};
      p = _from(await repo.load());
      expect(p.acceptsDeclaredAge(18), isFalse);
      expect(p.acceptsDeclaredAge(21), isTrue);
    });

    test('convite desligado no runtime', () async {
      final repo = MemoryRuntimeConfig({});
      expect(_from(await repo.load()).inviteRequired, isTrue);
      repo.data = {'inviteRequired': false};
      expect(_from(await repo.load()).inviteRequired, isFalse);
    });

    test('IA desligada no runtime bloqueia a IA', () async {
      final repo = MemoryRuntimeConfig({'aiEnabled': true});
      expect(
        _from(await repo.load()).canUseAi(isMember: true, provider: _gemini),
        isTrue,
      );
      repo.data = {'aiEnabled': false};
      expect(
        _from(await repo.load()).canUseAi(isMember: true, provider: _gemini),
        isFalse,
      );
    });

    test('Conecta liga e desliga pelo runtime', () async {
      final repo = MemoryRuntimeConfig({'conectaEnabled': true});
      expect(
        _from(await repo.load()).canSeeConecta(isDemo: false, isMember: true),
        isTrue,
      );
      repo.data = null;
      expect(
        _from(await repo.load()).canSeeConecta(isDemo: false, isMember: true),
        isFalse,
      );
    });
  });

  test('termsMinAge do app confere com termsMinAge() das regras (CA-R6)', () {
    final rules = File('firestore.rules').readAsStringSync();
    final m = RegExp(r'function termsMinAge\(\)\s*\{\s*return\s+(\d+);')
        .firstMatch(rules);
    expect(m, isNotNull);
    expect(int.parse(m!.group(1)!), AppInfo.termsMinAge);
  });

  group('IA simulada', () {
    final file = ImportFile(
      name: 'p.png',
      mimeType: 'image/png',
      bytes: Uint8List(0),
    );

    test('extrator devolve exemplo pelo contrato', () async {
      final r = await FakeQuestionExtractor().extract(file);
      expect(r.questions, hasLength(2));
      expect(r.partial, isFalse);
    });

    test('extrator lança a falha pedida e resposta ruim vira malformed', () {
      expect(
        FakeQuestionExtractor(failure: AiFailure.quotaExhausted).extract(file),
        throwsA(
          isA<AiException>().having(
            (e) => e.failure,
            'failure',
            AiFailure.quotaExhausted,
          ),
        ),
      );
      expect(
        FakeQuestionExtractor(rawResponse: 'nada').extract(file),
        throwsA(
          isA<AiException>().having(
            (e) => e.failure,
            'failure',
            AiFailure.malformed,
          ),
        ),
      );
    });

    test('proponente usa o planejador e lança a falha pedida', () async {
      final ctx = DirectionContext(
        today: DateTime(2026, 11, 8),
        goal: const GoalSummary(exam: ExamTarget.enem, weeklyHours: 6),
        coverage: const [],
      );
      expect(await FakeStepProposer().propose(ctx), isNotEmpty);
      expect(
        FakeStepProposer(failure: AiFailure.offline).propose(ctx),
        throwsA(
          isA<AiException>().having(
            (e) => e.failure,
            'failure',
            AiFailure.offline,
          ),
        ),
      );
    });
  });
}
