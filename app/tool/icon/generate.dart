/// Regenerates every launcher icon of the desktop app from the SVG sources
/// sitting next to this file.
///
/// Run it from the app package:
///
/// ```sh
/// cd app && ../fw dart run tool/icon/generate.dart
/// ```
///
/// **Why this exists rather than `flutter_launcher_icons`.** That package
/// derives every size by downscaling one source image, and this mark does not
/// survive it: below ~48px the word closes up into a smudge. So there are two
/// drawings — [_master] for 64px and up, [_small] (heavier type, thinner
/// margin, no shadow) for 48px and down — and something has to choose between
/// them per size. That choice is the only real work here; the rest is
/// bookkeeping.
///
/// The sources carry no font dependency: the type is outlined, so they render
/// the same on a machine without Futura installed.
///
/// Rasterizing needs one of `rsvg-convert`, `inkscape` or `resvg` on PATH.
/// Nothing in CI runs this — the generated files are committed — so an
/// unsatisfied checkout only means you cannot *re*generate until you install
/// one.
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Art for 64px and up: the full squircle inset, with its drop shadow.
const _master = 'fw_icon.svg';

/// Art for 48px and down. Larger type and a thinner tile margin buy back the
/// pixels the shadow and the inset were spending.
const _small = 'fw_icon_small.svg';

/// Full-bleed, unrounded, art inside the 80% safe circle — what Android and
/// the PWA spec mean by `purpose: maskable`.
const _maskable = 'fw_icon_maskable.svg';

/// The largest size the small drawing is used at.
///
/// Read off a side-by-side render, not a rule of thumb: at 48 the small art is
/// plainly more legible, at 64 the master is better proportioned.
const _smallArtCutoff = 48;

/// Sizes the macOS asset catalog references. `Contents.json` maps these onto
/// the 1x/2x pairs; it is not regenerated, so leave it alone unless the set
/// here changes.
const _macSizes = [16, 32, 64, 128, 256, 512, 1024];

/// Windows packs several sizes into the single `.ico`.
const _icoSizes = [16, 32, 48, 256];

Future<void> main() async {
  var here = p.dirname(p.fromUri(Platform.script));
  var appRoot = p.normalize(p.join(here, '..', '..'));
  var rasterizer = await _findRasterizer();

  var temp = await Directory.systemTemp.createTemp('fw_icon');
  try {
    var render = _Renderer(rasterizer, here, temp.path);

    for (var size in _macSizes) {
      await render.to(
        _artFor(size),
        size,
        p.join(
          appRoot,
          'macos/Runner/Assets.xcassets/AppIcon.appiconset',
          'app_icon_$size.png',
        ),
      );
    }

    if (Platform.isMacOS) await _refreshBuiltBundles(appRoot);

    var frames = <img.Image>[];
    for (var size in _icoSizes) {
      var png = await render.toTemp(_artFor(size), size);
      frames.add(img.decodePng(await File(png).readAsBytes())!);
    }
    var ico = p.join(appRoot, 'windows/runner/resources/app_icon.ico');
    await File(ico).writeAsBytes(img.IcoEncoder().encodeImages(frames));
    print('wrote $ico (${_icoSizes.join(', ')})');

    // A favicon shown at 16 CSS px is shown at 32 device px on every retina
    // screen, so 32 is the size worth shipping. Flutter's default was 16.
    await render.to(_small, 32, p.join(appRoot, 'web/favicon.png'));
    for (var size in [192, 512]) {
      await render.to(
        _master,
        size,
        p.join(appRoot, 'web/icons/Icon-$size.png'),
      );
      await render.to(
        _maskable,
        size,
        p.join(appRoot, 'web/icons/Icon-maskable-$size.png'),
      );
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

String _artFor(int size) => size <= _smallArtCutoff ? _small : _master;

/// Bumps the modification date of every already-built `.app`, so macOS stops
/// serving the icon it cached for them.
///
/// Worth the twelve lines because the failure is so convincing: an incremental
/// build rewrites `Contents/Resources/AppIcon.icns` *inside* the bundle without
/// touching the bundle directory, and macOS caches a bundle's icon against that
/// directory's date. The `.icns` is correct, the Dock is wrong, and it reads as
/// "the new icon did not take" rather than as a stale cache.
///
/// A bundle that is currently running keeps its old icon until it is relaunched
/// — the Dock reads the icon once, at launch.
Future<void> _refreshBuiltBundles(String appRoot) async {
  var products = Directory(p.join(appRoot, 'build/macos/Build/Products'));
  if (!products.existsSync()) return;
  for (var configuration in products.listSync().whereType<Directory>()) {
    for (var bundle in configuration.listSync().whereType<Directory>()) {
      if (p.extension(bundle.path) != '.app') continue;
      await Process.run('touch', [bundle.path]);
      print('touched ${bundle.path} — relaunch it to see the new icon');
    }
  }
}

class _Renderer {
  _Renderer(this.tool, this.sourceDir, this.tempDir);

  final _Rasterizer tool;
  final String sourceDir;
  final String tempDir;

  Future<void> to(String source, int size, String destination) async {
    await File(destination).parent.create(recursive: true);
    await _run(source, size, destination);
    print('wrote $destination (${size}px from $source)');
  }

  Future<String> toTemp(String source, int size) async {
    var out = p.join(
      tempDir,
      '${p.basenameWithoutExtension(source)}_$size.png',
    );
    await _run(source, size, out);
    return out;
  }

  Future<void> _run(String source, int size, String destination) async {
    var input = p.join(sourceDir, source);
    var result = await Process.run(
      tool.executable,
      tool.argumentsFor(input, size, destination),
    );
    if (result.exitCode != 0) {
      throw StateError(
        '${tool.executable} failed on $source at ${size}px: '
        '${result.stderr}',
      );
    }
  }
}

class _Rasterizer {
  _Rasterizer(this.executable, this.argumentsFor);

  final String executable;
  final List<String> Function(String input, int size, String output)
  argumentsFor;
}

Future<_Rasterizer> _findRasterizer() async {
  var candidates = [
    _Rasterizer(
      'rsvg-convert',
      (input, size, output) => [
        '-w',
        '$size',
        '-h',
        '$size',
        '-o',
        output,
        input,
      ],
    ),
    _Rasterizer(
      'inkscape',
      (input, size, output) => [
        input,
        '-w',
        '$size',
        '-h',
        '$size',
        '-o',
        output,
      ],
    ),
    _Rasterizer(
      'resvg',
      (input, size, output) => ['-w', '$size', '-h', '$size', input, output],
    ),
  ];
  for (var candidate in candidates) {
    var found = await Process.run('which', [candidate.executable]);
    if (found.exitCode == 0) return candidate;
  }
  throw StateError(
    'No SVG rasterizer found. Install one of: rsvg-convert (brew install '
    'librsvg), inkscape, resvg.',
  );
}
