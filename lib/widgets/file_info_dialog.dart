import 'dart:io';
import 'package:flutter/material.dart';
import '../models/file_entry.dart';

/// Properties dialog — name, path, type, size/item-count, modified date.
Future<void> showFileInfoDialog(BuildContext context, FileEntry entry) async {
  String detail = 'Calculating...';

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        if (detail == 'Calculating...') {
          _computeDetail(entry).then((value) {
            if (ctx.mounted) setDialogState(() => detail = value);
          });
        }
        return AlertDialog(
          title: Text(entry.name, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Type', entry.isDirectory ? 'Folder' : 'File'),
              _infoRow('Path', entry.path),
              _infoRow(entry.isDirectory ? 'Contents' : 'Size', detail),
              _infoRow(
                'Modified',
                '${entry.modified.day}/${entry.modified.month}/${entry.modified.year} '
                    '${entry.modified.hour.toString().padLeft(2, '0')}:${entry.modified.minute.toString().padLeft(2, '0')}',
              ),
              if (entry.isGitRepo) _infoRow('Git', 'Yes — pushable to GitHub'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    ),
  );
}

Future<String> _computeDetail(FileEntry entry) async {
  try {
    if (!entry.isDirectory) return entry.readableSize;
    var files = 0;
    var folders = 0;
    await for (final item in Directory(entry.path).list(recursive: false)) {
      if (item is Directory) {
        folders++;
      } else {
        files++;
      }
    }
    return '$files file(s), $folders folder(s)';
  } catch (e) {
    return 'Unavailable';
  }
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
