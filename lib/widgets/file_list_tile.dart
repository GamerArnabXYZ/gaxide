import 'package:flutter/material.dart';
import '../models/file_entry.dart';

IconData _iconFor(FileEntry entry) {
  if (entry.isDirectory) return Icons.folder_rounded;
  switch (entry.extension) {
    case 'js':
    case 'jsx':
    case 'mjs':
    case 'ts':
      return Icons.javascript_rounded;
    case 'py':
      return Icons.code_rounded;
    case 'dart':
      return Icons.flutter_dash_rounded;
    case 'html':
    case 'htm':
    case 'xml':
      return Icons.html_rounded;
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'h':
    case 'hpp':
    case 'c':
      return Icons.memory_rounded;
    case 'json':
      return Icons.data_object_rounded;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'webp':
    case 'gif':
      return Icons.image_rounded;
    case 'zip':
    case 'apk':
    case 'gz':
      return Icons.folder_zip_rounded;
    case 'txt':
    case 'md':
      return Icons.article_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

Color _iconColorFor(FileEntry entry, ColorScheme scheme) {
  if (entry.isDirectory) return const Color(0xFFFFC24B);
  switch (entry.extension) {
    case 'js':
    case 'jsx':
    case 'mjs':
      return const Color(0xFFF7DF1E);
    case 'py':
      return const Color(0xFF4B8BBE);
    case 'dart':
      return const Color(0xFF40C4FF);
    case 'html':
    case 'htm':
      return const Color(0xFFE34C26);
    case 'cpp':
    case 'cc':
    case 'h':
    case 'hpp':
      return const Color(0xFF00599C);
    default:
      return scheme.onSurfaceVariant;
  }
}

/// Single row in the File Manager list — folder or file, with size/date subtitle.
class FileListTile extends StatelessWidget {
  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileListTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.isDirectory
        ? 'Folder'
        : '${entry.readableSize} • ${entry.modified.day}/${entry.modified.month}/${entry.modified.year}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(entry), color: _iconColorFor(entry, scheme), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),
              if (entry.isDirectory)
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant.withOpacity(0.5)),
              if (!entry.isDirectory)
                IconButton(
                  icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant.withOpacity(0.7), size: 20),
                  onPressed: onLongPress,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
