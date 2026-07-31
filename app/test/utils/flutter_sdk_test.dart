import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  /// A directory `FlutterSdkPath` will accept: it needs both binaries present.
  Directory fakeSdk(String name) {
    var dir = Directory(p.join(tmp.path, name));
    for (var binary in ['flutter', 'dart']) {
      File(p.join(dir.path, 'bin', binary))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh');
    }
    return dir;
  }

  /// A project root with `.flutterware/sdk` pointing at [sdk], which is what
  /// `init` leaves behind.
  Directory initializedProject(String name, Directory sdk) {
    var root = Directory(p.join(tmp.path, name))..createSync(recursive: true);
    Link(p.join(root.path, '.flutterware', 'sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(sdk.path);
    return root;
  }

  String real(Directory dir) => p.canonicalize(dir.resolveSymbolicLinksSync());

  // Resolved, because macOS hands out `/var/...` for a directory that really
  // lives at `/private/var/...`, and half the paths here are compared after a
  // link has been followed and half before.
  setUp(
    () => tmp = Directory(
      Directory.systemTemp.createTempSync('fw-sdk').resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'finds the SDK the project recorded, with nothing in the environment',
    () async {
      var sdk = fakeSdk('recorded');
      var root = initializedProject('project', sdk);

      var found = await FlutterSdkPath.findSdks(
        from: root,
        environment: const {},
      );

      expect(found.first.root, real(sdk));
    },
  );

  test(
    'finds it from a subdirectory, where commands are actually typed',
    () async {
      var sdk = fakeSdk('recorded');
      var root = initializedProject('project', sdk);
      var deep = Directory(p.join(root.path, 'app', 'lib'))
        ..createSync(recursive: true);

      var found = await FlutterSdkPath.findSdks(
        from: deep,
        environment: const {},
      );

      expect(found.first.root, real(sdk));
    },
  );

  test('falls back to fvm for a project that has not run init', () async {
    var sdk = fakeSdk('pinned');
    var root = Directory(p.join(tmp.path, 'project'))..createSync();
    Link(p.join(root.path, '.fvm', 'flutter_sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(sdk.path);

    var found = await FlutterSdkPath.findSdks(
      from: root,
      environment: const {},
    );

    expect(found.first.root, real(sdk));
  });

  test("the launcher's dart wins over what the project recorded", () async {
    var recorded = fakeSdk('recorded');
    var launcher = fakeSdk('launcher');
    var root = initializedProject('project', recorded);

    var found = await FlutterSdkPath.findSdks(
      from: root,
      environment: {
        dartExecutableEnvironmentKey: p.join(launcher.path, 'bin', 'dart'),
      },
    );

    expect(found.first.root, real(launcher));
    expect(found.map((s) => s.root), contains(real(recorded)));
  });

  test(
    'FLUTTER_HOME describes the machine, so the project outranks it',
    () async {
      var recorded = fakeSdk('recorded');
      var elsewhere = fakeSdk('elsewhere');
      var root = initializedProject('project', recorded);

      var found = await FlutterSdkPath.findSdks(
        from: root,
        environment: {'FLUTTER_HOME': elsewhere.path},
      );

      expect(found.first.root, real(recorded));
      expect(found.map((s) => s.root), contains(real(elsewhere)));
    },
  );

  test('one SDK reached two ways is one entry', () async {
    var sdk = fakeSdk('shared');
    var root = initializedProject('project', sdk);

    var found = await FlutterSdkPath.findSdks(
      from: root,
      environment: {'FLUTTER_HOME': sdk.path},
    );

    expect(found.where((s) => s.root == real(sdk)), hasLength(1));
  });

  test('a link left pointing at a deleted SDK is not an answer', () async {
    var sdk = fakeSdk('gone');
    var root = initializedProject('project', sdk);
    sdk.deleteSync(recursive: true);

    var found = await FlutterSdkPath.findSdks(
      from: root,
      environment: const {},
    );

    expect(found.map((s) => s.root), isNot(contains(p.canonicalize(sdk.path))));
  });
}
