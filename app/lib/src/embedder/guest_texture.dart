import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:flutterware/src/offscreen_raster.dart';

/// The guest's picture — a [Texture], except while the app is being rasterised
/// into an image.
///
/// **Every `Texture` in this application goes through here**, because the one
/// that does not is the one that takes the studio down. `OffscreenRaster` has
/// the whole of why; the short version is that `toImage` cannot draw an
/// external texture on any host, returns a transparent hole for it on macOS,
/// and segfaults the process on Linux. So for the frame a raster photographs,
/// there is no texture in the layer tree to segfault on.
///
/// The hole is not a loss. A picture of a panel *and* its guest has always been
/// two captures composited — see `WindowCapture` — because the guest is not in
/// the host's layer tree to begin with.
///
/// Temporary, and tied to an engine bug rather than to a design: when the
/// engine stops needing it, this becomes `Texture(textureId:)` again at every
/// call site and the file goes.
class GuestTexture extends StatelessWidget {
  const GuestTexture({super.key, required this.textureId});

  final int textureId;

  @override
  Widget build(BuildContext context) =>
      _WithheldWhileRastering(child: Texture(textureId: textureId));
}

/// Keeps [child] laid out and out of the layer tree while a raster is up.
///
/// **A render object rather than a builder, and that is the whole design.**
/// Withholding the *widget* — swapping it for a placeholder — costs a black
/// frame on the way back, which is visible on every click a human makes in a
/// live preview: a rebuilt `Texture` is a new `TextureBox` with a new layer,
/// and the compositor resolves a freshly registered external texture to black
/// for one frame before it has the guest's pixels. Measured on Linux; the
/// frame that goes *away* is not the problem, because the stage's own ground
/// is painted behind the guest and reads as an ordinary empty panel.
///
/// So nothing here is destroyed. The `TextureBox` is built once and lives as
/// long as the panel does; the notice only decides whether it is painted, and
/// only a repaint is invalidated for it — no rebuild, no relayout, and the
/// same texture on the other side.
///
/// It stays in the render tree too, which is what `WindowCapture` walks to
/// find where each guest was drawn.
class _WithheldWhileRastering extends SingleChildRenderObjectWidget {
  const _WithheldWhileRastering({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWithheld();
}

class _RenderWithheld extends RenderProxyBox {
  _RenderWithheld() {
    OffscreenRaster.notice.addListener(markNeedsPaint);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (OffscreenRaster.notice.value) return;
    super.paint(context, offset);
  }

  @override
  void dispose() {
    OffscreenRaster.notice.removeListener(markNeedsPaint);
    super.dispose();
  }
}
