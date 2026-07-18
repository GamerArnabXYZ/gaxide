import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_action.dart';

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
}
