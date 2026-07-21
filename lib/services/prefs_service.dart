import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_action.dart';
import '../utils/app_theme.dart';
import 'file_service.dart';

class GaxConfig {
  final String token;
  const GaxConfig({this.token = ''});
}

/// Per-tab path/label overrides. Empty tab2Path means "auto-detect SD card".
class TabSettings {
  final String tab1Path;
  final String tab1Label;
  final String tab2Path;
  final String tab2Label;
  const TabSettings({
    this.tab1Path = '',
    this.tab1Label = '',
    this.tab2Path = '',
    this.tab2Label = '',
  });
}

/// General File Manager behavior preferences.
class FileManagerPrefs {
  final bool showHiddenFiles;
  final bool confirmBeforeDelete;
  final int defaultSortIndex;
  const FileManagerPrefs({
    this.showHiddenFiles = false,
    this.confirmBeforeDelete = true,
    this.defaultSortIndex = 0,
  });
}

/// Color theme + UI font + editor font, all user-selectable in Settings.
class ThemePrefs {
  final AppThemeOption themeOption;
  final String uiFont;
  final String editorFont;
  const ThemePrefs({
    this.themeOption = AppThemeOption.purple,
    this.uiFont = AppFonts.defaultUiFont,
    this.editorFont = AppFonts.defaultEditorFont,
  });
}

/// Size-based safety thresholds and the GitHub-push ignore list — all
/// customizable in Settings instead of hard-coded.
class PerformancePrefs {
  final List<String> ignoreDirs;
  final int largeFileWarningKb;
  final int highlightLimitKb;
  const PerformancePrefs({
    this.ignoreDirs = FileService.ignoredDirNames,
    this.largeFileWarningKb = 100,
    this.highlightLimitKb = 150,
  });
}

/// All app settings — GitHub token, storage tab config, file manager
/// behavior, editor font size, and quick toolbar layout — autosaved
/// locally via shared_preferences.
class PrefsService {
  static const _kToken = 'gax_pat_token';
  static const _kTab1Path = 'gax_tab1_path';
  static const _kTab1Label = 'gax_tab1_label';
  static const _kTab2Path = 'gax_tab2_path';
  static const _kTab2Label = 'gax_tab2_label';
  static const _kShowHidden = 'gax_show_hidden';
  static const _kConfirmDelete = 'gax_confirm_delete';
  static const _kDefaultSort = 'gax_default_sort';
  static const _kFontSize = 'gax_editor_font_size';
  static const _kQuickToolbar = 'gax_quick_toolbar';
  static const _kWorkplaceShortcuts = 'gax_workplace_shortcuts';
  static const _kThemeOption = 'gax_theme_option';
  static const _kUiFont = 'gax_ui_font';
  static const _kEditorFont = 'gax_editor_font';
  static const _kIgnoreDirs = 'gax_ignore_dirs';
  static const _kLargeFileWarningKb = 'gax_large_file_warning_kb';
  static const _kHighlightLimitKb = 'gax_highlight_limit_kb';
  static const _kSeededSamplesShortcut = 'gax_seeded_samples_shortcut';

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  Future<GaxConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return GaxConfig(token: prefs.getString(_kToken) ?? '');
  }

  Future<void> saveTabSettings(TabSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTab1Path, settings.tab1Path);
    await prefs.setString(_kTab1Label, settings.tab1Label);
    await prefs.setString(_kTab2Path, settings.tab2Path);
    await prefs.setString(_kTab2Label, settings.tab2Label);
  }

  Future<TabSettings> loadTabSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return TabSettings(
      tab1Path: prefs.getString(_kTab1Path) ?? '',
      tab1Label: prefs.getString(_kTab1Label) ?? '',
      tab2Path: prefs.getString(_kTab2Path) ?? '',
      tab2Label: prefs.getString(_kTab2Label) ?? '',
    );
  }

  Future<void> saveFileManagerPrefs(FileManagerPrefs p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowHidden, p.showHiddenFiles);
    await prefs.setBool(_kConfirmDelete, p.confirmBeforeDelete);
    await prefs.setInt(_kDefaultSort, p.defaultSortIndex);
  }

  Future<FileManagerPrefs> loadFileManagerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return FileManagerPrefs(
      showHiddenFiles: prefs.getBool(_kShowHidden) ?? false,
      confirmBeforeDelete: prefs.getBool(_kConfirmDelete) ?? true,
      defaultSortIndex: prefs.getInt(_kDefaultSort) ?? 0,
    );
  }

  /// Remembers the pinch-zoomed editor font size across sessions/files.
  Future<void> saveFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontSize, size);
  }

  Future<double> loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kFontSize) ?? 14.0;
  }

  /// Which quick-insert buttons show above the keyboard, and in what order
  /// (canonical enum order — customized from Settings via checkboxes).
  Future<void> saveQuickToolbar(List<QuickAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQuickToolbar, actions.map((a) => a.name).join(','));
  }

  Future<List<QuickAction>> loadQuickToolbar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQuickToolbar);
    if (raw == null || raw.trim().isEmpty) return QuickActionX.defaultToolbar;

    final names = raw.split(',');
    final result = <QuickAction>[];
    for (final name in names) {
      for (final action in QuickAction.values) {
        if (action.name == name) {
          result.add(action);
          break;
        }
      }
    }
    return result.isEmpty ? QuickActionX.defaultToolbar : result;
  }

  /// Ordered list of absolute folder paths pinned to the Workplace tab.
  /// These are shortcuts only — the real folder always lives at its
  /// original location; nothing is ever copied.
  Future<void> saveWorkplaceShortcuts(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kWorkplaceShortcuts, paths);
  }

  Future<List<String>> loadWorkplaceShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kWorkplaceShortcuts) ?? [];
  }

  Future<void> saveThemePrefs(ThemePrefs p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeOption, p.themeOption.name);
    await prefs.setString(_kUiFont, p.uiFont);
    await prefs.setString(_kEditorFont, p.editorFont);
  }

  Future<ThemePrefs> loadThemePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemePrefs(
      themeOption: AppThemeOptionX.fromName(prefs.getString(_kThemeOption)),
      uiFont: prefs.getString(_kUiFont) ?? AppFonts.defaultUiFont,
      editorFont: prefs.getString(_kEditorFont) ?? AppFonts.defaultEditorFont,
    );
  }

  Future<void> savePerformancePrefs(PerformancePrefs p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kIgnoreDirs, p.ignoreDirs);
    await prefs.setInt(_kLargeFileWarningKb, p.largeFileWarningKb);
    await prefs.setInt(_kHighlightLimitKb, p.highlightLimitKb);
  }

  Future<PerformancePrefs> loadPerformancePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return PerformancePrefs(
      ignoreDirs: prefs.getStringList(_kIgnoreDirs) ?? FileService.ignoredDirNames,
      largeFileWarningKb: prefs.getInt(_kLargeFileWarningKb) ?? 100,
      highlightLimitKb: prefs.getInt(_kHighlightLimitKb) ?? 150,
    );
  }

  /// Whether the default "Samples" Workplace shortcut has already been
  /// seeded once. Only ever seeded on first run — if the user removes it,
  /// it must NOT come back on the next launch, so this flag is set
  /// regardless of whether the user keeps or deletes the shortcut.
  Future<bool> hasSeededSamplesShortcut() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeededSamplesShortcut) ?? false;
  }

  Future<void> setSeededSamplesShortcut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeededSamplesShortcut, true);
  }
}
