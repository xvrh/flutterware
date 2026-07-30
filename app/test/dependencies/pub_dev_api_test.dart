import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/dependencies/model/pub_dev_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Shapes taken from the live responses for `http` on 2026-07-29.
final _packageJson = jsonEncode({
  'name': 'http',
  'latest': {
    'version': '1.6.0',
    'published': '2025-11-10T18:27:56.434747Z',
    'pubspec': {
      'name': 'http',
      'version': '1.6.0',
      'description': 'A composable API for making HTTP requests.',
      'repository': 'https://github.com/dart-lang/http',
      'topics': ['http', 'network'],
    },
  },
  'versions': [
    {'version': '1.5.0', 'published': '2025-01-10T00:00:00.000Z'},
    {'version': '1.6.0', 'published': '2025-11-10T18:27:56.434747Z'},
  ],
});

final _scoreJson = jsonEncode({
  'grantedPoints': 160,
  'maxPoints': 160,
  'likeCount': 8461,
  'downloadCount30Days': 9761146,
  'tags': [
    'publisher:dart.dev',
    'sdk:dart',
    'sdk:flutter',
    'platform:android',
    'platform:ios',
    'platform:web',
    'is:wasm-ready',
    'is:dart3-compatible',
    'license:bsd-3-clause',
    'license:fsf-libre',
    'license:osi-approved',
  ],
});

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('fw_pub_dev');
  });

  tearDown(() => cache.deleteSync(recursive: true));

  PubDevApi apiWith(
    http.Client client, {
    Duration ttl = const Duration(hours: 12),
  }) => PubDevApi(client: client, cacheDirectory: cache, ttl: ttl);

  MockClient serving({
    String? package,
    String? score,
    int status = 200,
    List<Uri>? log,
  }) => MockClient((request) async {
    log?.add(request.url);
    if (request.url.path.endsWith('/score')) {
      return http.Response(score ?? _scoreJson, status);
    }
    return http.Response(package ?? _packageJson, status);
  });

  group('parsing', () {
    test('merges both endpoints into one record', () async {
      var result = (await apiWith(serving()).fetch('http'))!;

      expect(result.latestVersion, '1.6.0');
      expect(result.repository, 'https://github.com/dart-lang/http');
      expect(result.topics, ['http', 'network']);
      expect(result.downloadCount30Days, 9761146);
      expect(result.grantedPoints, 160);
      expect(result.maxPoints, 160);
    });

    test('reads publisher, platforms and SDKs out of the tags', () async {
      var result = (await apiWith(serving()).fetch('http'))!;

      expect(result.publisher, 'dart.dev');
      expect(result.platforms, ['android', 'ios', 'web']);
      expect(result.sdks, ['dart', 'flutter']);
      expect(result.isWasmReady, isTrue);
      expect(result.isDart3Compatible, isTrue);
    });

    test('picks the real licence out of the three license tags', () async {
      // pub.dev emits `license:fsf-libre` and `license:osi-approved` next to
      // the actual identifier; those are properties of the licence, not names.
      expect((await apiWith(serving()).fetch('http'))!.license, 'bsd-3-clause');
    });

    test('knows when the resolved version is the latest', () async {
      var result = (await apiWith(serving()).fetch('http'))!;
      expect(result.isLatest('1.6.0'), isTrue);
      expect(result.isLatest('1.5.0'), isFalse);
      expect(result.publishedAt('1.5.0'), DateTime.utc(2025, 1, 10));
      expect(result.publishedAt('0.0.1'), isNull);
    });
  });

  group('failure is never fatal', () {
    test('a 404 yields null rather than throwing', () async {
      expect(await apiWith(serving(status: 404)).fetch('nope'), isNull);
    });

    test('a network error yields null rather than throwing', () async {
      var api = apiWith(
        MockClient((_) async => throw const SocketException('offline')),
      );
      expect(await api.fetch('http'), isNull);
    });

    test('a malformed body yields null rather than throwing', () async {
      expect(await apiWith(serving(package: 'not json')).fetch('http'), isNull);
    });

    test('a missing package document wins over a present score', () async {
      // The score alone describes nothing, so it is not worth reporting.
      var api = apiWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/score')) {
            return http.Response(_scoreJson, 200);
          }
          return http.Response('{}', 404);
        }),
      );
      expect(await api.fetch('http'), isNull);
    });
  });

  group('caching', () {
    test('a second fetch does not hit the network', () async {
      var log = <Uri>[];
      var api = apiWith(serving(log: log));

      await api.fetch('http');
      expect(log, hasLength(2));
      await api.fetch('http');
      expect(log, hasLength(2), reason: 'served from memory');
    });

    test('a fresh disk cache is used by a new client', () async {
      await apiWith(serving()).fetch('http');

      var log = <Uri>[];
      var second = apiWith(serving(log: log));
      var result = await second.fetch('http');

      expect(log, isEmpty, reason: 'served from disk');
      expect(result!.latestVersion, '1.6.0');
    });

    test('an expired cache is refetched', () async {
      await apiWith(serving()).fetch('http');

      var log = <Uri>[];
      var second = apiWith(serving(log: log), ttl: Duration.zero);
      await second.fetch('http');

      expect(log, hasLength(2));
    });

    test('an expired cache is still served when the network fails', () async {
      // Expiry is a refresh policy, not a correctness boundary: a stale
      // download count beats a detail page with a hole in it.
      await apiWith(serving()).fetch('http');

      var offline = PubDevApi(
        client: MockClient((_) async => throw const SocketException('offline')),
        cacheDirectory: cache,
        ttl: Duration.zero,
      );
      var result = await offline.fetch('http');

      expect(result, isNotNull);
      expect(result!.downloadCount30Days, 9761146);
    });

    test('a corrupt cache file is ignored, not fatal', () async {
      File(p.join(cache.path, 'http.json')).writeAsStringSync('{ truncated');

      var result = await apiWith(serving()).fetch('http');
      expect(result!.latestVersion, '1.6.0');
    });

    test('an unwritable cache directory does not break fetching', () async {
      var api = PubDevApi(
        client: serving(),
        cacheDirectory: Directory('/dev/null/nope'),
      );
      expect((await api.fetch('http'))!.latestVersion, '1.6.0');
    });
  });
}
