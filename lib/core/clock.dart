import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relógio injetável: permite testar regras que dependem de "agora".
typedef Clock = DateTime Function();

final clockProvider = Provider<Clock>((ref) => DateTime.now);
