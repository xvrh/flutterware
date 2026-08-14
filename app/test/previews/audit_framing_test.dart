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

/// What `audit` renders each entry as.
///
/// It rendered everything at 900 × 700 — one warm guest, started at the panel's
/// size and never resized — whatever the project had declared. That is the
/// audit that cannot find the bug it exists to find: a phone layout laid out in
/// a desktop rectangle does not overflow and does not wrap, so a catalog of
/// phone screens came back green. It is the worst place for that default to be
/// wrong, because an audit is the one surface that claims to have checked
/// *everything*.
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

  var core = coreWith({
    'canvases': [
      {
        'prefix': 'demo/mobile',
        'devices': ['iphone-16'],
      },
      {
        'prefix': 'demo/desktop',
        'devices': ['macbook-pro'],
      },
    ],
  });

  test('each entry is framed as its own subtree declared', () {
    var (phone, _, phoneViewport) = core.auditFramingFor(
      '.',
      'demo/mobile/tile.dart',
      const {},
    );
    var (desk, _, deskViewport) = core.auditFramingFor(
      '.',
      'demo/desktop/bar.dart',
      const {},
    );

    expect(phone, 'iphone-16');
    expect(desk, 'macbook-pro');
    // The two that used to be one number. A guest holding the second size
    // cannot report the first one's overflow.
    expect(phoneViewport, isNot(deskViewport));
    expect(phoneViewport, CaptureViewport.of(deviceById('iphone-16')!));
  });

  test('an entry under no canvas keeps the plain rectangle', () {
    // The whole of the old behaviour, still available and now the exception
    // rather than the rule.
    var (device, _, viewport) = core.auditFramingFor(
      '.',
      'demo/shared/spacer.dart',
      const {},
    );

    expect(device, isNull);
    expect(viewport, CaptureViewport.panel);
  });

  test('a named device sweeps the whole catalog instead', () {
    // How to ask whether everything survives a small phone, which is a question
    // about the run rather than about any entry.
    for (var path in ['demo/mobile/tile.dart', 'demo/desktop/bar.dart']) {
      var (device, _, viewport) = core.auditFramingFor('.', path, const {
        'device': 'iphone-se',
      });
      expect(device, 'iphone-se', reason: path);
      expect(viewport, CaptureViewport.of(deviceById('iphone-se')!));
    }
  });

  test('a device this build has no entry for is refused, not approximated', () {
    // Loudly, and before anything is compiled — `_audit` runs this check once
    // up front for that reason. Rendering the catalog at a guessed size and
    // reporting it green is the one outcome an audit must never produce.
    expect(
      () => core.auditFramingFor('.', 'demo/mobile/tile.dart', const {
        'device': 'iphone-99',
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('the viewport compares by value', () {
    // The gate on the resize: the warm guest is only re-sized where the answer
    // actually changed, so a run of entries sharing a canvas costs one message
    // rather than one per entry.
    test('two viewports of one device are the same viewport', () {
      var phone = deviceById('iphone-16')!;

      expect(CaptureViewport.of(phone), CaptureViewport.of(phone));
      expect(
        CaptureViewport.of(phone).hashCode,
        CaptureViewport.of(phone).hashCode,
      );
    });

    test('a different screen is a different viewport', () {
      expect(
        CaptureViewport.of(deviceById('iphone-16')!),
        isNot(CaptureViewport.of(deviceById('iphone-se')!)),
      );
      expect(
        CaptureViewport.of(deviceById('macbook-pro')!),
        isNot(CaptureViewport.panel),
      );
    });

    test('the ratio counts, not only the pixels', () {
      // Two buffers of one size at different ratios are different logical
      // screens — which is the whole reason the guest is told them apart.
      expect(
        const CaptureViewport(width: 800, height: 600),
        isNot(const CaptureViewport(width: 800, height: 600, pixelRatio: 2)),
      );
    });
  });
}
