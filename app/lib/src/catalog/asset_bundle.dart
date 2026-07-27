import 'dart:convert';
import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:standard_message_codec/standard_message_codec.dart';
import 'package:yaml/yaml.dart';

import '../embedder/flutter_cache.dart';

/// Assembles the asset directory the embedder guest reads, without invoking
/// `flutter build bundle`.
///
/// The tool's bundle costs seconds and is almost entirely waste for this use:
/// it compiles a kernel we immediately overwrite with the resident compiler's
/// output, aggregates licenses into a `NOTICES.Z` nothing here displays, and
/// copies megabytes that already exist in the SDK cache and the project tree.
/// Only ~230 bytes of it — three manifests — are genuinely produced.
///
/// So this writes the manifests and **symlinks every payload**. Two
/// consequences beyond speed:
///
/// - editing an asset in the project tree needs no rebundle, because the
///   bundle entry *is* the project's file;
/// - `NOTICES.Z` is simply absent, which the guest does not mind.
///
/// `tool/catalog/bundle_probe.dart` is the regression check: it renders the
/// same scene against this and against the tool's bundle and compares the
/// frames byte for byte.
class AssetBundleBuilder {
  AssetBundleBuilder({
    required this.cache,
    required this.rootPackageRoot,
    required this.packageConfigPath,
  });

  final FlutterCache cache;

  /// The package that owns the entrypoint being compiled. Its assets are
  /// keyed unprefixed; every other package's are keyed
  /// `packages/<name>/...`, which is how the engine resolves them.
  final String rootPackageRoot;

  final String packageConfigPath;

  /// `<key in the manifest>` -> `<absolute file on disk>`, main asset first and
  /// then its higher-density variants.
  final _assets = <String, List<String>>{};
  final _fontFamilies = <Map<String, Object?>>[];
  var _usesMaterialDesign = false;

  Future<void> build(String output) async {
    await _collect();

    var dir = Directory(output);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    _writeManifests(output);
    _linkPayloads(output);
  }

  Future<void> _collect() async {
    var config = await loadPackageConfig(File(packageConfigPath));

    // The root package first: its asset keys are unprefixed.
    _readPubspec(rootPackageRoot, packageName: null);

    for (var package in config.packages) {
      if (!package.root.isScheme('file')) continue;
      var root = p.fromUri(package.root);
      if (p.equals(root, rootPackageRoot)) continue;
      _readPubspec(root, packageName: package.name);
    }
  }

  void _readPubspec(String packageRoot, {required String? packageName}) {
    var file = File(p.join(packageRoot, 'pubspec.yaml'));
    if (!file.existsSync()) return;

    YamlMap? pubspec;
    try {
      pubspec = loadYaml(file.readAsStringSync()) as YamlMap?;
    } catch (_) {
      return; // A dependency with an unparseable pubspec is not our problem.
    }
    var flutter = pubspec?['flutter'];
    if (flutter is! YamlMap) return;

    if (flutter['uses-material-design'] == true) _usesMaterialDesign = true;

    var declared = flutter['assets'];
    if (declared is YamlList) {
      for (var entry in declared) {
        if (entry is String) {
          _addAsset(packageRoot, entry, packageName);
        } else if (entry is YamlMap && entry['path'] is String) {
          _addAsset(packageRoot, entry['path'] as String, packageName);
        }
      }
    }

    var fonts = flutter['fonts'];
    if (fonts is YamlList) _addFonts(packageRoot, fonts, packageName);
  }

  /// A declaration is either a file or, when it ends in `/`, every file
  /// directly inside that directory.
  void _addAsset(String packageRoot, String declaration, String? packageName) {
    String key(String relative) =>
        packageName == null ? relative : 'packages/$packageName/$relative';

    if (declaration.endsWith('/')) {
      var directory = Directory(p.join(packageRoot, declaration));
      if (!directory.existsSync()) return;
      for (var entity in directory.listSync()) {
        if (entity is! File) continue;
        var relative = p
            .split(p.relative(entity.path, from: packageRoot))
            .join('/');
        _register(key(relative), entity.path, packageRoot, relative, key);
      }
    } else {
      var file = File(p.join(packageRoot, declaration));
      if (!file.existsSync()) return;
      _register(key(declaration), file.path, packageRoot, declaration, key);
    }
  }

  /// Registers an asset plus any `2.0x/`-style density variants beside it.
  void _register(
    String manifestKey,
    String absolute,
    String packageRoot,
    String relative,
    String Function(String) key,
  ) {
    // A variant directory is itself listed when a whole directory is declared;
    // it must not become an entry of its own.
    if (_parseScale(relative) != null) return;

    var variants = [absolute];
    var directory = p.dirname(p.join(packageRoot, relative));
    var name = p.basename(relative);
    var parent = Directory(directory);
    if (parent.existsSync()) {
      for (var entity in parent.listSync().whereType<Directory>()) {
        if (_parseScale('${p.basename(entity.path)}/') == null) continue;
        var candidate = File(p.join(entity.path, name));
        if (candidate.existsSync()) variants.add(candidate.path);
      }
    }
    variants.sort();
    _assets[manifestKey] = variants;
  }

