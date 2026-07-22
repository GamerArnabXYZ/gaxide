import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/editor_language.dart';

class RunResult {
  final bool success;
  final String output;
  const RunResult({required this.success, required this.output});
}

/// Runs code via the OnlineCompiler.io REST API
/// (https://api.onlinecompiler.io/docs) — sandboxed Docker containers, no
/// interpreter/compiler bundled on-device. Uses the synchronous endpoint
/// (`/api/run-code-sync/`), which returns the result directly in one
/// request — no callback URL/webhook to host, which wouldn't make sense
/// from a mobile app anyway.
///
/// HTML/CSS/JS deliberately do NOT go through here — those "run" inside a
/// real WebView instead (see PreviewScreen), since they're meant to
/// execute in a browser engine against sibling files on disk, not in a
/// sandboxed language runtime.
///
/// OnlineCompiler.io only supports 12 languages — Dart, Kotlin, Swift,
/// Bash, and plain JavaScript aren't among them, so those simply don't
/// get a Run button (see [canRun]) rather than pretending to work.
class CodeRunnerService {
  static const _baseUrl = 'https://api.onlinecompiler.io';
  static const _defaultApiKey = 'c69e5dcf31e7d2d3cd0eed31ad6bbb54';

  static const Map<EditorLanguage, String> _compilerId = {
    EditorLanguage.python: 'python-3.14',
    EditorLanguage.cpp: 'g++-15',
    EditorLanguage.java: 'openjdk-25',
    EditorLanguage.csharp: 'dotnet-csharp-9',
    EditorLanguage.php: 'php-8.5',
    EditorLanguage.ruby: 'ruby-4.0',
    EditorLanguage.go: 'go-1.26',
    EditorLanguage.rust: 'rust-1.93',
    EditorLanguage.typescript: 'typescript-deno',
  };

  bool canRun(EditorLanguage lang) => _compilerId.containsKey(lang);

  /// [apiKey] lets Settings override the built-in key (e.g. with your own
  /// OnlineCompiler.io account) — blank uses the built-in default.
  Future<RunResult> run(EditorLanguage lang, String code, String fileName, {String apiKey = ''}) async {
    final compiler = _compilerId[lang];
    if (compiler == null) {
      return const RunResult(success: false, output: "This file type can't be run here.");
    }

    final key = apiKey.trim().isEmpty ? _defaultApiKey : apiKey.trim();

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/run-code-sync/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': key,
            },
            body: jsonEncode({
              'compiler': compiler,
              'code': code,
            }),
          )
          // The API itself can block up to 30s for sync execution —
          // give it a little extra headroom before we give up client-side.
          .timeout(const Duration(seconds: 35));

      if (res.statusCode == 401 || res.statusCode == 403) {
        return RunResult(success: false, output: 'API key rejected [${res.statusCode}]:\n${res.body}');
      }
      if (res.statusCode == 429) {
        return const RunResult(
          success: false,
          output: 'The run service is at capacity right now (max 4 requests at once across all '
              'users of this key) — wait a moment and try again.',
        );
      }
      if (res.statusCode != 200) {
        return RunResult(success: false, output: 'Run service error [${res.statusCode}]:\n${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final output = data['output'] as String? ?? '';
      final error = data['error'] as String? ?? '';
      final exitCode = data['exit_code'];
      final signal = data['signal'];
      final status = data['status'] as String?;

      final buffer = StringBuffer();
      if (output.isNotEmpty) buffer.write(output);
      if (error.isNotEmpty) {
        if (output.isNotEmpty) buffer.writeln();
        buffer.writeln('— stderr —');
        buffer.write(error);
      }
      buffer.write('\n\n[exit code $exitCode');
      if (signal != null) buffer.write(', signal $signal');
      buffer.write(']');

      final text = buffer.toString().trim();
      return RunResult(success: status == 'success', output: text.isEmpty ? '(no output)' : text);
    } catch (e) {
      return RunResult(success: false, output: 'Could not reach the run service:\n$e');
    }
  }
}
