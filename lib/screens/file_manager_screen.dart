import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/github_push_dialog.dart';
import 'editor_screen.dart';
import 'github_config_screen.dart';

/// Home screen — a full ZArchiver/ES-style file manager: browse, create,
/// rename, delete, and open files directly into the code editor, or push
/// any file straight to GitHub without opening it at all.
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final _fileService = FileService();

  String _currentPath = FileService.rootStoragePath;
  List<FileEntry> _entries = [];
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
        _entries = entries;
        _loading = false;
        _permissionDenied = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Cannot open this folder: $e')),
        );
      }
    }
  }

  bool get _atRoot => _currentPath == FileService.rootStoragePath;

  void _navigateUp() {
    if (_atRoot) return;
    final segments = _currentPath.split('/')..removeLast();
    _loadDirectory(segments.join('/'));
  }

  String get _folderTitle => _atRoot ? 'GAX IDE' : _currentPath.split('/').last;

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

  // ---------------- Create / Rename / Delete ----------------

  Future<void> _showNameDialog({
    required String title,
    required String initialValue,
    required String hint,
    required String confirmLabel,
    required Future<void> Function(String value) onConfirm,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        await onConfirm(controller.text.trim());
        await _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
        }
      }
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      }
    }
  }

  void _createNewFolder() => _showNameDialog(
        title: 'New Folder',
        initialValue: '',
        hint: 'my-folder',
        confirmLabel: 'Create',
        onConfirm: (name) => _fileService.createFolder(_currentPath, name),
      );

  void _renameEntry(FileEntry entry) => _showNameDialog(
        title: 'Rename',
        initialValue: entry.name,
        hint: entry.name,
        confirmLabel: 'Rename',
        onConfirm: (name) => _fileService.rename(entry.path, entry.isDirectory, name),
      );

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
        }
      }
    }
  }

  // ---------------- Bottom sheet actions ----------------

  void _showEntryActionSheet(FileEntry entry) {
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded),
                title: const Text('Push to GitHub'),
                onTap: () => Navigator.pop(ctx, 'push'),
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
          final content = await _fileService.readFileAsString(entry.path);
          if (mounted) {
            await showGithubPushDialog(context, content: content, suggestedRepoPath: entry.name);
          }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _atRoot,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _navigateUp();
      },
      child: Scaffold(
        appBar: AppBar(
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
              tooltip: 'Home',
              icon: const Icon(Icons.home_rounded),
              onPressed: () => _loadDirectory(FileService.rootStoragePath),
            ),
            IconButton(
              tooltip: 'New Folder',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createNewFolder,
            ),
            IconButton(
              tooltip: 'New File',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _createNewFile,
            ),
            IconButton(
              tooltip: 'GitHub Settings',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GithubConfigScreen()),
              ),
            ),
          ],
        ),
        body: _buildBody(scheme),
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

    if (_entries.isEmpty) {
      return Center(
        child: Text('Empty folder', style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDirectory(_currentPath),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return FileListTile(
            entry: entry,
            onTap: () => entry.isDirectory ? _loadDirectory(entry.path) : _openInEditor(entry),
            onLongPress: () => _showEntryActionSheet(entry),
          );
        },
      ),
    );
  }
}
