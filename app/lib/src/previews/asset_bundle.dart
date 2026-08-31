import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hooks_runner/hooks_runner.dart'
    show KernelAsset, KernelAssetAbsolutePath, KernelAssets;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:standard_message_codec/standard_message_codec.dart';

import '../assets/build_hooks.dart';
import '../assets/model/asset_catalog.dart';
import '../embedder/flutter_cache.dart';
import '../utils/run_dir.dart';
import 'asset_transformer.dart';

/// What one [AssetBundleBuilder.build] did to the directory, so a caller can
/// decide whether anyone needs telling.
///
/// [fontsChanged] is separate because fonts need more than cache eviction:
/// the engine registers `FontManifest.json` when it starts, so a changed one
/// reaches a *running* guest only through heavier means than a repaint.
typedef BundleSync = ({bool changed, bool fontsChanged});

/// The backends `impellerc` writes runtime stage data for: the **union** of
/// every stage list flutter_tools has, in its order.
///
/// A union rather than one of them because one artifact serves two lanes and
/// they do not agree. `flutter build bundle` compiles for a single target and
/// ships stages only that target can use — `ShaderCompiler` in flutter_tools
/// gives desktop-GL hosts `sksl/gles/gles3/vulkan` and macOS `sksl/metal` —
/// where the file cached here is loaded by a `flutter_tester` on the host's own
/// backend *and* by the embedder guest, which on macOS is Metal and nowhere
/// else is. Compiling per target would mean a cache entry per lane; compiling
/// every stage once costs ~250ms more and loads everywhere.
///
/// A list of its own because it is half of the cache key: the compiled bytes
/// are decided by the engine revision *and* by this, and a stage added here
/// has to invalidate what an earlier flutterware left on the machine. Once, it
/// did not. `--runtime-stage-metal` was added to fix an entry dying on *"does
/// not contain appropriate runtime stage data for current backend (Metal)"*,
/// and every machine that had already compiled these shaders for its engine
/// revision — which is every machine that had run previews once — kept serving
/// the four-stage file and kept dying in exactly the same words.
const shaderStages = [
  '--sksl',
  '--runtime-stage-gles',
  '--runtime-stage-gles3',
  '--runtime-stage-vulkan',
  '--runtime-stage-metal',
];

/// [shaderStages] as a directory-name fragment, so editing that list is the
/// whole of invalidating the cache.
final _stagesKey = sha1
    .convert(utf8.encode(shaderStages.join(' ')))
    .toString()
    .substring(0, 8);

/// Distinguishes one in-process shader compile from another, so two that
/// overlap do not write one scratch file. See `_compiledShader`.
var _scratchSerial = 0;

/// Where bundled native libraries land inside the bundle, flat.
///
/// One directory, plain basenames, mirroring `flutter test`'s
/// `build/native_assets/<os>/` for the two properties that layout buys: a
/// dylib that references a sibling through `@loader_path` finds it, and on
/// Windows there is a single directory to put on the tester's `PATH` so a
/// DLL's own dependencies resolve.
const nativeAssetsDirName = 'native_assets';

/// The framework's own fragment shaders in [cache]'s checkout — the M3
/// ink-sparkle ripple and the stretch-overscroll effect — as they exist.
///
/// Empty for a cache directory that is not a Flutter checkout, which is what
/// lets a test build a bundle against a fixture.
List<String> frameworkShaderSources(FlutterCache cache) {
  var src = p.join(cache.flutterRoot, 'packages', 'flutter', 'lib', 'src');
  return [
    for (var source in [
      p.join(src, 'material', 'shaders', 'ink_sparkle.frag'),
      p.join(src, 'widgets', 'shaders', 'stretch_effect.frag'),
    ])
      if (File(source).existsSync()) source,
  ];
}

