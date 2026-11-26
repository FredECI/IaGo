import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/data/ai/gemini/app_check_setup.dart';

void main() {
  setUp(resetAppCheckOutcome);

  group('planAppCheck', () {
    AppCheckPlan plan({
      bool isWeb = true,
      bool emulator = false,
      String web = '',
      String android = '',
      String debug = '',
    }) => planAppCheck(
      isWeb: isWeb,
      usesEmulator: emulator,
      webSiteKey: web,
      androidSiteKey: android,
      debugToken: debug,
    );

    test('sem token de depuração nunca escolhe o provedor de depuração', () {
      expect(plan(web: 'k'), isA<AppCheckRecaptcha>());
      expect(plan(isWeb: false, android: 'k'), isA<AppCheckRecaptcha>());
      expect(plan(), isNot(isA<AppCheckDebug>()));
      expect(plan(isWeb: false), isNot(isA<AppCheckDebug>()));
    });

    test('com token usa depuração', () {
      expect(plan(debug: 't', web: 'k'), isA<AppCheckDebug>());
    });

    test('web usa a chave web; Android usa a chave Android', () {
      expect((plan(web: 'W', android: 'A') as AppCheckRecaptcha).siteKey, 'W');
      expect(
        (plan(
          isWeb: false,
          web: 'W',
          android: 'A',
        ) as AppCheckRecaptcha).siteKey,
        'A',
      );
    });

    test('Android sem chave: IA indisponível', () {
      final p = plan(isWeb: false, web: 'W');
      expect((p as AppCheckSkip).outcome, AppCheckOutcome.noSiteKey);
    });

    test('emulador não ativa nada, mesmo com token', () {
      final p = plan(emulator: true, debug: 't', web: 'k');
      expect((p as AppCheckSkip).outcome, AppCheckOutcome.skippedEmulator);
    });
  });

  group('activateAppCheck', () {
    Future<AppCheckOutcome> run({
      String web = 'k',
      String debug = '',
      required AppCheckActivator activator,
      Duration timeout = const Duration(seconds: 1),
    }) => activateAppCheck(
      isWeb: true,
      usesEmulator: false,
      webSiteKey: web,
      androidSiteKey: '',
      debugToken: debug,
      timeout: timeout,
      activator: activator,
    );

    test('sucesso com chave: active', () async {
      AppCheckPlan? used;
      final o = await run(activator: (p) async => used = p);
      expect(o, AppCheckOutcome.active);
      expect(lastAppCheckOutcome.isActive, isTrue);
      expect(used, isA<AppCheckRecaptcha>());
    });

    test('com token: activeDebug e o ativador recebe a depuração', () async {
      AppCheckPlan? used;
      final o = await run(debug: 'tok', activator: (p) async => used = p);
      expect(o, AppCheckOutcome.activeDebug);
      expect(used, isA<AppCheckDebug>());
    });

    test('falha não lança e deixa a IA indisponível', () async {
      final o = await run(
        debug: 'segredo',
        activator: (_) => Future.error(StateError('token segredo inválido')),
      );
      expect(o, AppCheckOutcome.failed);
      expect(lastAppCheckOutcome.isActive, isFalse);
    });

    test('travou: estoura o timeout e segue', () async {
      final o = await run(
        timeout: const Duration(milliseconds: 20),
        activator: (_) => Completer<void>().future,
      );
      expect(o, AppCheckOutcome.failed);
    });

    test('sem chave: não chama o ativador', () async {
      var called = false;
      final o = await run(
        web: '',
        activator: (_) async {
          called = true;
        },
      );
      expect(o, AppCheckOutcome.noSiteKey);
      expect(called, isFalse);
    });
  });

  test('ativação tardia é única e só acontece quando pedida', () async {
    expect(lastAppCheckOutcome, AppCheckOutcome.notAttempted);
    final first = ensureAppCheckActivated();
    final second = ensureAppCheckActivated();
    expect(identical(first, second), isTrue);
    // Sem chaves nesta compilação de teste: IA indisponível, sem lançar.
    expect(await first, AppCheckOutcome.noSiteKey);
  });

  test('falha não fica memoizada: tenta de novo; sucesso fica', () async {
    var calls = 0;
    var fail = true;
    Future<void> activator(AppCheckPlan _) async {
      calls++;
      if (fail) throw StateError('transitória');
    }

    final first = await ensureAppCheckActivated(
      activator: activator,
      isWeb: true,
      webSiteKey: 'k',
    );
    expect(first, AppCheckOutcome.failed);
    fail = false;
    final second = await ensureAppCheckActivated(
      activator: activator,
      isWeb: true,
      webSiteKey: 'k',
    );
    expect(second, AppCheckOutcome.active);
    expect(calls, 2);
    final third = await ensureAppCheckActivated(
      activator: activator,
      isWeb: true,
      webSiteKey: 'k',
    );
    expect(third, AppCheckOutcome.active);
    expect(calls, 2);
  });

  test('esta compilação de teste não tem token de depuração embutido', () {
    // CA-T14: o token só entra pelo define local; aqui ele não existe.
    expect(const String.fromEnvironment('FIREBASE_APPCHECK_DEBUG_TOKEN'), '');
  });
}
