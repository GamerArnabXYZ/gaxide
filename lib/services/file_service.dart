import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../models/file_entry.dart';

/// Direct raw-filesystem access (no SAF/file_picker cache-copy limitations).
/// Requires "All files access" on Android 11+ — grabbed via [ensureStoragePermission].
class FileService {
  /// Common Android shared-storage root. Works on the vast majority of devices.
  static const String rootStoragePath = '/storage/emulated/0';

  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<bool> isPermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    return (await Permission.manageExternalStorage.status).isPermanentlyDenied;
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  /// Lists a directory: folders first, then files, both alphabetical.
  /// Silently skips hidden entries and anything unreadable (e.g. system-locked).
  Future<List<FileEntry>> listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    final entries = <FileEntry>[];

    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      try {
        final stat = await entity.stat();
        entries.add(FileEntry(
          name: name,
          path: entity.path,
          isDirectory: entity is Directory,
          sizeBytes: stat.size,
          modified: stat.modified,
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

  Future<void> createFile(String dirPath, String fileName) async {
    final file = File('$dirPath/$fileName');
    if (await file.exists()) throw Exception('A file with that name already exists.');
    await file.create(recursive: true);
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
}
