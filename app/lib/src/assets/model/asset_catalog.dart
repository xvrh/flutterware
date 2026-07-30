import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Every asset key a package's bundle resolves to, and the file behind each one.
///
/// This is Flutter's asset resolution written in plain Dart — no Flutter, no
/// `flutter_tools`, no build. It answers the only question that matters about
/// an asset: **what will `Image.asset('…')` find at run time**, which is not the
/// same question as what is on disk.
///
/// **Two consumers, and that is the point.** `AssetBundleBuilder` turns this
/// into the manifests the embedder guest reads; the asset inspector turns it
/// into what the panel, `fw` and MCP show. A second implementation would be a
/// second set of answers to "does this key resolve", and the one the user reads
/// would be the one nothing verifies. Here, the inspector is right exactly when
/// the guest renders.
///
/// What it deliberately does not do: [resolve] reads and parses, and nothing
/// else. No decoding, no hashing, no `flutter pub get` — that keeps it inside
/// `PluginCore.computeAll`'s budget, so every surface can call it freely.
///
/// Not yet handled, and absent rather than half-done: `flavors:` on an asset
/// entry, `transformers:`, and `.lottie` archives.
class AssetCatalog {
  AssetCatalog._({
    required this.assets,
    required this.declarations,
    required this.fonts,
    required this.usesMaterialDesign,
    required this.problems,
  });

  /// Resolved keys, in the order the engine's manifest lists them: the root
  /// package first — its keys are unprefixed — then each package in the config,
  /// and within a package its assets before its fonts.
  ///
  /// The order is load-bearing. `AssetManifest.bin` is an encoded map, and a
  /// reordering would rewrite every byte of it for no reason.
  final List<ResolvedAsset> assets;

  /// Every `assets:` entry that was read, resolved or not.
  ///
  /// Kept because the assets alone cannot answer "what did this project ask
  /// for": a directory declaration whose files all sit one level deeper
  /// produces no assets at all, and that is precisely the case worth reporting.
  final List<AssetDeclaration> declarations;

  final List<FontFamily> fonts;

  /// True when *any* package in the bundle asks for it, which is what pulls
  /// `MaterialIcons-Regular.otf` in.
  final bool usesMaterialDesign;

  /// What was declared and could not be resolved.
  ///
  /// Collected rather than skipped: a declaration that silently resolves to
  /// nothing is the single most common asset bug, and the old code's `return`
  /// on a missing file is exactly why nothing could report it. Includes
  /// problems found in dependencies — whose pubspecs are not the project's
  /// fault, which is why each one records the package it came from.
  final List<AssetProblem> problems;

  late final Map<String, ResolvedAsset> byKey = {
    for (var asset in assets) asset.key: asset,
  };

  /// Resolves the bundle for [rootPackageRoot] — its own assets, plus those of
  /// every package it actually depends on.
  ///
  /// **Depends on, not "is in the package config".** A config resolves imports,
  /// and in a pub workspace it resolves them for every member at once, so
  /// walking it would put a sibling app's assets in this app's bundle. It would
  /// pull in dev-dependencies too. `flutter_tools` filters the same way and
  /// says why in the same words — see `computeTransitiveDependencies` at
  /// `asset.dart:423` in 3.47.0-0.1.pre.
  ///
  /// Dev-dependencies are excluded outright, which is what a build does; the
  /// tool keeps a flag to include them when building a test bundle, and nothing
  /// here has asked for one.
  static Future<AssetCatalog> resolve({
    required String rootPackageRoot,
    required String packageConfigPath,
  }) async {
    var builder = _Resolver(rootPackageRoot);
    var config = await loadPackageConfig(File(packageConfigPath));

    // The root package first: its asset keys are unprefixed.
    builder.readPubspec(rootPackageRoot, packageName: null);

    var reachable = builder.dependenciesOf(rootPackageRoot, config);
    // Config order rather than discovery order, so the manifest a bundle writes
    // stays stable as dependencies are added and removed.
    for (var package in config.packages) {
      if (!package.root.isScheme('file')) continue;
      if (!reachable.contains(package.name)) continue;
      // Normalised because a package config's root always ends in a slash, and
      // this path is handed out on every asset as `ResolvedAsset.packageRoot`.
      var root = p.normalize(p.fromUri(package.root));
      if (p.equals(root, rootPackageRoot)) continue;
      builder.readPubspec(root, packageName: package.name);
    }

    return AssetCatalog._(
      assets: builder.assets.values.toList(),
      declarations: builder.declarations,
      fonts: builder.fonts,
      usesMaterialDesign: builder.usesMaterialDesign,
      problems: builder.problems,
    );
  }

