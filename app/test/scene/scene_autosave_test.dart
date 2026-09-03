// There is no save button: the workspace is written when the editor goes
// quiet, and a version that arrives on disk is taken rather than clobbered.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/autosave.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/workspace.dart';

void main() {
  /// A file as it would come off disk, so its bytes are known.
  (SceneFile, String) opened() {
    var scene = coffeeBannerDraft();
    var source = emitSceneFile(
      scene,
      className: 'BannerScene',
      motions: {'BannerIntro': coffeeIntroDraft(scene)},
    );
    var open = SceneFile.open('/scenes/banner.scene.dart', source);
    expect(open.ok, isTrue, reason: open.refusals.join('; '));
    return (open.file!, source);
  }

  test('a file writes nothing when the bytes are the ones already there', () {
    var (file, source) = opened();
    var writes = <String>[];
    expect(file.save((_, source) => writes.add(source)), isEmpty);
    expect(writes, isEmpty, reason: 'opening a canonical file is not an edit');
    expect(file.isDirty, isFalse);

    var node = file.scene.nodeNamed('headline')!;
    file.editor.rename(node, 'headlineText');
    expect(file.isDirty, isTrue);
    expect(file.save((_, source) => writes.add(source)), isEmpty);
    expect(writes, hasLength(1));
    expect(writes.single, contains('headlineText'));

    // Undoing back to where it started puts the original bytes back, so the
    // file a version control system sees is the one it started with. That is
    // what keeps an editor which saves by itself out of your diff.
    file.editor.undo();
    expect(file.save((_, written) => writes.add(written)), isEmpty);
    expect(writes, hasLength(2));
    expect(writes.last, source);
    expect(file.isDirty, isFalse);

    // And now there is nothing left to write.
    expect(file.save((_, written) => writes.add(written)), isEmpty);
    expect(writes, hasLength(2));
  });

  test('the write lands after the editor has been quiet', () {
    fakeAsync((async) {
      var (file, _) = opened();
      var workspace = SceneWorkspace(file);
      var writes = <String>[];
      var autosave = SceneAutosave(
        write: (_, source) => writes.add(source),
        onChanged: () {},
      );
      addTearDown(autosave.dispose);
      autosave.bind(workspace);

      file.editor.rename(file.scene.nodeNamed('headline')!, 'headlineText');
      expect(autosave.state, SceneSaveState.pending);
      async.elapse(const Duration(milliseconds: 400));
      expect(writes, isEmpty, reason: 'still inside the quiet period');

      // A second edit restarts it, so a drag is one write and not sixty.
      file.editor.rename(file.scene.nodeNamed('subtitle')!, 'subtitleText');
      async.elapse(const Duration(milliseconds: 700));
      expect(writes, isEmpty);
      async.elapse(const Duration(milliseconds: 200));
      expect(writes, hasLength(1));
      expect(autosave.state, SceneSaveState.saved);
      expect(writes.single, contains('subtitleText'));

      // Selection is not an edit: it must not hold the write off, and it must
      // not cause one.
      file.editor.select(file.scene.nodeNamed('cup'));
      async.elapse(const Duration(seconds: 2));
      expect(writes, hasLength(1));
    });
  });

  test('binding a workspace that already has work writes it', () {
    fakeAsync((async) {
      var (file, _) = opened();
      file.editor.rename(file.scene.nodeNamed('headline')!, 'headlineText');
      var writes = <String>[];
      var autosave = SceneAutosave(
        write: (_, source) => writes.add(source),
        onChanged: () {},
      );
      addTearDown(autosave.dispose);
      // A hot reload rebinds a workspace mid-session, and saying "saved"
      // over work nobody has written is the one thing this must not do.
      autosave.bind(SceneWorkspace(file));
      expect(autosave.state, SceneSaveState.pending);
      async.elapse(const Duration(seconds: 1));
      expect(writes, hasLength(1));
      expect(autosave.state, SceneSaveState.saved);
    });
  });

  test('an external change is taken when the editor has nothing to lose', () {
    var (file, _) = opened();
    var elsewhere = coffeeBannerDraft();
    elsewhere.nodeNamed('headline')!.name = 'headlineFromDisk';
    var incoming = emitSceneFile(elsewhere, className: 'BannerScene');

    expect(file.matchesDisk(incoming), isFalse);
    expect(file.adopt(incoming), isEmpty);
    expect(file.scene.nodeNamed('headlineFromDisk'), isNotNull);
    expect(file.isDirty, isFalse, reason: 'the editor now holds what disk has');
    expect(file.matchesDisk(incoming), isTrue, reason: 'no write owed back');

    // Undoable, which is what makes taking it safe without a dialog.
    file.editor.undo();
    expect(file.scene.nodeNamed('headline'), isNotNull);
    expect(file.scene.nodeNamed('headlineFromDisk'), isNull);
  });

  test('a suspended file is not written until somebody says whose wins', () {
    fakeAsync((async) {
      var (file, _) = opened();
      var workspace = SceneWorkspace(file);
      var writes = <String>[];
      var autosave = SceneAutosave(
        write: (_, source) => writes.add(source),
        onChanged: () {},
      );
      addTearDown(autosave.dispose);
      autosave.bind(workspace);

      file.editor.rename(file.scene.nodeNamed('headline')!, 'headlineText');
      autosave.suspend(file.path, 'changed on disk');
      async.elapse(const Duration(seconds: 2));
      expect(writes, isEmpty, reason: 'an automatic write never overwrites');
      expect(autosave.state, SceneSaveState.conflicted);

      // ⌘S is a person saying their version wins.
      autosave.flush();
      expect(writes, hasLength(1));
      expect(autosave.state, SceneSaveState.saved);
      expect(autosave.isSuspended(file.path), isFalse);
    });
  });

  test('adopting a file whose motion is gone closes the timeline', () {
    var (file, _) = opened();
    file.editor.activeMotion = 'BannerIntro';
    var without = emitSceneFile(coffeeBannerDraft(), className: 'BannerScene');
    expect(file.adopt(without), isEmpty);
    expect(file.editor.motions, isEmpty);
    expect(file.editor.activeMotion, isNull);
  });

  test('a file the parser refuses is reported, and nothing is taken', () {
    var (file, source) = opened();
    expect(file.adopt('class Nope {}'), isNotEmpty);
    expect(file.scene.nodeNamed('headline'), isNotNull);
    expect(file.matchesDisk(source), isTrue, reason: 'still what we read');
  });
}
