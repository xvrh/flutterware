import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Serves a built catalog page, so the thing that was just compiled can be
/// looked at.
///
/// A Flutter web build cannot be opened as a `file:` URL — it fetches its own
/// manifests and its CanvasKit payload, and every one of those requests is
/// cross-origin from a file. So there has to be a server, and this is the
/// smallest one that works.
///
/// **Hand-rolled rather than `shelf_static`.** The CLI compiles this app on the
/// user's machine at first run, so a dependency is a thing everyone installing
/// flutterware has to fetch and build. What is needed here is one directory,
/// read-only, on loopback, with content types — not the package's symlink
/// policy, directory listings and cache validators.
class CatalogWebServer {
  CatalogWebServer._(this._server, this.root, this.basePath);

  final HttpServer _server;

  /// The directory being served, absolute.
  final String root;

  /// The path the page is mounted at. `/` unless it was built with a
  /// `--base-href`, which is a promise about where it will be served from.
  final String basePath;

  Uri get url => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: basePath,
  );

  /// Binds an ephemeral port on loopback.
  ///
  /// **Loopback, never `anyIPv4`.** A catalog is unreleased UI: it is a picture
  /// of what a product is about to look like, and binding it to every interface
  /// publishes that to whatever network the machine is on. Someone who wants
  /// that can copy the directory to a host that is meant to be public.
  ///
  /// [basePath] must match the `--base-href` the page was built with. A build
  /// with a base href writes `<base href="/catalog/">` into its index, so every
  /// asset it asks for is under that prefix — served at the root instead, the
  /// page loads and then fetches nothing it needs.
  static Future<CatalogWebServer> serve(
    String root, {
    String basePath = '/',
  }) async {
    var absolute = p.absolute(root);
    if (!Directory(absolute).existsSync()) {
      throw ArgumentError.value(root, 'root', 'is not a directory');
    }
    var prefix = normaliseBasePath(basePath);
    var server = await io.serve(
      _handlerFor(absolute, prefix),
      InternetAddress.loopbackIPv4,
      0,
    );
    return CatalogWebServer._(server, absolute, prefix);
  }

  Future<void> close() => _server.close(force: true);

  /// A mount point with both slashes, which is the form [basePath] is compared
  /// and matched in. Exposed so a caller deciding whether an existing server
  /// still fits compares the same thing this stored.
  static String normaliseBasePath(String basePath) {
    var prefix = basePath.isEmpty ? '/' : basePath;
    if (!prefix.startsWith('/')) prefix = '/$prefix';
    return prefix.endsWith('/') ? prefix : '$prefix/';
  }

  static Handler _handlerFor(String root, String prefix) => (request) {
    // `Request.url` is always relative — no leading slash — so the prefix is
    // compared without one.
    var relativePrefix = prefix.substring(1);
    var path = request.url.path;
    if (relativePrefix.isNotEmpty) {
      if (!path.startsWith(relativePrefix)) {
        return Response.notFound('This page is served at $prefix');
      }
      path = path.substring(relativePrefix.length);
    }

    var requested = path.isEmpty ? 'index.html' : path;
    var file = File(p.join(root, requested));

    // `..` in a URL is the whole of the traversal risk here. Resolving first
    // and then checking containment catches it however it was spelled, which
    // string matching on the request does not.
    var resolved = p.normalize(file.absolute.path);
    if (!p.equals(resolved, root) && !p.isWithin(root, resolved)) {
      return Response.forbidden('Outside the served directory.');
    }

    if (!file.existsSync()) return Response.notFound('Not found: $requested');

    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': _contentType(resolved),
        // A rebuild writes over this directory while the tab is open, and the
        // next thing anyone does is reload it. A cached response would show
        // them the build they were trying to replace.
        'cache-control': 'no-store',
      },
      context: {'shelf.io.buffer_output': false},
    );
  };

  /// Enough of a table for what `flutter build web` emits.
  ///
  /// A wrong type here is not cosmetic: a `.js` served as text/plain does not
  /// execute, and `.wasm` served as anything else fails
  /// `instantiateStreaming` — both of which present as a blank page.
  static String _contentType(String path) => switch (p.extension(path)) {
    '.html' => 'text/html; charset=utf-8',
    '.js' || '.mjs' => 'text/javascript; charset=utf-8',
    '.json' || '.map' => 'application/json; charset=utf-8',
    '.css' => 'text/css; charset=utf-8',
    '.wasm' => 'application/wasm',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.svg' => 'image/svg+xml',
    '.ico' => 'image/x-icon',
    '.ttf' => 'font/ttf',
    '.otf' => 'font/otf',
    '.woff' => 'font/woff',
    '.woff2' => 'font/woff2',
    // Covers `.bin`, `.symbols`, `.dat`, and whatever the engine adds next. A
    // byte stream the browser does not try to interpret is the safe default.
    _ => 'application/octet-stream',
  };
}
