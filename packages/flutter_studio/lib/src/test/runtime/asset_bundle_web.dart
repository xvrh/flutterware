import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'asset_bundle.dart';
import 'setup.dart' show BundleParameters;

const _assetManifestKey = 'AssetManifest.json';

class WebAssetBundle extends CachingAssetBundle implements ScenarioBundle {
  final BundleParameters bundleParams;
  final ByteData assetManifest;
  final Zone realAsyncZone;

  WebAssetBundle._(this.bundleParams, this.assetManifest, this.realAsyncZone);

  static Future<WebAssetBundle> create(BundleParameters bundleParams) async {
    final realAsyncZone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask:
            (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
          Zone.root.scheduleMicrotask(f);
        },
        createTimer: (Zone self, ZoneDelegate parent, Zone zone,
            Duration duration, void Function() f) {
          return Zone.root.createTimer(duration, f);
        },
        createPeriodicTimer: (Zone self, ZoneDelegate parent, Zone zone,
            Duration period, void Function(Timer timer) f) {
          return Zone.root.createPeriodicTimer(period, f);
        },
      ),
    );

    var manifestData = await rootBundle.load(_assetManifestKey);
    var webBundle = WebAssetBundle._(bundleParams, manifestData, realAsyncZone);

    var manifestMap = jsonDecode(utf8.decode(manifestData.buffer.asUint8List()))
        as Map<String, dynamic>;
    var loadFutures = <Future>[];
    for (var entry in manifestMap.entries) {
      var key = entry.key;
      if (bundleParams.translationPredicate(key)) {
        loadFutures.add(webBundle.load(key));
      }
    }
    await Future.wait(loadFutures);

    return webBundle;
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    var packageName = bundleParams.projectPackageName;
    final data = await load(key);
    var string = utf8.decode(data.buffer.asUint8List());
    if (key == 'FontManifest.json' && packageName != null) {
      string = string.replaceAll('packages/$packageName/', '');
    }
    return string;
  }

  final cache = <String, Future<ByteData>>{};
  int _inflightRequests = 0;

  @override
  Future<ByteData> load(String key) async {
    return cache[key] ??= _load(key);
  }

  Future<ByteData> _load(String key) {
    if (key == _assetManifestKey) {
      return Future.value(assetManifest);
    }

    ++_inflightRequests;
    return realAsyncZone.run<Future<ByteData>>(() async {
      try {
        return await rootBundle.load(key);
      } finally {
        --_inflightRequests;
      }
    });
  }

  @override
  Future<void> waitFinishLoading() async {
    // We had some issues with the Zone being blocked here. So we use a workaround
    // to poll each few milliseconds instead of awaiting for the Futures
    var completer = Completer();

    Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (_inflightRequests <= 0) {
        timer.cancel();
        completer.complete();
      }
    });

    return completer.future;
  }

  @override
  Future<void> runWithNetworkOverride(Future<void> Function() callback) async {
    await callback();
  }
}
