/// What a preview is framed as, addressed by where it lives.
///
/// One package routinely holds more than one form factor — a phone app and a
/// desktop dashboard sharing a theme, a model layer and a widget library — and
/// a single device on the package frames half the catalog on the wrong screen.
/// A canvas says *this subtree renders like this*, which is the fact that was
/// previously inexpressible.
///
/// Pure Dart, and exported by `plugins.dart`, `devices.dart` and
/// `flutter_test.dart` alike. That is the point rather than a convenience: the
/// list belongs to the **project**, not to the tool, so a project keeps it in
/// its own package and hands the same value to `tool/flutterware.dart` and to
/// whatever else needs to know what a directory is meant to look like.
library;

import 'devices.dart';

/// The devices one subtree of a package is meant to be seen on.
///
/// ```dart
/// // demo/lib/canvases.dart — no Flutter import, so `tool/flutterware.dart`
/// // can read it under a plain `dart run` and a test can read it too.
/// const canvases = [
///   PreviewCanvas('src/mobile', devices: [Devices.iphone16, Devices.iphoneSe]),
///   PreviewCanvas('src/desktop', devices: [Devices.macbookPro]),
/// ];
/// ```
///
/// **Named `PreviewCanvas` rather than `Canvas` because of `dart:ui`.** A test
/// importing `package:flutterware/flutter_test.dart` has Flutter's `Canvas` in
/// scope through `package:flutter_test`, and two exported `Canvas`es are an
/// ambiguous name in every file that imports both — which is precisely the file
/// this type exists to serve.
class PreviewCanvas {
  const PreviewCanvas(
    this.prefix, {
    this.devices = const [],
    this.orientations = const [],
  });

  /// Which entries this covers: a path relative to the **package**, in the same
  /// coordinates as `PreviewsPackage.directory` and the paths the tool reports
  /// entries under.
  ///
  /// The empty string covers the whole package, which is what a project with
  /// one form factor writes and what a bare `device:` on the package means.
  ///
  /// Matched on segment boundaries, never as raw text — `src/mobile` covers
  /// `src/mobile/tile.dart` and pointedly not `src/mobile_legacy/tile.dart`.
  ///
  /// **A file is a legal prefix**, and supported rather than incidental: the
  /// last segment of a path is a file, so `src/mobile/tile.dart` covers exactly
  /// the entries in that one file. It is how a single preview differs from its
  /// neighbours without giving it a directory of its own. This said "a
  /// directory" for a while, and a consumer who tried a file, watched it work
  /// and could not tell whether they were allowed to depend on it is the reason
  /// it does not any more.
  final String prefix;

  /// The devices these entries are worth looking at on.
  ///
  /// **The list is the offered set, and its head is the default** — the same
  /// sentence `ScenarioProfile` is built on, deliberately, because previews are
  /// asking that tool's question in a different vocabulary. A card with a
  /// breakpoint in it is meant to survive a small phone *and* a large one, and
  /// which of the two broke is usually the interesting part; anything drawing
  /// one picture takes the head, and anything sweeping takes all of it.
  ///
  /// Empty is a complete declaration and means the plain rectangle, which is
  /// how one subtree opts out of a canvas its parent declared.
  final List<Device> devices;

  /// The orientations worth crossing [devices] with, head first, likewise.
  ///
  /// Crossed rather than listed alongside: a tablet in landscape is the same
  /// tablet, so two short lists beat one long one with the rotatable entries
  /// written twice. Empty means portrait.
  final List<ScreenOrientation> orientations;

  /// [prefix] with its slashes tidied — no leading or trailing one, `.` and the
  /// empty string both meaning the whole package.
  ///
  /// Every comparison goes through this rather than through [prefix] itself, so
  /// `demo/`, `/demo` and `demo` are one rule and not three.
  String get root {
    var trimmed = prefix.trim();
    if (trimmed == '.' || trimmed == '/') return '';
    var start = trimmed.startsWith('/') ? 1 : 0;
    var end = trimmed.endsWith('/') ? trimmed.length - 1 : trimmed.length;
    return start >= end ? '' : trimmed.substring(start, end);
  }

  /// What one picture of an entry under this canvas is framed as.
  Device? get defaultDevice => devices.isEmpty ? null : devices.first;

  /// Which way up that picture is.
  ScreenOrientation? get defaultOrientation =>
      orientations.isEmpty ? null : orientations.first;

  /// Whether [path] — a package-relative, `/`-separated file or directory — is
  /// under this canvas.
  bool covers(String path) {
    var under = root;
    if (under.isEmpty) return true;
    return path == under || path.startsWith('$under/');
  }

  Map<String, Object?> toJson() => {
    'prefix': root,
    if (devices.isNotEmpty) 'devices': [for (var d in devices) d.id],
    if (orientations.isNotEmpty)
      'orientations': [for (var o in orientations) o.name],
  };

  /// Reads back what [toJson] wrote.
  ///
  /// **An id this build has no device for is dropped, not refused.** This is
  /// read on the way to drawing something rather than while checking a command
  /// line, and the config is written against the `flutterware` the *project*
  /// pins — which can run ahead of the GUI reading its manifest. A device we
  /// cannot resolve has to mean a canvas with fewer devices, never a panel that
  /// will not open.
  static PreviewCanvas? fromJson(Object? raw) {
    if (raw is! Map) return null;
    var prefix = raw['prefix'];
    if (prefix is! String) return null;
    return PreviewCanvas(
      prefix,
      devices: [
        for (var id in (raw['devices'] as List? ?? const []))
          if (id is String) ?deviceById(id),
      ],
      orientations: [
        for (var name in (raw['orientations'] as List? ?? const []))
          if (name is String) ?orientationById(name),
      ],
    );
  }

  @override
  String toString() => 'PreviewCanvas(${root.isEmpty ? '<package>' : root})';
}

/// The rectangle an entry under no canvas is framed as, in logical pixels at a
/// ratio of 1.
///
/// **Both backends have to agree about it**, which is why it is one constant
/// and not two. The embedder guest reads it as `CaptureViewport.panel` and the
/// tester harness stages it when [canvasFor] finds nothing; a harness that
/// simply left the test surface alone would judge the same entry on
/// `flutter_test`'s 800×600 instead — measured, and it invented two overflows
/// the guest did not report.
const previewPanelWidth = 900;
const previewPanelHeight = 700;

/// The canvas that applies to [path], or null when none of them does.
///
/// **Longest prefix wins**, which is what makes the list ordered data rather
/// than a rule set with precedence to learn: declare nothing and get the plain
/// rectangle, declare one line and the package has a shape, declare a third
/// when one subtree really is 1920 wide. Declaration order breaks a tie between
/// two prefixes of equal length, which `Previews` refuses to let you write
/// anyway.
///
/// The tool and a project's own tests are expected to call *this* function
/// rather than each match the prefixes themselves — a rule applied twice is a
/// rule that eventually differs, and the whole value of the list is that the
/// panel, the screenshot and the test agree about what a directory is for.
PreviewCanvas? canvasFor(List<PreviewCanvas> canvases, String path) {
  PreviewCanvas? best;
  for (var canvas in canvases) {
    if (!canvas.covers(path)) continue;
    if (best == null || canvas.root.length > best.root.length) best = canvas;
  }
  return best;
}
