import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/clipboard_controller.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/file_browser_view.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

/// Home screen — hosts three independent tabs, each a self-contained
/// [FileBrowserView]:
///   0. Workplace — a pinned-shortcuts collection, starts empty, fixed
///      name, not editable from Settings.
///   1. Storage — internal storage root (editable path/label).
///   2. SD Card — external storage, auto-detected or custom (editable).
/// The app bar, FAB, search/sort/select actions live here and are
/// delegated down to whichever tab is currently active via GlobalKeys.
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

  final _workplaceKey = GlobalKey<FileBrowserViewState>();
  final _tab1Key = GlobalKey<FileBrowserViewState>(); // Storage
  final _tab2Key = GlobalKey<FileBrowserViewState>(); // SD Card

  String _tab1Path = FileService.rootStoragePath;
  String _tab1Label = 'Storage';
  String? _tab2Path;
  String _tab2Label = 'SD Card';

  bool _tabsLoading = true;
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
        if (_tabController.index == 0) {
          _workplaceKey.currentState?.reloadShortcuts();
        }
      }
    });
    _loadTabConfig();
    _initSharingIntent();
  }

  /// Handles files opened via "Open with GAX IDE" or shared via "Share"
  /// from another app — both while GAX IDE is already running and on a
  /// cold start.
  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (_) {},
    );
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final file = files.first;
    try {
      final content = await File(file.path).readAsString();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(filePath: file.path, initialContent: content)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Could not open shared file: $e')));
      }
    }
    ReceiveSharingIntent.instance.reset();
  }

  @override
  void dispose() {
    _intentSub?.cancel();
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
      _tab1Label = tabs.tab1Label.trim().isNotEmpty ? tabs.tab1Label.trim() : 'Storage';
      _tab2Path = resolvedTab2;
      _tab2Label = tabs.tab2Label.trim().isNotEmpty ? tabs.tab2Label.trim() : 'SD Card';
      _tabsLoading = false;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _loadTabConfig();
    _workplaceKey.currentState?.reloadPreferences();
    _tab1Key.currentState?.reloadPreferences();
    _tab2Key.currentState?.reloadPreferences();
  }

  GlobalKey<FileBrowserViewState> get _activeKey {
    switch (_tabController.index) {
      case 0:
        return _workplaceKey;
      case 1:
        return _tab1Key;
      default:
        return _tab2Key;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabsLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: _activeKey.currentState?.canPopFreely() ?? true,
      onPopInvokedWithResult: (didPop, result) {
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
              const Tab(icon: Icon(Icons.bookmark_rounded, size: 18), text: 'Workplace'),
              Tab(icon: const Icon(Icons.smartphone_rounded, size: 18), text: _tab1Label),
              Tab(icon: const Icon(Icons.sd_card_rounded, size: 18), text: _tab2Label),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            FileBrowserView(
              key: _workplaceKey,
              rootPath: '',
              tabLabel: 'Workplace',
              clipboard: _clipboard,
              isWorkplaceTab: true,
              onNavigationChanged: () => setState(() {}),
            ),
            FileBrowserView(
              key: _tab1Key,
              rootPath: _tab1Path,
              tabLabel: _tab1Label,
              clipboard: _clipboard,
              onNavigationChanged: () => setState(() {}),
            ),
            _tab2Path == null
                ? _buildNoExternalStorage()
                : FileBrowserView(
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
