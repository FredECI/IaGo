import 'package:cloud_firestore/cloud_firestore.dart';

/// Converte o mapa do domínio (datas como [DateTime]) para o Firestore. O SDK
/// já grava [DateTime] como Timestamp; aqui só tiramos os campos nulos.
Map<String, Object?> toFirestore(Map<String, Object?> map) => {
  for (final entry in map.entries)
    if (entry.value != null) entry.key: entry.value,
};

/// Converte um documento do Firestore para o mapa do domínio.
Map<String, Object?> fromFirestore(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    entry.key: switch (entry.value) {
      final Timestamp t => t.toDate(),
      final Object? other => other,
    },
};

/// Escritas não esperam o servidor por mais que isto: sem internet, o
/// Firestore guarda localmente e sincroniza depois (a tela não trava).
const Duration writeTimeout = Duration(seconds: 4);

Future<void> commitOrQueue(Future<void> write) =>
    write.timeout(writeTimeout, onTimeout: () {});
