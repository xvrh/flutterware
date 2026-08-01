import 'dart:io';

import 'package:flutterware_app/src/previews/asset_bundle.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The in-place contract: a rebuild updates the directory the engine holds a
/// file descriptor to, and never replaces it. Each test is one clause of that
/// contract; the live-guest consequence — a replaced directory bricks every
/// asset load — is in `integration_test/asset_refresh_test.dart` and the
/// 2026-07-30 mid-session spec.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_bundle_test'));
  tearDown(() => root.deleteSync(recursive: true));

  String projectRoot() => p.join(root.path, 'project');
  String output() => p.join(root.path, 'bundle');

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  AssetBundleBuilder builder() => AssetBundleBuilder(
    // A cache directory that holds nothing: every SDK payload link is
    // skipped, which keeps these tests about the project's own assets.
    cache: FlutterCache(p.join(root.path, 'cache')),
    rootPackageRoot: projectRoot(),
    packageConfigPath: p.join(
      projectRoot(),
      '.dart_tool',
      'package_config.json',
    ),
  );

  setUp(() {
    write('project/.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": []}
''');
    write('project/pubspec.yaml', '''
name: project
flutter:
  assets:
    - assets/images/
''');
    write('project/assets/images/logo.png', 'logo');
  });

  test('a rebuild keeps the directory and reports no change', () async {
    var first = await builder().build(output());
    expect(first.changed, isTrue, reason: 'The first build made everything.');

    // What the engine actually holds is a file descriptor; what a test can
    // hold is a file *in* the directory that a delete-and-recreate would
    // destroy. The daemon's kernel is exactly such a file.
    var kernel = File(p.join(output(), 'kernel_blob.bin'))
      ..writeAsStringSync('the kernel');

    var second = await builder().build(output());
    expect(second.changed, isFalse);
    expect(second.fontsChanged, isFalse);
    expect(kernel.readAsStringSync(), 'the kernel');
  });

  test('an added asset appears, as a change', () async {
    await builder().build(output());
    write('project/assets/images/added.png', 'added');

    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    expect(sync.fontsChanged, isFalse);
    expect(
      Link(p.join(output(), 'assets', 'images', 'added.png')).targetSync(),
      p.join(projectRoot(), 'assets', 'images', 'added.png'),
    );
  });

  test('a removed asset is pruned, manifest included', () async {
    write('project/assets/images/doomed.png', 'doomed');
    await builder().build(output());
    var link = Link(p.join(output(), 'assets', 'images', 'doomed.png'));
    expect(link.existsSync(), isTrue);

    File(p.join(projectRoot(), 'assets', 'images', 'doomed.png')).deleteSync();
    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    // existsSync resolves the target; what must be gone is the link itself.
    expect(FileSystemEntity.isLinkSync(link.path), isFalse);
  });

  test('a font change is called out as one', () async {
    await builder().build(output());
    write('project/assets/fonts/Brand.ttf', 'ttf');
    write('project/pubspec.yaml', '''
name: project
flutter:
  assets:
    - assets/images/
  fonts:
    - family: Brand
      fonts:
        - asset: assets/fonts/Brand.ttf
''');

    var sync = await builder().build(output());

    expect(sync.changed, isTrue);
    expect(sync.fontsChanged, isTrue);

    // And only a font change: the same pubspec again is quiet.
    var again = await builder().build(output());
    expect(again.changed, isFalse);
  });

  test('editing an asset file is not a bundle change', () async {
    await builder().build(output());
    write('project/assets/images/logo.png', 'repainted');

    var sync = await builder().build(output());

    expect(
      sync.changed,
      isFalse,
      reason:
          'The bundle entry is a symlink to the file, so the edit is already '
          'in the bundle. This is what makes edits need no rebundle at all.',
    );
  });
}
