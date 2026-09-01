// The actions, which are the only part of the plugin `fw` and an agent can
// reach. Everything here goes through `invoke` by name, the same door the CLI
// and MCP use.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/canvas_toy/drafts.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scene_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
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
            {'path': '.', 'directory': 'demo'},
          ],
        },
      ),
    );
  }

  void writeScene(String name, {bool withMotion = true}) {
    var file = File(p.join(root.path, 'demo', '$name.scene.dart'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      emitSceneFile(
        coffeeBannerDraft(),
        className: name,
        motions: withMotion ? {'${name}Intro': coffeeIntroDraft()} : const {},
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

  test('list reports the scenes and where they are', () async {
    writeScene('BannerScene');
    writeScene('OtherScene', withMotion: false);
    var result = (await core().invoke('list'))! as Map<String, Object?>;
    expect(result['package'], '.');
    var scenes = (result['scenes']! as List).cast<Map<String, Object?>>();
    expect(scenes.map((s) => s['class']).toSet(), {
      'BannerScene',
      'OtherScene',
    });
    expect(scenes.first['path'], startsWith('demo/'));
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

  test('a project with no scene player says what to declare', () {
    writeScene('BannerScene');
    expect(
      () => core().invoke('video', arguments: {'scene': 'BannerScene'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('scenePlayer'), contains('pair')),
        ),
      ),
    );
  });
}
