import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'model/icons.dart';

class AppIconImageProvider extends ImageProvider<Object> {
  final AppIcon image;

  AppIconImageProvider(this.image);

  @override
  ImageStreamCompleter load(Object key, DecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: 1.0,
      debugLabel: 'AppIconImageProvider(${describeIdentity(key)})',
    );
  }

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(image);
  }

  Future<ui.Codec> _loadAsync(Object key) async {
    var buffer = await ui.ImmutableBuffer.fromUint8List(
        image.preview.buffer.asUint8List());
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.previewWidth,
      height: image.previewHeight,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    return descriptor.instantiateCodec();
  }
}
