import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/catalog_devices.dart';
import 'package:flutterware_app/src/previews/island_phone_frame.dart';

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

  test('no iPhone falls through to the generic body', () {
    // The bug this half exists for: `iphone-16` had no artwork, so it drew as
    // `DeviceInfo.genericPhone` — a lozenge with an 80pt forehead and a camera
    // dot above the glass, which is a generic Android and reads as one.
    var ours = 0;
    for (var device in Devices.all) {
      if (device.platform != DevicePlatform.ios ||
          device.kind != DeviceKind.phone) {
        continue;
      }
      var frame = deviceFrameFor(device)!;
      if (namedFrameFor(device.id) != null) continue;
      ours++;
      expect(
        frame.framePainter,
        isA<IslandPhoneFramePainter>(),
        reason: device.id,
      );
    }
    expect(ours, 2, reason: 'the two 16s');
  });

  test('the island is a hole in the screen, not a pill drawn over it', () {
    // Which is what makes it black without anything rendering there, and what
    // stops a demo from painting over the top of it.
    var path = deviceFrameFor(Devices.iphone16)!.screenPath;
    var glass = path.getBounds();

    expect(
      path.contains(Offset(glass.center.dx, glass.top + 25)),
      isFalse,
      reason: 'the middle of the island is not screen',
    );
    expect(
      path.contains(Offset(glass.left + 90, glass.top + 25)),
      isTrue,
      reason: 'the glass beside it is',
    );
  });

  test('an iPhone we draw ourselves says what it looks like turned', () {
    // Same default not taken as the generic silhouette below: left alone,
    // `rotatedSafeAreas` is zero rather than null, and the body claims it
    // rotates and then draws landscape with no island and no home indicator.
    var frame = deviceFrameFor(Devices.iphone16)!;
    var turned = Devices.iphone16.rotated();

    expect(frame.rotatedSafeAreas, isNotNull);
    expect(frame.rotatedSafeAreas!.left, turned.insetLeft);
    expect(frame.rotatedSafeAreas!.top, turned.insetTop);
    expect(frame.rotatedSafeAreas!.bottom, turned.insetBottom);
  });

  test('an iPhone body is built from the table, not measured again', () {
    // The reason this needs no `frames_test` pinning of its own: it is built
    // from the [Device], so there is no second set of measurements to drift.
    var device = Devices.iphone16ProMax;
    var frame = deviceFrameFor(device)!;

    expect(frame.screenSize, Size(device.width, device.height));
    expect(frame.pixelRatio, device.pixelRatio);
    expect(frame.safeAreas.top, device.insetTop);
    expect(frame.safeAreas.bottom, device.insetBottom);
    expect(frame.name, device.label);
    // The frame is bigger than the glass, and the glass sits inside it — a
    // painter drawing to the wrong box would put the screen off the body.
    expect(frame.frameSize.width, greaterThan(device.width));
    expect(frame.frameSize.height, greaterThan(device.height));
    expect(
      frame.screenPath.getBounds().size,
      Size(device.width, device.height),
    );
  });

  test('a desktop gets no silhouette to turn', () {
    expect(deviceFrameFor(Devices.wideWindow), isNull);
  });

  test('asking whether a device has a body agrees with drawing one', () {
    // The frame toggle asks the cheap question every build; the canvas asks the
    // expensive one when it draws. A disagreement is a switch that is live for
    // a picture it cannot change, which is what it used to be for a window.
    for (var device in Devices.all) {
      expect(
        canBeFramed(device),
        deviceFrameFor(device) != null,
        reason: device.id,
      );
    }
  });

  test('no named frame for an id outside the table', () {
    expect(namedFrameFor('android-medium'), isNull);
    expect(namedFrameFor('macbook-pro'), isNull);
    expect(namedFrameFor('nonsense'), isNull);
  });
}
