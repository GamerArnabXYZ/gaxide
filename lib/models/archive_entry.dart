import 'package:archive/archive.dart';

/// A single row inside the in-zip file browser (ArchiveViewerScreen).
/// Folders are virtual — derived from the common path prefixes of the
/// zip's flat file list, since most zips don't store real folder
/// records. Only [file] entries carry actual content to preview/extract.
class ArchiveEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final ArchiveFile? file;

  const ArchiveEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.file,
  });

  int get sizeBytes => file?.size ?? 0;

  String get extension {
    if (isDirectory || !name.contains('.')) return '';
    return name.split('.').last.toLowerCase();
  }
}
