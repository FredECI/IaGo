import 'package:material_ui/material_ui.dart';

import '../domain/area.dart';

/// Tokens de cor do IaGo. Sem o deck oficial, a identidade parte de um índigo
/// (foco, confiança) com destaque âmbar; trocar aqui muda o app inteiro.
abstract final class AppColors {
  static const Color seed = Color(0xFF4F46E5);

  /// Degradê fixo do logotipo (igual nos temas claro e escuro).
  static const List<Color> brandGradient = [
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
  ];

  /// Selo "Beta 0.1" em âmbar, com texto escuro (contraste alto nos 2 temas).
  static Color betaBackground(Brightness b) =>
      b == Brightness.light ? const Color(0xFFFDE68A) : const Color(0xFFF59E0B);

  static const Color betaForeground = Color(0xFF451A03);

  /// Cor de cada área: fundo de ícone com branco por cima (contraste ≥ 4,5:1).
  static Color area(Area area) => switch (area) {
    Area.languages => const Color(0xFFAD1457),
    Area.humanities => const Color(0xFF9C5700),
    Area.naturalSciences => const Color(0xFF2E7D32),
    Area.mathematics => const Color(0xFF1565C0),
  };
}

abstract final class AppIcons {
  static IconData area(Area area) => switch (area) {
    Area.languages => Icons.translate,
    Area.humanities => Icons.public,
    Area.naturalSciences => Icons.science_outlined,
    Area.mathematics => Icons.calculate_outlined,
  };
}

abstract final class AppTheme {
  /// Fonte embutida (funciona offline e é a mesma do PDF).
  static const String fontFamily = 'Inter';

  static final ThemeData light = _build(Brightness.light);

  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    // "fidelity" mantém o índigo da marca vivo (o padrão dessatura demais).
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    final radius = BorderRadius.circular(14);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 1,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
      ),
    );
  }
}
