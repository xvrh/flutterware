/// Where `flutter_native_splash:create` puts what it makes, and whether what is
/// there is still current.
///
/// This is the half of the plugin that looks at **ground truth** rather than at
/// the config. It is what makes `artifacts` able to hand an agent the real PNG
/// instead of a simulation, and what makes the drift check possible without
/// running anything: a `stat` on these against a `stat` on the config answers
/// "have you regenerated since you last edited?".
///
/// Paths are transcribed from the package's `flavor_helper.dart` and
/// `android.dart`. Discovery is glob-ish rather than an exact manifest on
/// purpose — the generator's exact density set varies with `android_min_sdk`
/// and the platforms present, and a hard list would report a missing file every
/// time it changed.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'surface.dart';

/// One file the generator produced.
class SplashArtifact {
  const SplashArtifact({
    required this.path,
    required this.surface,
    required this.theme,
    required this.modified,
    this.density,
  });

  /// Package-relative, so it reads the same on another machine.
  final String path;

  final SplashSurface surface;
  final SplashTheme theme;

  /// `xxhdpi`, `@3x`, `4x` — whatever the platform calls it. Null when the
  /// platform has only one.
  final String? density;

  final DateTime modified;

  Map<String, Object?> toJson() => {
    'path': path,
    'surface': surface.name,
    'theme': theme.name,
    if (density != null) 'density': density,
    'modified': modified.toIso8601String(),
  };
}

/// The Android resource root, which moves when the project uses flavors.
///
/// `android/app/src/<flavor>/res/` when there is one, `android/app/src/main/res/`
/// otherwise — the package's own `_androidResFolder`.
String androidResFolder(String? flavor) =>
    p.join('android', 'app', 'src', flavor ?? 'main', 'res');

/// Everything the generator wrote under [packageRoot], newest information
/// first.
///
/// Returns an empty list when nothing has been generated, which is a real and
/// common state — it is what "run `generate` first" is based on.
List<SplashArtifact> findSplashArtifacts(String packageRoot, {String? flavor}) {
  var found = <SplashArtifact>[];

  void add(
    File file,
    SplashSurface surface,
    SplashTheme theme,
    String? density,
  ) {
    found.add(
      SplashArtifact(
        path: p.relative(file.path, from: packageRoot),
        surface: surface,
        theme: theme,
        density: density,
        modified: file.statSync().modified,
      ),
    );
  }

  // ---- Android ----------------------------------------------------------
  // One `splash.png` per density folder, plus `android12splash.png` for the
  // Android 12 path and `branding.png` beside them. `-night` in the folder name
  // is what makes a resource the dark one.
  var res = Directory(p.join(packageRoot, androidResFolder(flavor)));
  if (res.existsSync()) {
    for (var entry in res.listSync().whereType<Directory>()) {
      var folder = p.basename(entry.path);
      if (!folder.startsWith('drawable')) continue;
      var theme = folder.contains('night')
          ? SplashTheme.dark
          : SplashTheme.light;
      var density = folder
          .replaceFirst('drawable-', '')
          .replaceFirst('night-', '');
      for (var file in entry.listSync().whereType<File>()) {
        var name = p.basename(file.path);
        var surface = switch (name) {
          'android12splash.png' => SplashSurface.android12,
          'splash.png' || 'branding.png' => SplashSurface.android,
          _ => null,
        };
        if (surface != null) {
          add(file, surface, theme, density == folder ? null : density);
        }
      }
    }
  }

  // ---- iOS --------------------------------------------------------------
  // **`LaunchImage.imageset` is not evidence of anything.** Every Flutter
  // project ships one, with `LaunchImage.png`, `@2x` and `@3x` already in it,
  // from `flutter create` onwards. Counting it made a project that had never
  // run the generator report three generated files — and then report them as
  // stale, which is a drift warning about work that never happened.
  //
  // `LaunchBackground.imageset` is the honest marker: `_createiOSSplash` writes
  // its `Contents.json` unconditionally, and nothing else creates it.
  var iosAssets = p.join(packageRoot, 'ios', 'Runner', 'Assets.xcassets');
  var iosGenerated = Directory(
    p.join(iosAssets, 'LaunchBackground.imageset'),
  ).existsSync();

  for (var set in ['LaunchImage', 'BrandingImage', 'LaunchBackground']) {
    if (!iosGenerated) break;
    var dir = Directory(p.join(iosAssets, '$set.imageset'));
    if (!dir.existsSync()) continue;
    for (var file in dir.listSync().whereType<File>()) {
      if (p.extension(file.path) != '.png') continue;
      var name = p.basenameWithoutExtension(file.path);
      var density = switch (name) {
        _ when name.endsWith('@3x') => '@3x',
        _ when name.endsWith('@2x') => '@2x',
        _ => null,
      };
      var theme = name.toLowerCase().contains('dark')
          ? SplashTheme.dark
          : SplashTheme.light;
      add(file, SplashSurface.ios, theme, density);
    }
  }

  // ---- Web --------------------------------------------------------------
  var web = Directory(p.join(packageRoot, 'web', 'splash', 'img'));
  if (web.existsSync()) {
    for (var file in web.listSync().whereType<File>()) {
      if (p.extension(file.path) != '.png') continue;
      var name = p.basenameWithoutExtension(file.path);
      var theme = name.contains('dark') ? SplashTheme.dark : SplashTheme.light;
      var density = RegExp(r'(\dx)$').firstMatch(name)?.group(1);
      add(file, SplashSurface.web, theme, density);
    }
  }

  found.sort((a, b) => a.path.compareTo(b.path));
  return found;
}

/// Whether the config has been edited since the splash was last generated.
///
/// False when nothing has been generated at all — "you have never run it" is a
/// different thing from "what you have is out of date", and reporting the
/// second when the first is true reads as a problem with the output rather than
/// its absence.
bool splashIsStale({
  required String configPath,
  required List<SplashArtifact> artifacts,
}) {
  if (artifacts.isEmpty) return false;
  var config = File(configPath);
  if (!config.existsSync()) return false;
  var configTime = config.statSync().modified;
  var newest = artifacts
      .map((a) => a.modified)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return configTime.isAfter(newest);
}
