/// What a file says about itself, as opposed to what a pubspec says about it.
///
/// All of it **without Flutter**, which is the point: `fw describe` and an agent
/// get the same dimensions and the same animation facts the panel shows, rather
/// than a byte count and an apology. The two readers here are the whole reason
/// that is possible — a raster's size is in its header and a Lottie is a JSON
/// document.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'asset_scan.dart';

/// A raster's dimensions, read from the header.
class RasterFacts {
  RasterFacts({
    required this.width,
    required this.height,
    required this.frames,
  });

  final int width;
  final int height;

  /// More than one for an animated GIF or WebP.
  final int frames;
}

/// Reads [bytes]' header only — `startDecode` parses the metadata and leaves
/// the pixels alone, which is what makes this cheap enough to run over a whole
/// bundle.
RasterFacts? readRaster(Uint8List bytes) {
  try {
    var decoder = img.findDecoderForData(bytes);
    var info = decoder?.startDecode(bytes);
    if (info == null) return null;
    return RasterFacts(
      width: info.width,
      height: info.height,
      frames: info.numFrames,
    );
  } catch (_) {
    // A truncated or lying file has no dimensions to report. Its size in bytes
    // and its failure to decode are both still worth saying, and both are said
    // elsewhere.
    return null;
  }
}

/// One layer of an animation, as far as a list needs it.
class AnimationLayer {
  AnimationLayer({required this.name, required this.type});

  final String name;

  /// The kind After Effects exported — `shape`, `text`, `image`…
  final String type;
}

/// A Lottie animation's facts, read as JSON.
///
/// No `lottie` package involved. Duration, frame rate, size and the layer list
/// are top-level fields of the document, so the only surface that needs the
/// renderer is the one drawing pixels — which means the CLI and an agent get
/// the interesting half for free.
class AnimationFacts {
  AnimationFacts({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.inPoint,
    required this.outPoint,
    required this.layers,
    required this.markers,
    required this.version,
  });

  final int width;
  final int height;
  final double frameRate;

  /// First and last frame the animation is defined over. Rarely 0 and rarely
  /// the whole file: an exporter trims.
  final double inPoint;
  final double outPoint;

  final List<AnimationLayer> layers;

  /// Named points an exporter left behind — what a caller would seek to.
  final List<String> markers;

  /// The Bodymovin schema version the file was written against.
  final String? version;

  int get frames => (outPoint - inPoint).round();

  Duration get duration => frameRate <= 0
      ? Duration.zero
      : Duration(
          milliseconds: (((outPoint - inPoint) / frameRate) * 1000).round(),
        );
}

/// Reads [source] as a Lottie document, or null when it is not one.
///
/// Null is the ordinary answer, not an error: most `.json` in a bundle is
/// configuration. The test is structural — the fields an animation cannot be
/// missing — rather than a schema check, because a document that has them is
/// one the renderer will accept and one this can describe.
AnimationFacts? readLottie(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;

  var width = decoded['w'];
  var height = decoded['h'];
  var frameRate = decoded['fr'];
  var layers = decoded['layers'];
  if (width is! num || height is! num || frameRate is! num || layers is! List) {
    return null;
  }

  return AnimationFacts(
    width: width.toInt(),
    height: height.toInt(),
    frameRate: frameRate.toDouble(),
    inPoint: (decoded['ip'] as num?)?.toDouble() ?? 0,
    outPoint: (decoded['op'] as num?)?.toDouble() ?? 0,
    version: decoded['v'] as String?,
    layers: [
      for (var layer in layers)
        if (layer is Map<String, Object?>)
          AnimationLayer(
            name: layer['nm'] as String? ?? 'unnamed',
            type: _layerType(layer['ty']),
          ),
    ],
    markers: [
      for (var marker in (decoded['markers'] as List? ?? const []))
        if (marker is Map<String, Object?> && marker['cm'] is String)
          marker['cm']! as String,
    ],
  );
}

/// Bodymovin's numeric layer types, named. An unknown number is reported as
/// itself rather than guessed at.
String _layerType(Object? type) => switch (type) {
  0 => 'precomp',
  1 => 'solid',
  2 => 'image',
  3 => 'null',
  4 => 'shape',
  5 => 'text',
  6 => 'audio',
  _ => 'type $type',
};

/// The Dart that loads this asset.
///
/// The single most useful line `describe` produces. A model writing
/// `Image.asset('assets/logo.png')` is guessing at a string it has no other way
/// to learn, and the guess is wrong often enough to matter — a `packages/`
/// prefix omitted, a directory remembered wrong.
///
/// Names the package that would have to be depended on where it is not the
/// framework's, since the snippet is useless without it.
String snippetFor(String key, {String? fontFamily}) {
  if (fontFamily != null) {
    return "TextStyle(fontFamily: '$fontFamily')";
  }
  return switch (assetKindOf(key)) {
    AssetKind.image => "Image.asset('$key')",
    AssetKind.vector => "SvgPicture.asset('$key')  // package:flutter_svg",
    AssetKind.data when p.extension(key).toLowerCase() == '.json' =>
      "Lottie.asset('$key')  // package:lottie, if it is an animation",
    _ => "rootBundle.load('$key')",
  };
}