  /// `assets/2.0x/foo.png` -> 2.0. Null when the path has no density segment.
  static double? parseScale(String path) {
    for (var segment in p.split(path)) {
      var match = _densityDirectory.firstMatch(segment);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }
}

/// A density directory: `2.0x`, and equally `3x` or `2.7x`. **Not** `dark` —
/// there is no such thing as a theme variant, whatever a directory beside an
/// asset happens to be called.
///
/// `flutter_tools` spells this `RegExp(r'/?(\d+(\.\d*)?)x$')`
/// (`asset.dart:111` and `:935` in 3.47.0-0.1.pre, whose own comment offers
/// `plants/3x` as a match), and this must keep agreeing with it — a disagreement
/// here is a bundle whose `dpr` values differ from the tool's.
///
/// Two deliberate differences, both narrowing:
///
/// - anchored, so a directory named `foo2x` is not a variant directory here
///   while `flutter_tools`' suffix match accepts it;
/// - matched against every path segment rather than only the key's immediate
///   parent, which is what `_createAssetManifestBinary` inspects.
final _densityDirectory = RegExp(r'^(\d+(\.\d*)?)x$');

/// One asset key, and every file that serves it.
class ResolvedAsset {
  ResolvedAsset({
    required this.key,
    required this.package,
    required this.packageRoot,
    required this.declaration,
    required this.files,
  });

  /// What `Image.asset` is given: `assets/logo.png` for the root package,
  /// `packages/<name>/assets/logo.png` for anything else.
  final String key;

  /// The package that declared it, or null for the root package — whose assets
  /// are the only unprefixed ones.
  final String? package;

  /// Absolute path to [package]'s root, so a reader can make [files] relative
  /// to something a human recognises.
  final String packageRoot;

  /// The pubspec entry that pulled this in — `assets/images/` for a directory
  /// declaration, the path itself for a file one.
  ///
  /// Kept because "why is this in my bundle" is a question about the
  /// declaration, not the file, and a directory declaration is answerable no
  /// other way.
  final String declaration;

  /// The main asset and its density variants, in manifest order.
  final List<AssetFile> files;

  /// The file used at 1× — the one the key names directly.
  AssetFile get main =>
      files.firstWhere((f) => f.scale == null, orElse: () => files.first);

  /// The density variants found beside [main].
  Iterable<AssetFile> get variants => files.where((f) => f.scale != null);

  bool get isFont => _fontExtensions.contains(p.extension(key).toLowerCase());

  int get totalBytes {
    var total = 0;
    for (var file in files) {
      total += file.length;
    }
    return total;
  }

  @override
  String toString() => 'ResolvedAsset($key, ${files.length} file(s))';
}

const _fontExtensions = {'.ttf', '.otf', '.ttc', '.woff', '.woff2'};

/// One `assets:` entry, as the pubspec wrote it.
class AssetDeclaration {
  AssetDeclaration({
    required this.package,
    required this.packageRoot,
    required this.path,
  });

  /// The package that declared it; null for the root package.
  final String? package;

  final String packageRoot;

  /// Verbatim, trailing slash included — which is the part that decides whether
  /// this names one file or the files directly inside a directory.
  final String path;

  bool get isDirectory => path.endsWith('/');
}

/// One file behind an asset key.
class AssetFile {
  AssetFile({
    required this.path,
    required this.key,
    required this.scale,
    int? length,
    // Not an initializing formal: the field is the lazy cache behind `length`,
    // and a named parameter cannot be spelled `_length`.
    // ignore: prefer_initializing_formals
  }) : _length = length;

