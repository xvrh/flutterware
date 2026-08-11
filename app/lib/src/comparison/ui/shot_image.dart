import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../capture/settle.dart';
import '../shot_cache.dart';

/// One frame out of the shot cache, decoded once and kept.
class Shot {
  const Shot(this.image, this.record);

  final ui.Image image;
  final ShotRecord record;

  double get aspect => image.width / image.height;
}

/// Loads and holds the decoded frames a stage is showing.
///
/// **Raw rgba straight to a texture, never through a PNG.** The cache stores
/// frames unencoded precisely because encoding is most of what a capture costs;
/// re-encoding here to hand `Image.memory` something it recognises would pay
/// that price back, per frame, on every click in the list.
///
/// One of these per detail pane, not per image: a stage shows two frames and
/// wants them together — a slider that arrives with only the head loaded shows
/// a comparison against nothing for one frame, which reads as a change.
class ShotPair extends ChangeNotifier implements SettleSource {
  ShotPair(this.cache);

  final ShotCache cache;

  Shot? base;
  Shot? head;

  /// The keys currently loaded, so re-selecting the same row costs nothing.
  String? _baseKey;
  String? _headKey;

  var _disposed = false;
  var _pending = 0;

  /// True once a load has finished, whatever it found.
  ///
  /// **Distinct from having an image**, and the distinction is a message: an
  /// entry that failed on both sides has no frames and never will, and a pane
  /// that said "Loading…" over it said so forever.
  var settled = false;

  bool get hasFrames => base != null || head != null;

  /// A capture must not photograph a stage mid-decode: the frames are the
  /// subject, and an empty stage looks exactly like a comparison of two blank
  /// screens.
  @override
  String? get busyWith => _pending > 0 ? 'loading frames' : null;

  Future<void> load({String? baseKey, String? headKey}) async {
    if (settled && baseKey == _baseKey && headKey == _headKey) return;
    _baseKey = baseKey;
    _headKey = headKey;
    _pending++;
    var loaded = await Future.wait([_decode(baseKey), _decode(headKey)]);
    _pending--;
    if (_disposed || baseKey != _baseKey || headKey != _headKey) {
      // Superseded by a later selection. Disposing here rather than letting it
      // fall out of scope: a `ui.Image` holds GPU memory that a garbage
      // collector is in no hurry about, and a fast walk down a list of two
      // hundred entries is four hundred of them.
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

  Future<Shot?> _decode(String? key) async {
    if (key == null) return null;
    var bytes = cache.read(key);
    var record = cache.meta(key);
    if (bytes == null || record == null) return null;
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    var descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: record.width,
      height: record.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    var codec = await descriptor.instantiateCodec();
    var frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return Shot(frame.image, record);
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
    // Not `RawImage`'s own fit: the stage lays the two frames on top of each
    // other and they have to land on the same rect even when their sizes
    // differ, which is exactly the case a size change produces.
    child: RawImage(
      image: shot.image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
  );
}
