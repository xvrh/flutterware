import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:standard_message_codec/standard_message_codec.dart';

import '../assets/model/asset_catalog.dart';
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
/// **Which keys resolve to which files is not decided here** — [AssetCatalog]
/// decides it, and the asset inspector reads the same answer. What is left in
/// this class is the encoding: manifests in the shapes the engine expects, and
/// a symlink per payload.
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

  Future<void> build(String output) async {
    var catalog = await AssetCatalog.resolve(
      rootPackageRoot: rootPackageRoot,
      packageConfigPath: packageConfigPath,
    );

    var dir = Directory(output);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    _writeManifests(output, catalog);
    _linkPayloads(output, catalog);
  }

  void _writeManifests(String output, AssetCatalog catalog) {
    var families = <Map<String, Object?>>[
      for (var family in catalog.fonts)
        {
          'family': family.family,
          'fonts': [
            for (var font in family.fonts)
              {
                'asset': font.key,
                if (font.weight != null) 'weight': font.weight,
                if (font.style != null) 'style': font.style,
              },
          ],
        },
    ];
    if (catalog.usesMaterialDesign) {
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
    for (var asset in catalog.assets) {
      manifest[asset.key] = [
        for (var file in asset.files) {'asset': file.key, 'dpr': ?file.scale},
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

  void _linkPayloads(String output, AssetCatalog catalog) {
    for (var asset in catalog.assets) {
      for (var file in asset.files) {
        _link(p.join(output, file.key), file.path);
      }
    }

    if (catalog.usesMaterialDesign) {
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
}
