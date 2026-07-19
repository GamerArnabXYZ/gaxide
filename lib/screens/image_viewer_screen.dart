import 'dart:io';
import 'package:flutter/material.dart';

/// Full-screen image preview with pinch-to-zoom/pan. Uses only core
/// Flutter (Image + InteractiveViewer) — no extra package needed, and no
/// gesture conflicts since a plain Image isn't editable/scrollable text.
class ImageViewerScreen extends StatelessWidget {
  final String filePath;
  const ImageViewerScreen({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final fileName = filePath.split('/').last;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(fileName, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.file(
            File(filePath),
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '⚠️ Could not render this image.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
