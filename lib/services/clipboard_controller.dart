import 'package:flutter/foundation.dart';
import '../models/file_entry.dart';

/// Shared between both storage tabs so you can cut/copy a file in one tab
/// (e.g. Internal) and paste it into the other (e.g. SD Card).
class ClipboardController extends ChangeNotifier {
  List<FileEntry>? entries;
  bool isCut = false;

  bool get hasItems => entries != null && entries!.isNotEmpty;

  void set(List<FileEntry> newEntries, bool cut) {
    entries = newEntries;
    isCut = cut;
    notifyListeners();
  }

  void clear() {
    entries = null;
    notifyListeners();
  }
}
