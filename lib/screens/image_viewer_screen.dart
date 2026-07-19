import 'dart:io';
import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/file_service.dart';
import '../widgets/file_info_dialog.dart';

/// Full-screen gallery viewer for every image in the current folder —
/// swipe left/right between them like a native gallery, double-tap or
/// pinch to zoom, and quick actions (info / delete) right from the app
/// bar. Tap the image once to hide/show the app bar for a
/// distraction-free view.
class ImageViewerScreen extends StatefulWidget {
  final List<FileEntry> images;
  final int initialIndex;

  const ImageViewerScreen({super.key, required this.images, required this.initialIndex});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final _fileService = FileService();
  late final PageController _pageController;
  late List<FileEntry> _images;
  late int _currentIndex;
  bool _chromeVisible = true;
  bool _changed = false; // becomes true after a delete, so the caller refreshes

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.images);
    _currentIndex = widget.initialIndex.clamp(0, _images.isEmpty ? 0 : _images.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  FileEntry get _current => _images[_currentIndex];

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Future<void> _showInfo() => showFileInfoDialog(context, _current);

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image?'),
        content: Text('"${_current.name}" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _fileService.delete(_current.path, false);
      _changed = true;
      if (!mounted) return;
      if (_images.length <= 1) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _images.removeAt(_currentIndex);
        if (_currentIndex >= _images.length) _currentIndex = _images.length - 1;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _chromeVisible
            ? AppBar(
                backgroundColor: Colors.black.withOpacity(0.55),
                elevation: 0,
                foregroundColor: Colors.white,
                title: Text(
                  _images.length > 1 ? '${_currentIndex + 1} / ${_images.length}' : _current.name,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(tooltip: 'Info', icon: const Icon(Icons.info_outline_rounded), onPressed: _showInfo),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
                ],
              )
            : null,
        body: PageView.builder(
          controller: _pageController,
          itemCount: _images.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (context, index) => _ZoomableImage(
            key: ValueKey(_images[index].path),
            filePath: _images[index].path,
            onTap: _toggleChrome,
          ),
        ),
      ),
    );
  }
}

/// One gallery page — pinch-zoom via [InteractiveViewer], plus a
/// double-tap that smoothly animates between fit-to-screen and 3x zoom
/// centered on the tap point. A single tap (not a drag/pinch) toggles the
/// surrounding app bar via [onTap].
class _ZoomableImage extends StatefulWidget {
  final String filePath;
  final VoidCallback onTap;
  const _ZoomableImage({super.key, required this.filePath, required this.onTap});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        if (_animation != null) _transformController.value = _animation!.value;
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final isZoomedIn = !_transformController.value.isIdentity();
    late final Matrix4 endMatrix;
    if (isZoomedIn) {
      endMatrix = Matrix4.identity();
    } else {
      final pos = _doubleTapDetails?.localPosition ?? Offset.zero;
      endMatrix = Matrix4.identity()
        ..translate(-pos.dx * 2, -pos.dy * 2)
        ..scale(3.0);
    }
    _animation = Matrix4Tween(begin: _transformController.value, end: endMatrix).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.5,
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(widget.filePath),
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
