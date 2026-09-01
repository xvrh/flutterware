// The workspace layer: a file is one document (scene + its motions, one
// journal), and the breadcrumb is how nesting is navigated.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/workspace.dart';

SceneFile openDraft({String path = '/demo/banner.scene.dart'}) => SceneFile(
  path: path,
  className: 'BannerScene',
  scene: coffeeBannerDraft(),
  motions: {'BannerIntro': coffeeIntroDraft()},
);

MotionKeyRef refFor(
  SceneEditor editor,
  String group,
  String prop, {
  int index = 0,
}) {
  var track = editor.trackOf('BannerIntro', group, prop)!;
  return MotionKeyRef('BannerIntro', group, prop, track.keys[index].id);
}

void main() {
  group('a file is one document', () {
    test('opening parses the pair through the door', () {
      var source = openDraft().emit();
      var opened = SceneFile.open('/demo/banner.scene.dart', source);
      expect(opened.ok, true);
      expect(opened.file!.className, 'BannerScene');
      expect(opened.file!.motions.keys, ['BannerIntro']);
      expect(opened.file!.editor.doc.walk().length, 11);
    });

    test('a refused file yields no document and every reason', () {
      var opened = SceneFile.open('/bad.scene.dart', 'class Nope {}');
      expect(opened.ok, false);
      expect(opened.refusals, isNotEmpty);
    });

    test('dirty tracks the editor, and save writes through the door', () {
      var file = openDraft();
      expect(file.isDirty, false);
      file.editor.perform('Edit x', () => file.scene.nodeNamed('glow')!.x = 42);
      expect(file.isDirty, true);
      String? wrotePath;
      String? wroteSource;
      var refusals = file.save((path, source) {
        wrotePath = path;
        wroteSource = source;
      });
      expect(refusals, isEmpty);
      expect(wrotePath, '/demo/banner.scene.dart');
      expect(file.isDirty, false);
      // What was written round-trips, motions included.
      var reopened = SceneFile.open(wrotePath!, wroteSource!);
      expect(reopened.ok, true);
      expect(reopened.file!.scene.nodeNamed('glow')!.x, 42);
      expect(reopened.file!.motions.keys, ['BannerIntro']);
    });

    test('an undo back to the saved state still reads dirty', () {
      var file = openDraft();
      file.save((_, _) {});
      file.editor.perform('Edit x', () => file.scene.nodeNamed('glow')!.x = 42);
      file.editor.undo();
      expect(file.scene.nodeNamed('glow')!.x, 600);
      expect(file.isDirty, true, reason: 'safe direction to be wrong in');
    });
  });

  group('both planes share one journal', () {
    test('a key edit undoes through the same door as a layout edit', () {
      var file = openDraft();
      var editor = file.editor;
      var ref = refFor(editor, 'headlineIn', 'opacity', index: 1);
      editor.perform('Edit x', () => file.scene.nodeNamed('glow')!.x = 42);
      editor.perform('Retune', () => editor.keyOf(ref)!.value = 0.25);
      expect(editor.keyOf(ref)!.value, 0.25);
      editor.undo();
      expect(editor.keyOf(ref)!.value, 1.0);
      expect(file.scene.nodeNamed('glow')!.x, 42);
      editor.undo();
      expect(file.scene.nodeNamed('glow')!.x, 600);
    });

    test('restore revives keys in place, so a bound motion survives', () {
      var file = openDraft();
      var editor = file.editor;
      var bound = BoundMotion.bind(file.motions['BannerIntro']!, file.scene);
      var ref = refFor(editor, 'headlineIn', 'opacity', index: 1);
      editor.perform('Retune', () => editor.keyOf(ref)!.value = 0.25);
      editor.undo();
      // The same key object came back — the group the player holds is still
      // the group in the document.
      bound.apply(const Duration(milliseconds: 260));
      expect(file.scene.nodeNamed('headline')!.fxRendered('opacity'), 1.0);
      expect(editor.keyOf(ref), isNotNull);
    });

    test('a key moved past its neighbour keeps its identity', () {
      var file = openDraft();
      var editor = file.editor;
      var ref = refFor(editor, 'glowMood', 'opacity', index: 2);
      editor.setKeySelection([ref]);
      editor.nudgeKeys(const Duration(milliseconds: -1500));
      var track = editor.trackOf('BannerIntro', 'glowMood', 'opacity')!;
      // The last key sorted to the middle (0, 300, 900), and the selection
      // still points at it — an index would now be off by one.
      expect(track.keys.map((k) => k.at.inMilliseconds), [0, 300, 900]);
      expect(track.keys[1].id, ref.keyId);
      expect(editor.keyOf(ref)!.at, const Duration(milliseconds: 300));
      expect(editor.selectedKeys, [ref]);
      editor.undo();
      expect(editor.keyOf(ref)!.at, const Duration(milliseconds: 1800));
    });

    test('deleting keys drops them and the refs go stale, not stray', () {
      var file = openDraft();
      var editor = file.editor;
      var ref = refFor(editor, 'headlineIn', 'opacity');
      editor.setKeySelection([ref]);
      editor.deleteKeys();
      expect(editor.trackOf('BannerIntro', 'headlineIn', 'opacity')!.keys, [
        isA<MotionKey>(),
      ]);
      expect(editor.keyOf(ref), isNull);
      expect(editor.selectedKeys, isEmpty);
      editor.undo();
      expect(editor.keyOf(ref), isNotNull);
    });

    test('the two selection domains never hold at once', () {
      var file = openDraft();
      var editor = file.editor;
      editor.select(file.scene.nodeNamed('glow'));
      editor.selectKey(refFor(editor, 'headlineIn', 'opacity'));
      expect(editor.selectionNames, isEmpty);
      expect(editor.selectedKeys, hasLength(1));
      editor.select(file.scene.nodeNamed('glow'));
      expect(editor.selectedKeys, isEmpty);
      expect(editor.selectionNames, ['glow']);
    });
  });

  group('the breadcrumb', () {
    test('starts at the file you opened', () {
      var root = openDraft();
      var workspace = SceneWorkspace(root);
      expect(workspace.crumbs, hasLength(1));
      expect(workspace.active, root);
      expect(workspace.isNested, false);
      expect(workspace.editor, root.editor);
    });

    test('entering switches the surface and leaves a crumb', () {
      var root = openDraft();
      var nested = openDraft(path: '/demo/badge.scene.dart');
      var workspace = SceneWorkspace(
        root,
        resolveNested: (node) => node.name == 'badge' ? nested : null,
      );
      workspace.enter(root.scene.nodeNamed('badge')!);
      expect(workspace.active, nested);
      expect(workspace.isNested, true);
      expect(workspace.crumbs.map((c) => c.viaNode), [null, 'badge']);
      workspace.exit();
      expect(workspace.active, root);
      // Coming back selects the node you went in through.
      expect(root.editor.selectionNames, ['badge']);
    });

    test('a node that is not a nested scene refuses loudly', () {
      var root = openDraft();
      var workspace = SceneWorkspace(root, resolveNested: (_) => null);
      expect(
        () => workspace.enter(root.scene.nodeNamed('glow')!),
        throwsArgumentError,
      );
      expect(
        () => SceneWorkspace(root).enter(root.scene.nodeNamed('badge')!),
        throwsStateError,
      );
    });

    test('goTo pops everything deeper in one step', () {
      var root = openDraft();
      var a = openDraft(path: '/a.scene.dart');
      var b = openDraft(path: '/b.scene.dart');
      var files = {'badge': a, 'loading': b};
      var workspace = SceneWorkspace(
        root,
        resolveNested: (node) => files[node.name],
      );
      workspace.enter(root.scene.nodeNamed('badge')!);
      workspace.enter(a.scene.nodeNamed('loading')!);
      expect(workspace.crumbs, hasLength(3));
      workspace.goTo(0);
      expect(workspace.active, root);
      expect(workspace.crumbs, hasLength(1));
    });

    test('anyDirty sees unsaved work anywhere in the breadcrumb', () {
      var root = openDraft();
      var nested = openDraft(path: '/n.scene.dart');
      var workspace = SceneWorkspace(root, resolveNested: (_) => nested);
      workspace.enter(root.scene.nodeNamed('badge')!);
      expect(workspace.anyDirty, false);
      nested.editor.perform('Edit', () => nested.scene.nodeNamed('cup')!.x = 5);
      workspace.exit();
      expect(workspace.active, root);
      // Left the nested scene, but its unsaved work is still unsaved.
      expect(workspace.anyDirty, true);
      expect(workspace.dirtyFiles.map((f) => f.path), ['/n.scene.dart']);
    });
  });
}
