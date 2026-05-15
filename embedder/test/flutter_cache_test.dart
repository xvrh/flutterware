import 'dart:io';

import 'package:flutterware_embedder/src/flutter_cache.dart';
import 'package:test/test.dart';

void main() {
  test('resolves existing Flutter cache artifacts from the running SDK', () {
    var cache = FlutterCache.fromRunningSdk();

    expect(File(cache.platformDill).existsSync(), isTrue,
        reason: 'platform_strong.dill should exist at ${cache.platformDill}');
    expect(File(cache.icuData).existsSync(), isTrue,
        reason: 'icudtl.dat should exist at ${cache.icuData}');
    expect(
        Directory(cache.macOsFrameworkDir).existsSync(), isTrue,
        reason: 'framework dir should exist at ${cache.macOsFrameworkDir}');
    expect(
        Directory('${cache.macOsFrameworkDir}/FlutterMacOS.framework')
            .existsSync(),
        isTrue);
  });
}
