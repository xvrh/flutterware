import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/previews_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// What a preview is framed as when nobody says.
///
/// The default was 900 × 700 — landscape, desktop-shaped — with no way through
/// it from the project. That is the bad kind of wrong: a phone screen laid out
/// in a 900-wide frame does not overflow and does not wrap, so the picture
/// looks fine and the bug you opened the preview to find is the one thing it
/// cannot show. Reported by a consumer whose catalog is 90 phone screens and
/// nothing else, who caught it because a human looked at the aspect ratio.
///
/// The precedence below is the whole of the fix, and it is the part worth
/// pinning: a project says what it is once, and every surface that renders
/// without being told agrees with it.
void main() {
  PreviewsCore coreWith(Map<String, Object?> package) => PreviewsCore(
    PluginHost(
      id: uiCatalogPluginId,
      label: 'Previews',
      worktree: const Worktree(path: '/project'),
      workspace: Workspace(
        root: '/project',
        declared: const [Pkg('.')],
        discovered: const ['.'],
        appContext: AppContext(logger: LogClient.print()),
        flutterSdk: FlutterSdkPath('/flutter'),
      ),
      config: {
        'packages': [
          {'path': '.', ...package},
        ],
      },
    ),
  );

  group('what the package declares', () {
    test('reaches the core as a device and an orientation', () {
      var core = coreWith({'device': 'ipad', 'orientation': 'landscape'});

      var framing = core.defaultFramingFor('.');
      expect(framing.device?.id, 'ipad');
      expect(framing.orientation, ScreenOrientation.landscape);
    });

    test('a package that declares nothing still answers', () {
      expect(coreWith(const {}).defaultFramingFor('.').device, isNull);
      expect(coreWith(const {}).defaultFramingFor('.').orientation, isNull);
    });

    test('a device this build never heard of is ignored, not thrown', () {
      // Read on the way to drawing something rather than while checking a
      // command line. A typo that blanked the panel would be a worse report
      // than one that renders the rectangle it always used to.
      expect(
        coreWith({'device': 'iphone-99'}).defaultFramingFor('.').device,
        isNull,
      );
    });
  });

  group('precedence', () {
    var phone = deviceById('iphone-16')!;
    var tablet = deviceById('ipad')!;

    test('an undeclared package still gets the plain rectangle', () {
      var (deviceId, orientationId, viewport) = PreviewsCore.framingFor(
        const {},
      );
      expect(deviceId, isNull);
      expect(orientationId, isNull);
      expect(viewport.width, CaptureViewport.panel.width);
    });

    test('the declaration frames a call that names no device', () {
      var (deviceId, _, viewport) = PreviewsCore.framingFor(
        const {},
        fallback: (device: phone, orientation: null),
      );
      expect(deviceId, 'iphone-16');
      // On the address as well as in the pixels: a picture framed as a phone
      // whose address says nothing is a picture nobody can ask for again.
      expect(viewport.width, CaptureViewport.of(phone).width);
    });

    test('a call that names a device wins', () {
      var (deviceId, _, viewport) = PreviewsCore.framingFor(
        const {'device': 'ipad'},
        fallback: (device: phone, orientation: null),
      );
      expect(deviceId, 'ipad');
      expect(viewport.width, CaptureViewport.of(tablet).width);
    });

    test('`fit` is an answer, not an absence', () {
      // The one that would break if the fallback were applied to anything
      // falsy: `fit` is how a single call asks for the plain rectangle back,
      // so the default it is countermanding must not win.
      var (deviceId, _, viewport) = PreviewsCore.framingFor(
        const {'device': fitDeviceId},
        fallback: (device: phone, orientation: null),
      );
      expect(deviceId, fitDeviceId);
      expect(viewport.width, CaptureViewport.panel.width);
    });

    test('a declared orientation turns the declared device', () {
      var (deviceId, orientationId, viewport) = PreviewsCore.framingFor(
        const {},
        fallback: (device: tablet, orientation: ScreenOrientation.landscape),
      );
      expect(deviceId, 'ipad');
      expect(orientationId, 'landscape');
      expect(
        viewport.width,
        greaterThan(viewport.height),
        reason: 'the declared landscape never reached the viewport',
      );
    });

    test('it does not turn a device the call picked instead', () {
      // An orientation belongs to the device it was declared for. Inheriting
      // the tablet's landscape onto a phone somebody just asked for would be a
      // picture nobody chose.
      var (_, orientationId, viewport) = PreviewsCore.framingFor(
        const {'device': 'iphone-16'},
        fallback: (device: tablet, orientation: ScreenOrientation.landscape),
      );
      expect(orientationId, isNull);
      expect(viewport.height, greaterThan(viewport.width));
    });

    test('width and height still override the declaration', () {
      var (deviceId, _, viewport) = PreviewsCore.framingFor(
        const {'width': 400, 'height': 800},
        fallback: (device: phone, orientation: null),
      );
      expect(deviceId, 'iphone-16', reason: 'the device is still on record');
      expect(viewport.width, 400);
      expect(viewport.height, 800);
    });
  });
}
