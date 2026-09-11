import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/dependencies/model/package_origin.dart';
import 'package:flutterware_app/src/dependencies/model/pub_deps.dart';
import 'package:flutterware_app/src/dependencies/model/pub_deps_store.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:flutterware_app/src/package_ref.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

import '../support/declared_dependencies.dart';

/// The live end-to-end check: really shells out to `flutter pub deps --json`
/// against this repo, which is a three-member pub workspace.
///
/// `resolution_test.dart` covers the same ground against a captured fixture and
/// covers far more of it. This one exists for what a fixture cannot notice — a
/// wrong executable, a wrong working directory, or a future SDK changing the
/// shape of the output while the fixture keeps saying everything is fine.
void main() {
  late FlutterSdkPath sdk;

  setUpAll(() async {
    // Walks up from the Dart running this test to the Flutter SDK that owns it,
    // so this works in a fresh worktree where the pinned SDK is gitignored.
    var found = await FlutterSdkPath.tryFind(Platform.resolvedExecutable);
    if (found == null) {
      fail(
        'Could not find the Flutter SDK from ${Platform.resolvedExecutable}',
      );
    }
    sdk = found;
  });

  DependenciesService serviceAt(String path) => DependenciesService(
    PackageRef(AppContext(logger: LogClient.print()), path, sdk),
  );

  test(
    'the resolution is read through `flutter pub`, never `dart pub`',
    () async {
      String? executable;
      var service = DependenciesService(
        PackageRef(AppContext(logger: LogClient.print()), '..', sdk),
        runProcess: (e, arguments, {workingDirectory}) async {
          executable = e;
          return ProcessResult(0, 1, '', 'not run');
        },
      );
      addTearDown(service.dispose);
      await expectLater(
        service.dependencies.refreshOrThrow(),
        throwsA(anything),
      );

      // `dart pub` refuses outright the moment pub has to re-resolve anything
      // that depends on the Flutter SDK — which every member of this workspace
      // does, directly or through a sibling. It only ever appeared to work
      // because the SDK's own `dart` lets pub infer FLUTTER_ROOT from where the
      // executable sits; a stale FLUTTER_ROOT in the environment defeats that
      // and the panel fails to load against this very repo.
      expect(executable, sdk.flutter);
      expect(executable, isNot(sdk.dart));
    },
  );

  // The other two members. `fixtures/probe_app` is opened live by the test below
  // and in more detail; the root package and `app` were opened by nothing, and
  // the root package is the one that was reported broken.
  for (var member in const ['..', '.']) {
    test('the resolution loads for $member', () async {
      var service = serviceAt(member);
      addTearDown(service.dispose);
      var dependencies = await service.dependencies.refreshOrThrow();

      var declared = DeclaredDependencies.of('$member/pubspec.yaml');
      expect(
        dependencies.directs.map((d) => d.name).toSet(),
        declared.dependencies,
      );
      expect(dependencies.devs.map((d) => d.name).toSet(), declared.devs);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('a workspace member classifies against its own resolution', () async {
    var service = serviceAt('../fixtures/probe_app');
    var dependencies = await service.dependencies.refreshOrThrow();

    // The classification has to match what *this member* declares, not what
    // the workspace resolves — before the fix every one of the ~174 resolved
    // packages came back as direct, because `PubspecLock.load(<member dir>)`
    // found nothing and a workspace keeps its one lockfile at the root.
    //
    // Read off the member's pubspec rather than written down here: name sets
    // say which packages were misclassified, where a count only says that
    // some were.
    var declared = DeclaredDependencies.of(
      '../fixtures/probe_app/pubspec.yaml',
    );
    expect(
      dependencies.directs.map((d) => d.name).toSet(),
      declared.dependencies,
    );
    expect(dependencies.devs.map((d) => d.name).toSet(), declared.devs);

    // And the resolution really is bigger than the declarations, so the two
    // assertions above are not passing because everything is empty.
    expect(dependencies.transitives, isNotEmpty);
    expect(
      dependencies.transitives.length,
      greaterThan(dependencies.directs.length),
    );

    // Reachability, live: `process_runner` is the root package's own dev
    // dependency, not this member's, even though both resolve from the same
    // lockfile. (It used to be `file_picker`, the studio's — until the
    // example's web demo made the example depend on the studio.)
    var names = dependencies.dependencies.map((d) => d.name).toSet();
    expect(names, isNot(contains('process_runner')));

    service.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the resolution is cached against the lockfile that produced it', () async {
    // The disk half of `PubDepsStore`, live: `fw` and the MCP server are born
    // for one request and hold nothing, so this file is the only reason a cold
    // process does not pay for pub every time. The stamp is what makes serving
    // it safe — it is a hash of the lockfile and the package config, which is
    // everything `pub deps` reads.
    var root = PubDepsStore.resolutionRoot('..')!;
    var stamp = PubDepsStore.stampFor(root, sdk.flutter)!;
    var before = PubDepsStore.cacheFileFor(root, stamp);
    if (before.existsSync()) before.deleteSync();

    var service = serviceAt('..');
    addTearDown(service.dispose);
    await service.dependencies.refreshOrThrow();

    var cached = PubDepsStore.cacheFileFor(root, stamp);
    expect(cached.existsSync(), isTrue, reason: 'nothing was cached');
    // And it is pub's answer rather than a rendering of it, so a future SDK
    // adding a field does not quietly lose it on the way through.
    expect(PubDeps.parse(cached.readAsStringSync()).members, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('origins come back filled in, not blank', () async {
    var service = serviceAt('../fixtures/probe_app');
    var dependencies = await service.dependencies.refreshOrThrow();

    // Every one of these used to be null: the lookup went to a lockfile that
    // does not exist beside a workspace member.
    for (var dependency in dependencies.dependencies) {
      expect(
        dependency.origin,
        isNot(isA<UnknownOrigin>()),
        reason: '${dependency.name} has an unrecognised origin',
      );
    }

    // `flutterware` is a path dependency onto a sibling workspace member.
    expect(dependencies['flutterware']!.origin, isA<WorkspaceOrigin>());
    // `flutter` comes from the SDK and resolves as 0.0.0.
    var flutter = dependencies['flutter']!;
    expect(flutter.origin, isA<SdkOrigin>());
    expect(flutter.hasMeaningfulVersion, isFalse);
    // And an ordinary pub package has a real version from the root lockfile.
    var path = dependencies['path']!;
    expect(path.origin, isA<HostedOrigin>());
    expect(path.resolvedVersion, isNot('0.0.0'));

    service.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
