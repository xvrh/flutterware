import 'dart:io';

import 'package:path/path.dart' as p;

/// The `dart` belonging to the SDK **running this test**.
///
/// Shared by the two suites that spawn the CLI as a real process, because they
/// each had a copy and the copies were wrong in the same way.
///
/// `FLUTTER_ROOT` first, and the ordering is the whole fix. `flutter test`
/// runs a suite under `flutter_tester`, so `Platform.resolvedExecutable` does
/// not end in `/dart` — and the previous version fell through to `which dart`,
/// which is whatever SDK happens to be on PATH. On a checkout pinned to a newer
/// SDK than the system one, the spawned process then refuses the package
/// outright ("language version 3.13 is too high") and the test sees exit 254
/// with nothing to say why.
///
/// PATH stays as the last resort, for a plain `dart test` run outside Flutter.
String resolveDartExecutable() {
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final bundled = p.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin', exe);
    if (File(bundled).existsSync()) return bundled;
  }

  if (Platform.resolvedExecutable.endsWith('${p.separator}$exe')) {
    return Platform.resolvedExecutable;
  }

  final found = Process.runSync('/usr/bin/which', ['dart']);
  if (found.exitCode == 0) {
    final path = (found.stdout as String).trim();
    if (path.isNotEmpty) return path;
  }

  throw StateError(
    'Could not locate a dart executable. FLUTTER_ROOT was '
    '"${flutterRoot ?? '<unset>'}".',
  );
}
