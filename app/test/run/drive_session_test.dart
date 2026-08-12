import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/drive_session.dart';
import 'package:flutterware_app/src/run/handle.dart';

/// The session outlives the handle snapshot it was created from, and the
/// core hands it the current snapshot on every act. The trap this guards:
/// the first act against a run often lands mid-build (agents are told to
/// open with `observe`), when the handle has no VM uri yet — a session
/// frozen on that read answered "still building" forever after the app
/// came up.
void main() {
  RunHandle handle({String? vmService}) => RunHandle(
    worktree: '/w',
    worktreeName: '~',
    device: 'macos',
    entrypoint: 'lib/main.dart',
    launcherPid: pid,
    startedAt: DateTime.now(),
    handlePath: '/w/run/handle.json',
    vmService: vmService,
  );

  test('an act before the VM uri exists refuses as still building', () {
    var session = DriveSession(handle());
    expect(
      session.act({'verb': 'observe'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('still building'),
        ),
      ),
    );
  });

  test('a refreshed handle clears the still-building refusal', () async {
    var session = DriveSession(handle());
    await expectLater(
      session.act({'verb': 'observe'}),
      throwsA(isA<StateError>()),
    );

    // The build finished; the next probe read a uri. The same session must
    // now dial it — a connection failure, because nothing listens on this
    // port, but no longer the stale refusal.
    session.refresh(handle(vmService: 'ws://127.0.0.1:9/ws'));
    await expectLater(
      session.act({'verb': 'observe'}),
      throwsA(isNot(isA<StateError>())),
    );
  });
}
