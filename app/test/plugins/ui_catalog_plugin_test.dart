import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Everything asserted here is read through [PluginReport] — the same data the
/// sidebar, `fw` and an agent see. Nothing touches a widget, which is the point:
/// a capability that only exists in the panel is invisible to every other
/// renderer.
void main() {
  late Directory root;

  UiCatalogPlugin plugin({
    String? entrypoint,
    List<String> packages = const ['.'],
  }) {
    var worktree = Worktree(path: root.path);
    return UiCatalogPlugin(
      PluginHost(
        id: uiCatalogPluginId,
        label: 'UI catalog',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [for (var path in packages) Pkg(path)],
          discovered: packages,
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            for (var path in packages)
              {'path': path, 'entrypoint': ?entrypoint},
          ],
        },
      ),
    );
  }

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_catalog_plugin_test');
    write('demo/team/avatar_tile.dart', '''
@Demo(name: 'Members')
Widget members() => const Placeholder();

@Demo(name: 'Empty')
Widget empty() => const Placeholder();
''');
    write('demo/counter.dart', '''
@Demo(name: 'Counter')
Widget counter() => const Placeholder();
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('addressFor — the identity every surface carries', () {
    test('is legible: only the # is escaped, the path stays a path', () {
      var subject = plugin();
      var address = subject.core.addressFor('.', 'demo/counter.dart#counter');
      expect(
        address.toString(),
        'fw://${p.basename(root.path)}/flutterware.ui_catalog'
        '/./demo/counter.dart%23counter',
      );
    });

    test('round-trips back to the same segments', () {
      var subject = plugin();
      var address = subject.core.addressFor('.', 'demo/counter.dart#counter');
      var parsed = Address.parse(address.toString());
      expect(parsed, address);
      expect(parsed.segments, ['.', 'demo', 'counter.dart#counter']);
    });

    test('carries the package, so two packages cannot collide', () {
      var subject = plugin(packages: ['.', 'app']);
      expect(
        subject.core.addressFor('.', 'demo/x.dart#x'),
        isNot(subject.core.addressFor('app', 'demo/x.dart#x')),
      );
    });

    test('axes are applied, not identity — bare strips them', () {
      var subject = plugin();
      var sized = subject.core.addressFor(
        '.',
        'demo/counter.dart#counter',
        axes: {'width': '900', 'height': '700'},
      );
      expect(sized.axes, {'height': '700', 'width': '900'});
      expect(
        sized.bare,
        subject.core.addressFor('.', 'demo/counter.dart#counter'),
      );
      // Different axes are different addresses: a 420-wide capture is not the
      // same artifact as a 900-wide one, and the file names must differ too.
      expect(
        sized,
        isNot(
          subject.core.addressFor(
            '.',
            'demo/counter.dart#counter',
            axes: {'width': '420', 'height': '320'},
          ),
        ),
      );
    });
  });

  /// Waits for the scan [track] kicked off. It runs in another isolate, so the
  /// report is only meaningful once it lands.
  Future<void> scanned(UiCatalogPlugin subject) async {
    while (subject.core.isScanning) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('reports nothing and scans nothing until something asks', () {
    var subject = plugin();

    expect(subject.report.status, Status.none);
    expect(subject.core.entries, isEmpty);
    expect(
      subject.report.children.single.status,
      Status.none,
      reason: 'constructing the plugin must not read the disk',
    );
  });

  test('track starts the scan, and stays quiet about a healthy one', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    expect(subject.core.entries, hasLength(3));
    // A count is not news, and it cannot be known before something asks for it.
    // The row keeps its room for what is actually moving.
    expect(subject.report.status, Status.none);
    expect(subject.report.children.single.status, Status.none);
  });

  test('the entries reach a non-GUI renderer through the view', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    var text = subject.report.toText();
    expect(text, contains('Avatar tile / Members'));
    expect(text, contains('Avatar tile / Empty'));
    expect(text, contains('Counter'));
    expect(text, contains('demo/counter.dart#counter'));
  });

  test('the report round-trips to JSON', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    var json = subject.report.toJson();
    expect(json['id'], uiCatalogPluginId);
    expect([
      for (var a in json['actions']! as List) (a as Map)['id'],
    ], containsAll(['rescan', 'screenshot']));
    expect(json['view'], isNotEmpty);
  });

  test('a package with no demos says so rather than looking healthy', () async {
    var subject = plugin(entrypoint: 'nonexistent')..core.track('.');
    await scanned(subject);

    expect(subject.report.status.tone, Tone.warn);
    expect(subject.report.status.message, 'no entries');
  });

  test('entrypoint overrides the demo/ convention', () async {
    write('catalog/thing.dart', '''
@Demo(name: 'Elsewhere')
Widget thing() => const Placeholder();
''');
    var subject = plugin(entrypoint: 'catalog')..core.track('.');
    await scanned(subject);

    expect(subject.core.entries.map((e) => e.name), ['Elsewhere']);
  });

  test('a scan error is reported, not swallowed', () async {
    // Two annotations on one declaration derive the same id, which discovery
    // refuses. The plugin must surface that rather than show a short list.
    write('demo/broken.dart', '''
@Demo(name: 'A')
@Demo(name: 'B')
Widget broken() => const Placeholder();
''');
    var subject = plugin()..core.track('.');
    await scanned(subject);

    expect(subject.report.status.tone, Tone.error);
    expect(subject.report.toText(), contains('same id'));
  });

  test('rescan picks up a file added after the first scan', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);
    expect(subject.core.entries, hasLength(3));

    write('demo/added.dart', '''
@Demo(name: 'Added')
Widget added() => const Placeholder();
''');
    await subject.invoke('rescan');
    await scanned(subject);

    expect(subject.core.entries.map((e) => e.name), contains('Added'));
  });

  test('an unknown action is refused loudly', () async {
    expect(plugin().invoke('nope'), throwsArgumentError);
  });

  test('the screenshot action declares what it needs', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    var action = subject.report.actions.firstWhere((a) => a.id == 'screenshot');
    var entry = action.parameters.firstWhere((p) => p.id == 'entry');

    expect(entry.kind, ActionParameterKind.choice);
    expect(entry.required, isTrue);
    expect(
      entry.options.map((o) => o.value),
      contains('demo/counter.dart#counter'),
      reason: 'a small catalog inlines its options',
    );
    expect(
      entry.optionsFrom,
      'view',
      reason: 'a large one points at the list already in the report',
    );
    expect(
      action.parameters.firstWhere((p) => p.id == 'output').required,
      isFalse,
    );
  });

  test('the action survives a JSON round trip', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    var original = subject.report.actions.firstWhere(
      (a) => a.id == 'screenshot',
    );
    var restored = PluginAction.fromJson(original.toJson());

    expect(restored.parameters, hasLength(original.parameters.length));
    var entry = restored.parameters.first;
    expect(entry.id, 'entry');
    expect(entry.kind, ActionParameterKind.choice);
    expect(entry.optionsFrom, 'view');
    expect(entry.options.first.label, isNotNull);
  });

  test('screenshot refuses a missing or unknown entry', () async {
    var subject = plugin()..core.track('.');
    await scanned(subject);

    expect(subject.invoke('screenshot'), throwsArgumentError);
    expect(
      subject.invoke('screenshot', arguments: {'entry': 'nope#nope'}),
      throwsArgumentError,
    );
  });
}
