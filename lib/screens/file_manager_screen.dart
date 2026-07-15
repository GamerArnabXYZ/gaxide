import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/repo_push_dialog.dart';
import 'editor_screen.dart';
import 'github_config_screen.dart';

enum _SortMode { nameAsc, nameDesc, dateNewest, dateOldest, sizeLargest, sizeSmallest }

/// Home screen — a full ZArchiver/ES-style file manager: browse, search,
/// sort, multi-select (cut/copy/paste/delete), create files/folders via
/// FAB, open files in the code editor, and push a whole git-repo folder to
/// GitHub in one atomic commit. Push only ever appears on folders that
/// contain a `.git` — plain files/folders never show it.
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final _fileService = FileService();

  String _currentPath = FileService.rootStoragePath;
  List<FileEntry> _allEntries = [];
  bool _loading = true;
  bool _permissionDenied = false;

  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  _SortMode _sortMode = _SortMode.nameAsc;

  bool _selectionModeActive = false;
  final Set<String> _selectedPaths = {};

  List<FileEntry>? _clipboardEntries;
  bool _clipboardIsCut = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final granted = await _fileService.ensureStoragePermission();
    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }
    await _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _loading = true);
    try {
      final entries = await _fileService.listDirectory(path);
      setState(() {
        _currentPath = path;
        _allEntries = entries;
        _loading = false;
        _permissionDenied = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Cannot open this folder: $e')));
      }
    }
  }

  bool get _atRoot => _currentPath == FileService.rootStoragePath;
  String get _folderTitle => _atRoot ? 'GAX IDE' : _currentPath.split('/').last;

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
        case _SortMode.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case _SortMode.dateNewest:
          return b.modified.compareTo(a.modified);
        case _SortMode.dateOldest:
          return a.modified.compareTo(b.modified);
        case _SortMode.sizeLargest:
          return b.sizeBytes.compareTo(a.sizeBytes);
        case _SortMode.sizeSmallest:
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

  void _showCreateSheet() {
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
          ],
        ),
      ),
    );
  }

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

  Future<void> _deleteEntry(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('"${entry.name}" will be permanently deleted.'),
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
    if (confirmed == true) {
      try {
        await _fileService.delete(entry.path, entry.isDirectory);
        await _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  // ---------------- Multi-select: cut / copy / paste / delete ----------------

  void _cutOrCopySelected({required bool isCut}) {
    final entries = _allEntries.where((e) => _selectedPaths.contains(e.path)).toList();
    setState(() {
      _clipboardEntries = entries;
      _clipboardIsCut = isCut;
      _selectionModeActive = false;
      _selectedPaths.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPaths.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: Text('$count item(s) will be permanently deleted.'),
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
    if (confirmed != true) return;

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
    _loadDirectory(_currentPath);
  }

  Future<void> _pasteClipboard() async {
    final items = _clipboardEntries;
    if (items == null || items.isEmpty) return;
    final isCut = _clipboardIsCut;

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
    setState(() => _clipboardEntries = null);
    _loadDirectory(_currentPath);
  }

  void _cancelClipboard() => setState(() => _clipboardEntries = null);

  // ---------------- Sort sheet ----------------

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('Sort by', style: TextStyle(fontWeight: FontWeight.bold))),
            _sortTile('Name (A-Z)', _SortMode.nameAsc),
            _sortTile('Name (Z-A)', _SortMode.nameDesc),
            _sortTile('Date (Newest)', _SortMode.dateNewest),
            _sortTile('Date (Oldest)', _SortMode.dateOldest),
            _sortTile('Size (Largest)', _SortMode.sizeLargest),
            _sortTile('Size (Smallest)', _SortMode.sizeSmallest),
          ],
        ),
      ),
    );
  }

  Widget _sortTile(String label, _SortMode mode) {
    return ListTile(
      leading: Icon(
        _sortMode == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
        size: 20,
      ),
      title: Text(label),
      onTap: () {
        setState(() => _sortMode = mode);
        Navigator.pop(context);
      },
    );
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
            if (entry.isDirectory && entry.isGitRepo)
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF16A34A)),
                title: const Text('Push to GitHub'),
                subtitle: const Text('Commits every file in this project'),
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

    return PopScope(
      canPop: _atRoot && !_selectionModeActive && !_isSearching,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_selectionModeActive) {
          setState(() {
            _selectionModeActive = false;
            _selectedPaths.clear();
          });
          return;
        }
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          });
          return;
        }
        _navigateUp();
      },
      child: Scaffold(
        appBar: _buildAppBar(scheme),
        body: _buildBody(scheme),
        bottomNavigationBar: _buildClipboardBar(scheme),
        floatingActionButton: (_selectionModeActive || _isSearching)
            ? null
            : FloatingActionButton(onPressed: _showCreateSheet, child: const Icon(Icons.add_rounded)),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme) {
    if (_selectionModeActive) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() {
            _selectionModeActive = false;
            _selectedPaths.clear();
          }),
        ),
        title: Text('${_selectedPaths.length} selected'),
        actions: [
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
      );
    }

    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          }),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search this folder...', border: InputBorder.none),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (!_atRoot) {
            _navigateUp();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
      ),
      title: Text(_folderTitle),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _isSearching = true),
        ),
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_rounded),
          onPressed: () => _loadDirectory(FileService.rootStoragePath),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'sort':
                _showSortSheet();
                break;
              case 'select':
                setState(() => _selectionModeActive = true);
                break;
              case 'settings':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GithubConfigScreen()));
                break;
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'sort', child: Text('Sort by...')),
            PopupMenuItem(value: 'select', child: Text('Select Files')),
            PopupMenuItem(value: 'settings', child: Text('GitHub Settings')),
          ],
        ),
      ],
    );
  }

  Widget? _buildClipboardBar(ColorScheme scheme) {
    if (_clipboardEntries == null || _clipboardEntries!.isEmpty) return null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: scheme.surfaceContainerHigh,
        child: Row(
          children: [
            Icon(_clipboardIsCut ? Icons.content_cut_rounded : Icons.copy_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${_clipboardEntries!.length} item(s) ready to paste')),
            TextButton(onPressed: _cancelClipboard, child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(onPressed: _pasteClipboard, child: const Text('Paste Here')),
          ],
        ),
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
