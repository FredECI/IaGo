import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase_config.dart';

/// O que aconteceu com o App Check na abertura.
enum AppCheckOutcome {
  /// Ainda não tentou (ou Firebase fora do ar).
  notAttempted,
  active,
  activeDebug,

  /// Emulador: o App Check não é ativado (e o AI Logic não tem emulador).
  skippedEmulator,

  /// Sem chave de site desta plataforma: IA indisponível, resto segue.
  noSiteKey,
  failed;

  bool get isActive => this == active || this == activeDebug;
}

/// Último resultado, lido pelo `FirebaseAiGateway`. Muda só em
/// [activateAppCheck].
AppCheckOutcome lastAppCheckOutcome = AppCheckOutcome.notAttempted;

Future<AppCheckOutcome>? _activation;

@visibleForTesting
void resetAppCheckOutcome() {
  lastAppCheckOutcome = AppCheckOutcome.notAttempted;
  _activation = null;
}

/// Ativação tardia e única: só é chamada quando uma conta real vai usar a IA
/// (nunca na abertura nem na demo). Chamadas seguintes devolvem o mesmo
/// resultado. Nunca lança.
Future<AppCheckOutcome> ensureAppCheckActivated({
  AppCheckActivator? activator,
  bool? isWeb,

  /// Só para testes: no app valem os defines de `FirebaseConfig`.
  String? webSiteKey,
}) {
  final running = _activation;
  if (running != null) return running;
  final future = activateAppCheck(
    isWeb: isWeb ?? kIsWeb,
    usesEmulator: FirebaseConfig.usesEmulator,
    webSiteKey: webSiteKey ?? FirebaseConfig.appCheckWebSiteKey,
    androidSiteKey: FirebaseConfig.appCheckAndroidSiteKey,
    debugToken: FirebaseConfig.appCheckDebugToken,
    activator: activator ?? _activateReal,
  );
  _activation = future;
  // Falha (possivelmente transitória) não fica memoizada: a próxima chamada
  // tenta de novo. Sucesso e resultados definitivos (sem chave, emulador) sim.
  future.then((o) {
    if (o == AppCheckOutcome.failed && identical(_activation, future)) {
      _activation = null;
    }
  });
  return future;
}

/// Qual provedor usar. Decisão pura, só pelas entradas.
sealed class AppCheckPlan {
  const AppCheckPlan();
}

class AppCheckSkip extends AppCheckPlan {
  const AppCheckSkip(this.outcome);
  final AppCheckOutcome outcome;
}

class AppCheckRecaptcha extends AppCheckPlan {
  const AppCheckRecaptcha(this.siteKey);
  final String siteKey;
}

class AppCheckDebug extends AppCheckPlan {
  const AppCheckDebug(this.token);
  final String token;
}

AppCheckPlan planAppCheck({
  required bool isWeb,
  required bool usesEmulator,
  required String webSiteKey,
  required String androidSiteKey,
  required String debugToken,
}) {
  if (usesEmulator) return const AppCheckSkip(AppCheckOutcome.skippedEmulator);
  // O provedor de depuração só existe com o token (CA-T14): sem o define, o
  // build de publicação nunca o ativa.
  if (debugToken.isNotEmpty) return AppCheckDebug(debugToken);
  final key = isWeb ? webSiteKey : androidSiteKey;
  if (key.isEmpty) return const AppCheckSkip(AppCheckOutcome.noSiteKey);
  return AppCheckRecaptcha(key);
}

/// Ativa o provedor escolhido. Injetável nos testes.
typedef AppCheckActivator = Future<void> Function(AppCheckPlan plan);

Future<void> _activateReal(AppCheckPlan plan) async {
  final instance = FirebaseAppCheck.instance;
  switch (plan) {
    case AppCheckDebug(:final token):
      await instance.activate(
        providerWeb: WebDebugProvider(debugToken: token),
        providerAndroid: AndroidDebugProvider(debugToken: token),
      );
    case AppCheckRecaptcha(:final siteKey):
      await instance.activate(
        providerWeb: ReCaptchaEnterpriseProvider(siteKey),
        providerAndroid: AndroidReCaptchaProvider(siteKey),
      );
    case AppCheckSkip():
      return;
  }
  // Sem renovação automática: abas abertas não gastam as avaliações do mês.
  await instance.setTokenAutoRefreshEnabled(false);
}

/// Ativa o App Check depois do `Firebase.initializeApp`. **Nunca lança**: a
/// falha só deixa a IA indisponível; Auth, Firestore e demo seguem.
Future<AppCheckOutcome> activateAppCheck({
  required bool isWeb,
  required bool usesEmulator,
  required String webSiteKey,
  required String androidSiteKey,
  required String debugToken,
  Duration timeout = const Duration(seconds: 5),
  AppCheckActivator activator = _activateReal,
}) async {
  final plan = planAppCheck(
    isWeb: isWeb,
    usesEmulator: usesEmulator,
    webSiteKey: webSiteKey,
    androidSiteKey: androidSiteKey,
    debugToken: debugToken,
  );
  var outcome = switch (plan) {
    AppCheckSkip(:final outcome) => outcome,
    AppCheckDebug() => AppCheckOutcome.activeDebug,
    AppCheckRecaptcha() => AppCheckOutcome.active,
  };
  if (plan is! AppCheckSkip) {
    try {
      await activator(plan).timeout(timeout);
    } catch (_) {
      // Sem detalhes no log: a mensagem poderia ecoar o token.
      outcome = AppCheckOutcome.failed;
    }
  }
  lastAppCheckOutcome = outcome;
  return outcome;
}
