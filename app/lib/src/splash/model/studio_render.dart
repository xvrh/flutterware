/// Turning a source image and a crop into the PNG the generator wants.
///
/// The only half of the studio that pushes pixels. `studio.dart` decides the
/// canvas and where the source sits on it, which is the part `fw` and the crop
/// surface both need; this composites it, which only the moment of export
/// needs.
///
/// No Flutter. `package:image` is what `flutter_native_splash` itself decodes
/// with, so a file this writes is one the generator can certainly read.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'studio.dart';

/// A source image measured, without decoding the pixels.
///
/// Enough to compute a canvas and a fit from, which is what a caller wants
/// before it has decided to export anything.
class SplashSourceFacts {
  const SplashSourceFacts({required this.width, required this.height});

  final int width;
  final int height;
}

/// Measures [bytes], or null when nothing can decode them.
SplashSourceFacts? measureSplashSource(Uint8List bytes) {
  try {
    var decoder = img.findDecoderForData(bytes);
    var info = decoder?.startDecode(bytes);
    if (info == null) return null;
    return SplashSourceFacts(width: info.width, height: info.height);
  } catch (_) {
    return null;
  }
}

/// Composites [source] onto [canvas] at [crop] and encodes a PNG.
///
/// **Transparent by default, and that matters.** Every one of these files is
/// drawn over something the config already decides — the window background, the
/// splash colour — so baking a background in would produce a logo sitting on a
/// white rectangle the moment somebody sets `color_dark`. [background] exists
/// for the one case that wants it: a source with transparency being exported
/// for a target that will be photographed rather than composited.
///
/// Runs on the calling isolate. [renderSplashPngInIsolate] is the one a GUI
/// should call — a 1152² composite plus a PNG encode is not a frame's worth of
/// work.
Uint8List renderSplashPng({
  required Uint8List sourceBytes,
  required SplashStudioCanvas canvas,
  required SplashCrop crop,
  int? background,
}) {
  // `decodeImage` does not merely return null on rubbish. It walks its decoders
  // asking each whether the bytes are its format, and the PSD probe reads a
  // 32-bit header field without checking the buffer is that long — so three
  // stray bytes come out as `RangeError (length): Not in inclusive range 0..2`,
  // which is what a user picking a corrupt file would otherwise be shown.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(sourceBytes);
  } catch (e) {
    throw FormatException('Could not decode that image: $e');
  }
  if (decoded == null) {
    throw const FormatException('Could not decode that image.');
  }
  var source = decoded.convert(numChannels: 4);

  var output = img.Image(
    width: canvas.width,
    height: canvas.height,
    numChannels: 4,
  );
  if (background != null) {
    img.fill(
      output,
      color: img.ColorRgba8(
        (background >> 16) & 0xFF,
        (background >> 8) & 0xFF,
        background & 0xFF,
        (background >> 24) & 0xFF,
      ),
    );
  }

  var drawnWidth = (source.width * crop.scale).round();
  var drawnHeight = (source.height * crop.scale).round();
  if (drawnWidth < 1 || drawnHeight < 1) {
    throw const FormatException('That scale leaves nothing to draw.');
  }

  var scaled = img.copyResize(
    source,
    width: drawnWidth,
    height: drawnHeight,
    // Downscaling a 4× export is the ordinary case and `average` is visibly
    // better at it; `linear` only wins going the other way.
    interpolation: source.width >= drawnWidth
        ? img.Interpolation.average
        : img.Interpolation.linear,
  );

  img.compositeImage(
    output,
    scaled,
    dstX: ((canvas.width - drawnWidth) / 2 + crop.offsetX).round(),
    dstY: ((canvas.height - drawnHeight) / 2 + crop.offsetY).round(),
  );

  return img.encodePng(output);
}

/// [renderSplashPng] on another isolate.
Future<Uint8List> renderSplashPngInIsolate({
  required Uint8List sourceBytes,
  required SplashStudioCanvas canvas,
  required SplashCrop crop,
  int? background,
}) {
  // Hoisted so the closure sends these rather than `this` or a whole core.
  var width = canvas.width;
  var height = canvas.height;
  var target = canvas.target;
  var usableWidth = canvas.usableWidth;
  var usableHeight = canvas.usableHeight;
  var circular = canvas.circularMask;
  var scale = crop.scale;
  var offsetX = crop.offsetX;
  var offsetY = crop.offsetY;

  return Isolate.run(
    () => renderSplashPng(
      sourceBytes: sourceBytes,
      canvas: SplashStudioCanvas(
        target: target,
        width: width,
        height: height,
        usableWidth: usableWidth,
        usableHeight: usableHeight,
        circularMask: circular,
        explanation: '',
      ),
      crop: SplashCrop(scale: scale, offsetX: offsetX, offsetY: offsetY),
      background: background,
    ),
  );
}
