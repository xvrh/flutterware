/// Reading one package's launcher icons off disk.
///
/// The budget here is the plugin-core budget: list directories, read a few
/// image headers, parse three small XML files, cache the result. Nothing here
/// decodes an image — dimensions and alpha come out of the PNG header, for the
/// same reason the splash scan reads IHDR directly, and the panel decodes only
/// what it is about to draw.
///
/// Discovery is deliberately **broad, then classified**. Globbing for
/// `ic_launcher_foreground.png` by name would only find icons a particular
/// generator wrote; listing every PNG in `mipmap-*` and then asking the
/// project's own wiring what each one is finds them whoever wrote them — and,
/// more usefully, finds the ones nothing references at all.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import 'role.dart';
import 'wiring.dart';

/// One icon file, and what its header says about it.
class IconFile {
  const IconFile({
    required this.path,
    required this.absolutePath,
    required this.modified,
    this.width,
    this.height,
    this.hasAlpha = false,
    this.density,
    this.icoFrames = const [],
    this.declaredSize,
  });

  /// Package-relative, so it reads the same on another machine.
  final String path;

  /// Where to actually load it from. The panel needs this; every reported path
  /// stays relative.
  final String absolutePath;

  final DateTime modified;

  /// Null when the header could not be read — a truncated file, or a format
  /// with no cheap header. Reported as unknown rather than guessed.
  final int? width;
  final int? height;

  /// Whether the pixels can be transparent. The App Store rejects an iOS icon
  /// that can.
  final bool hasAlpha;

  /// `xxhdpi`, `@3x`, `192` — whatever the platform calls this variant. Null
  /// when the platform has only one.
  final String? density;

  /// The sizes an `.ico` packs, largest last. Empty for every other format.
  final List<int> icoFrames;

  /// What an Apple asset catalog says this file's pixel size should be.
  ///
  /// Kept beside the real [width] so the two can disagree out loud: a catalog
  /// promising 1024×1024 over a 512×512 file is a fact about the files, needing
  /// no opinion about how they were made.
  final int? declaredSize;

  String get name => p.basenameWithoutExtension(path);

  bool get sizeMismatch =>
      declaredSize != null && width != null && width != declaredSize;
}

/// Everything found for one role.
class IconRoleScan {
  const IconRoleScan({
    required this.role,
    required this.files,
    this.color,
    this.referenced,
  });

  final IconRole role;

  /// Sorted smallest first.
  final List<IconFile> files;

  /// The adaptive background when it is a colour rather than an image.
  final String? color;

  /// Whether the project's wiring points at this. Null off Android, where
  /// there is no wiring to read and presence is the whole answer.
  final bool? referenced;

  bool get isEmpty => files.isEmpty && color == null;
  bool get isNotEmpty => !isEmpty;

  /// The largest file, which is the one worth drawing.
  IconFile? get largest => files.isEmpty ? null : files.last;
}

/// Which shape the iOS asset situation is in.
///
/// Three states rather than a bool because a modern project can legitimately
/// have **no per-size PNGs at all**: Xcode 26 generates every variant from a
/// single Icon Composer `.icon` bundle at build time. Reporting "no iOS icons"
/// there would be wrong, and would be the first thing anyone noticed.
enum IosCatalog {
  /// Nothing found.
  none,

  /// The classic `AppIcon.appiconset` with a PNG per size.
  appIconSet,

  /// An Icon Composer `.icon` bundle. Xcode expands it during the build.
  iconComposer,

  /// Both present, which Apple's own forums are full of people getting
  /// submission failures from.
  both,
}

/// One thing worth saying about what was found.
class IconFinding {
  const IconFinding(this.tone, this.message, {this.role});

  final Tone tone;
  final String message;
  final IconRole? role;
}

/// Everything one package's icons turned out to be.
class IconScan {
  const IconScan({
    required this.packagePath,
    required this.roles,
    required this.findings,
    this.flavor,
    this.flavors = const [],
    this.android,
    this.ios = IosCatalog.none,
    this.iconBundles = const [],
  });

