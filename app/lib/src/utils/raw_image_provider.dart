// From https://github.com/yrom/flutter_raw_image_provider/blob/master/lib/raw_image_provider.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Decodes the given [image] (raw image pixel data) as an image ('dart:ui')
class RawImageProvider extends ImageProvider<Object> {
  final RawImageData image;

  RawImageProvider(this.image);

  @override
  ImageStreamCompleter loadBuffer(Object key, DecoderBufferCallback decode) {
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
    var bytes = await image.file.readAsBytes();
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
  final String path;

  _RawImageKey(this.w, this.h, this.format, this.path);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is _RawImageKey &&
        other.w == w &&
        other.h == h &&
        other.format == format &&
        other.path == path;
  }

  @override
  int get hashCode {
    return Object.hash(w, h, format, path);
  }
}

/// Raw pixels data of an image
class RawImageData {
  final File file;
  final int width;
  final int height;
  final ui.PixelFormat pixelFormat;

  RawImageData(
    this.file,
    this.width,
    this.height, {
    this.pixelFormat = ui.PixelFormat.rgba8888,
  });

  _RawImageKey? _key;
  _RawImageKey _obtainKey() {
    return _key ??= _RawImageKey(width, height, pixelFormat.index, file.path);
  }
}
