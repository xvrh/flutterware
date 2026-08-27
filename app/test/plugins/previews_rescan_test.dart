import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/previews_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Reading the package again, and the rule for two reads at once.
///
/// This scan is not the panel's list — the panel's comes from the compiler
/// daemon, which watches the files. This one is what the previews harness
/// generates its program from, and it was read once, when the package was
/// first tracked. [PreviewsCore.rescan] is how it hears that it is behind.
///
/// Two looks can now be in flight at once, which is the part with a rule: an
/// action scans unconditionally and a rescan fires whenever the daemon says the
/// catalog moved, and they read the disk at different moments. The one that
/// started last is the one whose answer is about now.
void main() {
  late Directory root;

  PreviewsCore catalog() {
    var worktree = Worktree(path: root.path);
    return PreviewsCore(
      PluginHost(
        id: uiCatalogPluginId,
        label: 'Previews',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: const ['.'],
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
  }

  void write(String relative, String content) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_previews_rescan_test');
    write('demo/counter.dart', '''
@Preview(name: 'Counter')
Widget counter() => const Placeholder();
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> idsOf(PreviewsCore subject) => [
    for (var entry in subject.entriesFor('.')) entry.id,
  ];

  test('a preview written since the first look is found by a rescan', () async {
    var subject = catalog();
    await subject.computeAll();
    expect(idsOf(subject), ['demo/counter.dart#counter']);

    write('demo/added.dart', '''
@Preview(name: 'Added')
Widget added() => const Placeholder();
''');
    await subject.rescan('.');

    expect(idsOf(subject), contains('demo/added.dart#added'));
  });

  test('an overtaken look hands its caller the newer answer', () async {
    // The regression: a look that loses the race used to return having written
    // nothing, so the caller that awaited it — `entries`, which documents that
    // it always re-scans rather than answering from the cache — read the
    // catalog from before the edit that started the overtaking look.
    var subject = catalog();
    await subject.computeAll();

    var first = subject.rescan('.');
    write('demo/added.dart', '''
@Preview(name: 'Added')
Widget added() => const Placeholder();
''');
    var second = subject.rescan('.');

    await first;
    expect(
      idsOf(subject),
      contains('demo/added.dart#added'),
      reason: 'awaiting any look means an answer is in, and it is the freshest',
    );
    await second;
  });

  test('and the overtaken look never writes over the newer one', () async {
    var subject = catalog();
    await subject.computeAll();

    var first = subject.rescan('.');
    // Deleted rather than added, so a stale answer is loud: the entry the first
    // look may still be about is gone from the disk the second one reads.
    File(p.join(root.path, 'demo', 'counter.dart')).deleteSync();
    var second = subject.rescan('.');

    await Future.wait([first, second]);
    expect(idsOf(subject), isEmpty);
  });
}