  void _addFonts(String packageRoot, YamlList fonts, String? packageName) {
    for (var family in fonts) {
      if (family is! YamlMap) continue;
      var name = family['family'];
      var declared = family['fonts'];
      if (name is! String || declared is! YamlList) continue;

      var entries = <Map<String, Object?>>[];
      for (var font in declared) {
        if (font is! YamlMap) continue;
        var asset = font['asset'];
        if (asset is! String) continue;
        var file = File(p.join(packageRoot, asset));
        if (!file.existsSync()) continue;

        var manifestKey = packageName == null
            ? asset
            : 'packages/$packageName/$asset';
        _assets.putIfAbsent(manifestKey, () => [file.path]);
        entries.add({
          'asset': manifestKey,
          if (font['weight'] != null) 'weight': font['weight'],
          if (font['style'] != null) 'style': font['style'],
        });
      }
      if (entries.isEmpty) continue;
      _fontFamilies.add({
        'family': packageName == null ? name : 'packages/$packageName/$name',
        'fonts': entries,
      });
    }
  }

  void _writeManifests(String output) {
    var families = [..._fontFamilies];
    if (_usesMaterialDesign) {
      families.add({
        'family': 'MaterialIcons',
        'fonts': [
          {'asset': 'fonts/MaterialIcons-Regular.otf'},
        ],
      });
    }
    File(
      p.join(output, 'FontManifest.json'),
    ).writeAsStringSync(jsonEncode(families));

    // Mirrors flutter_tools' asset.dart: a map of key -> list of
    // {asset, dpr?} entries, encoded with the standard message codec.
    var manifest = <String, Object?>{};
    for (var MapEntry(key: key, value: variants) in _assets.entries) {
      manifest[key] = [
        for (var variant in variants)
          {
            'asset': _keyFor(key, variant),
            'dpr': ?_parseScale(_keyFor(key, variant)),
          },
      ];
    }
    var encoded = const StandardMessageCodec().encodeMessage(manifest)!;
    File(
      p.join(output, 'AssetManifest.bin'),
    ).writeAsBytesSync(encoded.buffer.asUint8List(0, encoded.lengthInBytes));

    File(p.join(output, 'NativeAssetsManifest.json')).writeAsStringSync(
      jsonEncode({
        'format-version': [1, 0, 0],
        'native-assets': <String, Object?>{},
      }),
    );
  }

  /// The manifest key of one variant of [key] — the main asset keeps the key,
  /// a variant gets its density directory spliced back in.
  String _keyFor(String key, String absolute) {
    var scaleDir = p.basename(p.dirname(absolute));
    if (_parseScale('$scaleDir/') == null) return key;
    return '${p.dirname(key)}/$scaleDir/${p.basename(key)}';
  }

  void _linkPayloads(String output) {
    for (var MapEntry(key: key, value: variants) in _assets.entries) {
      for (var variant in variants) {
        _link(p.join(output, _keyFor(key, variant)), variant);
      }
    }

    if (_usesMaterialDesign) {
      _link(
        p.join(output, 'fonts', 'MaterialIcons-Regular.otf'),
        p.join(
          cache.cacheDir,
          'artifacts',
          'material_fonts',
          'MaterialIcons-Regular.otf',
        ),
      );
    }

    var src = p.join(cache.flutterRoot, 'packages', 'flutter', 'lib', 'src');
    _link(
      p.join(output, 'shaders', 'ink_sparkle.frag'),
      p.join(src, 'material', 'shaders', 'ink_sparkle.frag'),
    );
    _link(
      p.join(output, 'shaders', 'stretch_effect.frag'),
      p.join(src, 'widgets', 'shaders', 'stretch_effect.frag'),
    );

    _link(
      p.join(output, 'isolate_snapshot_data'),
      p.join(
        cache.cacheDir,
        'artifacts',
        'engine',
        'darwin-x64',
        'isolate_snapshot.bin',
      ),
    );
    // Empty in a JIT debug build, and the engine expects the file to exist.
    File(p.join(output, 'vm_snapshot_data')).writeAsBytesSync(const []);
  }

  void _link(String at, String target) {
    if (!File(target).existsSync()) return;
    Directory(p.dirname(at)).createSync(recursive: true);
    var link = Link(at);
    if (link.existsSync()) link.deleteSync();
    link.createSync(target);
  }

  /// `assets/2.0x/foo.png` -> 2.0. Null when the path has no density segment.
  static double? _parseScale(String path) {
    for (var segment in p.split(path)) {
      var match = RegExp(r'^(\d+(\.\d*)?)x$').firstMatch(segment);
      if (match != null) return double.tryParse(match.group(1)!);
    }
    return null;
  }
}
