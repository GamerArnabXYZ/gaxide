import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class OpenedFile {
  final String path;
  final String name;
  final String content;
  const OpenedFile({required this.path, required this.name, required this.content});
}

/// Handles local device file open/save for the mobile-first editing workflow.
class FileService {
  /// Android 11+ (API 30+) needs "All files access" for direct read/write on
  /// arbitrary paths. Fine for a personal sideloaded build (not Play Store).
  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<OpenedFile?> openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.single.path == null) return null;

    final path = result.files.single.path!;
    final content = await File(path).readAsString();
    return OpenedFile(path: path, name: result.files.single.name, content: content);
  }

  Future<String> saveToPath(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content, flush: true);
    return path;
  }

  /// Used the first time a brand-new (never opened) file is saved.
  Future<String> saveAsNew(String fileName, String content) async {
    Directory dir;
    try {
      dir = (await getExternalStorageDirectory())!;
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    final path = '${dir.path}/$fileName';
    return saveToPath(path, content);
  }
}
