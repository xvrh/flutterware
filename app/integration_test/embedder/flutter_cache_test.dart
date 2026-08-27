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
    // The tester lane's ICU, which is the one that resolves per host: this is
    // what `audit`, the thumbnails and the scenario runner all spawn against,
    // so on Linux and Windows it is the assertion that matters.
    expect(
      File(cache.testerIcuData).existsSync(),
      isTrue,
      reason: 'icudtl.dat should exist at ${cache.testerIcuData}',
    );
    expect(
      cache.engineRevision,
      matches(RegExp(r'^[0-9a-f]{40}$')),
      reason: 'engine.stamp should hold a 40-char git revision',
    );
  });

  test("resolves the embedder guest's own ICU", () {
    // Separate, and macOS-only, because [FlutterCache.icuData] is deliberately
    // `darwin-x64`: it is loaded beside `FlutterEmbedder.framework`, which
    // ships for macOS and nowhere else. Off macOS there is no such file and
    // nothing that would read it — see the guest's README.
    var cache = FlutterCache.fromRunningSdk();

    expect(
      File(cache.icuData).existsSync(),
      isTrue,
      reason: 'icudtl.dat should exist at ${cache.icuData}',
    );
  }, skip: Platform.isMacOS ? null : 'the embedder guest is macOS-only');
}
