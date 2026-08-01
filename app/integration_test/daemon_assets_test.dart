@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The daemon notices asset changes on refresh and says so.
///
/// No guest and no GPU — what is claimed here is daemon behaviour: a refresh
/// rebuilds the shared bundle in place, a client that subscribed hears
/// [AssetsChanged] exactly when something differed, and the session's mirror
/// resolves the new file. What a *running guest* then needs is measured in
/// `asset_refresh_test.dart`, which is where the GPU is.
void main() {
  late String exampleRoot;
  late DaemonConfig config;
  late String dartExecutable;
  late CompilerDaemonClient daemon;
  late DaemonReady ready;
  late File added;
  late File pubspec;
  late String pubspecBefore;

  setUpAll(() async {
    var appRoot = Directory.current.path;
    exampleRoot = p.join(p.dirname(appRoot), 'examples', 'example');
    var cache = FlutterCache.fromRunningSdk();
    dartExecutable = p.join(cache.flutterRoot, 'bin', 'dart');
    config = DaemonConfig(
      appPackageRoot: appRoot,
      projectRoot: exampleRoot,
      packageConfig: requirePackageConfig(exampleRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: const ['demo'],
    );

    added = File(
      p.join(exampleRoot, 'assets', 'images', 'daemon_assets_probe.png'),
    );
    if (added.existsSync()) added.deleteSync();
    pubspec = File(p.join(exampleRoot, 'pubspec.yaml'));
    pubspecBefore = pubspec.readAsStringSync();

    // A daemon left over from an earlier run has that run's bundle state.
    var (stale, _) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    await stale.stopDaemon();

    (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
  });

  tearDownAll(() async {
    // The example project is a workspace member; whatever this test did to it
    // must not outlive the test.
    pubspec.writeAsStringSync(pubspecBefore);
    if (added.existsSync()) added.deleteSync();
    await daemon.close();
  });

  /// The next [AssetsChanged], subscribed before [provoke] so the broadcast
  /// cannot land in the gap.
  Future<AssetsChanged> announced(void Function() provoke) {
    var next = daemon.assetsChanges.first;
    provoke();
    return next.timeout(const Duration(seconds: 30));
  }

  test('an added file is announced, and reaches the session mirror', () async {
    added.writeAsBytesSync(const [1, 2, 3]);

    var change = await announced(daemon.refresh);

    expect(change.fontsChanged, isFalse);
    var mirrored = File(
      p.join(ready.assetsDir, 'assets', 'images', 'daemon_assets_probe.png'),
    );
    expect(
      mirrored.existsSync(),
      isTrue,
      reason:
          'The session assets dir mirrors the shared bundle, so the new '
          'symlink must resolve through it — this is the path a guest reads.',
    );
  });

  test('a refresh with nothing moved says nothing', () async {
    var heard = false;
    var sub = daemon.assetsChanges.listen((_) => heard = true);
    daemon.refresh();
    // No reply to wait on — refresh is fire-and-forget — so give a wrong
    // broadcast ample time to arrive before believing its absence.
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    expect(
      heard,
      isFalse,
      reason:
          'An unchanged bundle must not be announced: every announcement '
          'costs each session an evict and a reassemble.',
    );
  });

  test('a font declaration is announced as one', () async {
    var change = await announced(() {
      pubspec.writeAsStringSync('''
$pubspecBefore
    - family: DaemonAssetsProbe
      fonts:
        - asset: assets/fonts/Roboto-Bold.ttf
''');
      daemon.refresh();
    });

    expect(change.fontsChanged, isTrue);
  });

  test('a removed file is announced too', () async {
    pubspec.writeAsStringSync(pubspecBefore);
    added.deleteSync();

    var change = await announced(daemon.refresh);

    // The pubspec restore above also un-declares the probe font family.
    expect(change.fontsChanged, isTrue);
    expect(
      File(
        p.join(ready.assetsDir, 'assets', 'images', 'daemon_assets_probe.png'),
      ).existsSync(),
      isFalse,
    );
  });
}
