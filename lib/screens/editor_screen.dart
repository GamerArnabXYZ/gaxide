import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';

import '../models/editor_language.dart';
import '../models/quick_action.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/code_editor.dart';
import '../widgets/quick_toolbar.dart';

/// Code editor for a single file already on disk — reached by tapping a
/// file in the File Manager (home screen). Push lives at the folder level
/// only (FAB or long-press a folder in the File Manager) — this screen is
/// just for editing and saving.
///
/// [readOnly] powers "Open Read-Only" from the file's long-press menu: the
/// Save button and quick toolbar are hidden entirely (the toolbar inserts
/// text directly into the controller, bypassing TextField's own readOnly
/// flag, so it has to be hidden rather than just disabled) and the file
/// can never become dirty.
class EditorScreen extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final bool readOnly;

  const EditorScreen({
    super.key,
    required this.filePath,
    required this.initialContent,
    this.readOnly = false,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // Above this many characters, syntax highlighting is skipped entirely.
  // The `highlight` package parses the WHOLE file synchronously on the UI
  // thread, and that cost grows fast enough that a large file (500KB+)
  // can freeze the app for minutes and eventually crash it outright. A
  // plain monospace TextField has none of that cost, so big files still
  // open instantly — just without color-coding. Customizable in Settings;
  // loaded (async) inside _initController, alongside the deferred
  // CodeController construction below.
  int _highlightSizeLimit = 150000; // ~150 KB default, overridden from Settings

  final _fileService = FileService();
  final _prefsService = PrefsService();

  // Nullable and built one frame late on purpose: constructing a
  // CodeController runs a full syntax-highlight pass over the entire file
  // right away. For large files that's slow enough to make the
  // file-list-to-editor transition look frozen. Deferring it to right
  // after the first frame lets a lightweight loading spinner paint
  // immediately instead, so opening a big file *feels* instant even
  // though the highlighting work itself still takes the same time.
  CodeController? _codeController;
  late UndoHistoryController _undoController;
  late EditorLanguage _currentLanguage;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _highlightingDisabled = false;

  List<QuickAction> _quickActions = QuickActionX.defaultToolbar;

  String get _fileName => widget.filePath.split('/').last;

  @override
  void initState() {
    super.initState();
    _currentLanguage = EditorLanguageX.fromExtension(_fileName);
    _undoController = UndoHistoryController();
    _loadQuickToolbar();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initController());
  }

  Future<void> _initController() async {
    final perfPrefs = await _prefsService.loadPerformancePrefs();
    _highlightSizeLimit = perfPrefs.highlightLimitKb * 1024;
    _highlightingDisabled = widget.initialContent.length > _highlightSizeLimit;

    final controller = CodeController(
      text: widget.initialContent,
      language: _highlightingDisabled ? null : _currentLanguage.mode,
    );
    controller.addListener(_markDirty);
    if (mounted) {
      setState(() => _codeController = controller);
      if (_highlightingDisabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📄 Large file — syntax highlighting turned off to keep things smooth.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _loadQuickToolbar() async {
    final actions = await _prefsService.loadQuickToolbar();
    if (mounted) setState(() => _quickActions = actions);
  }

  void _markDirty() {
    if (!widget.readOnly && !_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    _codeController?.dispose();
    _undoController.dispose();
    super.dispose();
  }

  void _onLanguageChanged(EditorLanguage lang) {
    final current = _codeController;
    if (current == null) return;
    final text = current.text;
    final oldController = current;
    final oldUndo = _undoController;
    oldController.removeListener(_markDirty);
    setState(() {
      _currentLanguage = lang;
      _codeController = CodeController(text: text, language: _highlightingDisabled ? null : lang.mode);
      _codeController!.addListener(_markDirty);
      _undoController = UndoHistoryController();
    });
    oldController.dispose();
    oldUndo.dispose();
  }

  Future<void> _save() async {
    if (widget.readOnly) return;
    final controller = _codeController;
    if (controller == null) return;
    setState(() => _isSaving = true);
    try {
      await _fileService.saveToPath(widget.filePath, controller.text);
      if (!mounted) return;
      setState(() {
        _isDirty = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('💾 Saved: $_fileName'), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Save failed: $e')));
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_isDirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard & Leave')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isDirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty() && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(child: Text(_fileName, overflow: TextOverflow.ellipsis)),
              if (widget.readOnly) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
              ],
              if (_isDirty) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 8, color: scheme.error),
              ],
            ],
          ),
          actions: [
            if (!widget.readOnly)
              IconButton(
                tooltip: 'Save',
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                onPressed: (_isSaving || _codeController == null) ? null : _save,
              ),
          ],
        ),
        body: SafeArea(
          child: _codeController == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (_highlightingDisabled)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.speed_rounded, size: 16, color: scheme.onTertiaryContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Large file — syntax highlighting is off for smooth performance.',
                                  style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: CodeEditorView(
                          controller: _codeController!,
                          currentLanguage: _currentLanguage,
                          onLanguageChanged: _onLanguageChanged,
                          undoController: _undoController,
                          readOnly: widget.readOnly,
                        ),
                      ),
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 8),
                        QuickToolbar(
                          controller: _codeController!,
                          undoController: _undoController,
                          actions: _quickActions,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
