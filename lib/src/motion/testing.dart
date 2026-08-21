import 'package:flutter_test/flutter_test.dart';

import 'guest.dart';

/// Driving a motion from a test.
///
/// In-process, not over the VM service. A scenario runs the widget tree in
/// the test isolate, so there is nothing to connect to and nothing to wait a
/// frame for — this writes the playhead and pumps. `ext.flutterware.motion.*`
/// exists for a *host* looking at a guest in another process; here the registry
/// is just an object.
///
/// What this is for is golden frames of a motion mid-run, which is the part
/// nothing else covers. A widget test asserts the end state and a screenshot
/// shows it; both of the real timing bugs in flutterware's own demos were
/// correct at both ends and wrong in the middle.
extension MotionTester on WidgetTester {
  /// Parks the motion at [t], 0..1, and pumps.
  Future<void> seekMotion(double t, {String? scope}) async {
    _require(scope).controller.progress = t;
    await pump();
  }

  /// Parks the motion at [position] and pumps.
  Future<void> seekMotionTo(Duration position, {String? scope}) async {
    _require(scope).controller.position = position;
    await pump();
  }

  /// How long the motion runs — for computing stops without hard-coding them.
  Duration motionDuration({String? scope}) =>
      _require(scope).motionValues.resolveDuration();

  /// What one property is worth right now, without recording a read.
  ///
  /// A `double` or a `Color`, or null when nothing tunes it. Lets a test assert
  /// a value at a moment instead of comparing a picture, which is the cheaper
  /// half of the same job: a golden catches what you did not think to check, an
  /// assertion says what you meant.
  Object? motionValue(String target, String property, {String? scope}) =>
      _require(scope).peek(target, property);

  MotionSurface _require(String? scope) {
    var found = MotionRegistry.instance.resolve(scope);
    if (found != null) return found;
    var mounted = MotionRegistry.instance.ids.toList();
    throw StateError(switch ((scope, mounted.length)) {
      (null, 0) =>
        'No MotionScope is mounted. Pump a widget that has one '
            'before seeking it.',
      (null, _) =>
        'There are ${mounted.length} MotionScopes mounted (${mounted.join(', ')}); '
            'name one with `scope:`.',
      _ => 'No mounted MotionScope "$scope"; there are ${mounted.join(', ')}.',
    });
  }
}
