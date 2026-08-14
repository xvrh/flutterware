import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

// The SDK is the one that started us, and nothing else is consulted. These
// tests exist mostly to keep it that way: a pin file, a version manager's
// cache or `FLUTTER_HOME` next to the process must not change the answer.
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

  test("the launcher's dart is the answer", () async {
    var sdk = fakeSdk(p.join(tmp.path, 'sdk'));
    var found = await FlutterSdkPath.findSdk(
      environment: {dartExecutableEnvironmentKey: p.join(sdk, 'bin', 'dart')},
    );
    expect(found?.root, p.canonicalize(sdk));
  });

  test('a dart with no SDK above it does not answer', () async {
    // Falls through to the executable running this test, which is inside a
    // real SDK — so the assertion is that the *stray path* was not adopted.
    var stray = Directory(p.join(tmp.path, 'nowhere'))..createSync();
    var found = await FlutterSdkPath.findSdk(
      environment: {dartExecutableEnvironmentKey: p.join(stray.path, 'dart')},
    );
    expect(found?.root, isNot(p.canonicalize(stray.path)));
  });

  test('nothing else on the machine is consulted', () async {
    // Every source the ladder used to carry, all naming one SDK, all ignored:
    // the answer is the running executable's, never this one.
    var decoy = fakeSdk(p.join(tmp.path, 'decoy'));
    File(p.join(tmp.path, '.fvmrc')).writeAsStringSync('{"flutter":"3.99.0"}');
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.99.0');
    fakeSdk(p.join(tmp.path, 'home', 'fvm', 'versions', '3.99.0'));
    Link(p.join(tmp.path, '.flutterware', 'sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(decoy);

    var found = await FlutterSdkPath.findSdk(
      environment: {
        'HOME': p.join(tmp.path, 'home'),
        'FLUTTER_HOME': decoy,
        'FVM_CACHE_PATH': p.join(tmp.path, 'home', 'fvm'),
      },
    );

    expect(found?.root, isNot(p.canonicalize(decoy)));
    expect(
      found?.root,
      isNot(contains(tmp.path)),
      reason: 'no source below the temp root may answer',
    );
  });
}
