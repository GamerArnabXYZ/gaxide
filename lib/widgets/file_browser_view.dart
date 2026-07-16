import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../models/sort_mode.dart';
import '../services/clipboard_controller.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/repo_push_dialog.dart';
import '../screens/editor_screen.dart';

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

  const FileBrowserView({
    super.key,
    required this.rootPath,
    required this.tabLabel,
    required this.clipboard,
    this.onNavigationChanged,
  });

  @override
  State<FileBrowserView> createState() => FileBrowserViewState();
}

class FileBrowserViewState extends State<FileBrowserView> {
  final _fileService = FileService();
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
    await _loadDirectory(_currentPath);
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
    _loadDirectory(_currentPath);
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

  bool get _atRoot => _currentPath == widget.rootPath;
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

  void goHome() => _loadDirectory(widget.rootPath);

  void enterSelectionMode() {
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

  // ---------------- Open in Editor ----------------

  Future<void> _openInEditor(FileEntry entry) async {
    try {
      final content = await _fileService.readFileAsString(entry.path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditorScreen(filePath: entry.path, initialContent: content)),
      );
      if (mounted) _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Could not open: $e')));
      }
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
            if (entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF16A34A)),
                title: const Text('Push to GitHub'),
                subtitle: const Text('Commits every file in this folder'),
                onTap: () => Navigator.pop(ctx, 'push'),
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
        case 'push':
          await showRepoPushDialog(context, folderPath: entry.path);
          break;
        case 'select':
          setState(() {
            _selectionModeActive = true;
            _selectedPaths.add(entry.path);
          });
          widget.onNavigationChanged?.call();
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
}
