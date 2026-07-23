import 'dart:convert';
import 'dart:io';

/// Serves a folder over HTTP for the in-editor HTML/CSS/JS preview.
///
/// Binds to all interfaces (0.0.0.0), not just loopback — so the same
/// link also works from Chrome (or any browser) on another device on the
/// same Wi-Fi, not just this app's own in-app WebView. There's no
/// authentication, same as any local dev-preview tool (live-server,
/// http-server, etc.) — anyone on the same network with the link can
/// view it while the preview screen stays open. It stops the moment the
/// preview screen closes.
///
/// Android WebView also increasingly refuses `file://` URLs pointing at
/// external storage (`net::ERR_ACCESS_DENIED`) regardless of the app's
/// own storage permission — serving over plain HTTP sidesteps that too.
///
/// Live reload: every HTML response gets a tiny polling script injected
/// right before `</body>` that checks a version counter and reloads the
/// page the instant it changes. That's what makes edits show up
/// automatically — in the in-app split view, in an external browser, and
/// on another device's browser — all through the exact same mechanism,
/// no matter who's looking at it.
class LocalPreviewServer {
  HttpServer? _server;
  int _liveVersion = 0;

  // relative path (e.g. "index.html") -> live, possibly-unsaved content.
  // Lets the file currently open in the editor preview instantly without
  // writing every keystroke to disk; anything not overridden here is
  // just read straight from [rootDir] as normal.
  final Map<String, String> _overrides = {};

  int? get port => _server?.port;

  Future<String> start(String rootDir) async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((request) => _handle(request, rootDir));
    return 'http://127.0.0.1:${server.port}';
  }

  /// Sets the live (possibly unsaved) content for [relativePath] and
  /// bumps the live-reload version so every connected viewer refreshes.
  void updateOverride(String relativePath, String content) {
    _overrides[relativePath] = content;
    _liveVersion++;
  }

  Future<void> _handle(HttpRequest request, String rootDir) async {
    try {
      final decodedPath = Uri.decodeComponent(request.uri.path);

      if (decodedPath == '/__gax_live__') {
        request.response.headers.contentType = ContentType.text;
        request.response.write('$_liveVersion');
        await request.response.close();
        return;
      }

      final relative = decodedPath == '/' ? '/index.html' : decodedPath;
      final overrideKey = relative.startsWith('/') ? relative.substring(1) : relative;
      final contentType = _contentTypeFor(relative);

      List<int> bytes;
      if (_overrides.containsKey(overrideKey)) {
        bytes = utf8.encode(_overrides[overrideKey]!);
      } else {
        final file = File('$rootDir$relative');
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('404 — not found: $relative');
          await request.response.close();
          return;
        }
        bytes = await file.readAsBytes();
      }

      final isHtml = contentType.mimeType == ContentType.html.mimeType;
      request.response.headers.contentType = contentType;
      if (isHtml) {
        final html = utf8.decode(bytes, allowMalformed: true);
        request.response.write(_injectLiveReload(html));
      } else {
        request.response.add(bytes);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Response may already be closed/broken — nothing more to do.
      }
    }
  }

  String _injectLiveReload(String html) {
    const script = '''
<script>
(function() {
  var lastVersion = null;
  function poll() {
    fetch('/__gax_live__').then(function(r) { return r.text(); }).then(function(v) {
      if (lastVersion === null) { lastVersion = v; }
      else if (v !== lastVersion) { location.reload(); return; }
      setTimeout(poll, 700);
    }).catch(function() { setTimeout(poll, 2000); });
  }
  poll();
})();
</script>
''';
    final idx = html.toLowerCase().lastIndexOf('</body>');
    if (idx == -1) return html + script;
    return html.substring(0, idx) + script + html.substring(idx);
  }

  ContentType _contentTypeFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'html':
      case 'htm':
        return ContentType.html;
      case 'css':
        return ContentType('text', 'css');
      case 'js':
      case 'mjs':
        return ContentType('application', 'javascript');
      case 'json':
        return ContentType.json;
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'gif':
        return ContentType('image', 'gif');
      case 'webp':
        return ContentType('image', 'webp');
      case 'woff':
        return ContentType('font', 'woff');
      case 'woff2':
        return ContentType('font', 'woff2');
      case 'ttf':
        return ContentType('font', 'ttf');
      case 'txt':
        return ContentType.text;
      default:
        return ContentType.binary;
    }
  }

  /// Best-effort LAN IPv4 address (typically the Wi-Fi interface) so the
  /// copied link also works from other devices on the same network —
  /// 127.0.0.1 only ever works on this device itself.
  static Future<String?> lanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // No usable network interface — the "Copy Link" feature will just
      // fall back to a loopback-only link (this device only).
    }
    return null;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _overrides.clear();
    _liveVersion = 0;
  }
}
