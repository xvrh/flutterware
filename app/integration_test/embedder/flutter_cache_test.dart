import 'dart:io';

import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:test/test.dart';

void main() {
  test('resolves existing Flutter cache artifacts from the running SDK', () {
    var cache = FlutterCache.fromRunningSdk();

    expect(
      File(cache.platformDill).existsSync(),
      isTrue,
      reason: 'platform_strong.dill should exist at ${cache.platformDill}',
    );
    // One ICU for both lanes now — the tester spawns against it and so does the
    // guest. It resolves per host, so on Linux and Windows this is the
    // assertion that matters.
    expect(
      File(cache.icuData).existsSync(),
      isTrue,
      reason: 'icudtl.dat should exist at ${cache.icuData}',
    );
    expect(
      cache.engineRevision,
      matches(RegExp(r'^[0-9a-f]{40}$')),
      reason: 'engine.stamp should hold a 40-char git revision',
    );
  });

  test('names this host the way the artifact server does', () {
    var cache = FlutterCache.fromRunningSdk();

    // The same string indexes the local cache and the download URL, so a typo
    // here is a 404 rather than a missing directory.
    expect(
      cache.hostPlatform,
      Platform.isMacOS
          ? 'darwin-x64'
          : matches(RegExp(r'^(linux|windows)-(x64|arm64)$')),
    );
  });
}
