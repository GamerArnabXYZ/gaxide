import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// Live preview for HTML — and, via a small generated wrapper, CSS/JS too
/// (see EditorScreen's _previewWrapped).
///
/// The critical difference from a naive "show this HTML as a string"
/// preview (the kind that breaks the moment a page references its own
/// stylesheet or script): this loads the page through a real `file://`
/// URL pointing at its ACTUAL location on disk. Because the WebView's
/// base URL is then that real folder, every relative reference — `<link
/// href="style.css">`, `<script src="script.js">`, `<img src="...">`,
/// links to sibling HTML pages — resolves exactly the way it would in a
/// real browser, against the real files sitting right next to it. That's
/// the whole fix: nothing needs to be inlined or rewritten.
///
/// Eruda (a mobile-friendly devtools overlay — console, elements,
/// network, resources) is auto-injected after every page load, giving a
/// small floating inspector button right on the page — the same
/// devtools-on-a-phone experience you'd set up manually on a real mobile
/// site. The actual Eruda bundle (v3.4.3) ships as a local asset — fetched
/// once at CI build-time (see .github/workflows/android.yml) and read
/// straight from `assets/eruda.min.js` here, so the inspector works fully
/// offline on the device; nothing about it needs a network connection at
/// preview time.
class PreviewScreen extends StatefulWidget {
  final String fileUrl; // a file:// URL from Uri.file(...)
  final String title;

  const PreviewScreen({super.key, required this.fileUrl, required this.title});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  // Cached across injections (e.g. the manual re-tap) so the asset is
  // only ever read from the bundle once per screen.
  static String? _erudaSourceCache;

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
      )
      ..loadRequest(Uri.parse(widget.fileUrl));
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
    setState(() => _loadError = null);
    _controller.reload();
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
