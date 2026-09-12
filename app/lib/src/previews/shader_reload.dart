import 'protocol.dart';

/// What a live guest is told when the bundle under it moved: each recompiled
/// shader reloaded, then the manifest evicted and the app reassembled.
///
/// [call] is one service-extension round trip — the guest channel's
/// `callExtension`, in `CatalogSession._onAssetsChanged` — so a caller can
/// pass a recording fake instead of a live guest. Pure Dart on purpose and its own small file for
/// it: `asset_refresh_test.dart` drives this same sequence against a real
/// guest under plain `dart test`, which cannot compile a `dart:ui` import,
/// and `catalog_session.dart` pulls in all of Flutter.
///
/// One shader key that [call] rejects is reported through [onShaderError]
/// rather than thrown: the remaining keys, the evict and the reassemble still
/// run, because a manifest that has moved and a program that could not be
/// reread are unrelated facts.
Future<void> reloadGuestAssets(
  AssetsChanged change,
  Future<void> Function(String method, [Map<String, String>? args]) call, {
  void Function(String key, Object error)? onShaderError,
}) async {
  // A program is cached by key for the life of the isolate, so new bytes on
  // disk are invisible until the engine is told to read them again — what
  // `flutter run`'s `r` does for a `shaders:` entry. It swaps the program
  // under every live FragmentShader and zeroes their uniforms; the
  // reassemble below is what makes a painter set them again.
  for (var key in change.shaders) {
    try {
      await call('ext.ui.window.reinitializeShader', {
        // Encoded the way `FragmentProgram.fromAsset` files the program,
        // since the engine looks the key up exactly as given.
        'assetKey': Uri(path: Uri.encodeFull(key)).path,
      });
    } catch (e) {
      onShaderError?.call(key, e);
    }
  }
  await call('ext.flutter.evict', {'value': 'AssetManifest.bin'});
  await call('ext.flutter.reassemble');
}