  /// Workspace-relative — `.`, `examples/example`.
  final String packagePath;

  /// The source set this scan read, or null for the default.
  final String? flavor;

  /// The other Android source sets that exist, so the panel can offer them.
  final List<String> flavors;

  final List<IconRoleScan> roles;
  final List<IconFinding> findings;

  final AndroidWiring? android;
  final IosCatalog ios;

  /// Package-relative paths of any Icon Composer bundles.
  final List<String> iconBundles;

  IconRoleScan? forRole(IconRole role) {
    for (var scan in roles) {
      if (scan.role == role) return scan;
    }
    return null;
  }

  List<IconRoleScan> forPlatform(IconPlatform platform) => [
    for (var scan in roles)
      if (scan.role.platform == platform) scan,
  ];

  /// The platforms that turned up anything at all.
  List<IconPlatform> get platforms => [
    for (var platform in IconPlatform.values)
      if (forPlatform(platform).any((s) => s.isNotEmpty)) platform,
  ];

  int get fileCount {
    var total = 0;
    for (var scan in roles) {
      total += scan.files.length;
    }
    return total;
  }

  bool get isEmpty => roles.every((r) => r.isEmpty) && ios == IosCatalog.none;
}

/// Scans [packageRoot], which must be absolute.
IconScan scanIcons({
  required String packageRoot,
  required String packagePath,
  String? flavor,
}) {
  var roles = <IconRole, IconRoleScan>{};
  var findings = <IconFinding>[];

  var android = _scanAndroid(packageRoot, flavor, roles);
  var (ios, bundles) = _scanApple(packageRoot, roles);
  _scanWeb(packageRoot, roles);
  _scanDesktop(packageRoot, roles);

  var scan = IconScan(
    packagePath: packagePath,
    flavor: flavor,
    flavors: androidFlavors(packageRoot),
    roles: [
      for (var role in IconRole.values)
        roles[role] ?? IconRoleScan(role: role, files: const []),
    ],
    findings: findings,
    android: android,
    ios: ios,
    iconBundles: bundles,
  );

  findings.addAll(_findings(scan));
  return scan;
}

// ---- Android ---------------------------------------------------------------

/// The Android source sets that are not build types, in listing order.
List<String> androidFlavors(String packageRoot) {
  var dir = Directory(p.join(packageRoot, 'android', 'app', 'src'));
  if (!dir.existsSync()) return const [];

  const reserved = {
    'main',
    'debug',
    'profile',
    'release',
    'test',
    'androidTest',
  };
  return [
    for (var entry in dir.listSync().whereType<Directory>())
      if (!reserved.contains(p.basename(entry.path))) p.basename(entry.path),
  ]..sort();
}

