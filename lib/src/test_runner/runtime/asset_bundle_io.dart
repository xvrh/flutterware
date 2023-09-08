import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../../../flutter_test.dart';
import 'asset_bundle.dart';
import 'setup.dart' show BundleParameters;

void mockFlutterAssets(AssetBundle delegate) {
  /// Navigation related actions (pop, push, replace) broadcasts these actions via
  /// platform messages.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation,
          (MethodCall methodCall) async {
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    assert(message != null);
    var key = utf8.decode(message!.buffer.asUint8List());
    return delegate.load(key);
  });
}

class IOAssetBundle extends CachingAssetBundle implements TestBundle {
  final String assetFolderPath;
  final BundleParameters bundleParams;

  IOAssetBundle(this.assetFolderPath, {required this.bundleParams}) {
    mockFlutterAssets(this);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    var packageName = bundleParams.projectPackageName;
    var data = await load(key);
    var string = utf8.decode(data.buffer.asUint8List());
    if (key == 'FontManifest.json' && packageName != null) {
      string = string.replaceAll('packages/$packageName/', '');
    }
    return string;
  }

  @override
  Future<ByteData> load(String key) async {
    var projectRoot = bundleParams.rootProjectPath;
    File asset;
    if (projectRoot != null && key.startsWith('assets/')) {
      asset = File(path.join(projectRoot, key));
    } else {
      asset = File(path.join(assetFolderPath, key));
    }

    var encoded = Uint8List.fromList(asset.readAsBytesSync());
    return Future.value(encoded.buffer.asByteData());
  }

  @override
  Future<void> waitFinishLoading() async {}

  @override
  Future<void> runWithNetworkOverride(Future<void> Function() callback) async {
    await callback();
  }
}
