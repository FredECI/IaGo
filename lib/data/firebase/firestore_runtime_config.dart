import 'package:cloud_firestore/cloud_firestore.dart';

import '../runtime_config_repository.dart';

/// Lê `appConfig/runtime`, com timeout. Sem rede, sem permissão ou sem o
/// documento, devolve `null` e o padrão seguro da política vale (nunca trava
/// a tela nem lança).
class FirestoreRuntimeConfig implements RuntimeConfigRepository {
  FirestoreRuntimeConfig({
    required this._db,
    this.timeout = const Duration(seconds: 4),
  });

  final FirebaseFirestore _db;
  final Duration timeout;

  @override
  Future<Map<String, Object?>?> load() async {
    try {
      final doc = await _db
          .collection('appConfig')
          .doc('runtime')
          .get()
          .timeout(timeout);
      final data = doc.data();
      return data == null ? null : Map<String, Object?>.of(data);
    } catch (_) {
      return null;
    }
  }
}