AndroidWiring? _scanAndroid(
  String packageRoot,
  String? flavor,
  Map<IconRole, IconRoleScan> roles,
) {
  var sourceSet = p.join(
    packageRoot,
    'android',
    'app',
    'src',
    flavor ?? 'main',
  );
  var resFolder = p.join(sourceSet, 'res');
  if (!Directory(resFolder).existsSync()) return null;

  // A flavour source set may carry its own manifest; the icon attributes
  // usually stay in main, so that is the fallback rather than the only look.
  var manifest = File(p.join(sourceSet, 'AndroidManifest.xml')).existsSync()
      ? p.join(sourceSet, 'AndroidManifest.xml')
      : p.join(
          packageRoot,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        );

  var wiring = readAndroidWiring(
    packageRoot: packageRoot,
    resFolder: resFolder,
    manifestPath: manifest,
  );

  var byRole = <IconRole, List<IconFile>>{};

  for (var dir in Directory(resFolder).listSync().whereType<Directory>()) {
    var dirName = p.basename(dir.path);
    var isMipmap = dirName.startsWith('mipmap-') || dirName == 'mipmap';
    var isDrawable = dirName.startsWith('drawable-') || dirName == 'drawable';
    if (!isMipmap && !isDrawable) continue;
    // The adaptive XML is wiring, not an image; `wiring.dart` has it.
    if (dirName == 'mipmap-anydpi-v26') continue;

    var density = dirName.contains('-')
        ? dirName.substring(dirName.indexOf('-') + 1)
        : null;

    for (var file in dir.listSync().whereType<File>()) {
      if (p.extension(file.path).toLowerCase() != '.png') continue;
      var name = p.basenameWithoutExtension(file.path);
      var role = isMipmap
          ? _classifyMipmap(name, wiring)
          : _classifyDrawable(name);
      if (role == null) continue;
      byRole
          .putIfAbsent(role, () => [])
          .add(_pngFile(packageRoot, file, density: density));
    }
  }

  var playStore = File(p.join(sourceSet, 'ic_launcher-playstore.png'));
  if (playStore.existsSync()) {
    byRole
        .putIfAbsent(IconRole.androidPlayStore, () => [])
        .add(_pngFile(packageRoot, playStore));
  }

  var referenced = wiring.referencedNames;
  // Only meaningful once something was actually read: with an unreadable
  // manifest and no adaptive XML, every file would look unreferenced and the
  // panel would cry wolf about all of them.
  var wiringIsKnown = referenced.isNotEmpty;

  for (var entry in byRole.entries) {
    var files = entry.value..sort(_bySize);
    roles[entry.key] = IconRoleScan(
      role: entry.key,
      files: files,
      color: entry.key == IconRole.androidAdaptiveBackground
          ? wiring.backgroundColor
          : null,
      referenced: wiringIsKnown
          ? files.any((f) => referenced.contains(f.name))
          : null,
    );
  }

  // A colour background has no files at all, so it needs its own row.
  if (wiring.backgroundColor != null &&
      !roles.containsKey(IconRole.androidAdaptiveBackground)) {
    roles[IconRole.androidAdaptiveBackground] = IconRoleScan(
      role: IconRole.androidAdaptiveBackground,
      files: const [],
      color: wiring.backgroundColor,
      referenced: true,
    );
  }

  return wiring;
}

/// What a mipmap PNG is, asking the wiring before the naming convention.
///
/// The wiring first is what makes this generator-agnostic: a project whose
/// manifest says `android:icon="@mipmap/launcher"` gets its launcher icon
/// recognised, where a list of `icons_launcher`'s output names would miss it
/// entirely.
IconRole? _classifyMipmap(String name, AndroidWiring wiring) {
  if (name == _nameOrNull(wiring.manifestIcon)) return IconRole.androidLegacy;
  if (name == _nameOrNull(wiring.manifestRoundIcon)) {
    return IconRole.androidRound;
  }
  for (var xml in [wiring.launcher, wiring.launcherRound]) {
    if (xml == null) continue;
    if (name == _nameOrNull(xml.foreground)) {
      return IconRole.androidAdaptiveForeground;
    }
    if (name == _nameOrNull(xml.background)) {
      return IconRole.androidAdaptiveBackground;
    }
    if (name == _nameOrNull(xml.monochrome)) return IconRole.androidMonochrome;
  }

  return switch (name) {
    'ic_launcher' => IconRole.androidLegacy,
    'ic_launcher_round' => IconRole.androidRound,
    'ic_launcher_foreground' => IconRole.androidAdaptiveForeground,
    'ic_launcher_background' => IconRole.androidAdaptiveBackground,
    'ic_launcher_monochrome' => IconRole.androidMonochrome,
    _ => null,
  };
}

/// Notification icons are recognised by name alone.
///
/// Unlike the launcher icon they are referenced from application code or from a
/// `<meta-data>` element naming a library's convention, so there is no single
/// place to read. `ic_notification` and `ic_stat_*` are what the Android and
/// Firebase docs use.
IconRole? _classifyDrawable(String name) =>
    name == 'ic_notification' || name.startsWith('ic_stat')
    ? IconRole.androidNotification
    : null;

String? _nameOrNull(String? reference) =>
    reference == null ? null : resourceName(reference);

// ---- Apple -----------------------------------------------------------------