  /// Absolute path on disk.
  final String path;

  /// This file's own manifest key. Equal to the asset's key for the main file;
  /// a variant splices its density directory back in.
  final String key;

  /// The density this file serves, or null for the main asset.
  final double? scale;

  /// Size in bytes, `stat`ed on first ask and remembered.
  ///
  /// Can be supplied instead, which is what lets a catalog demo build an asset
  /// that never existed. The resolver never passes it: a file it registered is
  /// a file it found, so the stat cannot fail.
  int get length => _length ??= File(path).lengthSync();
  int? _length;

  @override
  String toString() => 'AssetFile($key${scale == null ? '' : ' @${scale}x'})';
}

/// A font family, as the engine's `FontManifest.json` describes it.
class FontFamily {
  FontFamily({
    required this.family,
    required this.package,
    required this.fonts,
  });

  /// Already package-prefixed, the way the manifest carries it.
  final String family;

  final String? package;
  final List<FontAsset> fonts;

  @override
  String toString() => 'FontFamily($family, ${fonts.length} font(s))';
}

class FontAsset {
  FontAsset({
    required this.key,
    required this.path,
    required this.weight,
    required this.style,
  });

  /// The asset key of the font file — fonts are assets too, and appear in
  /// [AssetCatalog.assets] under this key.
  final String key;

  /// Absolute path on disk.
  final String path;

  /// What the pubspec *claims*. Whether the file agrees is a different
  /// question, and not one this class asks.
  final int? weight;
  final String? style;
}

enum AssetProblemKind {
  missingFile('Declared, and not on disk.'),
  missingDirectory('Declared directory does not exist.'),
  malformedDeclaration('Not a path.'),
  missingFontFile('Font file declared, and not on disk.'),
  malformedFontEntry('Font entry is unusable and was dropped.'),
  unreadablePubspec('The pubspec could not be parsed.');

  const AssetProblemKind(this.summary);

  final String summary;
}

/// Something declared that resolves to nothing.
class AssetProblem {
  AssetProblem({
    required this.kind,
    required this.package,
    required this.packageRoot,
    required this.declaration,
    this.detail,
  });

  final AssetProblemKind kind;

  /// The package whose pubspec declared it; null for the root package.
  final String? package;

  final String packageRoot;

  /// What the pubspec said — the path, or the family for a font problem.
  final String declaration;

  /// The underlying error, where there was one.
  final String? detail;

  @override
  String toString() =>
      '${kind.summary} ${package == null ? '' : '[$package] '}$declaration';
}

/// Accumulates one bundle's resolution.
///
/// Separate from [AssetCatalog] so the catalog itself is immutable, and so the
/// map semantics stay visible: a re-registered key **overwrites in place**
/// (keeping its original position), while a font file already registered as an
/// asset keeps the registration it had. Both match what the engine's manifest
/// used to be built from, and both are why this is a map rather than a list.
class _Resolver {
  _Resolver(this.rootPackageRoot);

  final String rootPackageRoot;

  final assets = <String, ResolvedAsset>{};
  final declarations = <AssetDeclaration>[];
  final fonts = <FontFamily>[];
  final problems = <AssetProblem>[];
  var usesMaterialDesign = false;

  /// Every package [packageRoot] depends on, transitively, by name.
  ///
  /// `dependencies:` only. A dev-dependency reached no other way is not in the
  /// bundle, and the walk is what keeps a pub workspace's other members out of
  /// it — they are in the config, and they are not dependencies.
  Set<String> dependenciesOf(String packageRoot, PackageConfig config) {
    var seen = <String>{};
    var queue = [..._declaredDependencies(packageRoot)];
    while (queue.isNotEmpty) {
      var name = queue.removeLast();
      if (!seen.add(name)) continue;
      var package = config[name];
      if (package == null || !package.root.isScheme('file')) continue;
      queue.addAll(_declaredDependencies(p.normalize(p.fromUri(package.root))));
    }
    return seen;
  }

