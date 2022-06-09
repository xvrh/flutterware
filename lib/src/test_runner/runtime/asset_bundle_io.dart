import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'asset_bundle.dart';
import 'setup.dart' show BundleParameters;

class IOAssetBundle extends CachingAssetBundle implements ScenarioBundle {
  final String assetFolderPath;
  final BundleParameters bundleParams;

  IOAssetBundle(this.assetFolderPath, {required this.bundleParams});

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