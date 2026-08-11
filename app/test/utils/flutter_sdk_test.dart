import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

// The fresh-worktree case: the pin (`flutter_version`, or fvm's `.fvmrc`) is
// versioned, the SDK links are not — so before anything writes a link, the
// pin resolved against its tool's cache is the only project-scoped answer
// discovery can give.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fw-sdk-test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// An SDK is two executables — what [FlutterSdkPath.isValid] checks.
  String fakeSdk(String at) {
    for (var name in ['flutter', 'dart']) {
      File(p.join(at, 'bin', name)).createSync(recursive: true);
    }
    return at;
  }

  Directory project(String fvmrc) {
    var dir = Directory(p.join(tmp.path, 'project', 'inner'))
      ..createSync(recursive: true);
    File(p.join(tmp.path, 'project', '.fvmrc')).writeAsStringSync(fvmrc);
    return dir;
  }

  Directory fwProject(String flutterVersion) {
    var dir = Directory(p.join(tmp.path, 'project', 'inner'))
      ..createSync(recursive: true);
    File(
      p.join(tmp.path, 'project', 'flutter_version'),
    ).writeAsStringSync(flutterVersion);
    return dir;
  }

  test('a fresh fvm worktree resolves its pin through the cache', () async {
    var cached = fakeSdk(p.join(tmp.path, 'home', 'fvm', 'versions', '3.99.0'));
    // From a subdirectory: the pin sits at the root, commands are typed
    // anywhere.
    var sdks = await FlutterSdkPath.findSdks(
      from: project('{"flutter": "3.99.0"}'),
      environment: {'HOME': p.join(tmp.path, 'home')},
    );
    expect(sdks.map((s) => s.root), contains(p.canonicalize(cached)));
  });

  test('FVM_CACHE_PATH wins over the home cache', () async {
    fakeSdk(p.join(tmp.path, 'home', 'fvm', 'versions', '3.99.0'));
    var custom = fakeSdk(p.join(tmp.path, 'cache', 'versions', '3.99.0'));
    var sdks = await FlutterSdkPath.findSdks(
      from: project('{"flutter": "3.99.0"}'),
      environment: {
        'HOME': p.join(tmp.path, 'home'),
        'FVM_CACHE_PATH': p.join(tmp.path, 'cache'),
      },
    );
    expect(sdks.map((s) => s.root), contains(p.canonicalize(custom)));
  });

  test('an uncached pin and an unreadable pin both answer nothing', () async {
    for (var fvmrc in ['{"flutter": "3.99.0"}', 'not json', '{}']) {
      var sdks = await FlutterSdkPath.findSdks(
        from: project(fvmrc),
        environment: {'HOME': p.join(tmp.path, 'home')},
      );
      expect(
        sdks.where((s) => p.isWithin(tmp.path, s.root)),
        isEmpty,
        reason: 'for .fvmrc $fvmrc',
      );
    }
  });

  test(
    'a fresh fw worktree resolves its pin through the wrapper cache',
    () async {
      var cached = fakeSdk(
        p.join(tmp.path, 'home', '.flutterware', 'sdks', '3.99.0'),
      );
      var sdks = await FlutterSdkPath.findSdks(
        from: fwProject('3.99.0\n'),
        environment: {'HOME': p.join(tmp.path, 'home')},
      );
      expect(sdks.map((s) => s.root), contains(p.canonicalize(cached)));
    },
  );

  test('FW_SDK_CACHE wins over the home cache', () async {
    fakeSdk(p.join(tmp.path, 'home', '.flutterware', 'sdks', '3.99.0'));
    var custom = fakeSdk(p.join(tmp.path, 'cache', '3.99.0'));
    var sdks = await FlutterSdkPath.findSdks(
      from: fwProject('3.99.0'),
      environment: {
        'HOME': p.join(tmp.path, 'home'),
        'FW_SDK_CACHE': p.join(tmp.path, 'cache'),
      },
    );
    expect(sdks.map((s) => s.root), contains(p.canonicalize(custom)));
  });

  test('the fw pin outranks the fvm pin when a repo carries both', () async {
    var fw = fakeSdk(
      p.join(tmp.path, 'home', '.flutterware', 'sdks', '3.99.0'),
    );
    fakeSdk(p.join(tmp.path, 'home', 'fvm', 'versions', '3.44.0'));
    var from = fwProject('3.99.0');
    File(
      p.join(tmp.path, 'project', '.fvmrc'),
    ).writeAsStringSync('{"flutter": "3.44.0"}');
    var sdks = await FlutterSdkPath.findSdks(
      from: from,
      environment: {'HOME': p.join(tmp.path, 'home')},
    );
    expect(sdks.first.root, p.canonicalize(fw));
  });

  test('an empty or uncached fw pin answers nothing', () async {
    for (var pin in ['', '  \n', '3.99.0']) {
      var sdks = await FlutterSdkPath.findSdks(
        from: fwProject(pin),
        environment: {'HOME': p.join(tmp.path, 'home')},
      );
      expect(
        sdks.where((s) => p.isWithin(tmp.path, s.root)),
        isEmpty,
        reason: 'for flutter_version "$pin"',
      );
    }
  });
}