(IosCatalog, List<String>) _scanApple(
  String packageRoot,
  Map<IconRole, IconRoleScan> roles,
) {
  _scanAssetCatalog(
    packageRoot,
    p.join(packageRoot, 'ios', 'Runner', 'Assets.xcassets'),
    roles,
    light: IconRole.iosApp,
    dark: IconRole.iosDark,
    tinted: IconRole.iosTinted,
  );
  _scanAssetCatalog(
    packageRoot,
    p.join(packageRoot, 'macos', 'Runner', 'Assets.xcassets'),
    roles,
    light: IconRole.macosApp,
  );

  var bundles = _iconBundles(packageRoot);
  var hasSet = roles[IconRole.iosApp]?.files.isNotEmpty ?? false;

  return (
    switch ((hasSet, bundles.isNotEmpty)) {
      (true, true) => IosCatalog.both,
      (true, false) => IosCatalog.appIconSet,
      (false, true) => IosCatalog.iconComposer,
      (false, false) => IosCatalog.none,
    },
    bundles,
  );
}

/// Icon Composer bundles under `ios/`.
///
/// Looked for one level into `ios/` and inside `ios/Runner/`, which is where
/// Xcode puts one when you drag it in. Not a full walk: a recursive search of
/// `ios/` would wander into Pods.
List<String> _iconBundles(String packageRoot) {
  var found = <String>[];
  for (var relative in [p.join('ios'), p.join('ios', 'Runner')]) {
    var dir = Directory(p.join(packageRoot, relative));
    if (!dir.existsSync()) continue;
    for (var entry in dir.listSync()) {
      if (p.extension(entry.path).toLowerCase() == '.icon') {
        found.add(p.relative(entry.path, from: packageRoot));
      }
    }
  }
  return found..sort();
}

/// Reads every `*AppIcon.appiconset` in [catalogPath].
///
/// `Contents.json` is the authority rather than the filenames: it is what Xcode
/// reads, it is written the same way whoever generated it, and it is the only
/// place that says which file is the dark one. Guessing from `Icon-App-…@2x`
/// naming would bind this to one generator's spelling.
void _scanAssetCatalog(
  String packageRoot,
  String catalogPath,
  Map<IconRole, IconRoleScan> roles, {
  required IconRole light,
  IconRole? dark,
  IconRole? tinted,
}) {
  var catalog = Directory(catalogPath);
  if (!catalog.existsSync()) return;

  var byRole = <IconRole, List<IconFile>>{};

  // One file backs several catalog entries: 20x20@2x and 40x40@1x are the same
  // 40px square, and Xcode lists both. Counting per entry would report 19 files
  // where 15 exist, and — worse — say "19 icons carry an alpha channel" about
  // 15 files. Keyed by resolved path so two sets cannot collide.
  var seen = <String>{};

  for (var set in catalog.listSync().whereType<Directory>()) {
    if (!p.basename(set.path).endsWith('AppIcon.appiconset')) continue;

    var contents = File(p.join(set.path, 'Contents.json'));
    if (!contents.existsSync()) continue;

    List<Object?> images;
    try {
      var decoded = jsonDecode(contents.readAsStringSync());
      images =
          (decoded is Map ? decoded['images'] : null) as List<Object?>? ??
          const [];
    } catch (_) {
      continue;
    }

    for (var entry in images) {
      if (entry is! Map) continue;
      var filename = entry['filename'];
      if (filename is! String || filename.isEmpty) continue;

      var file = File(p.join(set.path, filename));
      if (!file.existsSync()) continue;
      if (!seen.add(file.path)) continue;

      var role = switch (_appearance(entry['appearances'])) {
        'dark' => dark ?? light,
        'tinted' => tinted ?? light,
        _ => light,
      };

      var scale = '${entry['scale'] ?? ''}';
      byRole
          .putIfAbsent(role, () => [])
          .add(
            _pngFile(
              packageRoot,
              file,
              density: scale.isEmpty ? null : scale,
              declaredSize: _declaredSize(entry),
            ),
          );
    }
  }

  for (var entry in byRole.entries) {
    roles[entry.key] = IconRoleScan(
      role: entry.key,
      files: entry.value..sort(_bySize),
    );
  }
}

