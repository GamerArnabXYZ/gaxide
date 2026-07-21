import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Starter file templates bundled under `assets/samples/` — powers the
/// "New File from Template" action so common boilerplate (a Dart main, an
/// HTML skeleton, etc.) is one tap away instead of typed from scratch.
///
/// The file list is a plain static list rather than something scanned from
/// the asset manifest at runtime — Flutter's manifest format has changed
/// across versions, and a hard-coded list that matches what's actually in
/// assets/samples/ is far more reliable than parsing a format that could
/// shift under a Flutter upgrade.
class TemplateService {
  static const List<String> templateFileNames = [
    'main.dart',
    'index.html',
    'style.css',
    'script.js',
    'Main.java',
    'main.py',
    'README.md',
  ];

  Future<String> loadTemplateContent(String fileName) => rootBundle.loadString('assets/samples/$fileName');

  /// Copies every bundled template out to a real, writable, browsable
  /// folder on disk (app-private storage) and returns its path — used
  /// once to seed the default "Samples" Workplace shortcut. This folder
  /// is a plain copy: renaming, editing, or deleting it (or removing the
  /// Workplace shortcut that points at it) never touches the actual
  /// assets bundled in the app, so "New File from Template" keeps
  /// working regardless of what happens to this folder.
  Future<String> ensureSamplesFolderOnDisk() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final samplesDir = Directory('${baseDir.path}/Samples');
    if (!await samplesDir.exists()) {
      await samplesDir.create(recursive: true);
    }
    for (final name in templateFileNames) {
      final file = File('${samplesDir.path}/$name');
      if (!await file.exists()) {
        final content = await loadTemplateContent(name);
        await file.writeAsString(content);
      }
    }
    return samplesDir.path;
  }
}
