import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/editor_language.dart';
import '../services/local_preview_server.dart';
import '../widgets/code_editor.dart';

/// Live preview for HTML — and, via a small generated wrapper, CSS/JS too
/// (see EditorScreen's _previewWrapped).
///
/// Serves [folderPath] over a local HTTP server (see LocalPreviewServer)
/// instead of a `file://` URL, which Android WebView increasingly refuses
/// for external storage paths. Every relative `<link>`/`<script>`/`<img>`
/// reference to a sibling file still resolves exactly like a real
/// browser, since the server root IS that real folder.
///
/// Orientation-aware:
/// - Landscape: the editor and a live preview sit side by side. Typing
///   updates the preview automatically (debounced ~500ms) without ever
///   needing to hit Save.
/// - Portrait: the preview takes the full screen, with a "Copy Link"
///   action in the app bar. That link (served on the device's own LAN
///   address, not just loopback) opens in Chrome or any browser — on
///   this device or another one on the same Wi-Fi — and live-updates the
///   exact same way, via a small polling script the server injects into
///   every page it serves.
///
/// [controller] is the SAME CodeController the editor screen is already
/// using — editing it here (in landscape) is editing the actual file
/// buffer, no separate sync needed; popping back to EditorScreen shows
/// the identical content since it's literally the same object.
class PreviewScreen extends StatefulWidget {
  final String folderPath; // directory the local server serves
  final String fileName; // file to actually load in the WebView
  final String liveOverridePath; // which served path gets live content from `controller`
  final String title;
  final CodeController controller;
  final EditorLanguage language;
  final ValueChanged<EditorLanguage> onLanguageChanged;
  final UndoHistoryController? undoController;
  final bool readOnly;

  const PreviewScreen({
    super.key,
    required this.folderPath,
    required this.fileName,
    required this.liveOverridePath,
    required this.title,
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
    this.undoController,
    this.readOnly = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  // Cached across injections (e.g. the manual re-tap) so the asset is
  // only ever read from the bundle once per screen.
  static String? _erudaSourceCache;

  final _server = LocalPreviewServer();
  late final WebViewController _webController;
  bool _loading = true;
  String? _loadError;
  Timer? _debounce;
  String? _lanUrl;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEdit);
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _injectEruda();
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadError = error.description;
              });
            }
          },
        ),
      );
    _startAndLoad();
  }

  Future<void> _startAndLoad() async {
    try {
      final baseUrl = await _server.start(widget.folderPath);
      // Seed with whatever's currently in the editor — even if it's
      // never been saved — so the very first load already reflects it.
      _server.updateOverride(widget.liveOverridePath, widget.controller.text);
      await _webController.loadRequest(Uri.parse('$baseUrl/${widget.fileName}'));

      final lan = await LocalPreviewServer.lanAddress();
      if (mounted) {
        setState(() {
          _lanUrl = lan != null ? 'http://$lan:${_server.port}/${widget.fileName}' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not start the local preview server:\n$e';
        });
      }
    }
  }

  void _onEdit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _server.updateOverride(widget.liveOverridePath, widget.controller.text);
      // No explicit reload call needed — the poll script running inside
      // whatever page is currently loaded (in-app, in Chrome, on another
      // device) picks up the version bump on its own and reloads itself.
    });
  }

  Future<void> _copyLink() async {
    final url = _lanUrl ?? 'http://127.0.0.1:${_server.port}/${widget.fileName}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _lanUrl != null
              ? '🔗 Link copied — open it in Chrome, or on another device on the same Wi-Fi. It updates live as you type.'
              : '🔗 Link copied (this device only — no Wi-Fi network detected).',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _injectEruda() async {
    try {
      _erudaSourceCache ??= await rootBundle.loadString('assets/eruda.min.js');
      const isDefined = "typeof eruda !== 'undefined'";
      final script = '''
if (!($isDefined)) {
  $_erudaSourceCache
}
if ($isDefined && !window.__erudaInited) {
  eruda.init();
  window.__erudaInited = true;
}
''';
      await _webController.runJavaScript(script);
    } catch (_) {
      // Non-fatal — if the bundle is missing/a stub, the inspector button
      // just silently does nothing. The actual page preview is unaffected.
    }
  }

  void _reload() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _webController.reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    _debounce?.cancel();
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(tooltip: 'Copy Link', icon: const Icon(Icons.link_rounded), onPressed: _copyLink),
              IconButton(
                tooltip: 'Inspect (Eruda devtools)',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: _injectEruda,
              ),
              IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
            ],
          ),
          body: SafeArea(child: isLandscape ? _buildSplitView() : _buildPreviewArea()),
        );
      },
    );
  }

  Widget _buildSplitView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: CodeEditorView(
              controller: widget.controller,
              currentLanguage: widget.language,
              onLanguageChanged: widget.onLanguageChanged,
              undoController: widget.undoController,
              readOnly: widget.readOnly,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildPreviewArea()),
      ],
    );
  }

  Widget _buildPreviewArea() {
    return Stack(
      children: [
        WebViewWidget(controller: _webController),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_loadError != null)
          Container(
            color: Theme.of(context).colorScheme.surface,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text('⚠️ Could not load preview.\n$_loadError', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
