import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'bootstrap.dart';

/// Tema escolhido (sistema, claro ou escuro), guardado no aparelho.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPreferencesProvider)?.getString(_key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  void select(ThemeMode mode) {
    state = mode;
    try {
      ref.read(sharedPreferencesProvider)?.setString(_key, mode.name);
    } catch (_) {
      // Sem armazenamento local: o tema vale só nesta sessão.
    }
  }
}
