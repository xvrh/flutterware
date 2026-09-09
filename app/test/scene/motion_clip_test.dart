// Clip blocks: bars on a placement's time track — evaluated as ramps,
// blended where two overlap, carried by the JSON and the file, moved,
// trimmed and reversed by the editor, and replaced by a key the moment one
// is added.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/editor.dart';

void main() {
  group('evaluate', () {
    test('holds before the block, ramps through it, holds after', () {
      var t = ClipTrack(
        at: const Duration(seconds: 1),
        length: const Duration(seconds: 2),
      );
      expect(t.evaluate(Duration.zero), 0.0);
      expect(t.evaluate(const Duration(seconds: 1)), 0.0);
      expect(t.evaluate(const Duration(seconds: 2)), 1.0);
      expect(t.evaluate(const Duration(seconds: 3)), 2.0);
      expect(t.evaluate(const Duration(seconds: 9)), 2.0);
      expect(t.duration, const Duration(seconds: 3));
    });

    test('speed, offset and reverse shape the ramp', () {
      var t = ClipTrack(
        at: Duration.zero,
        length: const Duration(seconds: 2),
        speed: 1.5,
        offset: const Duration(milliseconds: 500),
      );
      expect(t.evaluate(Duration.zero), 0.5);
      expect(t.evaluate(const Duration(seconds: 2)), closeTo(3.5, 1e-9));
      var back = ClipTrack(
        at: Duration.zero,
        length: const Duration(seconds: 2),
        reverse: true,
      );
      expect(back.evaluate(Duration.zero), 2.0);
      expect(back.evaluate(const Duration(seconds: 2)), 0.0);
    });

    test('two blocks that overlap crossfade across the overlap', () {
      var t = ClipBlocks([
        ClipBlock(
          clip: 'Walk',
          at: Duration.zero,
          length: const Duration(seconds: 1),
        ),
        ClipBlock(
          clip: 'Run',
          at: const Duration(milliseconds: 700),
          length: const Duration(seconds: 1),
        ),
      ]);
      var before = t.blendAt(const Duration(milliseconds: 500));
      expect((before.clip, before.clip2, before.blend), ('Walk', '', 0.0));
      expect(before.time, 0.5);
      var mid = t.blendAt(const Duration(milliseconds: 850));
      expect((mid.clip, mid.clip2), ('Walk', 'Run'));
      expect(mid.blend, closeTo(0.5, 1e-9));
      expect(mid.time, closeTo(0.85, 1e-9));
      expect(mid.time2, closeTo(0.15, 1e-9));
      var after = t.blendAt(const Duration(milliseconds: 1500));
      expect((after.clip, after.clip2, after.blend), ('Run', '', 0.0));
      expect(after.time, closeTo(0.8, 1e-9));
      var past = t.blendAt(const Duration(seconds: 5));
      expect(past.clip, 'Run');
      expect(past.time, 1.0, reason: 'the last block holds its end');
      expect(
        t.evaluate(const Duration(milliseconds: 850)),
        closeTo(0.85, 1e-9),
      );
    });
  });

  test('the JSON carries the blocks and a copy keeps them', () {
    var scene = SceneDocument(FrameNode(name: 'root'));
    var doc = MotionDocument(sceneClassName: 'S');
    var group = AnimateGroup(scene.root, name: 'g')
      ..tracks['animationTime'] = ClipBlocks([
        ClipBlock(
          clip: 'Run',
          at: const Duration(milliseconds: 100),
          length: const Duration(seconds: 2),
          speed: 2,
          reverse: true,
        ),
        ClipBlock(at: Duration.zero, length: const Duration(seconds: 1)),
      ]);
    doc.groups.add(group);
    doc.timeline = ParExpr([group]);
    var back = motionFromJson(doc.toJson(), sceneClassName: 'S', scene: scene);
    var clips = back.groups.single.tracks['animationTime']!.clips;
    expect(clips.map((c) => c.clip), ['', 'Run'], reason: 'sorted by start');
    expect(clips[1].length, const Duration(seconds: 2));
    expect(clips[1].speed, 2);
    expect(clips[1].reverse, isTrue);
    expect(group.tracks['animationTime']!.copy().clips, hasLength(2));
  });

  test(
    'the editor adds blocks, moves and trims one, and a key replaces them',
    () {
      var scene = SceneDocument(
        FrameNode(name: 'root')
          ..children.add(
            ModelNode(name: 'fox', asset: 'x.glb', animation: 'Run'),
          ),
      );
      var editor = SceneEditor(scene);
      var motion = editor.addMotion('S');
      var fox = scene.nodeNamed('fox')!;
      var group = editor.addGroup(motion, fox);
      const prop = 'animationTime';
      editor.addClip(
        motion,
        group.name,
        prop,
        at: Duration.zero,
        length: const Duration(seconds: 1),
        clip: 'Walk',
      );
      editor.addClip(
        motion,
        group.name,
        prop,
        at: const Duration(milliseconds: 700),
        length: const Duration(seconds: 1),
        clip: 'Run',
      );
      List<MotionClip> clips() =>
          editor.trackOf(motion, group.name, prop)!.clips;
      expect(clips().map((c) => c.clip), ['Walk', 'Run']);

      editor.nudgeClip(
        motion,
        group.name,
        prop,
        1,
        const Duration(milliseconds: 300),
      );
      expect(clips()[1].at, const Duration(seconds: 1));
      editor.nudgeClip(
        motion,
        group.name,
        prop,
        1,
        const Duration(milliseconds: 500),
        edge: 'end',
      );
      expect(clips()[1].length, const Duration(milliseconds: 1500));
      editor.nudgeClip(
        motion,
        group.name,
        prop,
        0,
        const Duration(milliseconds: 200),
        edge: 'start',
      );
      expect(clips()[0].at, const Duration(milliseconds: 200));
      expect(clips()[0].length, const Duration(milliseconds: 800));
      editor.nudgeClip(
        motion,
        group.name,
        prop,
        0,
        const Duration(seconds: -9),
        edge: 'start',
      );
      expect(clips()[0].at, Duration.zero, reason: 'never before the group');
      // Moved past the other, the blocks re-sort.
      editor.nudgeClip(motion, group.name, prop, 0, const Duration(seconds: 3));
      expect(clips().map((c) => c.clip), ['Run', 'Walk']);
      editor.undo();
      expect(clips().map((c) => c.clip), ['Walk', 'Run']);

      editor.setClip(
        motion,
        group.name,
        prop,
        1,
        speed: 2,
        reverse: true,
        clip: 'Survey',
      );
      expect(
        (clips()[1].speed, clips()[1].reverse, clips()[1].clip),
        (2.0, true, 'Survey'),
      );
      editor.undo();
      expect(clips()[1].speed, 1);

      editor.deleteClip(motion, group.name, prop, 0);
      expect(clips().map((c) => c.clip), ['Run']);
      editor.deleteClip(motion, group.name, prop, 0);
      expect(
        editor.trackOf(motion, group.name, prop),
        isNull,
        reason: 'the last block takes the track',
      );
      editor.undo();
      expect(clips(), hasLength(1));

      editor.addKey(motion, group.name, prop, const Duration(seconds: 1));
      var track = editor.trackOf(motion, group.name, prop)!;
      expect(track.clips, isEmpty, reason: 'a key replaces the blocks');
      expect(track.keys, hasLength(1));
    },
  );

  test('a selected block survives a re-sort and an undo, and the inspector '
      'doors hold at their limits', () {
    var scene = SceneDocument(
      FrameNode(name: 'root')
        ..children.add(ModelNode(name: 'fox', asset: 'x.glb')),
    );
    var editor = SceneEditor(scene);
    var motion = editor.addMotion('S');
    var group = editor.addGroup(motion, scene.nodeNamed('fox')!);
    const prop = 'animationTime';
    List<MotionClip> clips() => editor.trackOf(motion, group.name, prop)!.clips;
    editor.addClip(
      motion,
      group.name,
      prop,
      at: const Duration(seconds: 1),
      length: const Duration(seconds: 1),
      clip: 'Walk',
    );
    expect(editor.selectedClip, isNotNull, reason: 'a new block is selected');
    expect(editor.clipOf(editor.selectedClip!)!.clip, 'Walk');
    editor.addClip(
      motion,
      group.name,
      prop,
      at: const Duration(seconds: 2),
      length: const Duration(seconds: 1),
      clip: 'Run',
    );
    var run = editor.selectedClip!;
    expect(editor.clipIndexOf(run), 1);

    // Walk moved past Run: the list re-sorts, the selection holds Run.
    editor.nudgeClip(motion, group.name, prop, 0, const Duration(seconds: 5));
    expect(clips().map((c) => c.clip), ['Run', 'Walk']);
    expect(editor.selectedClip, run);
    expect(editor.clipIndexOf(run), 0);
    editor.undo();
    expect(editor.clipIndexOf(run), 1, reason: 'restored into the same id');

    // The inspector's fields, at their limits.
    editor.setClip(
      motion,
      group.name,
      prop,
      1,
      at: const Duration(seconds: -1),
      length: Duration.zero,
      speed: 0,
      offset: const Duration(seconds: -1),
    );
    var block = editor.clipOf(run)!;
    expect(block.at, Duration.zero);
    expect(block.length, const Duration(milliseconds: 50));
    expect(block.speed, 0.01);
    expect(block.offset, Duration.zero);
    expect(clips().first, same(block), reason: 'moved to the front, re-sorted');

    // A node selection ends the block's; delete-selected takes the block.
    editor.select(scene.nodeNamed('fox'));
    expect(editor.selectedClip, isNull);
    editor.selectClip(run);
    expect(editor.selectionNames, isEmpty);
    editor.deleteSelected();
    expect(clips().map((c) => c.clip), ['Walk']);
    expect(editor.selectedClip, isNull);
    editor.undo();
    expect(clips(), hasLength(2));
  });
}
