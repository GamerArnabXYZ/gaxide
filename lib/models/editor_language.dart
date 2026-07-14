import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/cpp.dart';

/// Supported languages for the dynamic syntax-highlighting dropdown.
enum EditorLanguage { javascript, python, dart, html, cpp }

extension EditorLanguageX on EditorLanguage {
  String get label {
    switch (this) {
      case EditorLanguage.javascript:
        return 'JavaScript';
      case EditorLanguage.python:
        return 'Python';
      case EditorLanguage.dart:
        return 'Dart';
      case EditorLanguage.html:
        return 'HTML';
      case EditorLanguage.cpp:
        return 'C++';
    }
  }

  /// Maps enum -> highlight.js Mode used by CodeController.
  Mode get mode {
    switch (this) {
      case EditorLanguage.javascript:
        return javascript;
      case EditorLanguage.python:
        return python;
      case EditorLanguage.dart:
        return dart;
      case EditorLanguage.html:
        return xml;
      case EditorLanguage.cpp:
        return cpp;
    }
  }

  String get defaultFileName {
    switch (this) {
      case EditorLanguage.javascript:
        return 'script.js';
      case EditorLanguage.python:
        return 'script.py';
      case EditorLanguage.dart:
        return 'main.dart';
      case EditorLanguage.html:
        return 'index.html';
      case EditorLanguage.cpp:
        return 'main.cpp';
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
      case 'py':
        return EditorLanguage.python;
      case 'dart':
        return EditorLanguage.dart;
      case 'html':
      case 'htm':
      case 'xml':
        return EditorLanguage.html;
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'h':
      case 'hpp':
        return EditorLanguage.cpp;
      default:
        return EditorLanguage.javascript;
    }
  }
}
