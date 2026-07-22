import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/editor_language.dart';

class RunResult {
  final bool success;
  final String output;
  const RunResult({required this.success, required this.output});
}

/// Runs non-web code (Python, Java, C++, Kotlin, Swift, PHP, Ruby, Go,
/// Rust, Bash, C#, TypeScript...) via the free, public Piston execution
/// API (https://github.com/engineer-man/piston) — no interpreter or
/// compiler bundled on-device, no API key or account needed.
///
/// HTML/CSS/JS deliberately do NOT go through here — those "run" inside a
/// real WebView instead (see PreviewScreen), since they're meant to
/// execute in a browser engine against sibling files on disk, not in a
/// sandboxed language runtime.
///
/// This depends on a third-party public service — treat any failure
/// (network, rate limit, an unexpected language-slug mismatch) as a
/// normal, recoverable outcome: report it in the output panel, never
/// crash the app over it.
class CodeRunnerService {
  static const _endpoint = 'https://emkc.org/api/v2/piston/execute';

  static const Map<EditorLanguage, String> _languageSlug = {
    EditorLanguage.python: 'python',
    EditorLanguage.dart: 'dart',
    EditorLanguage.cpp: 'c++',
    EditorLanguage.java: 'java',
    EditorLanguage.kotlin: 'kotlin',
    EditorLanguage.swift: 'swift',
    EditorLanguage.php: 'php',
    EditorLanguage.ruby: 'ruby',
    EditorLanguage.go: 'go',
    EditorLanguage.rust: 'rust',
    EditorLanguage.bash: 'bash',
    EditorLanguage.csharp: 'csharp',
    EditorLanguage.typescript: 'typescript',
  };

  bool canRun(EditorLanguage lang) => _languageSlug.containsKey(lang);

  Future<RunResult> run(EditorLanguage lang, String code, String fileName) async {
    final slug = _languageSlug[lang];
    if (slug == null) {
      return const RunResult(success: false, output: "This file type can't be run here.");
    }

    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'language': slug,
              'version': '*',
              'files': [
                {'name': fileName, 'content': code},
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200) {
        return RunResult(success: false, output: 'Run service error [${res.statusCode}]:\n${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final compile = data['compile'] as Map<String, dynamic>?;
      final runData = data['run'] as Map<String, dynamic>?;

      final buffer = StringBuffer();
      final compileErr = (compile?['stderr'] as String? ?? '').trim();
      if (compileErr.isNotEmpty) {
        buffer.writeln('— Compile output —');
        buffer.writeln(compileErr);
        buffer.writeln();
      }
      if (runData != null) {
        final stdout = (runData['stdout'] as String? ?? '');
        final stderr = (runData['stderr'] as String? ?? '').trim();
        final exitCode = runData['code'];
        if (stdout.isNotEmpty) buffer.write(stdout);
        if (stderr.isNotEmpty) {
          if (stdout.isNotEmpty) buffer.writeln();
          buffer.writeln('— stderr —');
          buffer.write(stderr);
        }
        buffer.write('\n\n[exited with code $exitCode]');
      }

      final output = buffer.toString().trim();
      return RunResult(success: true, output: output.isEmpty ? '(no output)' : output);
    } catch (e) {
      return RunResult(success: false, output: 'Could not reach the run service:\n$e');
    }
  }
}
