import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/file_entry.dart';
import '../models/sort_mode.dart';
import '../services/archive_service.dart';
import '../services/clipboard_controller.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/file_info_dialog.dart';
import '../widgets/repo_push_dialog.dart';
import '../screens/editor_screen.dart';
import '../screens/image_viewer_screen.dart';

/// One storage tab's worth of file browsing — its own root, its own
/// navigation/search/sort/selection state. The parent (FileManagerScreen)
/// drives search/sort/select/create/back-navigation through this State's
/// public methods via a GlobalKey, since the shared app bar/FAB live above
/// both tabs.
class FileBrowserView extends StatefulWidget {
  final String rootPath;
  final String tabLabel;
  final ClipboardController clipboard;
  final VoidCallback? onNavigationChanged;
  final bool isWorkplaceTab;

  const FileBrowserView({
    super.key,
    required this.rootPath,
    required this.tabLabel,
    required this.clipboard,
    this.onNavigationChanged,
    this.isWorkplaceTab = false,
  });

  @override
  State<FileBrowserView> createState() => FileBrowserViewState();
}

class FileBrowserViewState extends State<FileBrowserView> {
  final _fileService = FileService();
  final _archiveService = ArchiveService();
  final _prefsService = PrefsService();

  late String _currentPath = widget.rootPath;
  List<FileEntry> _allEntries = [];
  bool _loading = true;
  bool _permissionDenied = false;

  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  SortMode _sortMode = SortMode.nameAsc;
  bool _showHidden = false;
  bool _confirmBeforeDelete = true;

  bool _selectionModeActive = false;
  final Set<String> _selectedPaths = {};

  // Workplace-only state: showing the pinned-shortcuts list vs. having
  // drilled into one shortcut's real folder contents.
  bool _atShortcutsList = false;
  String? _activeShortcutRoot;
  List<FileEntry> _shortcutEntries = [];

