import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../comparison/closure.dart';
import '../comparison/import_graph.dart';
import '../comparison/shot_key.dart';
import '../comparison/skip.dart';
import 'catalog_entry.dart';
import 'package_config_locator.dart';

/// Names an entry's picture by everything that decides its pixels.
///
/// The same rule a comparison files a shot under, at a different `kind`: the
/// entry's whole import closure hashed, the pixel inputs no compile names
/// folded in, and the SDK. Deliberately the same machinery rather than a
/// cheaper stamp of its own, because the two answer the same question and a
/// second rule is a second thing to be wrong.
///
/// **What it buys is that a picture is not per-session.** A content key is
/// true of the bytes rather than of the process that took it, so a thumbnail
/// rendered in one worktree answers in every other worktree on the same
/// commit, and one taken before a restart answers after it. That is what makes
/// a page of a hundred and fifty pictures affordable at all: the catalog is
/// rendered once, ever, per state of the source.
///
/// **And it is per entry, which is the whole reason not to key on the catalog.**
/// The harness compiles one program, so it would be simpler to give every
/// picture one fingerprint of everything it compiled — but then editing one
/// demo moves every key, and a page that re-renders 154 entries because one
/// changed is a page nobody waits for. Measured on this repo: a demo's own edit
/// invalidates one entry this way; an edit to the design system invalidates
/// 129, which it should.
class ThumbnailKeys {
  ThumbnailKeys({
    required this.packageRoot,
    required this.sdkKey,
    required this.extra,
  });

  /// The package the entries belong to — what [CatalogEntry.path] is relative
  /// to.
  final String packageRoot;

  /// Which SDK rendered it. Two SDKs lay text out differently, so a picture
  /// taken by one is not the other's to serve.
  final String sdkKey;

  /// What the caller does to the picture that the source does not say: the
  /// size it was captured at, the format it was written in. Whatever a caller
  /// varies has to be in here, or two callers wanting different pictures share
  /// one key and the second is served the first's.
  final Map<String, String> extra;

  /// The checkout the closure is expressed in, which is the workspace root
  /// rather than the package: a member package's sources are hashed relative
  /// to the root that holds the one `package_config.json` they all resolve
  /// through, and a path outside it is not a source this can watch.
  late final String root = p.dirname(p.dirname(_packageConfig));
  late final String _packageConfig = requirePackageConfig(packageRoot);

  /// [packageRoot] as the closure expresses it — `app`, `examples/example`.
  late final String packagePath = p.relative(packageRoot, from: root);

  /// Everything that decides pixels and no compile mentions — assets,
  /// lockfiles, l10n bundles. Listed once and hashed once per root: the same
  /// files decide every entry.
  PixelInputs get _pixels =>
      _pixelsMemo ??= PixelInputs.of(packagePath: packagePath, roots: [root]);
  PixelInputs? _pixelsMemo;

  /// Who imports what, parsed once and walked per entry — one parse of each
  /// file it reaches rather than one per entry that reaches it.
  ImportGraph get _graph => _graphMemo ??= ImportGraph.read(
    root: root,
    packageConfig: _packageConfig,
  );
  ImportGraph? _graphMemo;

  /// Shared across the entries of one pass, which is what stops the shell and
  /// the design system being read once per entry. Measured on this repo's 154
  /// previews: 874ms of hashing becomes 87ms.
  ///
  /// Dropped by [invalidate], and that is the *only* thing that may extend its
  /// life: a digest is true of the file as it was read, so a cache that
  /// outlived a change would answer for a file edited since — the one mistake
  /// a picture key may never make.
  DigestCache _digests = DigestCache();

  /// Bumped by [invalidate], so work that started before it can tell that its
  /// answers are about a disk that has moved.
  ///
  /// Read by anything that takes a key, goes away, and comes back to *write*
  /// under it — a render is hundreds of milliseconds and the disk may move
  /// inside one. See [epoch].
  var _epoch = 0;

  /// Which disk the keys handed out now are about.
  ///
  /// **The guard for a key that outlives the call that took it.** A picture is
  /// filed under the key of the source it was rendered from, and the two are
  /// separated by the render itself; if [invalidate] runs in between, a key
  /// taken again afterwards describes source this picture was never made from.
  /// Writing under it is not a stale picture but a permanently wrong one —
  /// content-addressed, so every later session and every other worktree on that
  /// commit finds it and serves it. A caller that holds a key across an await
  /// holds this with it and drops the write when it moves.
  int get epoch => _epoch;

  /// Held until [invalidate], for the same span and the same reason as
  /// [_digests].
  final _keys = <String, String>{};