  Iterable<String> _declaredDependencies(String packageRoot) {
    var declared = _pubspecAt(packageRoot)?['dependencies'];
    if (declared is! YamlMap) return const [];
    return [
      for (var name in declared.keys)
        if (name is String) name,
    ];
  }

  /// Parsed once per package: the dependency walk and the asset read both want
  /// it, and a pubspec is read for every package in the bundle.
  YamlMap? _pubspecAt(String packageRoot) {
    if (_pubspecs.containsKey(packageRoot)) return _pubspecs[packageRoot];

    YamlMap? parsed;
    var file = File(p.join(packageRoot, 'pubspec.yaml'));
    if (file.existsSync()) {
      try {
        parsed = loadYaml(file.readAsStringSync()) as YamlMap?;
      } catch (e) {
        _unreadable[packageRoot] = '$e';
      }
    }
    return _pubspecs[packageRoot] = parsed;
  }

  final _pubspecs = <String, YamlMap?>{};
  final _unreadable = <String, String>{};

  void readPubspec(String packageRoot, {required String? packageName}) {
    var pubspec = _pubspecAt(packageRoot);
    if (_unreadable[packageRoot] case var error?) {
      problems.add(
        AssetProblem(
          kind: AssetProblemKind.unreadablePubspec,
          package: packageName,
          packageRoot: packageRoot,
          declaration: 'pubspec.yaml',
          detail: error,
        ),
      );
      return;
    }
    if (pubspec == null) return;

    var flutter = pubspec['flutter'];
    if (flutter is! YamlMap) return;

    if (flutter['uses-material-design'] == true) usesMaterialDesign = true;

    var declared = flutter['assets'];
    if (declared is YamlList) {
      for (var entry in declared) {
        if (entry is String) {
          _addAsset(packageRoot, entry, packageName);
        } else if (entry is YamlMap && entry['path'] is String) {
          _addAsset(packageRoot, entry['path'] as String, packageName);
        } else {
          problems.add(
            AssetProblem(
              kind: AssetProblemKind.malformedDeclaration,
              package: packageName,
              packageRoot: packageRoot,
              declaration: '$entry',
            ),
          );
        }
      }
    }

    var declaredFonts = flutter['fonts'];
    if (declaredFonts is YamlList) {
      _addFonts(packageRoot, declaredFonts, packageName);
    }
  }

  /// A declaration is either a file or, when it ends in `/`, every file
  /// **directly** inside that directory.
  ///
  /// Not recursive, and that is Flutter's rule rather than a shortcut here:
  /// declaring `assets/` leaves `assets/icons/star.png` out of the bundle while
  /// leaving it plainly visible on disk. `examples/example` carries a fixture
  /// for it.
  void _addAsset(String packageRoot, String declaration, String? packageName) {
    declarations.add(
      AssetDeclaration(
        package: packageName,
        packageRoot: packageRoot,
        path: declaration,
      ),
    );

    String key(String relative) =>
        packageName == null ? relative : 'packages/$packageName/$relative';

    if (declaration.endsWith('/')) {
      var directory = Directory(p.join(packageRoot, declaration));
      if (!directory.existsSync()) {
        problems.add(
          AssetProblem(
            kind: AssetProblemKind.missingDirectory,
            package: packageName,
            packageRoot: packageRoot,
            declaration: declaration,
          ),
        );
        return;
      }
      for (var entity in directory.listSync()) {
        if (entity is! File) continue;
        var relative = p
            .split(p.relative(entity.path, from: packageRoot))
            .join('/');
        _register(
          key(relative),
          entity.path,
          packageRoot,
          relative,
          key,
          packageName,
          declaration,
        );
      }
    } else {
      var file = File(p.join(packageRoot, declaration));
      if (!file.existsSync()) {
        problems.add(
          AssetProblem(
            kind: AssetProblemKind.missingFile,
            package: packageName,
            packageRoot: packageRoot,
            declaration: declaration,
          ),
        );
        return;
      }
      _register(
        key(declaration),
        file.path,
        packageRoot,
        declaration,
        key,
        packageName,
        declaration,
      );
    }
  }

