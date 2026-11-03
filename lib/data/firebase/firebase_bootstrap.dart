import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_config.dart';

/// Estado do Firebase para a tela de entrada.
enum FirebaseStatus {
  /// Sem configuração nesta compilação: só a demonstração.
  notConfigured,

  /// Pronto para cadastro e login.
  ready,

  /// Configurado, mas não respondeu (sem internet, por exemplo).
  unavailable,
}

/// Inicializa o Firebase **sem travar a abertura do app**: a demonstração
/// funciona enquanto isso (e mesmo se falhar). Na web o SDK do Firebase vem
/// de um CDN; sem internet, o resultado é [FirebaseStatus.unavailable].
Future<FirebaseStatus> initFirebase({
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (!FirebaseConfig.isConfigured) return FirebaseStatus.notConfigured;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseConfig.options)
          .timeout(timeout);
      final host = FirebaseConfig.emulatorHost;
      if (host.isNotEmpty) {
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8085);
      }
    }
    return FirebaseStatus.ready;
  } catch (_) {
    return FirebaseStatus.unavailable;
  }
}

/// Resultado da inicialização (o botão "Tentar de novo" invalida este provider).
final firebaseStatusProvider = FutureProvider<FirebaseStatus>(
  (ref) => initFirebase(),
);
