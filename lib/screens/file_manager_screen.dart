import 'package:flutter/material.dart';

import '../services/clipboard_controller.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/file_browser_view.dart';
import 'settings_screen.dart';

/// Home screen — hosts two independent storage tabs (Internal + SD Card,
/// ZArchiver-style), each a self-contained [FileBrowserView]. The app bar,
/// FAB, search/sort/select actions live here and are delegated down to
/// whichever tab is currently active via GlobalKeys.
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _clipboard = ClipboardController();
  final _prefsService = PrefsService();
  final _fileService = FileService();

  final _tab1Key = GlobalKey<FileBrowserViewState>();
  final _tab2Key = GlobalKey<FileBrowserViewState>();

  String _tab1Path = FileService.rootStoragePath;
  String _tab1Label = 'Internal';
  String? _tab2Path;
  String _tab2Label = 'SD Card';

  bool _tabsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadTabConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTabConfig() async {
    final tabs = await _prefsService.loadTabSettings();
    String? resolvedTab2 = tabs.tab2Path.trim().isNotEmpty ? tabs.tab2Path.trim() : null;
    resolvedTab2 ??= await _fileService.detectSecondaryStoragePath();

    if (!mounted) return;
    setState(() {
      _tab1Path = tabs.tab1Path.trim().isNotEmpty ? tabs.tab1Path.trim() : FileService.rootStoragePath;
      _tab1Label = tabs.tab1Label.trim().isNotEmpty ? tabs.tab1Label.trim() : 'Internal';
      _tab2Path = resolvedTab2;
      _tab2Label = tabs.tab2Label.trim().isNotEmpty ? tabs.tab2Label.trim() : 'SD Card';
      _tabsLoading = false;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _loadTabConfig();
    _tab1Key.currentState?.reloadPreferences();
    _tab2Key.currentState?.reloadPreferences();
  }

  GlobalKey<FileBrowserViewState> get _activeKey => _tabController.index == 0 ? _tab1Key : _tab2Key;

  @override
  Widget build(BuildContext context) {
    if (_tabsLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: _activeKey.currentState?.canPopFreely() ?? true,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _activeKey.currentState?.handleBackPress();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GAX IDE'),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => _activeKey.currentState?.toggleSearch(),
            ),
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_rounded),
              onPressed: () => _activeKey.currentState?.goHome(),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'sort':
                    _activeKey.currentState?.showSortSheet();
                    break;
                  case 'select':
                    _activeKey.currentState?.enterSelectionMode();
                    break;
                  case 'settings':
                    _openSettings();
                    break;
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'sort', child: Text('Sort by...')),
                PopupMenuItem(value: 'select', child: Text('Select Files')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.smartphone_rounded, size: 18), text: _tab1Label),
              Tab(icon: const Icon(Icons.sd_card_rounded, size: 18), text: _tab2Label),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            FileBrowserView(
              key: _tab1Key,
              rootPath: _tab1Path,
              tabLabel: _tab1Label,
              clipboard: _clipboard,
              onNavigationChanged: () => setState(() {}),
            ),
            _tab2Path == null ? _buildNoExternalStorage() : FileBrowserView(
              key: _tab2Key,
              rootPath: _tab2Path!,
              tabLabel: _tab2Label,
              clipboard: _clipboard,
              onNavigationChanged: () => setState(() {}),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _activeKey.currentState?.showCreateSheet(),
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  Widget _buildNoExternalStorage() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sd_card_alert_rounded, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('No SD card / external storage detected.', textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'You can set a custom path for this tab in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withOpacity(0.8)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _openSettings, child: const Text('Open Settings')),
          ],
        ),
      ),
    );
  }
}
