import 'package:flutter/material.dart';
import '../models/editor_language.dart';
import '../services/code_runner_service.dart';
import '../services/prefs_service.dart';

/// Shows stdout/stderr/exit code from running a file through the Piston
/// execution service — a plain console look (black background) so it
/// reads clearly regardless of the app's own color theme.
class RunOutputScreen extends StatefulWidget {
  final EditorLanguage language;
  final String code;
  final String fileName;

  const RunOutputScreen({super.key, required this.language, required this.code, required this.fileName});

  @override
  State<RunOutputScreen> createState() => _RunOutputScreenState();
}

class _RunOutputScreenState extends State<RunOutputScreen> {
  final _runner = CodeRunnerService();
  final _prefsService = PrefsService();
  bool _running = true;
  String _output = '';
  bool _success = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final apiKey = (await _prefsService.loadPerformancePrefs()).codeRunApiKey;
    final result = await _runner.run(widget.language, widget.code, widget.fileName, apiKey: apiKey);
    if (!mounted) return;
    setState(() {
      _running = false;
      _output = result.output;
      _success = result.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Run: ${widget.fileName}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Run Again',
            icon: const Icon(Icons.replay_rounded),
            onPressed: _running ? null : _run,
          ),
        ],
      ),
      body: SafeArea(
        child: _running
            ? const Center(child: CircularProgressIndicator())
            : Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _output,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                      color: _success ? Colors.greenAccent.shade100 : Colors.redAccent.shade100,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
