import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/catalog_devices.dart';

/// The test that makes the named-frame mapping safe: `device_frame`'s
/// hand-drawn bodies carry their own measurements, and a mismatch with our
/// device table would stretch every screenshot inside its frame. This is the
/// "price" the catalog's `deviceFrameFor` doc names for borrowing them.
void main() {
  test('every named frame matches our table exactly', () {
    var mapped = 0;
    for (var device in Devices.all) {
      var named = namedFrameFor(device.id);
      if (named == null) continue;
      mapped++;
      expect(
        named.screenSize,
        Size(device.width, device.height),
        reason: device.id,
      );
      expect(named.pixelRatio, device.pixelRatio, reason: device.id);
      // Portrait too, which only matters because the guest is laid out against
      // *our* insets while the body draws its own notch: a disagreement puts
      // the AppBar somewhere the artwork says there is no glass.
      expect(
        named.safeAreas,
        EdgeInsets.fromLTRB(
          device.insetLeft,
          device.insetTop,
          device.insetRight,
          device.insetBottom,
        ),
        reason: device.id,
      );
    }
    // The whole iOS shortlist has a real body.
    expect(mapped, 5);
  });

  test('every named frame agrees about landscape too', () {
    for (var device in Devices.all) {
      var named = namedFrameFor(device.id);
      if (named == null) continue;
      // The body draws its own rotated safe areas while our chrome places
      // itself from the table's. Two sets of numbers for one picture is the
      // same hazard the portrait check above exists for — a status bar drawn
      // where the artwork says there is glass.
      var turned = device.rotated();
      expect(
        named.rotatedSafeAreas,
        EdgeInsets.fromLTRB(
          turned.insetLeft,
          turned.insetTop,
          turned.insetRight,
          turned.insetBottom,
        ),
        reason: device.id,
      );
    }
  });

  test('a device with a body gets it, wherever the frame is drawn', () {
    // One function, so the flow and the preview canvas cannot disagree about
    // what an iPhone looks like — which they did, when the mapping lived in
    // `FramedShot` and only scenario shots consulted it.
    for (var device in Devices.all) {
      var named = namedFrameFor(device.id);
      if (named == null) continue;
      expect(deviceFrameFor(device), same(named), reason: device.id);
    }
  });

  test('a generic silhouette can be turned, and knows what it looks like '
      'turned', () {
    // `rotatedSafeAreas` defaults to zero rather than null, and `canRotate` is
    // `!= null` — so a body built without it claims it rotates and then draws
    // landscape with no notch at all. This is that default not being taken.
    var frame = deviceFrameFor(Devices.androidTall)!;

    // `canRotate` is exactly this being non-null.
    expect(frame.rotatedSafeAreas, isNotNull);
    expect(frame.rotatedSafeAreas, isNot(EdgeInsets.zero));
    expect(frame.rotatedSafeAreas!.top, Devices.androidTall.insetTop);
  });

  test('a desktop gets no silhouette to turn', () {
    expect(deviceFrameFor(Devices.macbookPro), isNull);
  });

  test('no named frame for an id outside the table', () {
    expect(namedFrameFor('android-medium'), isNull);
    expect(namedFrameFor('macbook-pro'), isNull);
    expect(namedFrameFor('nonsense'), isNull);
  });
}
