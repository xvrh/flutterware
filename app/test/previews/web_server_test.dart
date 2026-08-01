import 'dart:io';

import 'package:flutterware_app/src/previews/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What a browser needs from the server, asserted with a real client.
///
/// Every failure here presents as a blank page — a Flutter web build that
/// cannot fetch its own payload renders nothing and says nothing — so the
/// assertions are about headers and status codes rather than about anything
/// visible.
void main() {
  late Directory root;
  late HttpClient client;
  final servers = <CatalogWebServer>[];

  Future<CatalogWebServer> serve({String basePath = '/'}) async {
    var server = await CatalogWebServer.serve(root.path, basePath: basePath);
    servers.add(server);
    return server;
  }

  Future<HttpClientResponse> get(Uri url) async =>
      (await client.getUrl(url)).close();

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_web_server_test');
    client = HttpClient();
    write('index.html', '<!doctype html><title>catalog</title>');
    write('main.dart.js', 'console.log(1);');
    write('assets/AssetManifest.json', '{}');
  });

  tearDown(() async {
    client.close(force: true);
    for (var server in servers) {
      await server.close();
    }
    servers.clear();
    root.deleteSync(recursive: true);
  });

  test('the root serves the index', () async {
    var server = await serve();
    var response = await get(server.url);

    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/html');
  });

  test('script and manifest come back as their own types', () async {
    var server = await serve();

    // A `.js` served as text/plain does not execute, and the page is blank
    // with nothing in the console to say why.
    var script = await get(server.url.resolve('main.dart.js'));
    expect(script.statusCode, 200);
    expect(script.headers.contentType?.mimeType, 'text/javascript');

    var manifest = await get(server.url.resolve('assets/AssetManifest.json'));
    expect(manifest.statusCode, 200);
    expect(manifest.headers.contentType?.mimeType, 'application/json');
  });

  test('nothing is cached, so a rebuild is what a reload shows', () async {
    var server = await serve();
    var response = await get(server.url);

    expect(response.headers.value('cache-control'), 'no-store');
  });

  test('a path climbing out of the directory is refused', () async {
    write('../secret.txt', 'not yours');
    var server = await serve();

    // Sent raw rather than through `Uri.resolve`, which would normalise the
    // `..` away on the client and never exercise the server.
    var request = await client.get(
      server.url.host,
      server.url.port,
      '/../secret.txt',
    );
    var response = await request.close();

    expect(response.statusCode, anyOf(403, 404));
  });

  test('a missing file is a 404 rather than a hang', () async {
    var server = await serve();
    var response = await get(server.url.resolve('nope.js'));

    expect(response.statusCode, 404);
  });

  group('with a base href', () {
    test('the url carries the mount point', () async {
      var server = await serve(basePath: '/catalog/');
      expect(server.url.path, '/catalog/');
    });

    test('a slash is added at both ends if it was left off', () async {
      var server = await serve(basePath: 'catalog');
      expect(server.basePath, '/catalog/');
    });

    test('assets resolve under the prefix, and only there', () async {
      var server = await serve(basePath: '/catalog/');

      var index = await get(server.url);
      expect(index.statusCode, 200);

      var script = await get(server.url.resolve('main.dart.js'));
      expect(script.statusCode, 200);

      // The page's `<base href>` makes every asset request carry the prefix, so
      // serving the same files at the root as well would mean two URLs for one
      // page and a page that half-works from the wrong one.
      var atRoot = await get(
        Uri(
          scheme: 'http',
          host: server.url.host,
          port: server.url.port,
          path: '/main.dart.js',
        ),
      );
      expect(atRoot.statusCode, 404);
    });
  });
}
