import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/catalog/live_session.dart';

void main() {
  // Derived from the path, so nothing here touches a session a person has
  // actually got open — these roots exist nowhere.
  var root = '/tmp/flutterware-live-session-test/pkg';

  tearDown(() => LiveSession.clear(root));

  group('the key', () {
    test('is the same catalog however the path was spelled', () {
      // The GUI joins a package path onto a worktree and `fw` does the same,
      // and for the root package that join ends in `/.` — so if these three
      // did not agree, the root package could never attach at all.
      expect(LiveSession.keyFor(root), LiveSession.keyFor('$root/'));
      expect(LiveSession.keyFor(root), LiveSession.keyFor('$root/.'));
      expect(LiveSession.keyFor(root), LiveSession.keyFor('$root/sub/..'));
    });

    test('separates two packages', () {
      expect(
        LiveSession.keyFor(root),
        isNot(LiveSession.keyFor('$root-other')),
      );
    });
  });

  group('publishing', () {
    test('round-trips, and a spelling of the path does not matter', () {
      LiveSession.publish(
        LiveSession(
          projectRoot: root,
          vmServiceUri: 'http://127.0.0.1:4321/tok/',
          pid: 999,
        ),
      );

      var read = LiveSession.read('$root/');
      expect(read, isNotNull);
      expect(read!.vmServiceUri, 'http://127.0.0.1:4321/tok/');
      expect(read.pid, 999);
    });

    test('nothing published is null rather than an error', () {
      expect(LiveSession.read(root), isNull);
    });

    test('a half-written file reads as no session', () {
      var file = LiveSession.fileFor(root);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{"vmServiceUri": "http://12');

      // Not a throw: a caller that cannot read the handle can still render its
      // own guest, and failing the whole call over a scratch file would be
      // trading a working answer for none.
      expect(LiveSession.read(root), isNull);
    });

    test('clear removes it', () {
      LiveSession.publish(
        LiveSession(projectRoot: root, vmServiceUri: 'http://x/', pid: 1),
      );
      expect(LiveSession.fileFor(root).existsSync(), isTrue);
      LiveSession.clear(root);
      expect(LiveSession.fileFor(root).existsSync(), isFalse);
    });

    test('clearing what was never published is not an error', () {
      expect(() => LiveSession.clear(root), returnsNormally);
    });
  });

  group('attaching', () {
    test('is null when nothing is published', () async {
      expect(await attachToLiveSession(root), isNull);
    });

    test('a handle that will not connect is null, and is deleted', () async {
      // A GUI that crashed cannot delete its own file. Liveness is decided by
      // connecting rather than by a pid, so this is the whole stale path: port
      // 1 refuses, and the handle must not survive to cost the next caller
      // another timeout.
      LiveSession.publish(
        LiveSession(
          projectRoot: root,
          vmServiceUri: 'http://127.0.0.1:1/dead/',
          pid: 999999,
        ),
      );
      expect(LiveSession.fileFor(root).existsSync(), isTrue);

      expect(
        await attachToLiveSession(root, timeout: const Duration(seconds: 2)),
        isNull,
      );
      expect(LiveSession.fileFor(root).existsSync(), isFalse);
    });

    test('an empty URI is refused without trying to connect', () async {
      LiveSession.publish(
        LiveSession(projectRoot: root, vmServiceUri: '', pid: 1),
      );
      expect(await attachToLiveSession(root), isNull);
    });
  });

  tearDownAll(() {
    var dir = Directory('/tmp/flutterware-live-session-test');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
}
