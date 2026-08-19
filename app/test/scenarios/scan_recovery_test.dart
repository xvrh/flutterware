import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// A scan failure is a moment, not a verdict: a save caught mid-write throws
/// once, and the next successful scan must clear the error rather than leave
/// the package branded "scan failed" behind a fresh result.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scan_recovery_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a successful rescan clears an earlier scan failure', () async {
    var directory = Directory(p.join(root.path, 'test', 'scenarios'))
      ..createSync(recursive: true);
    var file = File(p.join(directory.path, 'a_test.dart'))
      // Invalid UTF-8 — the shape of a save caught mid-write. The scan's
      // readAsStringSync throws on it before anything parses.
      ..writeAsBytesSync([0x73, 0x63, 0xC3, 0x28]);

    var subject = ScenariosCore(
      PluginHost(
        id: scenariosPluginId,
        label: 'Scenarios',
        worktree: Worktree(path: root.path),
        workspace: Workspace(
          root: root.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
    );

    await subject.computeAll();
    expect(subject.scanErrorFor('.'), isNotNull);

    // The save completes; the watcher's rescan must land as the new truth.
    file.writeAsStringSync('''
void main() {
  scenario('A', () {});
}
''');
    subject.rescan('.');
    await subject.computeAll();
    expect(subject.scanErrorFor('.'), isNull);
    expect(subject.scanResultFor('.')!.scenarios, hasLength(1));
  });
}
