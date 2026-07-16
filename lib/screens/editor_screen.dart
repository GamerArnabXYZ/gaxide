import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';

import '../models/editor_language.dart';
import '../services/file_service.dart';
import '../widgets/code_editor.dart';

/// Code editor for a single file already on disk — reached by tapping a
/// file in the File Manager (home screen). Push lives at the folder level
/// only (FAB or long-press a folder in the File Manager) — this screen is
/// just for editing and saving.
class EditorScreen extends StatefulWidget {
  final String filePath;
  final String initialContent;

  const EditorScreen({super.key, required this.filePath, required this.initialContent});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _fileService = FileService();

  late CodeController _codeController;
  late EditorLanguage _currentLanguage;
  bool _isDirty = false;
  bool _isSaving = false;

  String get _fileName => widget.filePath.split('/').last;

  @override
  void initState() {
    super.initState();
    _currentLanguage = EditorLanguageX.fromExtension(_fileName);
    _codeController = CodeController(text: widget.initialContent, language: _currentLanguage.mode);
    _codeController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onLanguageChanged(EditorLanguage lang) {
    final text = _codeController.text;
    final old = _codeController;
    old.removeListener(_markDirty);
    setState(() {
      _currentLanguage = lang;
      _codeController = CodeController(text: text, language: lang.mode);
      _codeController.addListener(_markDirty);
    });
    old.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _fileService.saveToPath(widget.filePath, _codeController.text);
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
              if (_isDirty) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 8, color: scheme.error),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Save',
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CodeEditorView(
              controller: _codeController,
              currentLanguage: _currentLanguage,
              onLanguageChanged: _onLanguageChanged,
            ),
          ),
        ),
      ),
    );
  }
}
