import 'dart:io';
import 'package:archive/archive.dart';

/// Zip compress/extract — the core ZArchiver-style feature. Uses the
/// `archive` package's stable core API (ZipDecoder/ZipEncoder over raw
/// bytes) rather than newer convenience helpers, so it stays correct
/// across package versions.
class ArchiveService {
  /// Extracts [zipPath] into a sibling folder with the same name as the
  /// zip (minus its extension) — e.g. `project.zip` -> `project/`.
  /// Returns the path of the created folder.
  Future<String> extractZip(String zipPath) async {
    final zipFile = File(zipPath);
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final parentDir = zipPath.substring(0, zipPath.lastIndexOf('/'));
    final baseName = zipPath.split('/').last;
    final folderName = baseName.toLowerCase().endsWith('.zip')
        ? baseName.substring(0, baseName.length - 4)
        : baseName;
    final destination = '$parentDir/$folderName';

    for (final entry in archive) {
      final outPath = '$destination/${entry.name}';
      if (entry.isFile) {
        final data = entry.content as List<int>;
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    return destination;
  }

  /// Compresses a single folder into a `<folderName>.zip` sitting next to
  /// it (in its parent directory).
  Future<String> compressFolder(String folderPath) async {
    final name = folderPath.split('/').last;
    final parentDir = folderPath.substring(0, folderPath.lastIndexOf('/'));
    final outputZipPath = '$parentDir/$name.zip';
    await _writeZip({folderPath: name}, outputZipPath);
    return outputZipPath;
  }

  /// Compresses a single file into a `<fileName>.zip` sitting next to it.
  Future<String> compressFile(String filePath) async {
    final name = filePath.split('/').last;
    final parentDir = filePath.substring(0, filePath.lastIndexOf('/'));
    final outputZipPath = '$parentDir/$name.zip';
    await _writeZip({filePath: name}, outputZipPath);
    return outputZipPath;
  }

  /// Compresses several files/folders (multi-select) into one zip named
  /// `Archive.zip` in [destinationDir].
  Future<String> compressMultiple(List<String> paths, String destinationDir) async {
    final entries = <String, String>{
      for (final path in paths) path: path.split('/').last,
    };
    var outputZipPath = '$destinationDir/Archive.zip';
    var counter = 1;
    while (await File(outputZipPath).exists()) {
      outputZipPath = '$destinationDir/Archive ($counter).zip';
      counter++;
    }
    await _writeZip(entries, outputZipPath);
    return outputZipPath;
  }

  /// [sourcesWithArcName] maps an absolute source path (file or folder) to
  /// the name/prefix it should have inside the zip.
  Future<void> _writeZip(Map<String, String> sourcesWithArcName, String outputZipPath) async {
    final archive = Archive();

    Future<void> walk(Directory dir, String arcPrefix) async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split('/').last;
        final arcPath = '$arcPrefix/$name';
        if (entity is Directory) {
          await walk(entity, arcPath);
        } else if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(arcPath, bytes.length, bytes));
        }
      }
    }

    for (final entry in sourcesWithArcName.entries) {
      final sourcePath = entry.key;
      final arcName = entry.value;
      final type = await FileSystemEntity.type(sourcePath);
      if (type == FileSystemEntityType.directory) {
        await walk(Directory(sourcePath), arcName);
      } else if (type == FileSystemEntityType.file) {
        final bytes = await File(sourcePath).readAsBytes();
        archive.addFile(ArchiveFile(arcName, bytes.length, bytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to build the zip archive.');
    }
    final outFile = File(outputZipPath);
    await outFile.create(recursive: true);
    await outFile.writeAsBytes(zipData);
  }
}
