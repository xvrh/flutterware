import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_core.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Everything asserted here is read through [PluginReport] — the same data the
/// sidebar, `fw` and an agent see. Nothing touches a widget, which is the point:
/// a capability that only exists in the panel is invisible to every other
/// renderer.
///
/// So the subject is [UiCatalogCore], not the panel over it. The panel has no
/// report and no `invoke` to test: it builds a widget, and that is all it
/// does.
void main() {
  late Directory root;

  UiCatalogCore catalog({
    String? entrypoint,
    List<String> packages = const ['.'],
  }) {
    var worktree = Worktree(path: root.path);
    return UiCatalogCore(
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
      var subject = catalog();
      var address = subject.addressFor('.', 'demo/counter.dart#counter');
      expect(
        address.toString(),
        'fw://${p.basename(root.path)}/flutterware.ui_catalog'
        '/./demo/counter.dart%23counter',
      );
    });

    test('round-trips back to the same segments', () {
      var subject = catalog();
      var address = subject.addressFor('.', 'demo/counter.dart#counter');
      var parsed = Address.parse(address.toString());
      expect(parsed, address);
      expect(parsed.segments, ['.', 'demo', 'counter.dart#counter']);
    });

    test('carries the package, so two packages cannot collide', () {
      var subject = catalog(packages: ['.', 'app']);
      expect(
        subject.addressFor('.', 'demo/x.dart#x'),
        isNot(subject.addressFor('app', 'demo/x.dart#x')),
      );
    });

    test('axes are applied, not identity — bare strips them', () {
      var subject = catalog();
      var sized = subject.addressFor(
        '.',
        'demo/counter.dart#counter',
        axes: {'width': '900', 'height': '700'},
      );
      expect(sized.axes, {'height': '700', 'width': '900'});
      expect(sized.bare, subject.addressFor('.', 'demo/counter.dart#counter'));
      // Different axes are different addresses: a 420-wide capture is not the
      // same artifact as a 900-wide one, and the file names must differ too.
      expect(
        sized,
        isNot(
          subject.addressFor(
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
  Future<void> scanned(UiCatalogCore subject) async {
    while (subject.isScanning) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('reports nothing and scans nothing until something asks', () {
    var subject = catalog();

    expect(subject.report.status, Status.none);
    expect(subject.entries, isEmpty);
    expect(
      subject.report.children.single.status,
      Status.none,
      reason: 'constructing the plugin must not read the disk',
    );
  });

  test('track starts the scan, and stays quiet about a healthy one', () async {
    var subject = catalog()..track('.');
    await scanned(subject);

    expect(subject.entries, hasLength(3));
    // A count is not news, and it cannot be known before something asks for it.
    // The row keeps its room for what is actually moving.
    expect(subject.report.status, Status.none);
    expect(subject.report.children.single.status, Status.none);
  });

  test('the entries reach a non-GUI renderer through the view', () async {
    var subject = catalog()..track('.');
    await scanned(subject);

    var text = subject.report.toText();
    expect(text, contains('Avatar tile / Members'));
    expect(text, contains('Avatar tile / Empty'));
    expect(text, contains('Counter'));
    expect(text, contains('demo/counter.dart#counter'));
  });

  test('the report round-trips to JSON', () async {
    var subject = catalog()..track('.');
    await scanned(subject);

    var json = subject.report.toJson();
    expect(json['id'], uiCatalogPluginId);
    expect([
      for (var a in json['actions']! as List) (a as Map)['id'],
    ], containsAll(['entries', 'check', 'describe', 'screenshot']));
    expect(json['view'], isNotEmpty);
  });

  test('a package with no demos says so rather than looking healthy', () async {
    var subject = catalog(entrypoint: 'nonexistent')..track('.');
    await scanned(subject);

    expect(subject.report.status.tone, Tone.warn);
    expect(subject.report.status.message, 'no entries');
  });

  test('entrypoint overrides the demo/ convention', () async {
    write('catalog/thing.dart', '''
@Demo(name: 'Elsewhere')
Widget thing() => const Placeholder();
''');
    var subject = catalog(entrypoint: 'catalog')..track('.');
    await scanned(subject);

    expect(subject.entries.map((e) => e.name), ['Elsewhere']);
  });

  test('a scan error is reported, not swallowed', () async {
    // Two annotations on one declaration derive the same id, which discovery
    // refuses. The plugin must surface that rather than show a short list.
    write('demo/broken.dart', '''
@Demo(name: 'A')
@Demo(name: 'B')
Widget broken() => const Placeholder();
''');
    var subject = catalog()..track('.');
    await scanned(subject);

    expect(subject.report.status.tone, Tone.error);
    expect(subject.report.toText(), contains('same id'));
  });

  test('entries lists everything, with ids and addresses', () async {
    var subject = catalog();
    // No track() first: the action loads what it needs, which is the whole
    // point of it existing. A report would have answered "not computed".
    var result = (await subject.invoke('entries'))! as CatalogEntriesResult;
    var entries = result.packages.single.entries;

    expect(entries, hasLength(3));
    expect(entries.map((e) => e.id), contains('demo/counter.dart#counter'));
    expect(
      entries.first.address,
      startsWith('fw://'),
      reason: 'an agent should be able to take this straight to screenshot',
    );
    // The wire form is generated from those fields, so it cannot disagree
    // with them — but every surface reads it, so it is worth one look.
    expect(result.toJson()['packages'], isA<List<Object?>>());
  });

  test('entries picks up a file added after an earlier scan', () async {
    var subject = catalog()..track('.');
    await scanned(subject);
    expect(subject.entries, hasLength(3));

    write('demo/added.dart', '''
@Demo(name: 'Added')
Widget added() => const Placeholder();
''');
    var result = (await subject.invoke('entries'))! as CatalogEntriesResult;
    expect(
      result.packages.single.entries.map((e) => e.name),
      contains('Added'),
    );
  });

  test('describe answers from the scan, address included', () async {
    var subject = catalog();
    var described =
        (await subject.invoke(
              'describe',
              arguments: {'entry': 'demo/counter.dart#counter'},
            ))!
            as CatalogEntryDescription;

    expect(described.name, 'Counter');
    expect(described.package, '.');
    expect(described.file, 'demo/counter.dart');
    expect(described.symbol, 'counter');
    expect(described.address, startsWith('fw://'));
    // Knobs are a runtime fact and cost a build, so they are absent until
    // asked for by name — null, not empty, because "none declared" is a
    // different answer from "we did not look".
    expect(described.knobs, isNull);
    expect(described.toJson().containsKey('knobs'), isFalse);
  });

  test('describe refuses an entry that is not there', () async {
    expect(
      catalog().invoke('describe', arguments: {'entry': 'nope#nope'}),
      throwsArgumentError,
    );
    expect(catalog().invoke('describe'), throwsArgumentError);
  });

  test('entries refuses a package the plugin does not declare', () async {
    expect(
      catalog().invoke('entries', arguments: {'package': 'nope'}),
      throwsArgumentError,
    );
  });

  test('an unknown action is refused loudly', () async {
    expect(catalog().invoke('nope'), throwsArgumentError);
  });

  test('the screenshot action declares what it needs', () async {
    var subject = catalog()..track('.');
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
      'entries',
      reason:
          'a large one points at the action that returns them all — not at '
          'the report view, which stops at 20',
    );
    expect(
      action.parameters.firstWhere((p) => p.id == 'output').required,
      isFalse,
    );
  });

  test('the action survives a JSON round trip', () async {
    var subject = catalog()..track('.');
    await scanned(subject);

    var original = subject.report.actions.firstWhere(
      (a) => a.id == 'screenshot',
    );
    var restored = PluginAction.fromJson(original.toJson());

    expect(restored.parameters, hasLength(original.parameters.length));
    var entry = restored.parameters.first;
    expect(entry.id, 'entry');
    expect(entry.kind, ActionParameterKind.choice);
    expect(entry.optionsFrom, 'entries');
    expect(entry.options.first.label, isNotNull);
  });

  test('screenshot refuses a missing or unknown entry', () async {
    var subject = catalog()..track('.');
    await scanned(subject);

    expect(subject.invoke('screenshot'), throwsArgumentError);
    expect(
      subject.invoke('screenshot', arguments: {'entry': 'nope#nope'}),
      throwsArgumentError,
    );
  });
}
