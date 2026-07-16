import 'package:flutter/material.dart';

import '../models/sort_mode.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';

/// One settings screen for everything — GitHub access, per-tab storage
/// paths, and general file manager behavior (ZArchiver-style preferences).
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

  bool _showHidden = false;
  bool _confirmDelete = true;
  SortMode _defaultSort = SortMode.nameAsc;

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
    _detectedSdPath = await _fileService.detectSecondaryStoragePath();

    if (!mounted) return;
    _tokenController.text = config.token;
    _tab1LabelController.text = tabs.tab1Label;
    _tab1PathController.text = tabs.tab1Path;
    _tab2LabelController.text = tabs.tab2Label;
    _tab2PathController.text = tabs.tab2Path;

    setState(() {
      _showHidden = fmPrefs.showHiddenFiles;
      _confirmDelete = fmPrefs.confirmBeforeDelete;
      _defaultSort = SortMode.values[fmPrefs.defaultSortIndex];
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
                  Text('Tab 1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab1LabelController,
                    onChanged: _persistTabs,
                    decoration: const InputDecoration(labelText: 'Label', hintText: 'Internal'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tab1PathController,
                    onChanged: _persistTabs,
                    decoration: InputDecoration(labelText: 'Path', hintText: FileService.rootStoragePath),
                  ),
                  const Divider(height: 32),
                  Text('Tab 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary)),
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
