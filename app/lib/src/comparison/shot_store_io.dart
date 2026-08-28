import 'package:flutterware/comparison_report.dart';

import 'dart:io';

import 'shot_cache.dart';
import 'shot_store.dart';

/// The panel's store: keys open the machine's shot cache, refs open the files
/// a replay wrote.
class CacheShotStore implements ShotStore {
  const CacheShotStore(this.cache);

  final ShotCache cache;

  @override
  Future<Shot?> byKey(String key) async {
    var bytes = cache.read(key);
    var record = cache.meta(key);
    if (bytes == null || record == null) return null;
    return decodeRawShot(bytes, width: record.width, height: record.height);
  }

  @override
  Future<Shot?> byRef(FrameRef ref) async {
    if (!ref.isDrawable) return null;
    var file = File(ref.path);
    if (!file.existsSync()) return null;
    return decodeRawShot(
      file.readAsBytesSync(),
      width: ref.width,
      height: ref.height,
    );
  }
}
