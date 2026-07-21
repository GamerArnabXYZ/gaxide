import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_entry.dart';

/// Direct raw-filesystem access (no SAF/file_picker cache-copy limitations).
/// Requires "All files access" on Android 11+ — grabbed via [ensureStoragePermission].
class FileService {
  /// Common Android shared-storage root. Works on the vast majority of devices.
  static const String rootStoragePath = '/storage/emulated/0';

  /// Folders skipped entirely when collecting files for a GitHub push —
  /// build artifacts / dependency caches nobody wants committed.
  static const List<String> ignoredDirNames = [
    '.git',
    'node_modules',
    'build',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.vscode',
    'Pods',
    'dist',
    'out',
    'target',
    '__pycache__',
    '.venv',
    'venv',
    '.next',
  ];

  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  /// Best-effort SD-card / secondary-storage detection. Android exposes no
  /// clean "list storage volumes" API without native code, so this uses the
  /// well-known heuristic: getExternalStorageDirectories() returns one
  /// per-volume app-specific folder (…/Android/data/<pkg>/files); stripping
  /// that suffix off any volume beyond the first (internal) one gives the
  /// SD card's root, e.g. /storage/1234-5678.
  Future<String?> detectSecondaryStoragePath() async {
    if (!Platform.isAndroid) return null;
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs == null || dirs.length < 2) return null;
      for (final dir in dirs.skip(1)) {
        final idx = dir.path.indexOf('/Android/data');
        if (idx == -1) continue;
        final root = dir.path.substring(0, idx);
        if (await Directory(root).exists()) return root;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Lists a directory: folders first, then files, both alphabetical.
  /// Silently skips hidden entries and anything unreadable (e.g. system-locked).
  /// Each directory is also checked for a `.git` folder so the UI can badge it.
  Future<List<FileEntry>> listDirectory(String dirPath, {bool showHidden = false}) async {
    final dir = Directory(dirPath);
    final entries = <FileEntry>[];

    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (!showHidden && name.startsWith('.')) continue;
      try {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        var isGitRepo = false;
        if (isDir) {
          isGitRepo = await Directory('${entity.path}/.git').exists();
        }
        entries.add(FileEntry(
          name: name,
          path: entity.path,
          isDirectory: isDir,
          sizeBytes: stat.size,
          modified: stat.modified,
          isGitRepo: isGitRepo,
        ));
      } catch (_) {
        continue;
      }
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<String> readFileAsString(String path) => File(path).readAsString();

  Future<void> saveToPath(String path, String content) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  Future<void> createFile(String dirPath, String fileName, {String content = ''}) async {
    final file = File('$dirPath/$fileName');
    if (await file.exists()) throw Exception('A file with that name already exists.');
    await file.create(recursive: true);
    if (content.isNotEmpty) await file.writeAsString(content);
  }

  Future<void> createFolder(String dirPath, String folderName) async {
    final dir = Directory('$dirPath/$folderName');
    if (await dir.exists()) throw Exception('A folder with that name already exists.');
    await dir.create(recursive: true);
  }

  Future<String> rename(String oldPath, bool isDirectory, String newName) async {
    final parent = oldPath.substring(0, oldPath.lastIndexOf('/'));
    final newPath = '$parent/$newName';
    if (isDirectory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
    return newPath;
  }

  Future<void> delete(String path, bool isDirectory) async {
    if (isDirectory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  Future<void> copyEntry(String sourcePath, String destDir, bool isDirectory) async {
    final name = sourcePath.split('/').last;
    final destPath = '$destDir/$name';
    if (isDirectory) {
      await _copyDirectoryRecursive(sourcePath, destPath);
    } else {
      await File(sourcePath).copy(destPath);
    }
  }

  Future<void> _copyDirectoryRecursive(String src, String dest) async {
    await Directory(dest).create(recursive: true);
    await for (final entity in Directory(src).list(followLinks: false)) {
      final name = entity.path.split('/').last;
      final newPath = '$dest/$name';
      if (entity is Directory) {
        await _copyDirectoryRecursive(entity.path, newPath);
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<void> moveEntry(String sourcePath, String destDir, bool isDirectory) async {
    await copyEntry(sourcePath, destDir, isDirectory);
    await delete(sourcePath, isDirectory);
  }

  /// Recursively walks a git-repo folder and reads every trackable file as
  /// bytes, skipping [ignoreDirs] (defaults to [ignoredDirNames], but
  /// Settings can override this list). Used to build a GitHub push.
  Future<List<MapEntry<String, List<int>>>> collectFilesForPush(String rootPath, {List<String>? ignoreDirs}) async {
    final ignore = ignoreDirs ?? ignoredDirNames;
    final result = <MapEntry<String, List<int>>>[];

    Future<void> walk(Directory dir, String relBase) async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split('/').last;
        if (entity is Directory) {
          if (ignore.contains(name)) continue;
          await walk(entity, '$relBase$name/');
        } else if (entity is File) {
          try {
            final bytes = await entity.readAsBytes();
            result.add(MapEntry('$relBase$name', bytes));
          } catch (_) {
            continue;
          }
        }
      }
    }

    await walk(Directory(rootPath), '');
    return result;
  }
}
