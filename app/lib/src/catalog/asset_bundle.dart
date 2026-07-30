import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:standard_message_codec/standard_message_codec.dart';

import '../assets/model/asset_catalog.dart';
import '../embedder/flutter_cache.dart';
import '../utils/run_dir.dart';

/// What one [AssetBundleBuilder.build] did to the directory, so a caller can
/// decide whether anyone needs telling.
///
/// [fontsChanged] is separate because fonts need more than cache eviction:
/// the engine registers `FontManifest.json` when it starts, so a changed one
/// reaches a *running* guest only through heavier means than a repaint.
typedef BundleSync = ({bool changed, bool fontsChanged});

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
/// The one payload that cannot be symlinked to its source is the framework's
/// fragment shaders: the tool *compiles* those with `impellerc`, and
/// `FragmentProgram.fromAsset` parses the compiled bundle — handed the GLSL
/// source instead, it throws, which surfaces as a crash on the first tap of a
/// Material 3 button (the ink-sparkle ripple). They are compiled here with the
/// tool's exact invocation and cached per engine revision, so only the first
/// build after an SDK update pays the ~250ms per shader.
///
/// **In place, and never delete-and-recreate.** The engine opens every asset
/// relative to a file descriptor of this directory, so replacing the
/// directory makes a *running* guest unable to load anything — measured in
/// the 2026-07-30 mid-session spike as `Unable to load asset:
/// "AssetManifest.bin"` from a guest that kept innocently rendering its old
/// scene. A rebuild therefore updates the existing inode: manifests are
/// rewritten only when their bytes moved, links only when their target moved,
/// and whatever a previous build owned that this one does not is pruned.
/// `kernel_blob.bin` is the one entry the builder never owns — the daemon
/// puts it there, and deleting it would leave every attaching session a
/// dangling kernel.
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

  Future<BundleSync> build(String output) async {
    var catalog = await AssetCatalog.resolve(
      rootPackageRoot: rootPackageRoot,
      packageConfigPath: packageConfigPath,
    );

    Directory(output).createSync(recursive: true);

    var sync = _Sync();
    _writeManifests(output, catalog, sync);
    _linkPayloads(output, catalog, sync);
    await _linkCompiledShaders(output, sync);
    _prune(output, sync);
    return (changed: sync.changed, fontsChanged: sync.fontsChanged);
  }

  void _writeManifests(String output, AssetCatalog catalog, _Sync sync) {
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
    if (_write(
      output,
      'FontManifest.json',
      utf8.encode(jsonEncode(families)),
      sync,
    )) {
      sync.fontsChanged = true;
    }

    // Mirrors flutter_tools' asset.dart: a map of key -> list of
    // {asset, dpr?} entries, encoded with the standard message codec.
    var manifest = <String, Object?>{};
    for (var asset in catalog.assets) {
      manifest[asset.key] = [
        for (var file in asset.files) {'asset': file.key, 'dpr': ?file.scale},
      ];
    }
    var encoded = const StandardMessageCodec().encodeMessage(manifest)!;
    _write(
      output,
      'AssetManifest.bin',
      encoded.buffer.asUint8List(0, encoded.lengthInBytes),
      sync,
    );

    _write(
      output,
      'NativeAssetsManifest.json',
      utf8.encode(
        jsonEncode({
          'format-version': [1, 0, 0],
          'native-assets': <String, Object?>{},
        }),
      ),
      sync,
    );

    // Empty in a JIT debug build, and the engine expects the file to exist.
    _write(output, 'vm_snapshot_data', Uint8List(0), sync);
  }

  void _linkPayloads(String output, AssetCatalog catalog, _Sync sync) {
    for (var asset in catalog.assets) {
      for (var file in asset.files) {
        _link(output, file.key, file.path, sync);
      }
    }

    if (catalog.usesMaterialDesign) {
      _link(
        output,
        'fonts/MaterialIcons-Regular.otf',
        p.join(
          cache.cacheDir,
          'artifacts',
          'material_fonts',
          'MaterialIcons-Regular.otf',
        ),
        sync,
      );
    }

    _link(
      output,
      'isolate_snapshot_data',
      p.join(
        cache.cacheDir,
        'artifacts',
        'engine',
        'darwin-x64',
        'isolate_snapshot.bin',
      ),
      sync,
    );
  }

  /// The framework's default shaders — the M3 ink-sparkle ripple and the
  /// stretch-overscroll effect — bundled compiled, like the tool bundles them
  /// (unconditionally: whether they load is decided by the app's code, not its
  /// manifest).
  Future<void> _linkCompiledShaders(String output, _Sync sync) async {
    var src = p.join(cache.flutterRoot, 'packages', 'flutter', 'lib', 'src');
    var sources = [
      for (var source in [
        p.join(src, 'material', 'shaders', 'ink_sparkle.frag'),
        p.join(src, 'widgets', 'shaders', 'stretch_effect.frag'),
      ])
        if (File(source).existsSync()) source,
    ];
    // Nothing to compile means no engine revision to read — which is also
    // what lets a test run this against a cache directory that is not an SDK.
    if (sources.isEmpty) return;
    var cacheDir = p.join(flutterwareDir(), 'shaders', cache.engineRevision);
    await Future.wait([
      for (var source in sources)
        _compiledShader(source, cacheDir).then(
          (compiled) =>
              _link(output, 'shaders/${p.basename(source)}', compiled, sync),
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

  /// Writes [bytes] at [relative] when they differ from what is there.
  ///
  /// Returns whether it wrote. Comparing first is not an optimisation: the
  /// unchanged rebundle is the common case once this runs on every refresh,
  /// and "nothing changed" is an answer [build] promises to get right.
  bool _write(String output, String relative, List<int> bytes, _Sync sync) {
    sync.desired.add(relative);
    var file = File(p.join(output, relative));
    if (file.existsSync()) {
      var existing = file.readAsBytesSync();
      if (existing.length == bytes.length) {
        var same = true;
        for (var i = 0; i < bytes.length; i++) {
          if (existing[i] != bytes[i]) {
            same = false;
            break;
          }
        }
        if (same) return false;
      }
    }
    file.writeAsBytesSync(bytes);
    sync.changed = true;
    return true;
  }

  /// Points [relative] at [target], replacing whatever held the name.
  ///
  /// A link already pointing there is left alone — its mtime is nothing, but
  /// leaving it is what makes the no-change rebundle report no change.
  void _link(String output, String relative, String target, _Sync sync) {
    if (!File(target).existsSync()) return;
    sync.desired.add(relative);
    var at = p.join(output, relative);
    var link = Link(at);
    if (link.existsSync()) {
      if (link.targetSync() == target) return;
      link.deleteSync();
    } else if (File(at).existsSync()) {
      // A regular file squatting on the name — a hand-copied payload, or a
      // build that predates the symlink scheme.
      File(at).deleteSync();
    }
    Directory(p.dirname(at)).createSync(recursive: true);
    link.createSync(target);
    sync.changed = true;
  }

  /// Deletes what a previous build owned and this one does not.
  ///
  /// Files and links only; an emptied directory is harmless and the engine
  /// may be holding any of them open. `kernel_blob.bin` is spared — it is the
  /// daemon's, not this builder's.
  void _prune(String output, _Sync sync) {
    var root = Directory(output);
    for (var entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) continue;
      var relative = p.split(p.relative(entity.path, from: output)).join('/');
      if (relative == 'kernel_blob.bin') continue;
      if (sync.desired.contains(relative)) continue;
      entity.deleteSync();
      sync.changed = true;
    }
  }
}

class _Sync {
  /// Relative paths this build owns, `/`-separated like manifest keys.
  final desired = <String>{};
  var changed = false;
  var fontsChanged = false;
}
