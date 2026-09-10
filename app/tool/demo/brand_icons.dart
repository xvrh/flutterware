import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Writes the shop's launcher icon into every icon file the example's sets
/// already have, at the size each file already has.
///
/// ```sh
/// cd app && fvm dart run tool/demo/brand_icons.dart
/// ```
///
/// The art is `examples/example/demo/brand.dart`, photographed at 1024 into
/// `examples/example/assets/brand/<set>-<role>.png` by the studio:
///
/// ```sh
/// fw run previews screenshot --entry=demo/brand.dart#appIconVariant \
///   --knobs=set=pro,role=foreground --width=1024 --height=1024 \
///   --output=assets/brand/pro-foreground.png
/// ```
///
/// This script only resizes those into place. It never adds or removes a
/// file: the sets' *shapes* — one density overriding, an iOS-only set, a
/// themed layer dropped — are the fixtures the README explains, and they
/// are the point. The set is read off the path (`android/app/src/<set>/`,
/// `AppIcon-<set>.appiconset`) and the role off the file name.
void main() {
  var appRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var example = p.join(p.dirname(appRoot), 'examples', 'example');
  var sources = p.join(example, 'assets', 'brand');
  var written = 0;
  var cache = <String, img.Image>{};

  img.Image sourceFor(String set, String role) =>
      cache.putIfAbsent('$set-$role', () {
        var file = File(p.join(sources, '$set-$role.png'));
        if (!file.existsSync()) {
          stderr.writeln('No source ${p.relative(file.path, from: example)}');
          exit(1);
        }
        return img.decodePng(file.readAsBytesSync())!;
      });

  void write(File target, String set, String role) {
    var current = img.decodePng(target.readAsBytesSync())!;
    var resized = img.copyResize(
      sourceFor(set, role),
      width: current.width,
      height: current.height,
      interpolation: img.Interpolation.cubic,
    );
    target.writeAsBytesSync(img.encodePng(resized));
    written++;
  }

  // Android: a set per source set, a role per file name.
  var android = Directory(p.join(example, 'android', 'app', 'src'));
  for (var set in android.listSync().whereType<Directory>()) {
    var res = Directory(p.join(set.path, 'res'));
    if (!res.existsSync()) continue;
    for (var entity in res.listSync(recursive: true)) {
      if (entity is! File ||
          !p.basename(entity.path).startsWith('ic_launcher')) {
        continue;
      }
      if (p.extension(entity.path) != '.png') continue;
      var name = p.basenameWithoutExtension(entity.path);
      var role = switch (name) {
        'ic_launcher_foreground' => 'foreground',
        'ic_launcher_monochrome' => 'monochrome',
        _ => 'icon',
      };
      write(entity, p.basename(set.path), role);
    }
  }

  // iOS: a set per catalog, every file the opaque icon.
  var assets = Directory(p.join(example, 'ios', 'Runner', 'Assets.xcassets'));
  for (var catalog in assets.listSync().whereType<Directory>()) {
    var name = p.basename(catalog.path);
    if (!name.endsWith('.appiconset')) continue;
    var set = name == 'AppIcon.appiconset'
        ? 'main'
        : name.substring('AppIcon-'.length, name.length - '.appiconset'.length);
    for (var entity in catalog.listSync().whereType<File>()) {
      if (p.extension(entity.path) != '.png') continue;
      write(entity, set, 'icon');
    }
  }
  print('Wrote $written icon files from ${p.relative(sources, from: example)}');
}
