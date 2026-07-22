import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import '../services/local_preview_server.dart';

/// Live preview for HTML — and, via a small generated wrapper, CSS/JS too
/// (see EditorScreen's _previewWrapped).
///
/// Serves [folderPath] over a local `http://127.0.0.1` server (see
/// LocalPreviewServer) instead of loading a `file://` URL directly.
/// Android WebView increasingly refuses `file://` access to external
/// storage paths (`net::ERR_ACCESS_DENIED`) regardless of the app's own
/// storage permission — serving the same folder over plain localhost HTTP
/// sidesteps that entirely, while every relative `<link>`/`<script>`/
/// `<img>` reference to a sibling file still resolves exactly the way it
/// would in a real browser, since the server root IS that real folder.
///
/// Eruda (a mobile-friendly devtools overlay — console, elements,
/// network, resources) is auto-injected after every page load. The
/// bundle (v3.4.3) ships as a local asset — fetched once at CI build-time
/// (see .github/workflows/android.yml) — so the inspector works fully
/// offline; nothing about it needs a network connection at preview time.
class PreviewScreen extends StatefulWidget {
  final String folderPath; // directory to serve
  final String fileName; // file within it to open
  final String title;

  const PreviewScreen({super.key, required this.folderPath, required this.fileName, required this.title});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  // Cached across injections (e.g. the manual re-tap) so the asset is
  // only ever read from the bundle once per screen.
  static String? _erudaSourceCache;

  final _server = LocalPreviewServer();
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
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
      await _controller.loadRequest(Uri.parse('$baseUrl/${widget.fileName}'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not start the local preview server:\n$e';
        });
      }
    }
  }

  Future<void> _injectEruda() async {
    try {
      _erudaSourceCache ??= await rootBundle.loadString('assets/eruda.min.js');
      const isDefined = "typeof eruda !== 'undefined'";
      // Only evaluates the (fairly large) bundle if eruda isn't already
      // defined on this page, and only calls init() once per page load —
      // re-injecting is safe to call again (e.g. the manual button after
      // auto-inject already ran) without spawning duplicate UI.
      final script = '''
if (!($isDefined)) {
  $_erudaSourceCache
}
if ($isDefined && !window.__erudaInited) {
  eruda.init();
  window.__erudaInited = true;
}
''';
      await _controller.runJavaScript(script);
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
    _controller.reload();
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Inspect (Eruda devtools)',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: _injectEruda,
          ),
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
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
        ),
      ),
    );
  }
}
