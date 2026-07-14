import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';

import '../models/editor_language.dart';
import '../services/github_service.dart';
import '../services/file_service.dart';
import '../services/prefs_service.dart';
import '../widgets/config_panel.dart';
import '../widgets/code_editor.dart';
import '../widgets/status_log_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tokenController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController();
  final _pathController = TextEditingController();
  final _commitController = TextEditingController();

  final _githubService = GithubService();
  final _fileService = FileService();
  final _prefsService = PrefsService();

  late CodeController _codeController;
  EditorLanguage _currentLanguage = EditorLanguage.javascript;
  String? _openedFilePath;

  String _statusLog = 'System Ready. Open or write a script, then push.';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(
      text: '// Write your code here...\n'
          'function helloWorld() {\n'
          '  console.log("Hello from GAX IDE v2");\n'
          '}',
      language: _currentLanguage.mode,
    );
    _restoreConfig();
  }

  Future<void> _restoreConfig() async {
    final config = await _prefsService.load();
    if (!mounted) return;
    setState(() {
      _tokenController.text = config.token;
      _repoController.text = config.repo;
      _branchController.text = config.branch;
      _pathController.text = config.path;
    });
  }

  Future<void> _persistConfig([String? _]) async {
    await _prefsService.save(GaxConfig(
      token: _tokenController.text.trim(),
      repo: _repoController.text.trim(),
      branch: _branchController.text.trim(),
      path: _pathController.text.trim(),
    ));
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    _pathController.dispose();
    _commitController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _swapController(String text, EditorLanguage lang) {
    final old = _codeController;
    setState(() {
      _currentLanguage = lang;
      _codeController = CodeController(text: text, language: lang.mode);
    });
    old.dispose();
  }

  void _onLanguageChanged(EditorLanguage lang) => _swapController(_codeController.text, lang);

  Future<void> _openFile() async {
    setState(() => _statusLog = '⏳ Opening file picker...');
    final granted = await _fileService.ensureStoragePermission();
    if (!granted) {
      setState(() => _statusLog = '❌ Storage permission denied. Enable "All files access" in Settings.');
      return;
    }
    try {
      final opened = await _fileService.openFile();
      if (opened == null) {
        setState(() => _statusLog = 'ℹ️ File selection cancelled.');
        return;
      }
      final detectedLang = EditorLanguageX.fromExtension(opened.name);
      _openedFilePath = opened.path;
      _swapController(opened.content, detectedLang);
      setState(() {
        _pathController.text = opened.name;
        _statusLog = '✅ Opened: ${opened.name}';
      });
      _persistConfig();
    } catch (e) {
      setState(() => _statusLog = '❌ Could not open file: $e');
    }
  }

  Future<void> _saveFile() async {
    final content = _codeController.text;
    setState(() => _statusLog = '⏳ Saving...');
    try {
      if (_openedFilePath != null) {
        await _fileService.saveToPath(_openedFilePath!, content);
        setState(() => _statusLog = '💾 Saved to $_openedFilePath');
      } else {
        final granted = await _fileService.ensureStoragePermission();
        if (!granted) {
          setState(() => _statusLog = '❌ Storage permission denied.');
          return;
        }
        final fileName = _pathController.text.trim().isEmpty
            ? _currentLanguage.defaultFileName
            : _pathController.text.trim();
        final savedPath = await _fileService.saveAsNew(fileName, content);
        setState(() {
          _openedFilePath = savedPath;
          _statusLog = '💾 Saved new file: $savedPath';
        });
      }
    } catch (e) {
      setState(() => _statusLog = '❌ Save failed: $e');
    }
  }

  Future<void> _pushToGithub() async {
    final token = _tokenController.text.trim();
    final repo = _repoController.text.trim();
    final filePath = _pathController.text.trim();

    if (token.isEmpty || repo.isEmpty || filePath.isEmpty) {
      setState(() => _statusLog = '❌ Token, Repo, and File Path are required!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusLog = '⏳ Pushing to GitHub...';
    });

    final result = await _githubService.pushFile(
      token: token,
      repo: repo,
      filePath: filePath,
      branch: _branchController.text.trim(),
      content: _codeController.text,
      commitMessage:
          _commitController.text.trim().isEmpty ? 'Update via GAX IDE Mobile' : _commitController.text.trim(),
    );

    await _persistConfig();

    setState(() {
      _isLoading = false;
      _statusLog = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GAX IDE v2.0'),
        actions: [
          IconButton(tooltip: 'Open File', icon: const Icon(Icons.folder_open_rounded), onPressed: _openFile),
          IconButton(tooltip: 'Save File', icon: const Icon(Icons.save_rounded), onPressed: _saveFile),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              ConfigPanel(
                tokenController: _tokenController,
                repoController: _repoController,
                branchController: _branchController,
                pathController: _pathController,
                commitController: _commitController,
                onAnyFieldChanged: _persistConfig,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CodeEditorView(
                  controller: _codeController,
                  currentLanguage: _currentLanguage,
                  onLanguageChanged: _onLanguageChanged,
                ),
              ),
              const SizedBox(height: 10),
              StatusLogPanel(status: _statusLog),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pushToGithub,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(_isLoading ? 'PUSHING...' : 'PUSH TO GITHUB'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
