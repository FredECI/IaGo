import 'dart:math';

final Random _random = Random.secure();
const String _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Gera um identificador aleatório de 20 caracteres (mesmo formato do Firestore).
String newId() => String.fromCharCodes(
  List<int>.generate(
    20,
    (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ),
);