/// The `luminosity` appearance of a catalog entry — `dark`, `tinted`, or null
/// for the default.
String? _appearance(Object? appearances) {
  if (appearances is! List) return null;
  for (var appearance in appearances) {
    if (appearance is Map && appearance['appearance'] == 'luminosity') {
      return '${appearance['value']}';
    }
  }
  return null;
}

/// `size: "83.5x83.5"` × `scale: "2x"` in pixels, or null when either is
/// missing or unparseable.
int? _declaredSize(Map<Object?, Object?> entry) {
  var size = entry['size'];
  var scale = entry['scale'];
  if (size is! String) return null;

  var points = double.tryParse(size.split('x').first);
  if (points == null) return null;

  var multiplier = scale is String
      ? double.tryParse(scale.replaceAll('x', '')) ?? 1
      : 1;
  return (points * multiplier).round();
}

// ---- Web and desktop -------------------------------------------------------

void _scanWeb(String packageRoot, Map<IconRole, IconRoleScan> roles) {
  var byRole = <IconRole, List<IconFile>>{};

  var icons = Directory(p.join(packageRoot, 'web', 'icons'));
  if (icons.existsSync()) {
    for (var file in icons.listSync().whereType<File>()) {
      if (p.extension(file.path).toLowerCase() != '.png') continue;
      var role = p.basename(file.path).toLowerCase().contains('maskable')
          ? IconRole.webMaskable
          : IconRole.webIcon;
      byRole.putIfAbsent(role, () => []).add(_pngFile(packageRoot, file));
    }
  }

  for (var name in ['favicon.png', 'favicon.ico']) {
    var file = File(p.join(packageRoot, 'web', name));
    if (!file.existsSync()) continue;
    byRole
        .putIfAbsent(IconRole.webFavicon, () => [])
        .add(_imageFile(packageRoot, file));
  }

  for (var entry in byRole.entries) {
    roles[entry.key] = IconRoleScan(
      role: entry.key,
      files: entry.value..sort(_bySize),
    );
  }
}

void _scanDesktop(String packageRoot, Map<IconRole, IconRoleScan> roles) {
  var windows = Directory(
    p.join(packageRoot, 'windows', 'runner', 'resources'),
  );
  if (windows.existsSync()) {
    var files = [
      for (var file in windows.listSync().whereType<File>())
        if (p.extension(file.path).toLowerCase() == '.ico')
          _imageFile(packageRoot, file),
    ]..sort(_bySize);
    if (files.isNotEmpty) {
      roles[IconRole.windowsIco] = IconRoleScan(
        role: IconRole.windowsIco,
        files: files,
      );
    }
  }

  var snap = Directory(p.join(packageRoot, 'snap', 'gui'));
  if (snap.existsSync()) {
    var files = [
      for (var file in snap.listSync().whereType<File>())
        if (p.extension(file.path).toLowerCase() == '.png')
          _pngFile(packageRoot, file),
    ]..sort(_bySize);
    if (files.isNotEmpty) {
      roles[IconRole.linuxSnap] = IconRoleScan(
        role: IconRole.linuxSnap,
        files: files,
      );
    }
  }
}

// ---- Findings --------------------------------------------------------------