  /// Registers an asset plus any `2.0x/`-style density variants beside it.
  void _register(
    String manifestKey,
    String absolute,
    String packageRoot,
    String relative,
    String Function(String) key,
    String? packageName,
    String declaration,
  ) {
    // A variant directory is itself listed when a whole directory is declared;
    // it must not become an entry of its own.
    if (AssetCatalog.parseScale(relative) != null) return;

    var paths = [absolute];
    var directory = p.dirname(p.join(packageRoot, relative));
    var name = p.basename(relative);
    var parent = Directory(directory);
    if (parent.existsSync()) {
      for (var entity in parent.listSync().whereType<Directory>()) {
        if (AssetCatalog.parseScale('${p.basename(entity.path)}/') == null) {
          continue;
        }
        var candidate = File(p.join(entity.path, name));
        if (candidate.existsSync()) paths.add(candidate.path);
      }
    }
    paths.sort();

    assets[manifestKey] = ResolvedAsset(
      key: manifestKey,
      package: packageName,
      packageRoot: packageRoot,
      declaration: declaration,
      files: [
        for (var path in paths)
          AssetFile(
            path: path,
            key: _keyFor(manifestKey, path),
            scale: AssetCatalog.parseScale(_keyFor(manifestKey, path)),
          ),
      ],
    );
  }

  void _addFonts(String packageRoot, YamlList declared, String? packageName) {
    for (var family in declared) {
      if (family is! YamlMap) continue;
      var name = family['family'];
      var declaredFonts = family['fonts'];
      if (name is! String || declaredFonts is! YamlList) continue;

      var entries = <FontAsset>[];
      for (var font in declaredFonts) {
        if (font is! YamlMap) continue;
        var asset = font['asset'];
        if (asset is! String) continue;
        var file = File(p.join(packageRoot, asset));
        if (!file.existsSync()) {
          problems.add(
            AssetProblem(
              kind: AssetProblemKind.missingFontFile,
              package: packageName,
              packageRoot: packageRoot,
              declaration: asset,
              detail: 'Declared by family "$name".',
            ),
          );
          continue;
        }

        var manifestKey = packageName == null
            ? asset
            : 'packages/$packageName/$asset';
        // A font file already registered as an asset keeps that registration:
        // it carries the declaration that pulled it in, and this one would say
        // only that a font pointed at it.
        assets.putIfAbsent(
          manifestKey,
          () => ResolvedAsset(
            key: manifestKey,
            package: packageName,
            packageRoot: packageRoot,
            declaration: asset,
            files: [AssetFile(path: file.path, key: manifestKey, scale: null)],
          ),
        );

        // `weight` and `style` are dropped rather than passed through when the
        // pubspec gives them a type the manifest cannot carry. The old code
        // forwarded whatever YAML held, which differs only for a pubspec
        // `flutter_tools` itself rejects — and silently produced a font
        // descriptor the engine cannot read.
        var weight = font['weight'];
        var style = font['style'];
        if ((weight != null && weight is! int) ||
            (style != null && style is! String)) {
          problems.add(
            AssetProblem(
              kind: AssetProblemKind.malformedFontEntry,
              package: packageName,
              packageRoot: packageRoot,
              declaration: asset,
              detail:
                  'Family "$name" declares weight=$weight style=$style; '
                  'weight must be a number and style a string.',
            ),
          );
        }
        entries.add(
          FontAsset(
            key: manifestKey,
            path: file.path,
            weight: weight is int ? weight : null,
            style: style is String ? style : null,
          ),
        );
      }
      if (entries.isEmpty) continue;
      fonts.add(
        FontFamily(
          family: packageName == null ? name : 'packages/$packageName/$name',
          package: packageName,
          fonts: entries,
        ),
      );
    }
  }

  /// The manifest key of one variant of [key] — the main asset keeps the key,
  /// a variant gets its density directory spliced back in.
  String _keyFor(String key, String absolute) {
    var scaleDir = p.basename(p.dirname(absolute));
    if (AssetCatalog.parseScale('$scaleDir/') == null) return key;
    return '${p.dirname(key)}/$scaleDir/${p.basename(key)}';
  }
}
