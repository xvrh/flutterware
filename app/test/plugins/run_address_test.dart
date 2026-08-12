import 'package:flutterware_app/src/plugins/native/run_address.dart';
import 'package:test/test.dart';

void main() {
  group('round trip', () {
    for (var place in [
      const RunPlace.first(),
      const RunPlace.newRun(),
      const RunPlace('app-03109c1723af'),
      const RunPlace('app-03109c1723af', view: RunViewKind.logs),
    ]) {
      test('$place', () {
        expect(runPlace(runSegmentsOf(place)), place);
      });
    }
  });

  test('a run is written with its pane, always', () {
    // Not shortened for the default tab. A strip whose first tab produced a
    // shorter address than the others would make "copy this address" mean
    // something different depending on where you were standing.
    expect(runSegments('app-abc'), ['app-abc', 'screen']);
    expect(runSegments('app-abc', view: RunViewKind.logs), ['app-abc', 'logs']);
  });

  test('a bare key reads as its screen', () {
    expect(runPlace(['app-abc']), const RunPlace('app-abc'));
  });

  test('a tab this build does not know falls back to the screen', () {
    // The strip is an extension point: `Data` arrives as a devbar plugin
    // later. An address from a newer build should lose the pane, not the run.
    var place = runPlace(['app-abc', 'data']);
    expect(place.runKey, 'app-abc');
    expect(place.view, RunViewKind.screen);
    expect(place.isNew, isFalse);
  });

  test('the network tab is a place', () {
    var place = runPlace(['app-abc', 'network']);
    expect(place.runKey, 'app-abc');
    expect(place.view, RunViewKind.network);
  });

  test('empty segments are the default place, not an error', () {
    expect(runPlace(const []), const RunPlace.first());
    expect(runPlace(['']), const RunPlace.first());
  });

  test('new is a place of its own, with no run behind it', () {
    var place = runPlace([newRunSegment]);
    expect(place.isNew, isTrue);
    expect(place.runKey, isNull);
  });

  test('a run key is never confused with the new-run page', () {
    expect(runPlace(['app-new']).isNew, isFalse);
    expect(runPlace(['app-new']).runKey, 'app-new');
  });

  test('the default place and the new page are different places', () {
    expect(const RunPlace.first() == const RunPlace.newRun(), isFalse);
  });

  test('RunViewKind.byName refuses what it does not know', () {
    expect(RunViewKind.byName('logs'), RunViewKind.logs);
    expect(RunViewKind.byName('Screen'), isNull);
    expect(RunViewKind.byName(''), isNull);
  });

  test(
    'an address to the tree tab that briefly existed lands on the screen',
    () {
      // `tree` shipped as a third tab for a day before the design was re-read:
      // the Screen tab is a split, picture beside tree, and separating them was
      // the deviation. Anyone holding that address keeps their run.
      var place = runPlace(['app-abc', 'tree']);
      expect(place.runKey, 'app-abc');
      expect(place.view, RunViewKind.screen);
    },
  );
}