/// What is worth saying about what was found.
///
/// Every rule here is a **fact about the files**, never an opinion about how
/// they were made: nothing reads a generator's config, so nothing can complain
/// about one.
List<IconFinding> _findings(IconScan scan) {
  var findings = <IconFinding>[];
  var wiring = scan.android;

  if (wiring != null) {
    // Roles a specific rule below already explains. The generic
    // nothing-points-at-this sweep runs last and skips them, so a themed icon
    // with no <monochrome> layer is reported once, in the words that say what
    // to do about it, rather than twice.
    var explained = <IconRole>{};

    var monochrome = scan.forRole(IconRole.androidMonochrome);
    if (monochrome != null &&
        monochrome.files.isNotEmpty &&
        wiring.launcher != null &&
        !wiring.launcher!.hasMonochrome) {
      findings.add(
        IconFinding(
          Tone.warn,
          'A themed icon exists, but ${wiring.launcher!.path} declares no '
          '<monochrome> layer, so Android 13+ falls back to the full-colour '
          'icon.',
          role: IconRole.androidMonochrome,
        ),
      );
      explained.add(IconRole.androidMonochrome);
    }

    for (var xml in [wiring.launcher, wiring.launcherRound]) {
      if (xml == null) continue;
      for (var reference in [xml.foreground, xml.background, xml.monochrome]) {
        if (reference == null) continue;
        // A `@color/…` background resolves in colors.xml, not to a file.
        if (reference.startsWith('@color/')) continue;
        var name = resourceName(reference);
        var found = scan.roles.any(
          (role) => role.files.any((file) => file.name == name),
        );
        if (!found) {
          findings.add(
            IconFinding(
              Tone.error,
              '${xml.path} points at $reference, and no such image is on disk.',
            ),
          );
        }
      }
    }

    var adaptive = scan.forRole(IconRole.androidAdaptiveForeground);
    var legacy = scan.forRole(IconRole.androidLegacy);
    if (wiring.adaptiveReachesEveryone == false &&
        (adaptive?.files.isNotEmpty ?? false) &&
        (legacy?.files.isEmpty ?? true)) {
      findings.add(
        IconFinding(
          Tone.warn,
          'minSdk is ${wiring.minSdk}, so devices below API 26 fall back to the '
          'bitmap launcher icon — and there is not one.',
          role: IconRole.androidLegacy,
        ),
      );
      explained.add(IconRole.androidLegacy);
    }

    // Only meaningful once something was actually read: with an unreadable
    // manifest and no adaptive XML nothing is referenced, and saying so about
    // every file would be crying wolf.
    if (wiring.referencedNames.isNotEmpty) {
      for (var role in scan.roles) {
        if (role.role.platform != IconPlatform.android) continue;
        if (role.files.isEmpty || role.referenced != false) continue;
        if (explained.contains(role.role)) continue;
        // The Play Store icon is uploaded rather than referenced, and a
        // notification icon is named from application code the scan cannot see.
        if (role.role == IconRole.androidPlayStore) continue;
        if (role.role == IconRole.androidNotification) continue;
        findings.add(
          IconFinding(
            Tone.warn,
            '${role.files.length} file${role.files.length == 1 ? '' : 's'} on '
            'disk, but no adaptive icon XML or manifest attribute points at '
            '${role.files.first.name} — Android never draws it.',
            role: role.role,
          ),
        );
      }
    }
  }

  for (var role in [IconRole.iosApp, IconRole.iosDark, IconRole.iosTinted]) {
    var scanned = scan.forRole(role);
    if (scanned == null) continue;
    var withAlpha = scanned.files.where((f) => f.hasAlpha).toList();
    if (withAlpha.isNotEmpty) {
      findings.add(
        IconFinding(
          Tone.error,
          '${withAlpha.length} iOS icon${withAlpha.length == 1 ? '' : 's'} '
          'carr${withAlpha.length == 1 ? 'ies' : 'y'} an alpha channel. App '
          'Store Connect rejects a build whose icon does.',
          role: role,
        ),
      );
    }
  }

  if (scan.ios == IosCatalog.both) {
    findings.add(
      IconFinding(
        Tone.warn,
        'Both an Icon Composer bundle (${scan.iconBundles.join(', ')}) and a '
        'classic AppIcon.appiconset are present. Xcode uses one; which is '
        'decided by the target settings, not by what is on disk.',
      ),
    );
  }

  for (var role in scan.roles) {
    for (var file in role.files) {
      if (file.sizeMismatch) {
        findings.add(
          IconFinding(
            Tone.warn,
            '${file.path} is ${file.width}×${file.height}, where the asset '
            'catalog declares ${file.declaredSize}×${file.declaredSize}.',
            role: role.role,
          ),
        );
      }
    }
  }

  return findings;
}

// ---- File facts ------------------------------------------------------------