  /// What [entry]'s picture is filed under, right now.
  ///
  /// **What this costs, measured on this repo.** The first call builds the
  /// import graph and lists the pixel inputs, which is most of it:
  ///
  ///     first key                        170ms   (and 171ms for an 8-entry
  ///                                               package — it is the graph,
  ///                                               not the catalog)
  ///     the remaining 153                588ms
  ///     all 154 again, memoised           41us
  ///     asking the store for all 154     7.4ms
  ///
  /// So deciding what a whole catalog already has is **about six-tenths of a
  /// second cold and nothing warm**. A hover pays it once per package and hides
  /// it behind a harness bring-up that costs three seconds anyway. A caller
  /// that wants every entry at once — a page of thumbnails — is a different
  /// case: 600ms on the UI isolate is a visible stall, and it belongs off it.
  String keyFor(CatalogEntry entry) => _keys.putIfAbsent(
    entry.id,
    () => ShotKey.of(
      kind: 'preview-thumb',
      entryId: entry.id,
      closure: SourceClosure.of(
        _graph.closureOf(p.join(packagePath, entry.path)),
        root: root,
        digests: _digests,
      ).merge(_pixels.inRoot(root)).fingerprint,
      sdk: sdkKey,
      extra: extra,
    ),
  );

  /// Works out the keys for [entries] **off the UI isolate**, so that
  /// [keyFor] is a map lookup by the time a page asks.
  ///
  /// A key is a few hundred `stat`s and a few megabytes of sha1, and the whole
  /// catalog is about six-tenths of a second of it — which on the isolate that
  /// paints is a visible stall right at the moment a page of tiles is being
  /// laid out. Nothing here needs to be on that isolate: it reads files and
  /// hashes them, and hands back a map of strings.
  ///
  /// Idempotent and cheap once warm; safe to call on every scroll frame. One
  /// pass runs at a time, and a second call while one is in flight waits for
  /// it rather than starting another.
  Future<void> warm(List<CatalogEntry> entries) async {
    var wanted = [
      for (var entry in entries)
        if (!_keys.containsKey(entry.id)) entry,
    ];
    if (wanted.isEmpty) return;
    if (_warming case var running?) return running;
    var pass = _warming = _warmPass(wanted);
    try {
      await pass;
    } finally {
      if (identical(_warming, pass)) _warming = null;
    }
  }

  Future<void>? _warming;

  Future<void> _warmPass(List<CatalogEntry> wanted) async {
    // Everything the isolate needs, as plain values — the graph and the digest
    // cache are rebuilt inside it rather than sent, because neither is
    // sendable and both are cheaper to make than to marshal.
    var root = this.root;
    var packageConfig = _packageConfig;
    var packagePath = this.packagePath;
    var sdk = sdkKey;
    var extra = Map.of(this.extra);
    var paths = {for (var entry in wanted) entry.id: entry.path};
    var epoch = _epoch;
    var computed = await Isolate.run(
      () => _keysIn(
        root: root,
        packageConfig: packageConfig,
        packagePath: packagePath,
        sdkKey: sdk,
        extra: extra,
        paths: paths,
      ),
    );
    // **Dropped whole if the disk moved while it ran.** These are digests of
    // files as they were when the pass started; if [invalidate] has run since,
    // every one of them describes source that is gone, and filing them would
    // serve the previous version's picture for the new version. Cheaper to
    // hash again than to be wrong once.
    if (epoch != _epoch) return;
    for (var entry in computed.entries) {
      _keys.putIfAbsent(entry.key, () => entry.value);
    }
  }

  /// The disk moved: forget every digest, every key and the graph's own
  /// reading of who imports what.
  ///
  /// All of it rather than the entry that changed, because an import graph is
  /// not per entry — a demo that added an import has changed which files
  /// decide *its* pixels, and nothing in a per-entry drop would notice.
  void invalidate() {
    _epoch++;
    _keys.clear();
    _digests = DigestCache();
    _graphMemo = null;
    _pixelsMemo = null;
  }
}

/// One pass of key derivation, with nothing of the caller in it.
///
/// A top-level function taking plain values, because that is what
/// `Isolate.run` can carry: the graph and the digest cache are built here
/// rather than sent, both being unsendable and cheaper to make than to
/// marshal.
Map<String, String> _keysIn({
  required String root,
  required String packageConfig,
  required String packagePath,
  required String sdkKey,
  required Map<String, String> extra,
  required Map<String, String> paths,
}) {
  var graph = ImportGraph.read(root: root, packageConfig: packageConfig);
  var pixels = PixelInputs.of(packagePath: packagePath, roots: [root]);
  var digests = DigestCache();
  return {
    for (var entry in paths.entries)
      entry.key: ShotKey.of(
        kind: 'preview-thumb',
        entryId: entry.key,
        closure: SourceClosure.of(
          graph.closureOf(p.join(packagePath, entry.value)),
          root: root,
          digests: digests,
        ).merge(pixels.inRoot(root)).fingerprint,
        sdk: sdkKey,
        extra: extra,
      ),
  };
}
