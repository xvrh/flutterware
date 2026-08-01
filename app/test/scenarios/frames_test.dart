import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/scenarios/framed_shot.dart';

/// The test that makes the named-frame mapping safe: `device_frame`'s
/// hand-drawn bodies carry their own measurements, and a mismatch with our
/// device table would stretch every screenshot inside its frame. This is the
/// "test to hold the two together" the catalog's `deviceFrameFor` doc names
/// as the price of a second list.
void main() {
  test('every named frame matches our table exactly', () {
    var mapped = 0;
    for (var device in Devices.all) {
      var named = FramedShot.namedFrameFor(device.id);
      if (named == null) continue;
      mapped++;
      expect(
        named.screenSize,
        Size(device.width, device.height),
        reason: device.id,
      );
      expect(named.pixelRatio, device.pixelRatio, reason: device.id);
    }
    // The whole iOS shortlist has a real body.
    expect(mapped, 5);
  });

  test('no named frame for an id outside the table', () {
    expect(FramedShot.namedFrameFor('android-medium'), isNull);
    expect(FramedShot.namedFrameFor('macbook-pro'), isNull);
    expect(FramedShot.namedFrameFor('nonsense'), isNull);
  });
}
