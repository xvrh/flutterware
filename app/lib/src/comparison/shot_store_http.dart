import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'frame_ref.dart';
import 'shot_store.dart';

/// The exported page's store: every name in its `index.json` is a relative
/// path the export wrote, resolved against the page's own URL — so a page
/// moved to another host or mounted under a subdirectory still finds its own
/// frames.
class HttpShotStore implements ShotStore {
  const HttpShotStore(this.base);

  final Uri base;

  Future<Uint8List?> _fetch(String path) async {
    try {
      var response = await http.get(base.resolve(path));
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Shot?> byKey(String key) async {
    var bytes = await _fetch(key);
    return bytes == null ? null : decodeEncodedShot(bytes);
  }

  @override
  Future<Shot?> byRef(FrameRef ref) async {
    var bytes = await _fetch(ref.path);
    if (bytes == null) return null;
    // The export encodes every frame; raw survives only in a report that was
    // never exported, where the ref's own dimensions make it decodable.
    return ref.path.endsWith('.png')
        ? decodeEncodedShot(bytes)
        : decodeRawShot(bytes, width: ref.width, height: ref.height);
  }
}
