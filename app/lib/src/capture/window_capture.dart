import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../embedder/embedded_engine.dart';

/// A picture of the window, guests included.
///
/// Two captures composited, because the guest is not in the host's layer
/// tree. A catalog panel shows its guest through `Texture(textureId:)`, an
/// external texture the platform compositor resolves at raster time;
/// `RenderRepaintBoundary.toImage` rasterizes a layer tree offscreen. Measured
/// on macOS: the texture's rect comes back fully transparent, every sample,
/// zero alpha. So the host raster has a hole in it, and the guest's own frame
/// goes into that hole.
///
/// See decision 5 of
/// `docs/superpowers/specs/2026-07-27-gui-cli-mcp-architecture.md`, which
/// records the measurement and why the OS-level alternative was rejected.
abstract final class WindowCapture {
  /// Rasterizes [boundary] at [pixelRatio] and composites every live guest
  /// under it into the hole it left.
  static Future<img.Image> capture(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
  }) async {
    var host = await _raster(boundary, pixelRatio);
    for (var texture in _texturesUnder(boundary)) {
      var engine = EmbeddedEngine.withTexture(texture.textureId);
      // A texture nobody claims is left as the hole it is. It is not this
      // function's business to decide that is wrong — a host with a texture
      // from somewhere else is a legitimate thing to photograph.
      if (engine == null) continue;
      await _compositeGuest(
        host,
        engine,
        _rectOf(texture, boundary, pixelRatio),
      );
    }
    return host;
  }

  static Future<img.Image> _raster(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    var image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: data!.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } finally {
      image.dispose();
    }
  }

  static Future<void> _compositeGuest(
    img.Image host,
    EmbeddedEngine engine,
    Rect rect,
  ) async {
    if (rect.isEmpty) return;
    var guest = await engine.captureImage();
    // **Resampled here rather than by the paste**, when the guest renders at
    // a size the panel does not. A device frame is exactly this: the guest's
    // window *is* the phone screen, at the phone's pixel ratio, and the panel
    // scales the result down. `compositeImage`'s own scaling is a nearest
    // sample, which turns 3x device pixels into aliased text.
    var width = rect.width.round();
    var height = rect.height.round();
    if (guest.width != width || guest.height != height) {
      guest = img.copyResize(
        guest,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );
    }
    img.compositeImage(
      host,
      guest,
      dstX: rect.left.round(),
      dstY: rect.top.round(),
    );
  }

  /// Every external texture painted under [boundary].
  ///
  /// Found by walking the render tree rather than by panels registering their
  /// widgets, so a guest is composited wherever it ended up and at whatever
  /// size it was painted — including scaled inside a device frame, which a
  /// registry keyed on the panel would have had to be told about.
  static Iterable<TextureBox> _texturesUnder(RenderObject root) sync* {
    var found = <TextureBox>[];
    void walk(RenderObject node) {
      if (node is TextureBox) found.add(node);
      node.visitChildren(walk);
    }

    walk(root);
    yield* found;
  }

  /// Where [texture] painted, in the pixel coordinates `toImage` produced.
  static Rect _rectOf(
    TextureBox texture,
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) {
    var transform = texture.getTransformTo(boundary);
    var local = MatrixUtils.transformRect(
      transform,
      Offset.zero & texture.size,
    );
    return Rect.fromLTRB(
      local.left * pixelRatio,
      local.top * pixelRatio,
      local.right * pixelRatio,
      local.bottom * pixelRatio,
    );
  }
}
