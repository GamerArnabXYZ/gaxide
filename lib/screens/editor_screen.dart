import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';

import '../models/editor_language.dart';
import '../models/quick_action.dart';
import '../services/code_runner_service.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/code_editor.dart';
import '../widgets/quick_toolbar.dart';
import 'markdown_preview_screen.dart';
import 'preview_screen.dart';
import 'run_output_screen.dart';

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
  final _codeRunner = CodeRunnerService();

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

  // ---------------- Run / Preview ----------------

  /// Whether the Run/Preview button shows at all for the current language.
  bool get _canRunOrPreview {
    switch (_currentLanguage) {
      case EditorLanguage.html:
      case EditorLanguage.css:
      case EditorLanguage.javascript:
      case EditorLanguage.markdown:
        return true;
      default:
        return _codeRunner.canRun(_currentLanguage);
    }
  }

  /// "Run" (▶) icon vs "Preview" (eye) — HTML/CSS/JS/Markdown are always
  /// visual previews, not program execution, so the icon should say so.
  IconData get _runIcon {
    switch (_currentLanguage) {
      case EditorLanguage.html:
      case EditorLanguage.css:
      case EditorLanguage.markdown:
        return Icons.visibility_outlined;
      default:
        return Icons.play_arrow_rounded;
    }
  }

  Future<void> _runOrPreview() async {
    final controller = _codeController;
    if (controller == null) return;
    final content = controller.text;

    switch (_currentLanguage) {
      case EditorLanguage.markdown:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MarkdownPreviewScreen(content: content, title: _fileName)),
        );
        return;
      case EditorLanguage.html:
        await _previewHtml(content);
        return;
      case EditorLanguage.css:
        await _previewWrapped(content, isCss: true);
        return;
      case EditorLanguage.javascript:
        await _previewWrapped(content, isCss: false);
        return;
      default:
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RunOutputScreen(language: _currentLanguage, code: content, fileName: _fileName),
          ),
        );
    }
  }

  /// HTML preview loads straight from the file's own real path via a
  /// `file://` URL — this is the key fix for the classic archive-manager
  /// preview problem where a page's own <link>/<script> references to
  /// sibling CSS/JS files silently fail to load. Since the WebView's base
  /// URL is the file's real folder, those relative references resolve
  /// exactly like they would in a normal browser. Saves first (if
  /// editable) so the preview always reflects the latest edits — the
  /// WebView reads from disk, not from the in-memory editor buffer.
  Future<void> _previewHtml(String content) async {
    if (!widget.readOnly) {
      try {
        await _fileService.saveToPath(widget.filePath, content);
        if (mounted) setState(() => _isDirty = false);
      } catch (_) {
        // Preview can still proceed against the last-saved version.
      }
    }
    if (!mounted) return;
    final dir = widget.filePath.substring(0, widget.filePath.lastIndexOf('/'));
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(folderPath: dir, fileName: _fileName, title: _fileName),
      ),
    );
  }

  /// CSS/JS previewed standalone can't just be opened directly — a
  /// stylesheet or script isn't a page. A tiny wrapper HTML file is
  /// generated right next to it (same folder, so the relative
  /// `<link href="…">` / `<script src="…">` still resolves), loaded in
  /// the WebView, then cleaned up afterward so it doesn't clutter the
  /// folder. JS console output is captured and shown on the page since a
  /// WebView has no visible console of its own.
  Future<void> _previewWrapped(String content, {required bool isCss}) async {
    final dir = widget.filePath.substring(0, widget.filePath.lastIndexOf('/'));
    final wrapperPath = '$dir/.gax_preview_temp.html';
    final wrapperHtml = isCss ? _cssWrapperHtml(_fileName) : _jsWrapperHtml(_fileName);

    try {
      if (!widget.readOnly) {
        await _fileService.saveToPath(widget.filePath, content);
        if (mounted) setState(() => _isDirty = false);
      }
      await _fileService.saveToPath(wrapperPath, wrapperHtml);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(folderPath: dir, fileName: '.gax_preview_temp.html', title: _fileName),
      ),
    );

    try {
      await _fileService.delete(wrapperPath, false);
    } catch (_) {
      // Non-fatal — a leftover hidden temp file is harmless either way.
    }
  }

  String _cssWrapperHtml(String cssFileName) => '''
<!DOCTYPE html>
<html>
<head><link rel="stylesheet" href="$cssFileName"></head>
<body>
  <h1>Heading One</h1>
  <h2>Heading Two</h2>
  <p>A paragraph with a <a href="#">link</a> and <strong>bold text</strong>.</p>
  <button>A Button</button>
  <ul><li>List item one</li><li>List item two</li></ul>
  <input placeholder="An input field">
</body>
</html>
''';

  String _jsWrapperHtml(String jsFileName) => '''
<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: monospace; background:#0b0b12; color:#eee; padding:14px; }
  #out { white-space: pre-wrap; border-top: 1px solid #333; margin-top: 12px; padding-top: 12px; }
</style>
</head>
<body>
<div>&#9654; Running $jsFileName — console output below:</div>
<div id="out"></div>
<script>
  const out = document.getElementById('out');
  const log = (...args) => { out.textContent += args.map(String).join(' ') + '\\n'; };
  console.log = log;
  console.error = (...a) => log('[error]', ...a);
  console.warn = (...a) => log('[warn]', ...a);
  window.onerror = (msg) => log('[uncaught error]', msg);
</script>
<script src="$jsFileName"></script>
</body>
</html>
''';

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
            if (_codeController != null && _canRunOrPreview)
              IconButton(
                tooltip: _currentLanguage == EditorLanguage.html ||
                        _currentLanguage == EditorLanguage.css ||
                        _currentLanguage == EditorLanguage.markdown
                    ? 'Preview'
                    : 'Run',
                icon: Icon(_runIcon),
                onPressed: _runOrPreview,
              ),
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
