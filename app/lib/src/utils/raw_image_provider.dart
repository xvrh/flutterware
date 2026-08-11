// From https://github.com/yrom/flutter_raw_image_provider/blob/master/lib/raw_image_provider.dart

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Decodes the given [image] (raw image pixel data) as an image ('dart:ui')
class RawImageProvider extends ImageProvider<Object> {
  final RawImageData image;

  RawImageProvider(this.image);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: 1.0,
      debugLabel: 'RawImageProvider(${describeIdentity(key)})',
    );
  }

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(image._obtainKey());
  }

  /// see [ui.decodeImageFromPixels]
  Future<ui.Codec> _loadAsync(Object key) async {
    assert(key == image._obtainKey());
    var bytes = await image.load();
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: image.pixelFormat,
    );
    return descriptor.instantiateCodec();
  }
}

class _RawImageKey {
  final int w;
  final int h;
  final int format;
  final String id;

  _RawImageKey(this.w, this.h, this.format, this.id);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is _RawImageKey &&
        other.w == w &&
        other.h == h &&
        other.format == format &&
        other.id == id;
  }

  @override
  int get hashCode {
    return Object.hash(w, h, format, id);
  }
}

/// Raw pixels data of an image.
///
/// Takes a loader and an [id] to cache by rather than a `File`: the same
/// provider serves the panel, which reads the bytes off disk, and the exported
/// scenario page, which fetches them over HTTP with no filesystem in reach.
class RawImageData {
  final String id;
  final Future<Uint8List> Function() load;
  final int width;
  final int height;
  final ui.PixelFormat pixelFormat;

  RawImageData(
    this.id,
    this.load,
    this.width,
    this.height, {
    this.pixelFormat = ui.PixelFormat.rgba8888,
  });

  _RawImageKey? _key;
  _RawImageKey _obtainKey() {
    return _key ??= _RawImageKey(width, height, pixelFormat.index, id);
  }
}
