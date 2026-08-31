import 'dart:convert';
import 'dart:io';

import 'package:flutterware_render/client.dart';
import 'package:path/path.dart' as p;

import '../embedder/flutter_cache.dart';
import 'bundle_builder.dart';

/// One render, as a command: build (or refresh) a host-platform bundle under
/// `build/flutterware/`, spawn one guest, render one point, write one file.
///
/// The CLI form of what a server does with a resident [RenderPool] — same
/// bundle, same wire, no residency.
Future<({String outputPath, List<RenderWarning> warnings})> renderOneShot({
  required String packageRoot,
  required String target,
  required String point,
  required String format,
  Map<String, Object?> args = const {},
  RenderSize? size,
  RenderOptions options = const RenderOptions(),
  double pixelRatio = 3,
  String? output,
  required FlutterCache cache,
  void Function(String line)? log,
}) async {
  var bundleDir = p.join(
    packageRoot,
    'build',
    'flutterware',
    'render_bundle',
    'bundle',
  );
  await buildRenderBundle(
    packageRoot: packageRoot,
    target: target,
    output: bundleDir,
    cache: cache,
    log: log,
  );
  var pool = await RenderPool.start(bundle: bundleDir, onGuestLog: log);
  try {
    var info = pool.points.where((info) => info.name == point).firstOrNull;
    if (info == null) {
      throw StateError(
        'no render point named "$point"; $target declares: '
        '${pool.points.map((info) => info.name).join(', ')}',
      );
    }

    String text;
    List<int> bytes;
    List<RenderWarning> warnings;
    if (info.kind == RenderPointKind.document) {
      if (format != 'pdf') {
        throw StateError(
          '"$point" is a document render, which only produces pdf',
        );
      }
      var result = await pool.pdf(_document(point), args, options: options);
      text = '';
      bytes = result.bytes;
      warnings = result.warnings;
    } else {
      if (size == null) {
        throw StateError(
          'a widget render needs a size: `--size=<width>x<height>`',
        );
      }
      switch (format) {
        case 'svg':
          var result = await pool.svg(
            _widget(point),
            args,
            size: size,
            options: options,
          );
          text = result.text;
          bytes = const [];
          warnings = result.warnings;
        case 'png':
          var result = await pool.png(
            _widget(point),
            args,
            size: size,
            pixelRatio: pixelRatio,
          );
          text = '';
          bytes = result.bytes;
          warnings = result.warnings;
        case 'pdf':
          var result = await pool.pdfPage(
            _widget(point),
            args,
            size: size,
            options: options,
          );
          text = '';
          bytes = result.bytes;
          warnings = result.warnings;
        default:
          throw StateError('--as takes svg, png or pdf, not "$format"');
      }
    }

    var outputPath = p.absolute(output ?? '${point.split('/').last}.$format');
    Directory(p.dirname(outputPath)).createSync(recursive: true);
    if (format == 'svg') {
      File(outputPath).writeAsStringSync(text);
    } else {
      File(outputPath).writeAsBytesSync(bytes);
    }
    return (outputPath: outputPath, warnings: warnings);
  } finally {
    await pool.close();
  }
}

/// The CLI has no contract package to import, so it speaks raw-map args:
/// the codecs are identity and the guest's own decoder does the typing.
WidgetRender<Map<String, Object?>> _widget(String name) =>
    WidgetRender(name, encodeArgs: (args) => args, decodeArgs: (json) => json);

DocumentRender<Map<String, Object?>> _document(String name) => DocumentRender(
  name,
  encodeArgs: (args) => args,
  decodeArgs: (json) => json,
);

/// Parses `--args=` input: a JSON object, or `@file.json`.
Map<String, Object?> parseRenderArgs(String value) {
  var source = value.startsWith('@')
      ? File(value.substring(1)).readAsStringSync()
      : value;
  var decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw StateError('--args takes a JSON object, got: $source');
  }
  return decoded.cast<String, Object?>();
}
