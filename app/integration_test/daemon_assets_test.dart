@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
///
/// **Its subject is a project of its own**, built below rather than borrowed.
/// This used to catalog `examples/example`, and so hashed to the same
/// [DaemonAddress] as the second-project tests in `compiler_daemon_test.dart`
/// — which is the daemon working as designed, one process per catalog however
/// many clients want it. But `dart test` runs the two files at once, and one
/// of those tests restarts that daemon three times: this file's next `refresh`
/// then wrote to a socket nobody was holding, and the test that was waiting on
/// an announcement waited for one no process was left to make. Measured before
/// this: three whole-directory runs in four failed, on `Broken pipe` and on
/// `Bad state: No element`. A project nobody else names cannot be restarted
/// out from under this file — and, the other half of the same trade, the
/// pubspec rewrites below no longer land in a workspace member two other
/// suites are scanning.
void main() {
  late DaemonConfig config;
  late String dartExecutable;
  late CompilerDaemonClient daemon;
  late DaemonReady ready;
  late File added;
  late File pubspec;
  late String pubspecBefore;

  setUpAll(() async {
    var appRoot = Directory.current.path;
    var exampleRoot = p.join(p.dirname(appRoot), 'examples', 'example');
    var cache = FlutterCache.fromRunningSdk();
    dartExecutable = p.join(cache.flutterRoot, 'bin', 'dart');

    // A fixed path rather than a fresh temp directory per run: the address is
    // a hash of the config, so a project whose path moved every run would cold
    // compile a daemon every run and leave another `app/build/catalog/<key>`
    // behind it. Rebuilt from scratch below, so the contents are this run's
    // whatever the last one did.
    //
    // Outside the repository, because a pubspec inside it joins the pub
    // workspace and a `demo/` inside it joins the analysis.
    //
    // Named for the checkout, because `systemTemp` is one directory per *user*
    // and this machine has several worktrees. Their configs differ — the app
    // root and the package config are each checkout's own — so their daemons
    // would not collide, but the project underneath them would: the second
    // suite to reach `setUpAll` deletes the tree the first one's tests are
    // mid-way through rewriting. Which is the collision this whole file is
    // about, one scope further out.
    var projectRoot = Directory(
      p.join(
        Directory.systemTemp.path,
        'fw_daemon_assets_fixture.'
        '${sha1.convert(utf8.encode(appRoot)).toString().substring(0, 16)}',
      ),
    );
    if (projectRoot.existsSync()) projectRoot.deleteSync(recursive: true);
    Directory(p.join(projectRoot.path, 'demo')).createSync(recursive: true);
    Directory(p.join(projectRoot.path, 'assets', 'images'))
        .createSync(recursive: true);
    Directory(p.join(projectRoot.path, 'assets', 'fonts'))
        .createSync(recursive: true);

    // A real font file, because the bundle assembles what the pubspec declares
    // rather than taking its word for it.
    File(
      p.join(exampleRoot, 'assets', 'fonts', 'Roboto-Bold.ttf'),
    ).copySync(p.join(projectRoot.path, 'assets', 'fonts', 'Roboto-Bold.ttf'));
    // One file the bundle holds throughout, so the changes below are the only
    // ones there are.
    File(p.join(projectRoot.path, 'assets', 'images', 'anchor.png'))
        .writeAsBytesSync(const [0]);
    // A daemon with no entries refuses to start, so the project needs one.
    File(p.join(projectRoot.path, 'demo', 'probe.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Probe')
Widget assetsProbe() =>
    const Text('probe', textDirection: TextDirection.ltr);
''');

    pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
    pubspecBefore = '''
name: fw_daemon_assets_fixture
publish_to: none

environment:
  sdk: ^3.10.0

flutter:
  assets:
    - assets/images/
  fonts:
    - family: FixtureRoboto
      fonts:
        - asset: assets/fonts/Roboto-Bold.ttf
''';
    pubspec.writeAsStringSync(pubspecBefore);

    added = File(
      p.join(projectRoot.path, 'assets', 'images', 'daemon_assets_probe.png'),
    );

    config = DaemonConfig(
      appPackageRoot: appRoot,
      projectRoot: projectRoot.path,
      // The workspace's, since the fixture is outside it and has none of its
      // own: it is what resolves `package:flutter` for the probe demo.
      packageConfig: requirePackageConfig(exampleRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: const ['demo'],
    );

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

  // Nothing else catalogs this project, so the daemon is stopped rather than
  // left for a client that will never come.
  tearDownAll(() => daemon.stopDaemon());

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
