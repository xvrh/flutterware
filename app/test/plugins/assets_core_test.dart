import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/assets_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Everything asserted here is read through [PluginReport] — the same data the
/// sidebar, `fw` and an agent see. The subject is the core, because a fact that
/// only reaches the panel is a fact the other two surfaces do not have.
void main() {
  late Directory scratch;
  late Directory root;

  AssetsCore core({List<String> packages = const ['.']}) {
    var worktree = Worktree(path: root.path);
    return AssetsCore(
      PluginHost(
        id: assetsPluginId,
        label: 'Assets',
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
            for (var path in packages) {'path': path},
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

  /// A resolved config with no dependencies — enough for the resolver to run.
  void writePackageConfig() {
    write('.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": []
}
''');
  }

  setUp(() {
    // The worktree sits inside a directory of its own, so that a test writing a
    // sibling of the worktree — a path dependency, below — writes it somewhere
    // only this test owns.
    scratch = Directory.systemTemp.createTempSync('fw_assets_core_test');
    root = Directory(p.join(scratch.path, 'app'))..createSync();
    writePackageConfig();
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('reading the report starts no work', () {
    write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/logo.png
''');
    write('assets/logo.png', 'png');

    var plugin = core();
    var report = plugin.report;

    expect(plugin.scanFor('.'), isNull);
    expect(report.status, Status.none);
    expect(report.view.toText(), contains('not computed'));
  });

  test('a scanned package reports what its bundle holds', () async {
    write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/images/
''');
    write('assets/images/logo.png', 'x' * 100);
    write('assets/images/2.0x/logo.png', 'x' * 200);
    write('assets/images/badge.svg', 'x' * 50);

    var plugin = core();
    await plugin.computeAll();

    var report = plugin.report;
    expect(report.status, Status.none, reason: 'nothing is wrong');
    expect(report.children.single.status.message, contains('2 assets'));

    var text = report.view.toText();
    expect(text, contains('Assets: 2'));
    expect(text, contains('assets/images/logo.png'));
    // The variant is part of the asset, not another row.
    expect(text, isNot(contains('2.0x/logo.png')));
    expect(text, contains('1 variant'));
    expect(text, contains('1 images, 1 vectors'));
  });

  test('every listed asset says where it is', () async {
    write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/logo.png
''');
    write('assets/logo.png', 'png');

    var plugin = core();
    await plugin.computeAll();

    var hits = plugin.search('logo');
    expect(hits, isNotEmpty);
    expect(
      '${hits.first.address}',
      'fw:///worktrees/${p.basename(root.path)}/flutterware.assets/./assets/logo.png',
    );
  });

  test('search reaches past what the projection lists', () async {
    write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/
''');
    for (var i = 0; i < 40; i++) {
      write('assets/icon-${i.toString().padLeft(2, '0')}.png', 'png');
    }

    var plugin = core();
    await plugin.computeAll();

    // Well past the projection's cut-off, so the default report walk would
    // never see it.
    expect(plugin.report.view.toText(), isNot(contains('icon-39.png')));
    expect(
      plugin.search('icon-39').map((h) => h.title),
      contains('assets/icon-39.png'),
    );
  });

  test(
    'a declaration that resolves to nothing is reported, not hidden',
    () async {
      write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/logo.png
    - assets/gone.png
''');
      write('assets/logo.png', 'png');

      var plugin = core();
      await plugin.computeAll();

      var report = plugin.report;
      expect(report.status.message, '1 problem');
      expect(report.status.tone, Tone.warn);
      expect(report.badge.tone, Tone.warn);

      var text = report.view.toText();
      expect(text, contains('Problems'));
      expect(text, contains('assets/gone.png'));
      expect(text, contains('Declared, and not on disk.'));
    },
  );

  test('an unresolvable declaration is deliberately not addressable', () async {
    write('pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/gone.png
''');

    var plugin = core();
    await plugin.computeAll();

    expect(
      plugin.search('gone'),
      isEmpty,
      reason:
          'A problem row names no destination — there is nowhere to go, which '
          'is what is wrong with it.',
    );
  });

  test('a dependency contributes to the bundle, and says so', () async {
    write('pubspec.yaml', '''
name: app
dependencies:
  brand:
''');
    write('.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "brand",
      "rootUri": "../../brand",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ]
}
''');
    // A sibling of the worktree root, reached the way pub reaches a path
    // dependency. It goes with the scratch directory in tearDown.
    var brand = Directory(p.join(p.dirname(root.path), 'brand'));
    File(p.join(brand.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: brand
flutter:
  assets:
    - assets/mark.png
''');
    File(p.join(brand.path, 'assets', 'mark.png'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x' * 300);

    var plugin = core();
    await plugin.computeAll();

    var text = plugin.report.view.toText();
    expect(text, contains('From packages'));
    expect(text, contains('brand'));
    expect(
      plugin.search('mark').map((h) => h.title),
      contains('packages/brand/assets/mark.png'),
    );
  });

  test('a package with no resolved config fails out loud', () async {
    File(p.join(root.path, '.dart_tool', 'package_config.json')).deleteSync();
    write('pubspec.yaml', 'name: app\n');

    var plugin = core();
    await plugin.computeAll();

    expect(plugin.report.status.tone, Tone.error);
    expect(plugin.failureFor('.'), contains('flutter pub get'));
    expect(plugin.report.view.toText(), contains('package_config.json'));
  });

  test(
    'a plugin with no packages stays quiet; the panel says how to fix it',
    () {
      var plugin = core(packages: const []);

      expect(plugin.report.status, Status.none);
      expect(plugin.report.view.toText(), contains('tool/flutterware.dart'));
    },
  );
}
