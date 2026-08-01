import 'dart:io';

import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// How the daemon's own staleness is decided.
///
/// `daemonRevision` is part of the daemon address, so it is what stops a client
/// attaching to a daemon running yesterday's code — and that matters beyond
/// developer convenience, because the daemon decides what goes into a hot-reload
/// delta, and an older one can hand a guest a delta missing a library the guest
/// never had.
///
/// It used to be the newest mtime under a hand-written list of directories. The
/// list was wrong: it missed `lib/src/utils/run_dir.dart` and
/// `lib/src/assets/model/asset_catalog.dart`, both genuinely in the closure, so
/// editing either neither rebuilt the snapshot nor moved the revision. The list
/// is now the compiler's own, via `dart compile kernel --depfile`.
///
/// What is left to get wrong is the parsing, and specifically the two escapes
/// this machine will never produce: a space inside a path, and a `\`-continued
/// line. Hence a test rather than a glance.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fw-depfile-'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A depfile whose dependency list is [body], in a workspace at [root].
  File depfile(String body) =>
      File(p.join(dir.path, 'daemon.dill.d'))
        ..writeAsStringSync('${p.join(dir.path, 'daemon.dill')}: $body');

  String at(String relative) => p.join(dir.path, relative);
  String config() => at(p.join('.dart_tool', 'package_config.json'));

  test('reads the dependencies of the workspace it was built in', () {
    var deps = readDaemonDepfile(
      depfile(
        [
          config(),
          at('app/tool/catalog/compiler_daemon.dart'),
          at('app/lib/src/utils/run_dir.dart'),
        ].join(' '),
      ),
    );
    expect(deps, [
      config(),
      at('app/tool/catalog/compiler_daemon.dart'),
      at('app/lib/src/utils/run_dir.dart'),
    ]);
  });

  test('drops the SDK and the pub cache', () {
    // Immutable by construction: the way you change a dependency is to resolve a
    // different version, which rewrites the `package_config.json` that is itself
    // in the list. So a re-resolution moves the revision without any of these
    // being watched.
    var deps = readDaemonDepfile(
      depfile(
        [
          config(),
          at('app/lib/src/previews/protocol.dart'),
          '/Users/someone/.pub-cache/hosted/pub.dev/image-4.0.0/lib/image.dart',
          '/Users/someone/flutter/bin/cache/dart-sdk/lib/core/core.dart',
        ].join(' '),
      ),
    );
    expect(deps, [config(), at('app/lib/src/previews/protocol.dart')]);
  });

  test('a path with a space in it survives', () {
    // The reason this is parsed rather than split on whitespace. `~/My
    // Projects/…` is ordinary on macOS, and getting it wrong would silently
    // truncate the watched set to whatever came before the space.
    var spaced = at('My Projects/app/lib/src/previews/protocol.dart');
    var deps = readDaemonDepfile(
      depfile('${config()} ${spaced.replaceAll(' ', r'\ ')}'),
    );
    expect(deps, [config(), spaced]);
  });

  test('a continued line is one list', () {
    var deps = readDaemonDepfile(
      depfile(
        '${config()} \\\n  ${at('app/lib/a.dart')} \\\n  ${at('app/lib/b.dart')}',
      ),
    );
    expect(deps, [config(), at('app/lib/a.dart'), at('app/lib/b.dart')]);
  });

  group('falls back rather than answering wrongly', () {
    // Every null here means "use the guessed source list". A revision pinned to
    // the epoch — which is what an empty answer would produce — would make every
    // daemon look infinitely fresh, which is the failure this whole field exists
    // to prevent.
    test('no depfile at all', () {
      expect(readDaemonDepfile(File(p.join(dir.path, 'absent.d'))), isNull);
    });

    test('a depfile with no separator', () {
      expect(
        readDaemonDepfile(
          File(p.join(dir.path, 'x.d'))..writeAsStringSync('junk'),
        ),
        isNull,
      );
    });

    test('a depfile that names no package config, so no root', () {
      expect(readDaemonDepfile(depfile('/somewhere/else.dart')), isNull);
    });
  });

  test('a depfile of nothing but dependencies still watches the resolution', () {
    // Not a fallback case, which is what this test was written expecting. The
    // `package_config.json` is inside the root it defines, so it is always in the
    // answer — and it should be: a `pub get` that moves a dependency rewrites it,
    // and a daemon linked against the old resolution has to be replaced.
    expect(
      readDaemonDepfile(
        depfile('${config()} /Users/someone/.pub-cache/hosted/x/lib/x.dart'),
      ),
      [config()],
    );
  });
}
