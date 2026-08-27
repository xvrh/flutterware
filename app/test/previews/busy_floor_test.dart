import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/protocol.dart';

/// The floor between what the session *is* doing and what a status surface may
/// say it is doing.
///
/// Both questions are real and they are not the same one. Measured on this
/// repo's catalog: a warm switch is 64ms, and clicking the entry already on
/// screen is `compile 17ms · reload 104ms · 0 edited` — 121ms of announcement
/// for a frame that did not change. A rail row that appeared and left inside
/// either is a flash rather than news. But a capture must know the instant the
/// compiler starts, or `previews screenshot` races it and photographs the
/// previous demo, which is the one failure a screenshot tool must not have.
void main() {
  /// A connector that never answers, so [CatalogSession.start] gets as far as
  /// going busy and stops there — which is the whole state under test.
  Future<(CompilerDaemonClient, DaemonReady)> hangs({
    required String dartExecutable,
    required DaemonConfig config,
    void Function(String)? onLog,
    void Function(DaemonProgress)? onProgress,
  }) => Completer<(CompilerDaemonClient, DaemonReady)>().future;

  testWidgets('a surface is not told until the work has lasted', (
    tester,
  ) async {
    var session = CatalogSession(
      appPackageRoot: '/app',
      flutterSdkRoot: '/sdk',
      // A real package root, because [DaemonConfig.forPackage] resolves one
      // before the connector is ever called — a made-up path throws there and
      // the session is back to idle before the first expectation.
      projectRoot: Directory.current.path,
      connectToDaemon: hangs,
    );
    unawaited(session.start());

    expect(session.busyWith, 'building', reason: 'the truth, immediately');
    expect(session.visiblyBusyWith, isNull);

    await tester.pump(const Duration(milliseconds: 200));
    expect(
      session.visiblyBusyWith,
      isNull,
      reason: 'a warm switch is long over by here',
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(session.visiblyBusyWith, 'building');

    // In the body rather than a tearDown: the binding checks for stray timers
    // before those run, and a session that is busy is holding two.
    session.dispose();
  });

  testWidgets('and it is told at once when the work was already long', (
    tester,
  ) async {
    var session = CatalogSession(
      appPackageRoot: '/app',
      flutterSdkRoot: '/sdk',
      // A real package root, because [DaemonConfig.forPackage] resolves one
      // before the connector is ever called — a made-up path throws there and
      // the session is back to idle before the first expectation.
      projectRoot: Directory.current.path,
      connectToDaemon: hangs,
    );
    var notifications = 0;
    session.addListener(() => notifications++);
    unawaited(session.start());
    await tester.pump(const Duration(milliseconds: 300));

    // Crossing the floor is a change the surfaces have to hear about — nothing
    // else is going to rebuild the rail a quarter of a second after a click.
    expect(notifications, greaterThan(0));
    expect(session.visiblyBusyWith, 'building');

    session.dispose();
  });
}
