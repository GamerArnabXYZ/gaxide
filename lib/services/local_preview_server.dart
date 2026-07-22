import 'dart:io';

/// Serves a single folder over `http://127.0.0.1:<port>/` so the preview
/// WebView can load it as a normal HTTP page.
///
/// Android WebView increasingly refuses `file://` URLs pointing at
/// external storage (`net::ERR_ACCESS_DENIED`) — a scoped-storage/security
/// restriction that has nothing to do with the app's own storage
/// permission, and no WebViewController setting reliably works around it
/// on every device/OS version. Serving the same folder over plain HTTP to
/// localhost sidesteps the restriction completely: it's just an ordinary
/// web request, so every relative `<link>`/`<script>`/`<img>` reference
/// resolves exactly the way it would against a real folder, with none of
/// the file-scheme restrictions.
class LocalPreviewServer {
  HttpServer? _server;

  int? get port => _server?.port;

  /// Starts serving [rootDir] and returns the base URL
  /// (`http://127.0.0.1:<port>`). Only ever binds to loopback — nothing
  /// here is reachable from outside the device.
  Future<String> start(String rootDir) async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) => _handle(request, rootDir));
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> _handle(HttpRequest request, String rootDir) async {
    try {
      final decodedPath = Uri.decodeComponent(request.uri.path);
      final relative = decodedPath == '/' ? '/index.html' : decodedPath;
      final file = File('$rootDir$relative');

      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('404 — not found: $relative');
        await request.response.close();
        return;
      }

      request.response.headers.contentType = _contentTypeFor(file.path);
      await request.response.addStream(file.openRead());
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

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
