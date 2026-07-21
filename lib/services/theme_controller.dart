import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'prefs_service.dart';

/// Single shared instance — so changing the theme or a font in Settings is
/// picked up immediately by the root MaterialApp, with no app restart.
/// main.dart listens to this via AnimatedBuilder; SettingsScreen calls its
/// setters. Deliberately a plain static singleton (no Provider/Riverpod in
/// this project) to match the rest of the codebase's simple, dependency-free
/// style.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final _prefs = PrefsService();

  AppThemeOption _themeOption = AppThemeOption.purple;
  String _uiFont = AppFonts.defaultUiFont;
  String _editorFont = AppFonts.defaultEditorFont;
  bool _loaded = false;

  AppThemeOption get themeOption => _themeOption;
  String get uiFont => _uiFont;
  String get editorFont => _editorFont;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final saved = await _prefs.loadThemePrefs();
    _themeOption = saved.themeOption;
    _uiFont = saved.uiFont;
    _editorFont = saved.editorFont;
    notifyListeners();
  }

  Future<void> setThemeOption(AppThemeOption option) async {
    _themeOption = option;
    notifyListeners();
    await _persist();
  }

  Future<void> setUiFont(String font) async {
    _uiFont = font;
    notifyListeners();
    await _persist();
  }

  Future<void> setEditorFont(String font) async {
    _editorFont = font;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      _prefs.saveThemePrefs(ThemePrefs(themeOption: _themeOption, uiFont: _uiFont, editorFont: _editorFont));
}
