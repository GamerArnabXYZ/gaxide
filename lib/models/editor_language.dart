import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cs.dart';

/// Supported languages for the dynamic syntax-highlighting dropdown.
enum EditorLanguage {
  javascript,
  typescript,
  python,
  dart,
  html,
  css,
  cpp,
  java,
  kotlin,
  swift,
  php,
  ruby,
  go,
  rust,
  sql,
  json,
  yaml,
  markdown,
  bash,
  csharp,
}

extension EditorLanguageX on EditorLanguage {
  String get label {
    switch (this) {
      case EditorLanguage.javascript:
        return 'JavaScript';
      case EditorLanguage.typescript:
        return 'TypeScript';
      case EditorLanguage.python:
        return 'Python';
      case EditorLanguage.dart:
        return 'Dart';
      case EditorLanguage.html:
        return 'HTML';
      case EditorLanguage.css:
        return 'CSS';
      case EditorLanguage.cpp:
        return 'C++';
      case EditorLanguage.java:
        return 'Java';
      case EditorLanguage.kotlin:
        return 'Kotlin';
      case EditorLanguage.swift:
        return 'Swift';
      case EditorLanguage.php:
        return 'PHP';
      case EditorLanguage.ruby:
        return 'Ruby';
      case EditorLanguage.go:
        return 'Go';
      case EditorLanguage.rust:
        return 'Rust';
      case EditorLanguage.sql:
        return 'SQL';
      case EditorLanguage.json:
        return 'JSON';
      case EditorLanguage.yaml:
        return 'YAML';
      case EditorLanguage.markdown:
        return 'Markdown';
      case EditorLanguage.bash:
        return 'Bash';
      case EditorLanguage.csharp:
        return 'C#';
    }
  }

  /// Maps enum -> highlight.js Mode used by CodeController.
  Mode get mode {
    switch (this) {
      case EditorLanguage.javascript:
        return javascript;
      case EditorLanguage.typescript:
        return typescript;
      case EditorLanguage.python:
        return python;
      case EditorLanguage.dart:
        return dart;
      case EditorLanguage.html:
        return xml;
      case EditorLanguage.css:
        return css;
      case EditorLanguage.cpp:
        return cpp;
      case EditorLanguage.java:
        return java;
      case EditorLanguage.kotlin:
        return kotlin;
      case EditorLanguage.swift:
        return swift;
      case EditorLanguage.php:
        return php;
      case EditorLanguage.ruby:
        return ruby;
      case EditorLanguage.go:
        return go;
      case EditorLanguage.rust:
        return rust;
      case EditorLanguage.sql:
        return sql;
      case EditorLanguage.json:
        return json;
      case EditorLanguage.yaml:
        return yaml;
      case EditorLanguage.markdown:
        return markdown;
      case EditorLanguage.bash:
        return bash;
      case EditorLanguage.csharp:
        return cs;
    }
  }

  String get defaultFileName {
    switch (this) {
      case EditorLanguage.javascript:
        return 'script.js';
      case EditorLanguage.typescript:
        return 'script.ts';
      case EditorLanguage.python:
        return 'script.py';
      case EditorLanguage.dart:
        return 'main.dart';
      case EditorLanguage.html:
        return 'index.html';
      case EditorLanguage.css:
        return 'style.css';
      case EditorLanguage.cpp:
        return 'main.cpp';
      case EditorLanguage.java:
        return 'Main.java';
      case EditorLanguage.kotlin:
        return 'main.kt';
      case EditorLanguage.swift:
        return 'main.swift';
      case EditorLanguage.php:
        return 'index.php';
      case EditorLanguage.ruby:
        return 'script.rb';
      case EditorLanguage.go:
        return 'main.go';
      case EditorLanguage.rust:
        return 'main.rs';
      case EditorLanguage.sql:
        return 'query.sql';
      case EditorLanguage.json:
        return 'data.json';
      case EditorLanguage.yaml:
        return 'config.yaml';
      case EditorLanguage.markdown:
        return 'README.md';
      case EditorLanguage.bash:
        return 'script.sh';
      case EditorLanguage.csharp:
        return 'Program.cs';
    }
  }

  /// Auto-detects language from a file name/extension when opening a file.
  static EditorLanguage fromExtension(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'js':
      case 'jsx':
      case 'mjs':
        return EditorLanguage.javascript;
      case 'ts':
      case 'tsx':
        return EditorLanguage.typescript;
      case 'py':
        return EditorLanguage.python;
      case 'dart':
        return EditorLanguage.dart;
      case 'html':
      case 'htm':
      case 'xml':
        return EditorLanguage.html;
      case 'css':
      case 'scss':
      case 'less':
        return EditorLanguage.css;
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'h':
      case 'hpp':
      case 'c':
        return EditorLanguage.cpp;
      case 'java':
        return EditorLanguage.java;
      case 'kt':
      case 'kts':
        return EditorLanguage.kotlin;
      case 'swift':
        return EditorLanguage.swift;
      case 'php':
        return EditorLanguage.php;
      case 'rb':
        return EditorLanguage.ruby;
      case 'go':
        return EditorLanguage.go;
      case 'rs':
        return EditorLanguage.rust;
      case 'sql':
        return EditorLanguage.sql;
      case 'json':
        return EditorLanguage.json;
      case 'yaml':
      case 'yml':
        return EditorLanguage.yaml;
      case 'md':
      case 'markdown':
        return EditorLanguage.markdown;
      case 'sh':
      case 'bash':
      case 'zsh':
        return EditorLanguage.bash;
      case 'cs':
        return EditorLanguage.csharp;
      default:
        return EditorLanguage.javascript;
    }
  }
}