  @override
  void initState() {
    super.initState();
    widget.clipboard.addListener(_onClipboardChanged);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant FileBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _currentPath = widget.rootPath;
      _loadDirectory(widget.rootPath);
    }
  }

  @override
  void dispose() {
    widget.clipboard.removeListener(_onClipboardChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onClipboardChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final prefs = await _prefsService.loadFileManagerPrefs();
    _sortMode = SortMode.values[prefs.defaultSortIndex];
    _showHidden = prefs.showHiddenFiles;
    _confirmBeforeDelete = prefs.confirmBeforeDelete;

    final granted = await _fileService.ensureStoragePermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _loading = false;
        });
      }
      return;
    }

    if (widget.isWorkplaceTab) {
      await _loadShortcuts();
      if (mounted) {
        setState(() {
          _atShortcutsList = true;
          _loading = false;
        });
      }
      return;
    }

    await _loadDirectory(_currentPath);
  }

  /// Reads the pinned shortcut paths and builds display entries for them.
  /// Shortcuts whose real folder no longer exists (deleted/moved) are
  /// silently pruned from the saved list.
  Future<void> _loadShortcuts() async {
    final paths = await _prefsService.loadWorkplaceShortcuts();
    final entries = <FileEntry>[];
    final stillValid = <String>[];

    for (final path in paths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final stat = await dir.stat();
          final isGit = await Directory('$path/.git').exists();
          entries.add(FileEntry(
            name: path.split('/').last,
            path: path,
            isDirectory: true,
            sizeBytes: 0,
            modified: stat.modified,
            isGitRepo: isGit,
          ));
          stillValid.add(path);
        } catch (_) {
          continue;
        }
      }
    }

    if (stillValid.length != paths.length) {
      await _prefsService.saveWorkplaceShortcuts(stillValid);
    }
    if (mounted) setState(() => _shortcutEntries = entries);
  }

  /// Called by the parent when this tab becomes active, so newly-added
  /// shortcuts (pinned from another tab) show up immediately.
  Future<void> reloadShortcuts() async {
    if (!widget.isWorkplaceTab) return;
    await _loadShortcuts();
  }

  Future<void> _openShortcut(FileEntry entry) async {
    setState(() {
      _atShortcutsList = false;
      _activeShortcutRoot = entry.path;
    });
    await _loadDirectory(entry.path);
  }

  Future<void> _addToWorkplace(FileEntry entry) async {
    final current = await _prefsService.loadWorkplaceShortcuts();
    if (!current.contains(entry.path)) {
      current.add(entry.path);
      await _prefsService.saveWorkplaceShortcuts(current);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📌 Added "${entry.name}" to Workplace')),
      );
    }
  }

  Future<void> _removeFromWorkplace(String path) async {
    final current = await _prefsService.loadWorkplaceShortcuts();
    current.remove(path);
    await _prefsService.saveWorkplaceShortcuts(current);
    await _loadShortcuts();
  }

  /// Re-reads persisted behavior settings (called by the parent after the
  /// user returns from the Settings screen).
  Future<void> reloadPreferences() async {
    final prefs = await _prefsService.loadFileManagerPrefs();
    if (!mounted) return;
    setState(() {
      _sortMode = SortMode.values[prefs.defaultSortIndex];
      _showHidden = prefs.showHiddenFiles;
      _confirmBeforeDelete = prefs.confirmBeforeDelete;
    });
    if (!(widget.isWorkplaceTab && _atShortcutsList)) {
      _loadDirectory(_currentPath);
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _loading = true);
    try {
      final entries = await _fileService.listDirectory(path, showHidden: _showHidden);
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _allEntries = entries;
        _loading = false;
        _permissionDenied = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Cannot open this folder: $e')));
    }
    widget.onNavigationChanged?.call();
  }

  bool get _atRoot => widget.isWorkplaceTab ? _atShortcutsList : _currentPath == widget.rootPath;
  String get _folderTitle => _atRoot ? widget.tabLabel : _currentPath.split('/').last;

  List<FileEntry> get _visibleEntries {
    var list = _allEntries;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    final sorted = [...list];
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (_sortMode) {
        case SortMode.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case SortMode.dateNewest:
          return b.modified.compareTo(a.modified);
        case SortMode.dateOldest:
          return a.modified.compareTo(b.modified);
        case SortMode.sizeLargest:
          return b.sizeBytes.compareTo(a.sizeBytes);
        case SortMode.sizeSmallest:
          return a.sizeBytes.compareTo(b.sizeBytes);
      }
    });
    return sorted;
  }

  void _navigateUp() {
    if (widget.isWorkplaceTab && _currentPath == _activeShortcutRoot) {
      setState(() {
        _atShortcutsList = true;
        _activeShortcutRoot = null;
      });
      widget.onNavigationChanged?.call();
      return;
    }
    if (_atRoot) return;
    final segments = _currentPath.split('/')..removeLast();
    _loadDirectory(segments.join('/'));
  }

  // ---------------- Public API — driven by the parent's shared app bar/FAB ----------------

  bool canPopFreely() => _atRoot && !_isSearching && !_selectionModeActive;

  void handleBackPress() {
    if (_selectionModeActive) {
      setState(() {
        _selectionModeActive = false;
        _selectedPaths.clear();
      });
      widget.onNavigationChanged?.call();
      return;
    }
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _searchController.clear();
      });
      widget.onNavigationChanged?.call();
      return;
    }
    _navigateUp();
  }

  void toggleSearch() {
    setState(() => _isSearching = true);
    widget.onNavigationChanged?.call();
  }

  void goHome() {
    if (widget.isWorkplaceTab) {
      setState(() {
        _atShortcutsList = true;
        _activeShortcutRoot = null;
      });
      widget.onNavigationChanged?.call();
      return;
    }
    _loadDirectory(widget.rootPath);
  }

  void enterSelectionMode() {
    if (widget.isWorkplaceTab && _atShortcutsList) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a shortcut first to select files inside it.')),
      );
      return;
    }
    setState(() => _selectionModeActive = true);
    widget.onNavigationChanged?.call();
  }

  void showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('Sort by', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final mode in SortMode.values) _sortTile(mode),
          ],
        ),
      ),
    );
  }

  Widget _sortTile(SortMode mode) {
    return ListTile(
      leading: Icon(
        _sortMode == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
        size: 20,
      ),
      title: Text(mode.label),
      onTap: () {
        setState(() => _sortMode = mode);
        Navigator.pop(context);
      },
    );
  }

  void showCreateSheet() {
    if (widget.isWorkplaceTab && _atShortcutsList) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a shortcut first to create files inside it.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New File'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF16A34A)),
              title: const Text('Push This Folder to GitHub'),
              subtitle: Text(_folderTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                Navigator.pop(ctx);
                await showRepoPushDialog(context, folderPath: _currentPath);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Open (smart dispatch by file type) ----------------

  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  Future<void> _openInEditor(FileEntry entry) async {
    final ext = entry.extension;

    if (ext == 'zip') {
      await _confirmExtract(entry);
      return;
    }

    if (_imageExtensions.contains(ext)) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewerScreen(filePath: entry.path)),
      );
      return;
    }

    // Try as text/code first; anything that isn't (PDF, video, docx, apk...)
    // falls back to the system's own app via OpenFilex.
    try {
      final content = await _fileService.readFileAsString(entry.path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(filePath: entry.path, initialContent: content)),
      );
      if (mounted) _loadDirectory(_currentPath);
    } catch (_) {
      try {
        final result = await OpenFilex.open(entry.path);
        if (mounted && result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ ${result.message}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Could not open: $e')));
        }
      }
    }
  }

  // ---------------- Archive: extract / compress ----------------

  Future<void> _confirmExtract(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extract Archive?'),
        content: Text('Extract "${entry.name}" into this folder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Extract')),
        ],
      ),
    );
    if (confirmed == true) await _extractZip(entry);
  }

  Future<void> _extractZip(FileEntry entry) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Extracting...')));
    try {
      final destination = await _archiveService.extractZip(entry.path);
      await _loadDirectory(_currentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Extracted to ${destination.split('/').last}/')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Extract failed: $e')));
    }
  }

  Future<void> _compressEntry(FileEntry entry) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Compressing...')));
    try {
      final zipPath = entry.isDirectory
          ? await _archiveService.compressFolder(entry.path)
          : await _archiveService.compressFile(entry.path);
      await _loadDirectory(_currentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Created ${zipPath.split('/').last}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Compress failed: $e')));
    }
  }

  Future<void> _compressSelected() async {
    final entries = _allEntries.where((e) => _selectedPaths.contains(e.path)).toList();
    final paths = entries.map((e) => e.path).toList();
    setState(() {
      _selectionModeActive = false;
      _selectedPaths.clear();
    });
    widget.onNavigationChanged?.call();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Compressing...')));
    try {
      final zipPath = await _archiveService.compressMultiple(paths, _currentPath);
      await _loadDirectory(_currentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Created ${zipPath.split('/').last}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Compress failed: $e')));
    }
  }

  // ---------------- Create ----------------

  Future<void> _createNewFile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'example.js', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final fileName = name.trim();

    try {
      await _fileService.createFile(_currentPath, fileName);
      await _loadDirectory(_currentPath);
      final newPath = '$_currentPath/$fileName';
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditorScreen(filePath: newPath, initialContent: '')),
        );
        if (mounted) _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'my-folder', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        await _fileService.createFolder(_currentPath, controller.text.trim());
        await _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  // ---------------- Rename / Delete (single item) ----------------

  Future<void> _renameEntry(FileEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename')),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        await _fileService.rename(entry.path, entry.isDirectory, controller.text.trim());
        await _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  Future<bool> _confirmIfNeeded(String title, String message) async {
    if (!_confirmBeforeDelete) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteEntry(FileEntry entry) async {
    if (!await _confirmIfNeeded('Delete?', '"${entry.name}" will be permanently deleted.')) return;
    try {
      await _fileService.delete(entry.path, entry.isDirectory);
      await _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  // ---------------- Multi-select: cut / copy / paste / delete ----------------

  void _cutOrCopySelected({required bool isCut}) {
    final entries = _allEntries.where((e) => _selectedPaths.contains(e.path)).toList();
    widget.clipboard.set(entries, isCut);
    setState(() {
      _selectionModeActive = false;
      _selectedPaths.clear();
    });
    widget.onNavigationChanged?.call();
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPaths.length;
    if (!await _confirmIfNeeded('Delete Selected?', '$count item(s) will be permanently deleted.')) return;

    final entries = _allEntries.where((e) => _selectedPaths.contains(e.path)).toList();
    for (final entry in entries) {
      try {
        await _fileService.delete(entry.path, entry.isDirectory);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${entry.name}: $e')));
      }
    }
    setState(() {
      _selectionModeActive = false;
      _selectedPaths.clear();
    });
    widget.onNavigationChanged?.call();
    _loadDirectory(_currentPath);
  }

  Future<void> _pasteClipboard() async {
    final items = widget.clipboard.entries;
    if (items == null || items.isEmpty) return;
    final isCut = widget.clipboard.isCut;

    for (final entry in items) {
      try {
        if (isCut) {
          await _fileService.moveEntry(entry.path, _currentPath, entry.isDirectory);
        } else {
          await _fileService.copyEntry(entry.path, _currentPath, entry.isDirectory);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${entry.name}: $e')));
      }
    }
    widget.clipboard.clear();
    _loadDirectory(_currentPath);
  }

  // ---------------- Per-item action sheet ----------------

  void _showEntryActionSheet(FileEntry entry) {
    if (widget.isWorkplaceTab && _atShortcutsList) {
      _showShortcutActionSheet(entry);
      return;
    }

    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(entry.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded),
              title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Choose an action'),
            ),
            const Divider(height: 1),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.launch_rounded),
                title: const Text('Open in Editor'),
                onTap: () => Navigator.pop(ctx, 'open'),
              ),
            if (entry.extension == 'zip')
              ListTile(
                leading: const Icon(Icons.unarchive_rounded),
                title: const Text('Extract Here'),
                onTap: () => Navigator.pop(ctx, 'extract'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Compress to Zip'),
              onTap: () => Navigator.pop(ctx, 'compress'),
            ),
            if (entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF16A34A)),
                title: const Text('Push to GitHub'),
                subtitle: const Text('Commits every file in this folder'),
                onTap: () => Navigator.pop(ctx, 'push'),
              ),
            if (entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Add to Workplace'),
                onTap: () => Navigator.pop(ctx, 'addToWorkplace'),
              ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('Select'),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Properties'),
              onTap: () => Navigator.pop(ctx, 'properties'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    ).then((action) async {
      switch (action) {
        case 'open':
          _openInEditor(entry);
          break;
        case 'extract':
          await _extractZip(entry);
          break;
        case 'compress':
          await _compressEntry(entry);
          break;
        case 'push':
          await showRepoPushDialog(context, folderPath: entry.path);
          break;
        case 'addToWorkplace':
          await _addToWorkplace(entry);
          break;
        case 'select':
          setState(() {
            _selectionModeActive = true;
            _selectedPaths.add(entry.path);
          });
          widget.onNavigationChanged?.call();
          break;
        case 'properties':
          await showFileInfoDialog(context, entry);
          break;
        case 'rename':
          _renameEntry(entry);
          break;
        case 'delete':
          _deleteEntry(entry);
          break;
      }
    });
  }

  void _showShortcutActionSheet(FileEntry entry) {
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Choose an action'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.launch_rounded),
              title: const Text('Open'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_remove_outlined, color: Colors.redAccent),
              title: const Text('Remove from Workplace'),
              subtitle: const Text('Only unpins the shortcut — the real folder stays untouched'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    ).then((action) async {
      switch (action) {
        case 'open':
          _openShortcut(entry);
          break;
        case 'remove':
          await _removeFromWorkplace(entry.path);
          break;
      }
    });
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildTopBar(scheme),
        Expanded(child: _buildBody(scheme)),
        ListenableBuilder(
          listenable: widget.clipboard,
          builder: (ctx, _) => _buildClipboardBar(scheme),
        ),
      ],
    );
  }

  Widget _buildTopBar(ColorScheme scheme) {
    if (_selectionModeActive) {
      return Material(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _selectionModeActive = false;
                    _selectedPaths.clear();
                  });
                  widget.onNavigationChanged?.call();
                },
              ),
              Expanded(
                child: Text('${_selectedPaths.length} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Cut',
                icon: const Icon(Icons.content_cut_rounded),
                onPressed: _selectedPaths.isEmpty ? null : () => _cutOrCopySelected(isCut: true),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: _selectedPaths.isEmpty ? null : () => _cutOrCopySelected(isCut: false),
              ),
              IconButton(
                tooltip: 'Compress to Zip',
                icon: const Icon(Icons.folder_zip_rounded),
                onPressed: _selectedPaths.isEmpty ? null : _compressSelected,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _selectedPaths.isEmpty ? null : _deleteSelected,
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return Material(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => handleBackPress(),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search this folder...', border: InputBorder.none),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: _atRoot ? null : _navigateUp,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (!_atRoot) ...[
                const Icon(Icons.arrow_upward_rounded, size: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _folderTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipboardBar(ColorScheme scheme) {
    if (!widget.clipboard.hasItems) return const SizedBox.shrink();
    if (widget.isWorkplaceTab && _atShortcutsList) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(widget.clipboard.isCut ? Icons.content_cut_rounded : Icons.copy_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('${widget.clipboard.entries!.length} item(s) ready to paste')),
          TextButton(onPressed: widget.clipboard.clear, child: const Text('Cancel')),
          const SizedBox(width: 4),
          FilledButton(onPressed: _pasteClipboard, child: const Text('Paste Here')),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_rounded, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Storage permission needed to browse files.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final granted = await _fileService.ensureStoragePermission();
                  if (granted) {
                    _loadDirectory(_currentPath);
                  } else {
                    _fileService.openAppSettingsPage();
                  }
                },
                child: const Text('Grant Access'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.isWorkplaceTab && _atShortcutsList) {
      return _buildShortcutsList(scheme);
    }

    final visible = _visibleEntries;

    if (visible.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No matches' : 'Empty folder',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDirectory(_currentPath),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final entry = visible[index];
          final selected = _selectedPaths.contains(entry.path);
          return FileListTile(
            entry: entry,
            isSelectionMode: _selectionModeActive,
            isSelected: selected,
            onTap: () {
              if (_selectionModeActive) {
                setState(() {
                  if (selected) {
                    _selectedPaths.remove(entry.path);
                  } else {
                    _selectedPaths.add(entry.path);
                  }
                });
              } else if (entry.isDirectory) {
                _loadDirectory(entry.path);
              } else {
                _openInEditor(entry);
              }
            },
            onLongPress: () {
              if (_selectionModeActive) return;
              _showEntryActionSheet(entry);
            },
          );
        },
      ),
    );
  }

  Widget _buildShortcutsList(ColorScheme scheme) {
    final query = _searchQuery.toLowerCase();
    final visible = query.isEmpty
        ? _shortcutEntries
        : _shortcutEntries.where((e) => e.name.toLowerCase().contains(query)).toList();

    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border_rounded, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                _shortcutEntries.isEmpty ? 'No shortcuts yet' : 'No matches',
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              if (_shortcutEntries.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Long-press a folder in Storage or SD Card and tap "Add to Workplace".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShortcuts,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final entry = visible[index];
          return FileListTile(
            entry: entry,
            onTap: () => _openShortcut(entry),
            onLongPress: () => _showShortcutActionSheet(entry),
          );
        },
      ),
    );
  }
}
