import 'package:flutterware/devices.dart';
import 'package:test/test.dart';

/// Orientation as an axis over the table: what turning a device does to its
/// numbers, and which devices decline.
void main() {
  test('a tablet is swap-only — the insets stay where they are', () {
    var landscape = Devices.iPad.oriented(ScreenOrientation.landscape);

    expect(landscape.width, Devices.iPad.height);
    expect(landscape.height, Devices.iPad.width);
    // An iPad keeps its status bar across the top in landscape, which is why
    // nothing is declared for it and the default is right.
    expect(landscape.insetTop, Devices.iPad.insetTop);
    expect(landscape.insetLeft, 0);
  });

  test('a notched phone reads its declared landscape insets, not a rotation of '
      'the portrait four', () {
    var landscape = Devices.iphone13.oriented(ScreenOrientation.landscape);

    // The status bar is *gone*, not moved to a side — the whole reason these
    // are declared rather than permuted.
    expect(landscape.insetTop, 0);
    expect(landscape.insetLeft, 47);
    expect(landscape.insetRight, 47);
    // The home indicator stays at the interface bottom, and shrinks.
    expect(landscape.insetBottom, 21);
  });

  test('turning keeps the identity: a rotated iPad is still `ipad`', () {
    var landscape = Devices.iPad.oriented(ScreenOrientation.landscape);

    expect(landscape.id, 'ipad');
    expect(landscape.label, Devices.iPad.label);
    expect(landscape.pixelRatio, Devices.iPad.pixelRatio);
  });

  test('a desktop does not turn, and says so', () {
    expect(Devices.macbookPro.canRotate, isFalse);
    expect(Devices.iPad.canRotate, isTrue);
    expect(Devices.iphone16.canRotate, isTrue);

    var asked = Devices.macbookPro.oriented(ScreenOrientation.landscape);

    expect(asked.width, Devices.macbookPro.width);
    expect(asked.height, Devices.macbookPro.height);
  });

  test('portrait and null are the same device, untouched', () {
    expect(
      Devices.iphone16.oriented(ScreenOrientation.portrait),
      same(Devices.iphone16),
    );
    expect(Devices.iphone16.oriented(null), same(Devices.iphone16));
  });

  test('the vocabulary is one list, portrait first', () {
    expect(orientationIds, ['portrait', 'landscape']);
    expect(orientationById('landscape'), ScreenOrientation.landscape);
    expect(orientationById('sideways'), isNull);
    expect(isOrientationId('portrait'), isTrue);
    expect(isOrientationId('upside-down'), isFalse);
  });
}
