import 'dart:math' as math;

import '../previews/stage_zoom.dart' show zoomPixelBudget;

/// The pixel ratio to render an artboard at when the canvas draws it [zoom]
/// times life-size on a screen of [hostRatio].
///
/// The texture is drawn into `logical × zoom × hostRatio` physical pixels, so
/// that is the ratio that puts one texel on one pixel. Snapped so the texture's
/// width is a whole number of texels: a ratio a fraction off walks the
/// sampling phase across the picture and bands it sharp and soft, which reads
/// worse than a plainly wrong one. Below life-size the guest keeps the host's
/// ratio — minifying a texture is cheap and looks fine. Capped by the previews
/// stage's pixel budget rather than refused: past it the picture goes
/// gradually soft.
double sceneGuestRatio({
  required double width,
  required double height,
  required double hostRatio,
  required double zoom,
}) {
  var wanted = hostRatio * math.max(1.0, zoom);
  var area = width * height;
  if (area > 0) {
    var ceiling = math.sqrt(zoomPixelBudget / area);
    wanted = math.min(wanted, math.max(hostRatio, ceiling));
  }
  if (width <= 0) return wanted;
  return (width * wanted).round() / width;
}
