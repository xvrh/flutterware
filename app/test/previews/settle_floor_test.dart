import 'package:flutterware_app/src/previews/headless_catalog.dart';
import 'package:test/test.dart';

void main() {
  late SettleFloor floor;

  setUp(() => floor = SettleFloor());

  /// One settle pass, as `_settle` runs it: poll until two quiet readings in a
  /// row, or until the caller runs out of polls.
  bool settle(List<(int pending, int transient)> polls) {
    floor.begin();
    var zeros = 0;
    for (var (pending, transient) in polls) {
      if (floor.quiet(pending, transient)) {
        if (++zeros >= 2) {
          floor.settled(pending);
          return true;
        }
      } else {
        zeros = 0;
      }
    }
    floor.gaveUp();
    return false;
  }

  test('a clean cache settles on two quiet readings', () {
    expect(settle([(2, 0), (0, 0), (0, 0)]), isTrue);
    expect(floor.stuck, 0);
  });

  test('one quiet reading is not enough', () {
    // The frame before an animation starts looks exactly like a settled one.
    expect(settle([(0, 0)]), isFalse);
  });

  test('an animation never settles, and never raises the bar', () {
    // A ticker is tied to a mounted state and the next entry remounts, so
    // nothing here is owed to the entry after it. Raising the bar on this
    // would report the *next* looping demo as a still picture.
    expect(settle([(0, 1), (0, 1), (0, 1)]), isFalse);
    expect(floor.stuck, 0);
  });

  test('a stuck load costs the deadline once, not once per entry', () {
    // The measured bug: entry 5 leaves one load pending forever, and every
    // entry after it waited the full 3s — 282 seconds of a 324-second audit.
    expect(settle([(1, 0), (1, 0), (1, 0)]), isFalse, reason: 'entry 5');
    expect(floor.stuck, 1, reason: 'it learned the load is not coming');

    // Entry 6 has nothing pending of its own. It must not wait for entry 5's.
    expect(settle([(1, 0), (1, 0)]), isTrue);
  });

  test('a later entry still waits for its own images', () {
    settle([(1, 0), (1, 0), (1, 0)]);
    expect(floor.stuck, 1);

    // Two of its own on top of the stuck one: quiet only once they land.
    expect(settle([(3, 0), (3, 0)]), isFalse);
    expect(settle([(3, 0), (2, 0), (1, 0), (1, 0)]), isTrue);
  });

  test('the bar drops the moment the cache comes all the way down', () {
    settle([(1, 0), (1, 0), (1, 0)]);
    expect(floor.stuck, 1);

    // The stuck completer was evicted. Nothing is owed any more, and leaving
    // the bar up would accept one genuinely-pending image as settled.
    expect(settle([(0, 0), (0, 0)]), isTrue);
    expect(floor.stuck, 0);
    expect(settle([(1, 0), (1, 0)]), isFalse);
  });

  test('the bar is frozen for the pass that learns it', () {
    // Otherwise `quiet` starts passing halfway through the pass that is still
    // discovering how many loads are stuck, and the entry is judged on a frame
    // its own images had not landed in.
    floor.begin();
    expect(floor.quiet(2, 0), isFalse);
    expect(floor.quiet(2, 0), isFalse);
    floor.gaveUp();
    expect(floor.stuck, 2);
  });

  test('a pass that never polls leaves the bar alone', () {
    floor.begin();
    floor.gaveUp();
    expect(floor.stuck, 0);
  });
}
