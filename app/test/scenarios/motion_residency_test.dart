import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/scenarios/motion_player.dart';
import 'package:path/path.dart' as p;

/// What keeps a long flow from evicting itself.
///
/// Recorded frames are held at the step's own scale — 1.29MB of decoded pixels
/// each on a phone — so a scenario of any length would run past Flutter's
/// 100MB image cache and start throwing away the screenshots the flow is made
/// of. The residency is the bound; these are the properties it has to have.
void main() {
  // Evicting goes through the image cache, which is the binding's.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_motion_residency');
  });
  tearDown(() {
    scenarioMotionResidency.clear();
    root.deleteSync(recursive: true);
  });

  /// A step whose recording decodes to roughly [megabytes].
  ScenarioRunStep step(int index, {required int megabytes}) {
    var frames = p.join('run', '$index.frames');
    var directory = Directory(p.join(root.path, frames))
      ..createSync(recursive: true);
    // 10 frames of 512×512 rgba is ~10MB; the files only have to exist for
    // `frameFiles` to name them.
    var count = megabytes;
    for (var frame = 0; frame < count; frame++) {
      File(
        p.join(directory.path, '${frame.toString().padLeft(4, '0')}.raw'),
      ).writeAsBytesSync(const []);
    }
    return ScenarioRunStep(
      index: index,
      auto: false,
      image: 'run/$index.raw',
      format: 'raw',
      width: 512,
      height: 512,
      tree: 'run/$index.tree.json',
      texts: const [],
      address: 'fw://wt/p/$index',
      root: root.path,
      frames: frames,
      frameCount: count,
      frameWidth: 512,
      frameHeight: 512,
      frameIntervalMs: 33,
    );
  }

  test('a step of n frames costs its pixels, not its file size', () {
    // The number the budget is spent in: what the image cache holds is decoded
    // pixels, so PNG frames and raw frames cost exactly the same here.
    expect(scenarioMotionBytes(step(1, megabytes: 10)), 10 * 512 * 512 * 4);
  });

  test('holds recent transitions and hands the oldest back', () {
    var residency = ScenarioMotionResidency(budgetBytes: 25 * 1024 * 1024);
    // ~10MB each: two fit, the third pushes the first out.
    var a = step(1, megabytes: 10);
    var b = step(2, megabytes: 10);
    var c = step(3, megabytes: 10);

    residency
      ..touch(a)
      ..touch(b);
    expect(residency.residentSteps, 2);

    residency.touch(c);
    expect(residency.residentSteps, 2, reason: 'the oldest was released');
    expect(residency.residentBytes, lessThan(25 * 1024 * 1024));

    // Hovering back to `b` keeps it — it was the most recent, not the oldest,
    // so walking back and forth between two neighbours never re-decodes.
    residency.touch(b);
    expect(residency.residentSteps, 2);
  });

  test('never releases the transition being played', () {
    // A recording bigger than the whole budget still has to play, so the step
    // just touched is never the one evicted.
    var residency = ScenarioMotionResidency(budgetBytes: 1024);
    residency.touch(step(1, megabytes: 40));
    expect(residency.residentSteps, 1);
    expect(residency.residentBytes, greaterThan(1024));
  });

  test('an evicted transition stops being one the panel wants decoded', () {
    // What the precache loop checks between frames. Sweeping the pointer
    // across a flow starts a loop per node it crosses, and a loop that
    // outlived its own eviction would put the frames it was still decoding
    // back into the image cache — so the budget would only hold for somebody
    // hovering slowly.
    var residency = ScenarioMotionResidency(budgetBytes: 15 * 1024 * 1024);
    var a = step(1, megabytes: 10);
    var b = step(2, megabytes: 10);

    residency.touch(a);
    expect(residency.isResident(a), isTrue);

    residency.touch(b);
    expect(residency.isResident(a), isFalse, reason: 'a was pushed out');
    expect(residency.isResident(b), isTrue);
  });

  test('a re-run releases the frames it replaced', () {
    var residency = ScenarioMotionResidency();
    var old = step(1, megabytes: 5);
    residency.touch(old);
    expect(residency.residentSteps, 1);

    // The previous run's directory is deleted the moment the next one lands
    // (`scenarios_core.dart`), so its decoded pixels are pointing at nothing.
    residency.forget(old);
    expect(residency.residentSteps, 0);
    expect(residency.residentBytes, 0);
  });

  test('stays under the budget across a long flow', () async {
    // The case that motivated all of this: twenty steps of a real phone-sized
    // recording, walked end to end.
    var residency = ScenarioMotionResidency();
    for (var index = 1; index <= 20; index++) {
      residency.touch(step(index, megabytes: 21));
    }
    expect(residency.residentBytes, lessThanOrEqualTo(residency.budgetBytes));
    // And what it holds is a whole number of transitions — half a recording
    // is no use to anybody.
    expect(residency.residentSteps, greaterThanOrEqualTo(1));
    expect(
      PaintingBinding.instance.imageCache.currentSizeBytes,
      lessThan(100 << 20),
    );
  });
}
