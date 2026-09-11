import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Writes the launcher icon into every icon file the platforms already have,
/// at the size each file already has.
///
/// ```sh
/// dart run tool/brand_icons.dart
/// ```
///
/// The art is `demo/brand.dart`, photographed at 1024 into
/// `assets/brand/<set>-<role>.png` by the studio:
///
/// ```sh
/// fw run previews screenshot --entry=demo/brand.dart#appIconVariant \
///   --knobs=set=main,role=foreground --width=1024 --height=1024 \
///   --output=assets/brand/main-foreground.png
/// ```
///
/// This script only resizes those into place. It never adds or removes a
/// file: the set of files is the platforms' business — `flutter create`
/// laid most of them down, the adaptive layers were added by hand — and this
/// keeps their shapes and changes the picture. The set is read off the path
/// (`android/app/src/<set>/`, `AppIcon-<set>.appiconset`) and the role off
/// the file name.
void main() {
  var root = p.dirname(p.dirname(p.fromUri(Platform.script)));
  var sources = p.join(root, 'assets', 'brand');
  var written = 0;
  var cache = <String, img.Image>{};

  img.Image sourceFor(String set, String role) =>
      cache.putIfAbsent('$set-$role', () {
        var file = File(p.join(sources, '$set-$role.png'));
        if (!file.existsSync()) {
          stderr.writeln('No source ${p.relative(file.path, from: root)}');
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
    // The opaque icon is written without an alpha channel: App Store Connect
    // rejects a build whose icon has one, even fully opaque, and a screenshot
    // always comes with one.
    if (role == 'icon') resized = resized.convert(numChannels: 3);
    target.writeAsBytesSync(img.encodePng(resized));
    written++;
  }

  void catalog(Directory catalog, String set) {
    for (var entity in catalog.listSync().whereType<File>()) {
      if (p.extension(entity.path) != '.png') continue;
      write(entity, set, 'icon');
    }
  }

  // Android: a set per source set, a role per file name.
  var android = Directory(p.join(root, 'android', 'app', 'src'));
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
  var assets = Directory(p.join(root, 'ios', 'Runner', 'Assets.xcassets'));
  for (var entry in assets.listSync().whereType<Directory>()) {
    var name = p.basename(entry.path);
    if (!name.endsWith('.appiconset')) continue;
    var set = name == 'AppIcon.appiconset'
        ? 'main'
        : name.substring('AppIcon-'.length, name.length - '.appiconset'.length);
    catalog(entry, set);
  }

  // macOS and the web have no flavors: the main set, opaque.
  catalog(
    Directory(
      p.join(root, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'),
    ),
    'main',
  );
  catalog(Directory(p.join(root, 'web', 'icons')), 'main');
  write(File(p.join(root, 'web', 'favicon.png')), 'main', 'icon');

  stdout.writeln(
    'Wrote $written icon files from ${p.relative(sources, from: root)}',
  );
}
