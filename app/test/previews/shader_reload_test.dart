import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/previews/shader_reload.dart';

/// [reloadGuestAssets] itself, off a recording fake in place of a live
/// guest's VM service — [CatalogSession._onAssetsChanged] is private, and the
/// only other coverage of this sequence is `asset_refresh_test.dart`, which
/// drives a real guest and cannot arrange for one call to fail.
void main() {
  test(
    'reinitializes every shader before evicting, then reassembles',
    () async {
      var calls = <(String, Map<String, String>?)>[];
      await reloadGuestAssets(
        AssetsChanged(fontsChanged: false, shaders: ['a.frag', 'b.frag']),
        (method, [args]) async => calls.add((method, args)),
      );
      expect(calls.map((c) => c.$1), [
        'ext.ui.window.reinitializeShader',
        'ext.ui.window.reinitializeShader',
        'ext.flutter.evict',
        'ext.flutter.reassemble',
      ]);
      expect(calls[0].$2, {'assetKey': 'a.frag'});
      expect(calls[1].$2, {'assetKey': 'b.frag'});
      expect(calls[2].$2, {'value': 'AssetManifest.bin'});
      expect(calls[3].$2, isNull);
    },
  );

  test('a key the guest rejects is reported, and the evict and the reassemble '
      'still happen', () async {
    var calls = <String>[];
    var errors = <(String, Object)>[];
    await reloadGuestAssets(
      AssetsChanged(
        fontsChanged: false,
        shaders: ['a.frag', 'bad.frag', 'c.frag'],
      ),
      (method, [args]) async {
        calls.add(args == null ? method : '$method ${args.values.first}');
        if (args?['assetKey'] == 'bad.frag') {
          throw StateError('the engine could not parse it');
        }
      },
      onShaderError: (key, e) => errors.add((key, e)),
    );
    expect(errors, hasLength(1));
    expect(errors.single.$1, 'bad.frag');
    expect(errors.single.$2, isA<StateError>());
    expect(calls, [
      'ext.ui.window.reinitializeShader a.frag',
      'ext.ui.window.reinitializeShader bad.frag',
      'ext.ui.window.reinitializeShader c.frag',
      'ext.flutter.evict AssetManifest.bin',
      'ext.flutter.reassemble',
    ], reason: 'the failing key did not stop the keys or the tail after it');
  });

  test(
    'a key with a space is sent the way FragmentProgram.fromAsset stores it',
    () async {
      var sentKeys = <String>[];
      await reloadGuestAssets(
        AssetsChanged(
          fontsChanged: false,
          shaders: ['shaders/my glow.frag', 'shaders/plain.frag'],
        ),
        (method, [args]) async {
          if (method == 'ext.ui.window.reinitializeShader') {
            sentKeys.add(args!['assetKey']!);
          }
        },
      );
      expect(sentKeys, ['shaders/my%20glow.frag', 'shaders/plain.frag']);
    },
  );
}
