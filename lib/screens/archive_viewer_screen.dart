import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:code_text_field/code_text_field.dart';

import '../models/archive_entry.dart';
import '../models/editor_language.dart';
import '../services/archive_service.dart';
import '../services/prefs_service.dart';
import '../widgets/code_editor.dart';

/// Browse a .zip's contents WITHOUT extracting it first — ZArchiver-style.
/// Drill into folders inside the archive and preview text/code or image
/// files straight from memory. Extraction (a single file, or the whole
/// archive) is always one tap away but never forced on you.
class ArchiveViewerScreen extends StatefulWidget {
  final String zipPath;
  const ArchiveViewerScreen({super.key, required this.zipPath});

  @override
  State<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends State<ArchiveViewerScreen> {
  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  final _archiveService = ArchiveService();
  Archive? _archive;
  String? _error;
  String _currentDir = ''; // '' = zip root
  bool _extractingAll = false;

  String get _zipName => widget.zipPath.split('/').last;
  bool get _atRoot => _currentDir.isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final archive = await _archiveService.decodeZip(widget.zipPath);
      if (mounted) setState(() => _archive = archive);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Builds the current folder's rows from the zip's flat file list —
  /// virtual folders are just the set of distinct next-path-segments.
  List<ArchiveEntry> get _visibleEntries {
    final archive = _archive;
    if (archive == null) return [];
    final prefix = _currentDir.isEmpty ? '' : '$_currentDir/';
    final folderNames = <String>{};
    final files = <ArchiveEntry>[];

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (!name.startsWith(prefix)) continue;
      final rel = name.substring(prefix.length);
      if (rel.isEmpty) continue;
      final slashIdx = rel.indexOf('/');
      if (slashIdx == -1) {
        files.add(ArchiveEntry(name: rel, path: name, isDirectory: false, file: file));
      } else {
        folderNames.add(rel.substring(0, slashIdx));
      }
    }

    final folders = folderNames.map(
      (name) => ArchiveEntry(name: name, path: '$prefix$name', isDirectory: true),
    ).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...folders, ...files];
  }

  void _navigateUp() {
    if (_atRoot) {
      Navigator.pop(context);
      return;
    }
    final segments = _currentDir.split('/')..removeLast();
    setState(() => _currentDir = segments.join('/'));
  }

  void _openFolder(ArchiveEntry entry) => setState(() => _currentDir = entry.path);

  Future<void> _openFile(ArchiveEntry entry) async {
    final file = entry.file!;
    final bytes = file.content as List<int>;

    if (_imageExtensions.contains(entry.extension)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ArchiveImagePreviewScreen(name: entry.name, bytes: Uint8List.fromList(bytes)),
        ),
      );
      return;
    }

    String? text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = null;
    }

    if (text == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ This looks like a binary file — extract it to open.')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ArchiveTextPreviewScreen(name: entry.name, content: text!)),
    );
  }

  Future<void> _extractOne(ArchiveEntry entry) async {
    final destDir = widget.zipPath.substring(0, widget.zipPath.lastIndexOf('/'));
    try {
      final outPath = await _archiveService.extractSingleFile(entry.file!, destDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Extracted "${outPath.split('/').last}" next to the zip')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  Future<void> _extractAll() async {
    setState(() => _extractingAll = true);
    try {
      final destination = await _archiveService.extractZip(widget.zipPath);
      if (mounted) {
        Navigator.pop(context, true); // tells the File Manager to refresh
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Extracted to ${destination.split('/').last}/')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _extractingAll = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Extract failed: $e')));
      }
    }
  }

  void _showFileActions(ArchiveEntry entry) {
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded),
              title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_readableSize(entry.sizeBytes)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_rounded),
              title: const Text('Extract This File'),
              onTap: () => Navigator.pop(ctx, 'extract'),
            ),
          ],
        ),
      ),
    ).then((action) {
      switch (action) {
        case 'view':
          _openFile(entry);
          break;
        case 'extract':
          _extractOne(entry);
          break;
      }
    });
  }

  String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _navigateUp();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _navigateUp),
          title: Text(_atRoot ? _zipName : _currentDir.split('/').last, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Extract All',
              icon: _extractingAll
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.unarchive_rounded),
              onPressed: (_archive == null || _extractingAll) ? null : _extractAll,
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(scheme)),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('⚠️ Could not read this archive.\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (_archive == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _visibleEntries;
    if (entries.isEmpty) {
      return Center(child: Text('Empty', style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => entry.isDirectory ? _openFolder(entry) : _openFile(entry),
            onLongPress: entry.isDirectory ? null : () => _showFileActions(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      entry.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                      color: entry.isDirectory ? const Color(0xFFFFC24B) : scheme.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        if (!entry.isDirectory) ...[
                          const SizedBox(height: 2),
                          Text(
                            _readableSize(entry.sizeBytes),
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (entry.isDirectory)
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant.withOpacity(0.5))
                  else
                    IconButton(
                      icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant.withOpacity(0.7), size: 20),
                      onPressed: () => _showFileActions(entry),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Read-only image preview for a file that's still zipped up — decoded
/// straight from memory, nothing written to disk.
class _ArchiveImagePreviewScreen extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  const _ArchiveImagePreviewScreen({required this.name, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(name, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.memory(
            bytes,
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '⚠️ Could not render this image.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only syntax-highlighted preview for a text/code file that's still
/// zipped up. Reuses the same CodeEditorView as the real editor (in
/// readOnly mode) so highlighting looks identical.
class _ArchiveTextPreviewScreen extends StatefulWidget {
  final String name;
  final String content;
  const _ArchiveTextPreviewScreen({required this.name, required this.content});

  @override
  State<_ArchiveTextPreviewScreen> createState() => _ArchiveTextPreviewScreenState();
}

class _ArchiveTextPreviewScreenState extends State<_ArchiveTextPreviewScreen> {
  final _prefsService = PrefsService();
  int? _highlightSizeLimit; // null until loaded from Settings

  @override
  void initState() {
    super.initState();
    _prefsService.loadPerformancePrefs().then((p) {
      if (mounted) setState(() => _highlightSizeLimit = p.highlightLimitKb * 1024);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final content = widget.content;
    if (_highlightSizeLimit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lang = EditorLanguageX.fromExtension(name);
    final tooLargeToHighlight = content.length > _highlightSizeLimit!;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(
              child: Text('Read-only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (tooLargeToHighlight)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 16, color: Theme.of(context).colorScheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Large file — syntax highlighting is off for smooth performance.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: CodeEditorView(
                  controller: CodeController(text: content, language: tooLargeToHighlight ? null : lang.mode),
                  currentLanguage: lang,
                  onLanguageChanged: (_) {},
                  readOnly: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
