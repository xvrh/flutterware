// The actions, which are the only part of the plugin `fw` and an agent can
// reach. Everything here goes through `invoke` by name, the same door the CLI
// and MCP use.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scene_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/skeletons.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory scratch;
  late Directory root;

  SceneCore core() {
    var worktree = Worktree(path: root.path);
    return SceneCore(
      PluginHost(
        id: scenePluginId,
        label: 'Scene',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: const [Pkg('.')],
          discovered: const ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: const {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
    );
  }

  /// The scene goes in `demo/`, which this makes a group on the way.
  void writeScene(String name, {bool withMotion = true}) {
    var scene = coffeeBannerDraft();
    var file = File(p.join(root.path, 'demo', '$name.scene.dart'));
    file.parent.createSync(recursive: true);
    var declaration = File(p.join(root.path, 'demo', sceneGroupFileName));
    if (!declaration.existsSync()) {
      declaration.writeAsStringSync(emitGroupSkeleton());
    }
    file.writeAsStringSync(
      emitSceneFile(
        scene,
        className: name,
        motions: withMotion
            ? {'${name}Intro': coffeeIntroDraft(scene)}
            : const {},
      ),
    );
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('fw_scene_actions_test');
    root = Directory(p.join(scratch.path, 'app'))..createSync();
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('importTokens', () {
    var fixture = p.absolute('test/scene/fixtures/variables.json');

    test('writes the library, lists it in the group, regenerates', () async {
      writeScene('BannerScene', withMotion: false);
      var result =
          (await core().invoke('importTokens', arguments: {'file': fixture}))!
              as Map<String, Object?>;
      expect(result['path'], 'demo/imported.tokens.dart');
      expect(result['symbol'], 'importedTokens');
      expect(result['modes'], ['light', 'darkMode', 'defaultMode']);
      expect((result['tokens']! as List).length, 8);
      expect((result['refusals']! as List).length, 2);
      expect(result['listedBy'], ['demo'], reason: 'attached to its group');
      var written = File(p.join(root.path, 'demo', 'imported.tokens.dart'));
      expect(written.readAsStringSync(), startsWith(sceneTokensFileMarker));
      expect(
        written.readAsStringSync(),
        contains("Token<double>('radiusCard', 28"),
      );
      var declaration = File(p.join(root.path, 'demo', sceneGroupFileName));
      expect(
        declaration.readAsStringSync(),
        contains("import 'imported.tokens.dart';"),
      );
      expect(
        declaration.readAsStringSync(),
        contains('libraries: [importedTokens]'),
      );
      var args = File(p.join(root.path, 'demo', 'scene_args.dart'));
      expect(args.readAsStringSync(), contains('class SceneTokens {'));
      expect(args.readAsStringSync(), contains('static const darkMode'));
      // Importing again replaces the file it wrote, without being asked.
      await core().invoke('importTokens', arguments: {'file': fixture});
      expect(written.existsSync(), isTrue);
    });

    test('keeps a library not written by an import unless forced', () async {
      writeScene('BannerScene', withMotion: false);
      var written = File(p.join(root.path, 'demo', 'imported.tokens.dart'))
        ..writeAsStringSync(emitTokensSkeleton('importedTokens'));
      expect(
        () => core().invoke('importTokens', arguments: {'file': fixture}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not written by an import'),
          ),
        ),
      );
      await core().invoke(
        'importTokens',
        arguments: {'file': fixture, 'force': 'true'},
      );
      expect(written.readAsStringSync(), contains('brandPrimary'));
    });

    test('a missing file, or one with nothing in it, is refused', () {
      expect(
        () => core().invoke('importTokens', arguments: {'file': 'nope.json'}),
        throwsA(isA<ArgumentError>()),
      );
      var empty = File(p.join(scratch.path, 'empty.json'))
        ..writeAsStringSync('{"document": {}}');
      expect(
        () => core().invoke('importTokens', arguments: {'file': empty.path}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('nothing to import'),
          ),
        ),
      );
    });
  });

  test('list reports the groups, their scenes and where they are', () async {
    writeScene('BannerScene');
    writeScene('OtherScene', withMotion: false);
    var result = (await core().invoke('list'))! as Map<String, Object?>;
    expect(result['package'], '.');
    var groups = (result['groups']! as List).cast<Map<String, Object?>>();
    expect(groups.single['name'], 'demo');
    expect(groups.single['folder'], 'demo');
    var scenes = (groups.single['scenes']! as List)
        .cast<Map<String, Object?>>();
    expect(scenes.map((s) => s['class']).toSet(), {
      'BannerScene',
      'OtherScene',
    });
    expect(scenes.first['path'], startsWith('demo/'));
    expect(result['strayScenes'], 0);
  });

  group('tokens across the group', () {
    late String library;
    setUp(() {
      writeScene('BannerScene', withMotion: false);
      writeScene('OtherScene', withMotion: false);
      library = p.join(root.path, 'demo', 'brand.tokens.dart');
      File(library).writeAsStringSync('''
$sceneTokensFileMarker
import 'package:flutterware/scene_authoring.dart';

final brandTokens = [
  const Token<SceneColor>('brand', SceneColor(0xFFE8632B)),
];
''');
      var declaration = File(p.join(root.path, 'demo', sceneGroupFileName));
      declaration.writeAsStringSync(
        attachLibraryIn(
          declaration.readAsStringSync(),
          declaration.path,
          library,
          refuse: (r) => fail(r),
        )!,
      );
      // Both scenes read the token, spelled by hand the way the tool would.
      for (var name in ['BannerScene', 'OtherScene']) {
        var file = File(p.join(root.path, 'demo', '$name.scene.dart'));
        var source = file.readAsStringSync();
        expect(source, contains('fill: SceneColor(0xFF2B1B12)'));
        file.writeAsStringSync(
          source
              .replaceFirst(
                'fill: SceneColor(0xFF2B1B12)',
                'fill: tokens.brand',
              )
              .replaceFirst(
                'class $name extends SceneDefinition {',
                'class $name({final SceneTokens tokens = const SceneTokens()}) '
                    'extends SceneDefinition {',
              ),
        );
      }
    });

    test('readers are found in every scene of the group', () async {
      var core_ = core();
      await core_.invoke('list');
      var readers = core_.tokenReaders(
        '.',
        library,
        'brand',
        except: {p.join(root.path, 'demo', 'BannerScene.scene.dart')},
      );
      expect(readers.map((r) => '$r'), ['OtherScene · root.fill']);
      expect(core_.tokenReaders('.', library, 'brand'), hasLength(2));
      expect(core_.tokenReaders('.', library, 'nope'), isEmpty);
    });

    test('a rename rewrites the closed files, and they parse after', () async {
      var core_ = core();
      await core_.invoke('list');
      var open = p.join(root.path, 'demo', 'BannerScene.scene.dart');
      var touched = core_.renameTokenInFiles(
        '.',
        library,
        'brand',
        'accent',
        except: {open},
      );
      expect(touched.map(p.basename), ['OtherScene.scene.dart']);
      var other = File(p.join(root.path, 'demo', 'OtherScene.scene.dart'))
          .readAsStringSync();
      expect(other, contains('fill: tokens.accent'));
      expect(other, isNot(contains('tokens.brand')));
      expect(
        File(open).readAsStringSync(),
        contains('fill: tokens.brand'),
        reason: "the open file is its editor's to rename",
      );
    });
  });

  test('a scene file outside any group is counted, not listed', () async {
    File(p.join(root.path, 'lib', 'loose.scene.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        emitSceneFile(coffeeBannerDraft(), className: 'LooseScene'),
      );
    var result = (await core().invoke('list'))! as Map<String, Object?>;
    expect(result['groups'], isEmpty);
    expect(result['strayScenes'], 1);
  });

  test('newGroup writes the skeleton, and list finds the folder', () async {
    var made =
        (await core().invoke(
              'newGroup',
              arguments: {'folder': 'lib/scenes/m'},
            ))!
            as Map<String, Object?>;
    expect(made['path'], 'lib/scenes/m/$sceneGroupFileName');
    var result = (await core().invoke('list'))! as Map<String, Object?>;
    var groups = (result['groups']! as List).cast<Map<String, Object?>>();
    expect(groups.single['name'], 'm');
    expect(groups.single['scenes'], isEmpty);
    expect(
      File(p.join(root.path, 'lib/scenes/m', 'scene_args.dart')).existsSync(),
      isTrue,
      reason: 'the generated file follows, entries and all',
    );
    expect(
      () => core().invoke('newGroup', arguments: {'folder': 'lib/scenes/m'}),
      throwsA(isA<StateError>()),
    );
  });

  test('newLibrary writes an empty library and lists it in a group', () async {
    writeScene('BannerScene', withMotion: false);
    var made =
        (await core().invoke(
              'newLibrary',
              arguments: {'name': 'Brand', 'group': 'demo'},
            ))!
            as Map<String, Object?>;
    expect(made['path'], 'demo/brand.tokens.dart');
    expect(made['symbol'], 'brandTokens');
    expect(made['attachedTo'], 'demo');
    var result = (await core().invoke('list'))! as Map<String, Object?>;
    var groups = (result['groups']! as List).cast<Map<String, Object?>>();
    expect(groups.single['libraries'], ['demo/brand.tokens.dart']);
    var libraries = (result['libraries']! as List).cast<Map<String, Object?>>();
    expect(libraries.single['symbol'], 'brandTokens');
  });

  test('an unknown package is refused by naming the declared ones', () {
    expect(
      () => core().invoke('list', arguments: {'package': 'nope'}),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '$e',
          'message',
          contains('Declared: .'),
        ),
      ),
    );
  });

  test('a scene that is not there is refused by listing what is', () {
    writeScene('BannerScene');
    expect(
      () => core().invoke('video', arguments: {'scene': 'Nope'}),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '$e',
          'message',
          contains('Found: BannerScene'),
        ),
      ),
    );
  });

  test('a scene with no motion refuses rather than rendering one frame', () {
    writeScene('StillScene', withMotion: false);
    expect(
      () => core().invoke('video', arguments: {'scene': 'StillScene'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('has no motion'),
        ),
      ),
    );
  });

  test('a group whose generated player is gone says so', () async {
    writeScene('BannerScene');
    // The generated file carries the player; scan once so it exists, then
    // take it away.
    await core().invoke('list');
    File(p.join(root.path, 'demo', 'scene_args.dart')).deleteSync();
    expect(
      () => core().invoke('video', arguments: {'scene': 'BannerScene'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('no scene player'), contains('demo/')),
        ),
      ),
    );
  });
}