/// Runs `impellerc` over the GLSL at [source], writing the compiled form —
/// what `FragmentProgram.fromAsset` parses — to [destination].
///
/// The invocation is flutter_tools' `ShaderCompiler`, down to the include paths
/// and the `.spirv` by-product it produces and deletes; [stages] is the one
/// thing a caller chooses, because the tool picks a set per target platform and
/// [shaderStages] is the union of them.
///
/// Written to a scratch name and renamed in, so a reader of [destination] sees
/// whole bytes or none. The scratch carries a serial as well as the pid: two
/// builders race *inside* one process as readily as across two — the comparison
/// runner lists both sides at once, a `TesterHost` and its bundle each — and a
/// scratch named for the process alone is one path two invocations write at the
/// same time. A cold cache is the only time either compiles, which used to mean
/// a fresh machine and now means the first run after any change to [stages].
Future<void> compileShader({
  required FlutterCache cache,
  required String source,
  required String destination,
  required List<String> stages,
}) async {
  var scratch = '$destination.$pid.${_scratchSerial++}';
  var result = await Process.run(cache.impellerc, [
    ...stages,
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
  File(scratch).renameSync(destination);
}

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
/// Two kinds of payload cannot be symlinked to their source, and both are the
/// same shape: something compiles them, and the loader on the other side parses
/// the compiled form. (A third is copied for a different reason entirely —
/// see `_installNativeAssets`: a native library must be an inode nothing but
/// this builder ever rewrites.)
///
/// An asset the project declared with `transformers:` is the project's own
/// case. A build runs the chain and ships the output under the declared key, so
/// linking the source resolves the key to bytes no app ever sees —
/// `AssetBundleBuilder` runs the same chain and links the output, content-cached
/// so an unchanged asset never pays twice. See [AssetTransformerRunner].
///
/// The other is the framework's
/// fragment shaders: the tool *compiles* those with `impellerc`, and
/// `FragmentProgram.fromAsset` parses the compiled bundle — handed the GLSL
/// source instead, it throws, which surfaces as a crash on the first tap of a
/// Material 3 button (the ink-sparkle ripple). They are compiled here by
/// [compileShader] and cached per engine revision and stage list, so only the
/// first build after an SDK update pays the ~250ms per shader. The invocation
/// is flutter_tools' `ShaderCompiler`, but for [shaderStages] rather than for
/// one target platform's — so the bytes are deliberately *not* the tool's, and
/// `tool/catalog/bundle_probe.dart` says so in those terms rather than
/// demanding they match.
///
/// In place, and never delete-and-recreate. The engine opens every asset
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
/// Which keys resolve to which files is not decided here — [AssetCatalog]
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
    this.nativeAssetsForTesting,
  });

  final FlutterCache cache;

  /// Stands in for the hooks run's native assets, so a test can exercise the
  /// install without a fixture that resolves and builds a real hook. Non-null
  /// skips the hooks run entirely.
  @visibleForTesting
  final List<KernelAsset>? nativeAssetsForTesting;

  /// The package that owns the entrypoint being compiled. Its assets are
  /// keyed unprefixed; every other package's are keyed
  /// `packages/<name>/...`, which is how the engine resolves them.
  final String rootPackageRoot;

  final String packageConfigPath;

  Future<BundleSync> build(String output) async {
    // Before the catalog, not after it: a hook that generates assets writes
    // them into a directory its pubspec declares, and [AssetCatalog] lists that
    // directory's contents as it resolves. Run second and the catalog is a
    // faithful reading of an empty directory.
    // The failure is deliberately not acted on: a hook is a program a
    // *dependency* ships, so one that fails is closer to a compile error in
    // that dependency than to a broken catalog, and every entry that did not
    // need its output still builds. [BuildHooks] says so on stderr itself,
    // because the logger is not listened to in the two processes that call
    // this most. What *is* consumed is the native-assets mapping, below.
    List<KernelAsset> nativeAssets;
    if (nativeAssetsForTesting case var overridden?) {
      nativeAssets = overridden;
    } else {
      var hooks = await BuildHooks(
        dartExecutable: cache.dart,
        packageConfigPath: packageConfigPath,
        rootPackageRoot: rootPackageRoot,
      ).run();
      nativeAssets = hooks.nativeAssets;
    }

    var catalog = await AssetCatalog.resolve(
      rootPackageRoot: rootPackageRoot,
      packageConfigPath: packageConfigPath,
    );

    Directory(output).createSync(recursive: true);

    var sync = _Sync();
    var nativeAssetsManifest = _installNativeAssets(output, nativeAssets, sync);
    _writeManifests(output, catalog, nativeAssetsManifest, sync);
    _linkPayloads(output, catalog, await _transformed(catalog), sync);
    await _linkCompiledShaders(output, sync);
    _prune(output, sync);
    return (changed: sync.changed, fontsChanged: sync.fontsChanged);
  }

  /// Where each transformed file's bytes actually are, keyed by the file's own
  /// path — empty when nothing in the catalog declares a transformer, which is
  /// the ordinary project and costs one `isEmpty` check.
  ///
  /// Run here rather than inside [_linkPayloads] because it is the one part
  /// of a bundle build that is neither cheap nor synchronous: a cold cache
  /// spawns a process per asset. Pooled [AssetTransformerRunner.concurrency]
  /// wide, so a catalog of 21 vectors costs ~0.7s once instead of ~2.5s, and
  /// nothing on a warm cache.
  Future<Map<String, String>> _transformed(AssetCatalog catalog) async {
    var work = [
      for (var asset in catalog.assets)
        if (asset.transformers.isNotEmpty)
          for (var file in asset.files) (file, asset.transformers),
    ];
    if (work.isEmpty) return const {};

    var runner = AssetTransformerRunner(
      dart: cache.dart,
      projectRoot: rootPackageRoot,
      packageConfigPath: packageConfigPath,
    );
    var transformed = <String, String>{};
    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= work.length) return;
        var (file, chain) = work[index++];
        transformed[file.path] = await runner.pathFor(file, chain);
      }
    }

    await Future.wait([
      for (var i = 0; i < AssetTransformerRunner.concurrency; i++) worker(),
    ]);
    return transformed;
  }

  void _writeManifests(
    String output,
    AssetCatalog catalog,
    String nativeAssetsManifest,
    _Sync sync,
  ) {
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

    // The map the VM resolves `@Native` external functions through, produced
    // by the hooks run above — where a scenario's `sqlite3` finds its dylib.
    // Same channel `flutter test` uses: it copies this file into the test
    // asset directory, and the engine reads it from `--flutter-assets-dir`.
    _write(
      output,
      'NativeAssetsManifest.json',
      utf8.encode(nativeAssetsManifest),
      sync,
    );

    // Empty in a JIT debug build, and the engine expects the file to exist.
    _write(output, 'vm_snapshot_data', Uint8List(0), sync);
  }

  /// Brings the hook-built native libraries into the bundle and returns the
  /// `NativeAssetsManifest.json` content that names them there.
  ///
  /// A **copy**, where every other payload is a symlink, because the file a
  /// guest `dlopen`s must be one nothing else rewrites: the hook's own output
  /// under `.dart_tool/hooks_runner` is rewritten in place by any tool that
  /// re-runs the hook on this checkout — `flutter test` in another terminal, a
  /// package author editing their hook — and on macOS mutating a mapped,
  /// signed dylib can kill the process holding it. The copy is replaced by
  /// rename, never written in place, so a warm guest keeps its old inode
  /// through a rebundle and dies only when the restart that follows kills it
  /// on purpose.
  ///
  /// Only bundled libraries move; a `system`/`process`/`executable` entry has
  /// no file to bring. A source that has gone missing keeps its original path
  /// in the manifest — the load failure then names a real path, where dropping
  /// the entry would fall back to process lookup and succeed wrongly on macOS.
  String _installNativeAssets(
    String output,
    List<KernelAsset> assets,
    _Sync sync,
  ) {
    var installed = <KernelAsset>[];
    // Plain basenames share one namespace — the dynamic linker's own rule for
    // bundled libraries, per `package:code_assets` — so a collision is a
    // broken package graph, not something to paper over with renaming that
    // would break `@loader_path` references. First claim wins; the loser keeps
    // its original path.
    var claimed = <String, String>{};
    for (var asset in assets) {
      var path = asset.path;
      if (path is! KernelAssetAbsolutePath) {
        installed.add(asset);
        continue;
      }
      var source = path.uri.toFilePath();
      var name = p.basename(source);
      var owner = claimed[name] ??= source;
      var copied = owner == source
          ? _copiedNativeLibrary(output, source, name, sync)
          : null;
      installed.add(
        copied == null
            ? asset
            : KernelAsset(
                id: asset.id,
                target: asset.target,
                path: KernelAssetAbsolutePath(Uri.file(copied)),
              ),
      );
    }
    return KernelAssets(installed).toNativeAssetsFile();
  }

  /// The bundle's own copy of the library at [source], refreshed when the
  /// source moved, and its path.
  ///
  /// Freshness rides a stamp file beside the copy — source path, mtime and
  /// size — because a copy does not inherit its source's mtime and reading
  /// megabytes back to byte-compare on every rebundle is the wrong price.
  /// Same-name replace goes scratch-then-rename; on Windows a loaded DLL
  /// refuses even the delete, so the old file is renamed aside instead and a
  /// later [_prune] sweeps it once the guest that held it is gone.
  String? _copiedNativeLibrary(
    String output,
    String source,
    String name,
    _Sync sync,
  ) {
    var file = File(source);
    if (!file.existsSync()) return null;
    var relative = '$nativeAssetsDirName/$name';
    var stat = file.statSync();
    var dest = File(p.join(output, relative));
    // Before the stamp: `_write` writes where it is pointed and only `_link`
    // makes directories.
    dest.parent.createSync(recursive: true);
    sync.desired.add(relative);
    var stale = _write(
      output,
      '$relative.stamp',
      utf8.encode(
        '$source\n${stat.modified.microsecondsSinceEpoch}\n'
        '${stat.size}',
      ),
      sync,
    );
    if (stale || !dest.existsSync()) {
      var scratch = '${dest.path}.$pid.${_scratchSerial++}';
      file.copySync(scratch);
      if (dest.existsSync()) {
        try {
          dest.deleteSync();
        } on FileSystemException {
          dest.renameSync('${dest.path}.stale.$pid.${_scratchSerial++}');
        }
      }
      File(scratch).renameSync(dest.path);
      sync.changed = true;
    }
    return dest.path;
  }

  void _linkPayloads(
    String output,
    AssetCatalog catalog,
    Map<String, String> transformed,
    _Sync sync,
  ) {
    for (var asset in catalog.assets) {
      for (var file in asset.files) {
        // The declared key, pointed at the bytes a build would ship. That is
        // the whole of transformer support at this layer: the key never
        // changes, only what stands behind it.
        _link(output, file.key, transformed[file.path] ?? file.path, sync);
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

    _link(output, 'isolate_snapshot_data', cache.isolateSnapshotData, sync);
  }

  /// The framework's default shaders — the M3 ink-sparkle ripple and the
  /// stretch-overscroll effect — bundled compiled, like the tool bundles them
  /// (unconditionally: whether they load is decided by the app's code, not its
  /// manifest).
  Future<void> _linkCompiledShaders(String output, _Sync sync) async {
    var sources = frameworkShaderSources(cache);
    // Nothing to compile means no engine revision to read — which is also
    // what lets a test run this against a cache directory that is not an SDK.
    if (sources.isEmpty) return;
    var cacheDir = p.join(
      flutterwareDir(),
      'shaders',
      '${cache.engineRevision}-$_stagesKey',
    );
    await Future.wait([
      for (var source in sources)
        _compiledShader(source, cacheDir).then(
          (compiled) =>
              _link(output, 'shaders/${p.basename(source)}', compiled, sync),
        ),
    ]);
  }

  /// The compiled form of [source], produced on first use per cache key.
  Future<String> _compiledShader(String source, String cacheDir) async {
    var compiled = p.join(cacheDir, p.basename(source));
    if (File(compiled).existsSync()) return compiled;
    Directory(cacheDir).createSync(recursive: true);
    await compileShader(
      cache: cache,
      source: source,
      destination: compiled,
      stages: shaderStages,
    );
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
      try {
        entity.deleteSync();
      } on FileSystemException {
        // Windows will not delete a DLL a live guest still holds — the
        // renamed-aside copy `_copiedNativeLibrary` leaves. It is unlocked the
        // moment that guest is replaced, and the next build sweeps it.
        continue;
      }
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
