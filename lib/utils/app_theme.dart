import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable color themes — all dark-based (keeps contrast + battery/perf
/// characteristics consistent) but each with its own seed color.
enum AppThemeOption { purple, ocean, forest, sunset, crimson, mono }

extension AppThemeOptionX on AppThemeOption {
  String get label {
    switch (this) {
      case AppThemeOption.purple:
        return 'Purple (Default)';
      case AppThemeOption.ocean:
        return 'Ocean Blue';
      case AppThemeOption.forest:
        return 'Forest Green';
      case AppThemeOption.sunset:
        return 'Sunset Orange';
      case AppThemeOption.crimson:
        return 'Crimson Red';
      case AppThemeOption.mono:
        return 'Midnight Mono';
    }
  }

  Color get seed {
    switch (this) {
      case AppThemeOption.purple:
        return const Color(0xFF7C5CFF);
      case AppThemeOption.ocean:
        return const Color(0xFF2DB6FF);
      case AppThemeOption.forest:
        return const Color(0xFF34D399);
      case AppThemeOption.sunset:
        return const Color(0xFFFF7B54);
      case AppThemeOption.crimson:
        return const Color(0xFFFF4D6D);
      case AppThemeOption.mono:
        return const Color(0xFF9CA3AF);
    }
  }

  static AppThemeOption fromName(String? name) {
    return AppThemeOption.values.firstWhere(
      (o) => o.name == name,
      orElse: () => AppThemeOption.purple,
    );
  }
}

/// Font catalogs — kept separate on purpose: the UI font (menus, dialogs,
/// file names) is a regular proportional font, while the editor font MUST
/// be monospace so code columns/line numbers stay aligned. Both are Google
/// Fonts family names, resolved at runtime via [GoogleFonts.getFont] so
/// adding a new option never needs a per-font named method.
class AppFonts {
  AppFonts._();

  static const List<String> uiFontOptions = ['Manrope', 'Inter', 'Poppins', 'Nunito', 'Rubik', 'Roboto'];
  static const String defaultUiFont = 'Manrope';

  static const List<String> editorFontOptions = [
    'JetBrains Mono',
    'Fira Code',
    'Source Code Pro',
    'Roboto Mono',
    'IBM Plex Mono',
    'Space Mono',
  ];
  static const String defaultEditorFont = 'JetBrains Mono';

  /// The editor's own header uses a display font — kept as its own option
  /// list (proportional, not monospace) so it always matches the UI font
  /// catalog's intent even if editor code font differs.
  static const String headerFont = 'Space Grotesk';
}

/// Centralized Material 3 dark theme — high contrast, low-cost "glass" look
/// (no BackdropFilter/blur anywhere so it stays smooth on 3GB RAM devices).
/// Color seed and UI font are both user-selectable from Settings.
class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF0B0B12);

  static ThemeData themeFor(AppThemeOption option, String uiFont) {
    final scheme = ColorScheme.fromSeed(
      seedColor: option.seed,
      brightness: Brightness.dark,
      surface: bg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: GoogleFonts.getTextTheme(uiFont, ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.getFont(
          AppFonts.headerFont,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh.withOpacity(0.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      dividerColor: scheme.outlineVariant.withOpacity(0.3),
    );
  }
}
