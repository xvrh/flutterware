import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/dependencies/model/package_origin.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:flutterware_app/src/package_ref.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

import '../support/declared_dependencies.dart';

/// The live end-to-end check: really shells out to `dart pub deps --json`
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
    'a workspace member classifies against its own resolution',
    () async {
      var service = serviceAt('../examples/example');
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
        '../examples/example/pubspec.yaml',
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

      // Reachability, live: `file_picker` is flutterware_app's, not this
      // member's, even though both resolve from the same lockfile.
      var names = dependencies.dependencies.map((d) => d.name).toSet();
      expect(names, isNot(contains('file_picker')));

      service.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'origins come back filled in, not blank',
    () async {
      var service = serviceAt('../examples/example');
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
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
