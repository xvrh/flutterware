import 'package:flutterware_app/src/catalog/catalog_devices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the vocabulary an address may use', () {
    test('every offered device has an id, and they are distinct', () {
      var ids = [for (var d in Devices.all) d.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, everyElement(matches(RegExp(r'^[a-z0-9-]+$'))));
    });

    test('the accepted list is the offered list plus fit', () {
      // One list, so the picker and the address cannot disagree about what
      // exists. A vocabulary documented apart from the code that enforces it is
      // a vocabulary that is wrong.
      expect(deviceIds.first, fitDeviceId);
      expect(deviceIds, hasLength(Devices.all.length + 1));
      expect(deviceIds.every(isDeviceId), isTrue);
    });

    test('an id names the device that carries it', () {
      for (var device in Devices.all) {
        expect(deviceById(device.id), same(device), reason: device.id);
      }
      expect(deviceById(fitDeviceId), isNull, reason: 'fit is not a device');
    });
  });

  group('the list is the only source', () {
    test('a phone or tablet gets a silhouette built from its own numbers', () {
      // Not borrowed from a named `device_frame` device, so there is no second
      // set of measurements to drift from — which is why nothing here checks
      // one list against another any more.
      var device = deviceById('iphone-13')!;
      var chrome = deviceFrameFor(device)!;

      expect(chrome.screenSize.width, device.width);
      expect(chrome.screenSize.height, device.height);
      expect(chrome.pixelRatio, device.pixelRatio);
      expect(chrome.safeAreas.top, device.insetTop);
      expect(chrome.safeAreas.bottom, device.insetBottom);
      expect(chrome.name, device.label);
    });

    test('a desktop size gets none, because the panel already is one', () {
      expect(deviceFrameFor(deviceById('macbook-pro')!), isNull);
      expect(deviceFrameFor(deviceById('wide-monitor')!), isNull);
    });

    test('every phone and tablet can be drawn', () {
      for (var device in Devices.all) {
        expect(
          deviceFrameFor(device),
          device.kind == DeviceKind.desktop ? isNull : isNotNull,
          reason: device.id,
        );
      }
    });
  });

  group('a viewport built from a device', () {
    test('is physical pixels, but keeps the logical ratio and the notch', () {
      var viewport = CaptureViewport.of(deviceById('iphone-13')!);

      // 390x844 at 3x. The demo must read 390 from MediaQuery, not 1170, so the
      // ratio travels beside the buffer rather than being folded into it.
      expect(viewport.width, 1170);
      expect(viewport.height, 2532);
      expect(viewport.pixelRatio, 3);
      expect(viewport.insetTop, 47);
      expect(viewport.insetBottom, 34);
    });

    test('an explicit size stretches it without flattening it', () {
      // Asking for a taller iPhone is asking for a taller iPhone, not for a
      // slab of glass with no notch.
      var viewport = CaptureViewport.of(
        deviceById('iphone-13')!,
      ).resized(height: 3000);

      expect(viewport.width, 1170);
      expect(viewport.height, 3000);
      expect(viewport.pixelRatio, 3);
      expect(viewport.insetTop, 47);
    });

    test('the panel is the degenerate case', () {
      expect(CaptureViewport.panel.pixelRatio, 1);
      expect(CaptureViewport.panel.insetTop, 0);
    });
  });

  group('a device is derived, never held', () {
    // The bug this replaced: the picker set a field on the staging, the panel
    // copied that into the address a frame later, and the address copied back.
    // Two sources of truth with a copy loop between them — so a pick could be
    // read back from an address that had not caught up, and erased. There is
    // nothing to fall out of step with now.
    test('what the address names', () {
      expect(resolveDevice('iphone-13')?.id, 'iphone-13');
    });

    test('naming nothing is the panel', () {
      // It used to be the entry's turn to speak here, through `formFactor`.
      // With the declaration gone there is one answer and no `??` behind it.
      expect(resolveDevice(null), isNull);
    });

    test('fit is a choice, and reads as one', () {
      // Kept as a value rather than an absent parameter even though the two now
      // resolve alike: an address that says `fit` says somebody chose the panel,
      // and that survives a reload where an absent parameter would not.
      expect(resolveDevice(fitDeviceId), isNull);
      expect(unknownDeviceIn(fitDeviceId), isNull);
    });

    test('an unknown device frames as the panel, and is reported', () {
      // Loudly, because the silent failure is the dangerous one: framing as
      // the panel when the address asked for an iPhone produces a picture that
      // is wrong without looking wrong.
      expect(resolveDevice('iphone-99'), isNull);
      expect(unknownDeviceIn('iphone-99'), 'iphone-99');
    });

    test('and a good one is not', () {
      expect(unknownDeviceIn('ipad'), isNull);
      expect(unknownDeviceIn(fitDeviceId), isNull);
      expect(unknownDeviceIn(null), isNull);
    });
  });
}
