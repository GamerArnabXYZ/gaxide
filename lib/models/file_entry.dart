/// Represents a single file or folder row inside the File Manager.
class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;

  /// True only for directories that contain a `.git` folder — these are
  /// the only folders that ever show a "Push to GitHub" action.
  final bool isGitRepo;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
    this.isGitRepo = false,
  });

  String get extension {
    if (isDirectory || !name.contains('.')) return '';
    return name.split('.').last.toLowerCase();
  }

  String get readableSize {
    if (isDirectory) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
