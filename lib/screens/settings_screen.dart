import 'package:flutter/material.dart';

import '../models/quick_action.dart';
import '../models/sort_mode.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../services/theme_controller.dart';
import '../utils/app_theme.dart';

/// One settings screen for everything — GitHub access, per-tab storage
/// paths, general file manager behavior, appearance (theme/fonts), and
/// performance/safety thresholds (all ZArchiver-style preferences).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _prefsService = PrefsService();
  final _fileService = FileService();

  final _tokenController = TextEditingController();
  final _tab1LabelController = TextEditingController();
  final _tab1PathController = TextEditingController();
  final _tab2LabelController = TextEditingController();
  final _tab2PathController = TextEditingController();
  final _quickToolbarController = TextEditingController();
  final _ignoreDirsController = TextEditingController();
  final _largeFileWarningController = TextEditingController();
  final _highlightLimitController = TextEditingController();
  final _codeRunApiKeyController = TextEditingController();

  bool _showHidden = false;
  bool _confirmDelete = true;
  SortMode _defaultSort = SortMode.nameAsc;

  AppThemeOption _themeOption = AppThemeOption.purple;
  String _uiFont = AppFonts.defaultUiFont;
  String _editorFont = AppFonts.defaultEditorFont;

  bool _loading = true;
  String? _detectedSdPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _prefsService.loadConfig();
    final tabs = await _prefsService.loadTabSettings();
    final fmPrefs = await _prefsService.loadFileManagerPrefs();
    final quickActions = await _prefsService.loadQuickToolbar();
    final themePrefs = await _prefsService.loadThemePrefs();
    final perfPrefs = await _prefsService.loadPerformancePrefs();
    _detectedSdPath = await _fileService.detectSecondaryStoragePath();

    if (!mounted) return;
    _tokenController.text = config.token;
    _tab1LabelController.text = tabs.tab1Label;
    _tab1PathController.text = tabs.tab1Path;
    _tab2LabelController.text = tabs.tab2Label;
    _tab2PathController.text = tabs.tab2Path;
    _quickToolbarController.text = QuickActionX.toInputString(quickActions);
    _ignoreDirsController.text = perfPrefs.ignoreDirs.join(' ');
    _largeFileWarningController.text = perfPrefs.largeFileWarningKb.toString();
    _highlightLimitController.text = perfPrefs.highlightLimitKb.toString();
    _codeRunApiKeyController.text = perfPrefs.codeRunApiKey;

    setState(() {
      _showHidden = fmPrefs.showHiddenFiles;
      _confirmDelete = fmPrefs.confirmBeforeDelete;
      _defaultSort = SortMode.values[fmPrefs.defaultSortIndex];
      _themeOption = themePrefs.themeOption;
      _uiFont = themePrefs.uiFont;
      _editorFont = themePrefs.editorFont;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _tab1LabelController.dispose();
    _tab1PathController.dispose();
    _tab2LabelController.dispose();
    _tab2PathController.dispose();
    _quickToolbarController.dispose();
    _ignoreDirsController.dispose();
    _largeFileWarningController.dispose();
    _highlightLimitController.dispose();
    _codeRunApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _persistToken([String? _]) => _prefsService.saveToken(_tokenController.text.trim());

  Future<void> _persistTabs([String? _]) => _prefsService.saveTabSettings(TabSettings(
        tab1Path: _tab1PathController.text.trim(),
        tab1Label: _tab1LabelController.text.trim(),
        tab2Path: _tab2PathController.text.trim(),
        tab2Label: _tab2LabelController.text.trim(),
      ));

  Future<void> _persistFmPrefs() => _prefsService.saveFileManagerPrefs(FileManagerPrefs(
        showHiddenFiles: _showHidden,
        confirmBeforeDelete: _confirmDelete,
        defaultSortIndex: _defaultSort.index,
      ));

  Future<void> _persistQuickToolbar([String? _]) {
    final parsed = QuickActionX.parseFromInput(_quickToolbarController.text);
    return _prefsService.saveQuickToolbar(parsed);
  }

  Future<void> _persistTheme(AppThemeOption option) async {
    setState(() => _themeOption = option);
    await ThemeController.instance.setThemeOption(option);
  }

  Future<void> _persistUiFont(String font) async {
    setState(() => _uiFont = font);
    await ThemeController.instance.setUiFont(font);
  }

  Future<void> _persistEditorFont(String font) async {
    setState(() => _editorFont = font);
    await ThemeController.instance.setEditorFont(font);
  }

  Future<void> _persistPerformancePrefs([String? _]) {
    final ignoreDirs =
        _ignoreDirsController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final largeFileKb = int.tryParse(_largeFileWarningController.text.trim()) ?? 100;
    final highlightKb = int.tryParse(_highlightLimitController.text.trim()) ?? 150;
    return _prefsService.savePerformancePrefs(PerformancePrefs(
      ignoreDirs: ignoreDirs.isEmpty ? FileService.ignoredDirNames : ignoreDirs,
      largeFileWarningKb: largeFileKb < 1 ? 100 : largeFileKb,
      highlightLimitKb: highlightKb < 1 ? 150 : highlightKb,
      codeRunApiKey: _codeRunApiKeyController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _sectionHeader('Appearance'),
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<AppThemeOption>(
                    value: _themeOption,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: AppThemeOption.values
                        .map((o) => DropdownMenuItem(value: o, child: Text(o.label)))
                        .toList(),
                    onChanged: (o) {
                      if (o != null) _persistTheme(o);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _uiFont,
                    decoration: const InputDecoration(labelText: 'UI Font (menus, file names)'),
                    items: AppFonts.uiFontOptions
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (f) {
                      if (f != null) _persistUiFont(f);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _editorFont,
                    decoration: const InputDecoration(labelText: 'Editor Font (code)'),
                    items: AppFonts.editorFontOptions
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (f) {
                      if (f != null) _persistEditorFont(f);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The editor font is always monospace, so code stays aligned.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            _sectionHeader('GitHub'),
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    onChanged: _persistToken,
                    decoration: const InputDecoration(
                      labelText: 'Personal Access Token (PAT)',
                      prefixIcon: Icon(Icons.key_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Repo name & branch are auto-detected from each project\'s own .git folder — '
                    'nothing else to configure per project.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            _sectionHeader('Storage Tabs'),
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmark_rounded, size: 16, color: scheme.onSurfaceVariant.withOpacity(0.7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tab 1 is always "Workplace" — a shortcuts collection, not a real folder. Not editable.',
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text('Tab 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab1LabelController,
                    onChanged: _persistTabs,
                    decoration: const InputDecoration(labelText: 'Label', hintText: 'Storage'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab1PathController,
                    onChanged: _persistTabs,
                    decoration: InputDecoration(labelText: 'Path', hintText: FileService.rootStoragePath),
                  ),
                  const Divider(height: 32),
                  Text('Tab 3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab2LabelController,
                    onChanged: _persistTabs,
                    decoration: const InputDecoration(labelText: 'Label', hintText: 'SD Card'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab2PathController,
                    onChanged: _persistTabs,
                    decoration: InputDecoration(
                      labelText: 'Path (blank = auto-detect)',
                      hintText: _detectedSdPath ?? 'No SD card detected',
                      suffixIcon: _detectedSdPath == null
                          ? null
                          : IconButton(
                              tooltip: 'Use detected SD card',
                              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                              onPressed: () {
                                _tab2PathController.text = _detectedSdPath!;
                                _persistTabs();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Changes apply the next time you open a tab.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            _sectionHeader('File Manager'),
            _card(
              scheme,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Hidden Files'),
                    subtitle: const Text('Files & folders starting with a dot'),
                    value: _showHidden,
                    onChanged: (v) {
                      setState(() => _showHidden = v);
                      _persistFmPrefs();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Confirm Before Delete'),
                    value: _confirmDelete,
                    onChanged: (v) {
                      setState(() => _confirmDelete = v);
                      _persistFmPrefs();
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SortMode>(
                    value: _defaultSort,
                    decoration: const InputDecoration(labelText: 'Default Sort Order'),
                    items: SortMode.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label))).toList(),
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => _defaultSort = m);
                      _persistFmPrefs();
                    },
                  ),
                ],
              ),
            ),
            _sectionHeader('Performance & Safety'),
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _largeFileWarningController,
                          keyboardType: TextInputType.number,
                          onChanged: _persistPerformancePrefs,
                          decoration: const InputDecoration(labelText: 'Large-file warning (KB)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _highlightLimitController,
                          keyboardType: TextInputType.number,
                          onChanged: _persistPerformancePrefs,
                          decoration: const InputDecoration(labelText: 'Highlighting limit (KB)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Files bigger than the first number show a "may take a while" prompt before '
                    'opening. Files bigger than the second have syntax highlighting turned off '
                    'automatically so they stay smooth.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                  const Divider(height: 28),
                  Text('Code-Run Service (OnlineCompiler.io)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 8),
                  Text(
                    'Python, C++, Java, C#, F#, PHP, Ruby, Haskell, Go, Rust, and TypeScript run '
                    'via OnlineCompiler.io using a built-in key. If you have your own account, '
                    'enter its API key here to use it instead.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _codeRunApiKeyController,
                    onChanged: _persistPerformancePrefs,
                    obscureText: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Custom API key (optional)',
                      hintText: 'Leave blank to use the built-in key',
                    ),
                  ),
                  const Divider(height: 28),
                  Text('Ignored Folders (GitHub Push)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 8),
                  Text(
                    'Type folder names to skip when pushing, separated by spaces.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ignoreDirsController,
                    onChanged: _persistPerformancePrefs,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Ignored folder names',
                      hintText: '.git node_modules build .gradle',
                      suffixIcon: IconButton(
                        tooltip: 'Reset to default',
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        onPressed: () {
                          _ignoreDirsController.text = FileService.ignoredDirNames.join(' ');
                          _persistPerformancePrefs();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _sectionHeader('Quick Toolbar'),
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type the buttons you want, separated by spaces, in the order you want them.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _quickToolbarController,
                    onChanged: _persistQuickToolbar,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Toolbar buttons',
                      hintText: '{ } ( ) ; = " Undo Redo',
                      suffixIcon: IconButton(
                        tooltip: 'Reset to default',
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        onPressed: () {
                          _quickToolbarController.text = QuickActionX.toInputString(QuickActionX.defaultToolbar);
                          _persistQuickToolbar();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Available: ${QuickActionX.catalogHint}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            _sectionHeader('About'),
            _card(
              scheme,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline_rounded),
                title: Text('GAX IDE'),
                subtitle: Text('v2.0 — Mobile-first IDE with GitHub sync'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
      );

  Widget _card(ColorScheme scheme, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHigh.withOpacity(0.85),
            scheme.surfaceContainer.withOpacity(0.55),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}
