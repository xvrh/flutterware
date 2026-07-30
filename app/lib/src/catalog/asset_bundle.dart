import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:standard_message_codec/standard_message_codec.dart';

import '../assets/model/asset_catalog.dart';
import '../embedder/flutter_cache.dart';
import '../utils/run_dir.dart';

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
/// The one payload that cannot be symlinked is the framework's fragment
/// shaders: the tool *compiles* those with `impellerc`, and
/// `FragmentProgram.fromAsset` parses the compiled bundle — handed the GLSL
/// source instead, it throws, which surfaces as a crash on the first tap of a
/// Material 3 button (the ink-sparkle ripple). They are compiled here with the
/// tool's exact invocation and cached per engine revision, so only the first
/// build after an SDK update pays the ~250ms per shader.
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
    await _linkCompiledShaders(output);
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

  /// The framework's default shaders — the M3 ink-sparkle ripple and the
  /// stretch-overscroll effect — bundled compiled, like the tool bundles them
  /// (unconditionally: whether they load is decided by the app's code, not its
  /// manifest).
  Future<void> _linkCompiledShaders(String output) async {
    var src = p.join(cache.flutterRoot, 'packages', 'flutter', 'lib', 'src');
    var sources = [
      p.join(src, 'material', 'shaders', 'ink_sparkle.frag'),
      p.join(src, 'widgets', 'shaders', 'stretch_effect.frag'),
    ];
    var cacheDir = p.join(flutterwareDir(), 'shaders', cache.engineRevision);
    await Future.wait([
      for (var source in sources)
        if (File(source).existsSync())
          _compiledShader(source, cacheDir).then(
            (compiled) =>
                _link(p.join(output, 'shaders', p.basename(source)), compiled),
          ),
    ]);
  }

  /// The compiled form of [source], produced on first use per engine revision.
  ///
  /// The invocation is flutter_tools' `ShaderCompiler` verbatim, for the
  /// target platform `flutter build bundle` defaults to — which is what makes
  /// the output byte-identical to the tool's, and it includes the SkSL variant
  /// the guest's Skia engine actually consumes.
  Future<String> _compiledShader(String source, String cacheDir) async {
    var compiled = p.join(cacheDir, p.basename(source));
    if (File(compiled).existsSync()) return compiled;
    Directory(cacheDir).createSync(recursive: true);
    // Compiled under a scratch name and renamed in: two builders racing on a
    // fresh cache each write their own scratch, and the renames — of identical
    // bytes — land whole either way.
    var scratch = '$compiled.$pid';
    var result = await Process.run(cache.impellerc, [
      '--sksl',
      '--runtime-stage-gles',
      '--runtime-stage-gles3',
      '--runtime-stage-vulkan',
      '--iplr',
      '--sl=$scratch',
      '--spirv=$scratch.spirv',
      '--input=$source',
      '--input-type=frag',
      '--include=${p.dirname(source)}',
      '--include=${cache.shaderLib}',
    ]);
    if (result.exitCode != 0) {
      throw StateError('impellerc failed on $source:\n${result.stderr}');
    }
    // A by-product nothing reads; the tool deletes it too.
    File('$scratch.spirv').deleteSync();
    File(scratch).renameSync(compiled);
    return compiled;
  }

  void _link(String at, String target) {
    if (!File(target).existsSync()) return;
    Directory(p.dirname(at)).createSync(recursive: true);
    var link = Link(at);
    if (link.existsSync()) link.deleteSync();
    link.createSync(target);
  }
}
