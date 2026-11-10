import 'dart:async';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/gemini/ai_error_translation.dart';
import 'package:iago/domain/ai_ports.dart';
import 'package:iago/features/import/import_models.dart';

void main() {
  group('QA F5b: tradução de erros (bordas)', () {
    final cases = <String, (Object, AiFailure)>{
      '500 explícito': (
        ServerException('[500] Internal error encountered.'),
        AiFailure.unavailable,
      ),
      'rede indisponível': (
        const SocketException('Network is unreachable'),
        AiFailure.offline,
      ),
      'host lookup': (
        const SocketException(
          'Failed host lookup: firebasevertexai.googleapis.com',
        ),
        AiFailure.offline,
      ),
      'timeout de socket': (
        TimeoutException('Future not completed'),
        AiFailure.timeout,
      ),
      'maiúsculas': (
        ServerException('RESOURCE_EXHAUSTED'),
        AiFailure.quotaExhausted,
      ),
      'bloqueio sem a palavra safety': (
        FirebaseAIException('Response was blocked due to prohibited content'),
        AiFailure.blocked,
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(classifyAiError(e.value.$1), e.value.$2));
    }

    test('sem rede com texto "unavailable" ainda é rede', () {
      expect(
        classifyAiError(const SocketException('Network is unavailable')),
        AiFailure.offline,
      );
    });
  });

  group('QA F5b: mensagens em português', () {
    test('uma mensagem distinta por falha, sem jargão técnico', () {
      final seen = <String>{};
      for (final f in AiFailure.values) {
        final m = aiFailureMessage(f);
        expect(m, isNotEmpty);
        expect(m, isNot(contains('Exception')));
        expect(m, isNot(contains('Firebase')));
        expect(seen.add(m), isTrue, reason: 'mensagem repetida em $f');
      }
    });
  });

  group('QA F5b: arquitetura', () {
    test('firebase_ai e firebase_app_check só em lib/data/ai/gemini/', () {
      final bad = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final p = f.path.replaceAll(Platform.pathSeparator, '/');
        if (p.contains('lib/data/ai/gemini/')) continue;
        final text = f.readAsStringSync();
        if (text.contains('package:firebase_ai/') ||
            text.contains('package:firebase_app_check/')) {
          bad.add(p);
        }
      }
      expect(bad, isEmpty);
    });

    test('token de depuração não é impresso nem interpolado', () {
      for (final f in Directory(
        'lib/data/ai/gemini',
      ).listSync().whereType<File>()) {
        final t = f.readAsStringSync();
        expect(t, isNot(contains('print(')));
        expect(t, isNot(contains('debugPrint(')));
        expect(t, isNot(contains(r'$debugToken')));
      }
    });
  });
}