int _bySize(IconFile a, IconFile b) => (a.width ?? 0).compareTo(b.width ?? 0);

IconFile _pngFile(
  String packageRoot,
  File file, {
  String? density,
  int? declaredSize,
}) {
  Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } catch (_) {
    return IconFile(
      path: p.relative(file.path, from: packageRoot),
      absolutePath: file.path,
      modified: _modified(file),
      density: density,
      declaredSize: declaredSize,
    );
  }

  var header = readPngHeader(bytes);
  return IconFile(
    path: p.relative(file.path, from: packageRoot),
    absolutePath: file.path,
    modified: _modified(file),
    width: header?.width,
    height: header?.height,
    hasAlpha: header?.hasAlpha ?? false,
    density: density,
    declaredSize: declaredSize,
  );
}

/// A PNG or an `.ico`, decided by extension.
IconFile _imageFile(String packageRoot, File file) {
  if (p.extension(file.path).toLowerCase() != '.ico') {
    return _pngFile(packageRoot, file);
  }

  Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } catch (_) {
    return IconFile(
      path: p.relative(file.path, from: packageRoot),
      absolutePath: file.path,
      modified: _modified(file),
    );
  }

  var frames = readIcoFrames(bytes);
  return IconFile(
    path: p.relative(file.path, from: packageRoot),
    absolutePath: file.path,
    modified: _modified(file),
    width: frames.isEmpty ? null : frames.last,
    height: frames.isEmpty ? null : frames.last,
    // Every `.ico` frame can carry alpha; it says nothing about the artwork.
    icoFrames: frames,
  );
}

DateTime _modified(File file) {
  try {
    return file.lastModifiedSync();
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// What a PNG's IHDR chunk says.
class PngHeader {
  const PngHeader({
    required this.width,
    required this.height,
    required this.colorType,
    required this.hasTransparencyChunk,
  });

  final int width;
  final int height;

  /// 0 grey, 2 RGB, 3 palette, 4 grey+alpha, 6 RGBA.
  final int colorType;

  /// A `tRNS` chunk, which is how a palette image carries transparency.
  final bool hasTransparencyChunk;

  bool get hasAlpha => colorType == 4 || colorType == 6 || hasTransparencyChunk;
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Reads dimensions and colour type straight out of the header.
///
/// A valid PNG always puts IHDR first: 8-byte signature, 4-byte length, `IHDR`,
/// then width and height as big-endian 32-bit values, then bit depth and colour
/// type. Decoding a 1024×1024 image to learn how big it is would cost more than
/// the entire rest of the scan.
PngHeader? readPngHeader(Uint8List bytes) {
  if (bytes.length < 26) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }

  var data = ByteData.sublistView(bytes);
  return PngHeader(
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: bytes[25],
    hasTransparencyChunk: _hasChunk(bytes, 'tRNS'),
  );
}

/// Walks the chunk list looking for [type].
///
/// Bounded by the header scan it is used for: it stops at `IDAT`, because
/// everything that describes the image rather than carrying it comes first.
bool _hasChunk(Uint8List bytes, String type) {
  var data = ByteData.sublistView(bytes);
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    var length = data.getUint32(offset);
    var name = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (name == type) return true;
    if (name == 'IDAT') return false;
    offset += 12 + length;
  }
  return false;
}

/// The pixel sizes an `.ico` packs, ascending.
///
/// ICONDIR is a 6-byte header — reserved, type, count — then one 16-byte entry
/// per image, whose first byte is the width with zero meaning 256.
List<int> readIcoFrames(Uint8List bytes) {
  if (bytes.length < 6) return const [];
  var data = ByteData.sublistView(bytes);
  if (data.getUint16(0, Endian.little) != 0) return const [];
  if (data.getUint16(2, Endian.little) != 1) return const [];

  var count = data.getUint16(4, Endian.little);
  var frames = <int>[];
  for (var i = 0; i < count; i++) {
    var offset = 6 + i * 16;
    if (offset + 16 > bytes.length) break;
    var width = bytes[offset];
    frames.add(width == 0 ? 256 : width);
  }
  return frames..sort();
}
