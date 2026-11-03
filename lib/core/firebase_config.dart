import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuração do Firebase, injetada na compilação:
///
///     flutter run --dart-define-from-file=env/firebase.json
///
/// O arquivo fica fora do git (veja `env/firebase.example.json`). Sem ele, o
/// app roda só em modo demonstração. `env/emulator.json` aponta para os
/// emuladores locais (projeto `demo-iago`, sem conta nem internet).
abstract final class FirebaseConfig {
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );

  /// Host dos emuladores (ex.: 127.0.0.1). Vazio = Firebase de verdade.
  static const String emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
  );

  static String get appId => kIsWeb ? webAppId : androidAppId;

  static bool get isConfigured =>
      apiKey.isNotEmpty && projectId.isNotEmpty && appId.isNotEmpty;

  static bool get usesEmulator => emulatorHost.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: !kIsWeb && androidApiKey.isNotEmpty ? androidApiKey : apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: kIsWeb && authDomain.isNotEmpty ? authDomain : null,
  );
}
