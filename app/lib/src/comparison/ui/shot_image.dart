import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../frame_ref.dart';
import '../shot_cache.dart';

/// One frame, decoded once and kept.
class Shot {
  const Shot(this.image);

  final ui.Image image;

  double get aspect => image.width / image.height;
}

/// Loads and holds the two frames a stage is showing.
///
/// **Raw rgba straight to a texture, never through a PNG.** Frames are stored
/// unencoded precisely because encoding is most of what a capture costs;
/// re-encoding here to hand `Image.memory` something it recognises would pay
/// that price back, per frame, on every click in a list.
///
/// One of these per stage, not per image: a stage shows two frames and wants
/// them together — a slider that arrives with only the head loaded shows a
/// comparison against nothing for one frame, which reads as a change.
class ShotPair extends ChangeNotifier implements SettleSource {
  ShotPair(this.cache);

  final ShotCache cache;

  Shot? base;
  Shot? head;

  /// What is currently loaded, so re-selecting the same row costs nothing.
  String? _baseId;
  String? _headId;

  var _disposed = false;
  var _pending = 0;

  /// True once a load has finished, whatever it found.
  ///
  /// **Distinct from having an image**, and the distinction is a message: a
  /// step that failed on both sides has no frames and never will, and a pane
  /// that said "Loading…" over it said so forever.
  var settled = false;

  bool get hasFrames => base != null || head != null;

  /// A capture must not photograph a stage mid-decode: the frames are the
  /// subject, and an empty stage looks exactly like a comparison of two blank
  /// screens.
  @override
  String? get busyWith => _pending > 0 ? 'loading frames' : null;

  /// Two frames the renderer filed, by `ShotCache` key.
  Future<void> load({String? baseKey, String? headKey}) => _replace(
    baseId: baseKey,
    headId: headKey,
    decode: () => Future.wait([_fromCache(baseKey), _fromCache(headKey)]),
  );

  /// Two frames the replay wrote, by path — see [FrameRef].
  Future<void> loadFrames({FrameRef? base, FrameRef? head}) => _replace(
    baseId: base?.path,
    headId: head?.path,
    decode: () => Future.wait([fromFile(base), fromFile(head)]),
  );

  Future<void> _replace({
    required String? baseId,
    required String? headId,
    required Future<List<Shot?>> Function() decode,
  }) async {
    if (settled && baseId == _baseId && headId == _headId) return;
    _baseId = baseId;
    _headId = headId;
    _pending++;
    var loaded = await decode();
    _pending--;
    if (_disposed || baseId != _baseId || headId != _headId) {
      // Superseded by a later selection. Disposed here rather than left to fall
      // out of scope: a `ui.Image` holds GPU memory a garbage collector is in
      // no hurry about, and a fast walk down a list of two hundred entries is
      // four hundred of them.
      for (var shot in loaded) {
        shot?.image.dispose();
      }
      return;
    }
    base?.image.dispose();
    head?.image.dispose();
    base = loaded[0];
    head = loaded[1];
    settled = true;
    notifyListeners();
  }

  Future<Shot?> _fromCache(String? key) async {
    if (key == null) return null;
    var bytes = cache.read(key);
    var record = cache.meta(key);
    if (bytes == null || record == null) return null;
    return decodeRaw(bytes, width: record.width, height: record.height);
  }

  /// One frame the replay wrote. Public because a thumbnail wants one on its
  /// own, without a pair around it.
  static Future<Shot?> fromFile(FrameRef? ref) async {
    if (ref == null || !ref.isDrawable) return null;
    var file = File(ref.path);
    if (!file.existsSync()) return null;
    return decodeRaw(
      file.readAsBytesSync(),
      width: ref.width,
      height: ref.height,
    );
  }

  /// rgba8888 rows into a texture.
  static Future<Shot?> decodeRaw(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    if (width <= 0 || height <= 0) return null;
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    var descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    var codec = await descriptor.instantiateCodec();
    var frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return Shot(frame.image);
  }

  @override
  void dispose() {
    _disposed = true;
    base?.image.dispose();
    head?.image.dispose();
    super.dispose();
  }
}

/// A decoded frame, drawn to fit.
class ShotView extends StatelessWidget {
  const ShotView(this.shot, {super.key, this.opacity = 1.0});

  final Shot shot;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    // Not `RawImage`'s own alignment: the stage lays the two frames on top of
    // each other and they have to land on the same rect even when their sizes
    // differ, which is exactly the case a size change produces.
    child: RawImage(
      image: shot.image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
  );
}
