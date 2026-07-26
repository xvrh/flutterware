import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/project.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// Runs against this repo, which is a three-member pub workspace: one
/// `pubspec.lock` and one `.dart_tool/package_config.json` at the root, none in
/// the members.
///
/// That layout used to make every resolved package classify as direct, because
/// `PubspecLock.load(<member dir>)` found nothing and direct-ness was derived
/// from the (absent) lock entry.
void main() {
  Project projectAt(String path) => Project(
    AppContext(logger: LogClient.print()),
    path,
    FlutterSdkPath('/tmp/flutter'),
  );

  test(
    'a workspace member classifies against its own pubspec',
    () async {
      var project = projectAt('../examples/example');
      var dependencies = await project.dependencies.dependencies
          .refreshOrThrow();

      // The member declares ~14 dependencies; the workspace resolves ~170.
      // Before the fix this reported every resolved package as direct.
      expect(dependencies.directs, isNotEmpty);
      expect(
        dependencies.directs.length,
        lessThan(30),
        reason:
            'direct deps should come from the member pubspec, not the '
            'whole workspace resolution',
      );
      expect(dependencies.transitives, isNotEmpty);

      var names = dependencies.directs.map((d) => d.name).toSet();
      expect(names, contains('flutterware'));

      project.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the listing is scoped to what the member can reach',
    () async {
      var project = projectAt('../examples/example');
      var dependencies = await project.dependencies.dependencies
          .refreshOrThrow();

      // `build_runner` is a dev dependency of flutterware_app, a sibling member.
      // It is in the shared resolution but unreachable from this package, so it
      // must not appear in its listing.
      var names = dependencies.dependencies.map((d) => d.name).toSet();
      expect(names, isNot(contains('build_runner')));

      project.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
