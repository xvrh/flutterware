import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutterware/comparison_report.dart';
import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'cancel.dart';
import 'closure.dart';
import 'import_graph.dart';
import '../utils/flutter_sdk.dart';
import 'shot_cache.dart';
import 'shot_key.dart';
import 'skip.dart';

/// One side of a comparison, as the runner needs to talk to it.
///
/// An interface rather than `HeadlessCatalog` directly, for one reason that
/// pays for itself immediately: the orchestration — what to skip, what is
/// added, which side broke, what the index says — is most of the risk in this
/// feature and none of it needs a compiler, a guest or a Flutter SDK to be
/// wrong. A fake renderer makes all of that testable in milliseconds.
abstract interface class ComparisonSide {
  /// Every entry id this checkout declares.
  Future<List<String>> entries(String checkout);

  /// The package the entries live in, relative to a checkout root — where the
  /// pubspec declaring the assets and the lockfile recording the resolution
  /// sit, which is what [pixelInputsOf] reads.
  String get packagePath;

  /// Where [entryId]'s source lives, **relative to a checkout root**.
  ///
  /// Asked of the side rather than derived from the id, because an id is
  /// relative to its *package* and a checkout can hold several: in a
  /// workspace, `demo/buttons.dart#buttons` lives at
  /// `examples/example/demo/buttons.dart`. Deriving it here made every entry
  /// look like a missing file, which hashes the same on both sides — so a
  /// comparison of a genuinely changed preview skipped it and reported no
  /// change at all.
  String fileOf(String entryId);

  /// Renders [entryIds] and hands each frame over as it lands.
  ///
  /// Streamed for the reason `HeadlessCatalog.captureAll` streams: a frame is
  /// megabytes and a catalog is hundreds of them.
  ///
  /// Returns entry id → why nothing was rendered, for the ones that refused.
  Future<Map<String, String>> render({
    required String checkout,
    required List<String> entryIds,
    required Future<void> Function(RenderedEntry frame) onFrame,
  });
}

/// One rendered entry, as a side hands it to the runner.
class RenderedEntry {
  RenderedEntry({
    required this.entryId,
    required this.rgba,
    required this.width,
    required this.height,
    this.tree,
    this.complaint,
  });

  final String entryId;
  final Uint8List rgba;
  final int width;
  final int height;
  final InspectNode? tree;

  /// What the framework said while drawing it, when it drew it anyway — an
  /// overflow, a missing font. The picture is comparable and the complaint is
  /// still worth carrying, because "this overflows now" is a finding even when
  /// the pixels barely moved.
  final String? complaint;
}

/// Everything a comparison concluded.
class ComparisonResult {
  ComparisonResult({
    required this.items,
    required this.baseSha,
    required this.headRoot,
    required this.elapsed,
    required this.rendered,
    this.because = const {},
  });

  /// Worst first — [ComparedState] is declared in that order, so ranking is a
  /// sort.
  final List<ComparedItem> items;

  final String baseSha;
  final String headRoot;
  final Duration elapsed;

  /// How many renders actually happened, against how many entries there are.
  /// The number that says whether the skip rule earned its keep.
  final int rendered;

  /// Why the skip rule could not answer the entries it could not answer,
  /// folded — see [foldReasons].
  ///
  /// The other half of [rendered]. That number says the skip rule did not
  /// earn its keep; this one says which path it was that both checkouts
  /// disagreed about, which is the only form of the answer anybody can act
  /// on.
  final Map<String, int> because;

  int countOf(ComparedState state) =>
      items.where((item) => item.state == state).length;

  /// This half alone. Which base it was against and where head sits belong to
  /// the whole comparison rather than to one of its halves, so
  /// `ComparisonArtifact` writes them once at the top.
  Map<String, Object?> toJson() => {
    'rendered': rendered,
    'because': ?(because.isEmpty ? null : because),
    'ms': elapsed.inMilliseconds,
    'counts': {
      for (var state in ComparedState.values)
        if (countOf(state) > 0) state.name: countOf(state),
    },
    'items': [for (var item in items) item.toJson()],
  };
}

/// What a comparison already knows before it renders anything.
class ComparisonPlan {
  const ComparisonPlan({
    required this.settled,
    required this.toRender,
    required this.keys,
    required this.total,
    this.because = const {},
  });

  /// Rows whose verdict needed no picture: added, removed, skipped.
  final List<ComparedItem> settled;

  /// The entries that have to be rendered to be answered.
  final List<String> toRender;

  /// Why [toRender] has to be rendered, folded — see [foldReasons].
  final Map<String, int> because;

  /// Each entry's cache key on both sides.
  final Map<String, ({String base, String head})> keys;

  /// Every entry either side declares, settled and unsettled together.
  final int total;
}

/// One side could not render *anything* — it did not compile.
///
/// One finding, not one per entry. This used to be mapped onto every entry
/// the side was asked for, on the reasoning that a per-entry verdict lands on
/// the severity ladder rather than ending the comparison. Measured against a
/// base whose catalog did not compile, that reasoning produced twenty-four
/// identical rows, each saying the same sentence once, burying everything else
/// the run found. It is the argument the split branches already settled: one
/// decision in the source is one row, however many things hang off it.
///
/// Thrown by the side, which knows the reason; named by the runner, which knows
/// which checkout it handed over.
class SideDidNotCompile implements Exception {
  SideDidNotCompile(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Refused before anything is rendered.
class ComparisonRefused implements Exception {
  ComparisonRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs one comparison: decide, render what is left, diff, report.
///
/// The order is the design. **Deciding comes first and costs only hashing**,
/// so every row's verdict exists before the first render starts — which is
/// what lets a screen draw its full shape immediately and fill in the pictures
/// behind it, and what makes a branch that changed nothing cost no renders at
/// all.
class ComparisonRunner {
  ComparisonRunner({
    required this.headRoot,
    required this.baseRoot,
    required this.baseSha,
    required this.side,
    required this.cache,
    this.packageConfig,
    this.only,
    this.onItem,
    this.onPlan,
    this.onProgress,
    this.cancel,
  });

  /// The worktree as it sits on disk, uncommitted and untracked included.
  final String headRoot;

  /// The base, already checked out — see `BaseCheckout`.
  final String baseRoot;

  final String baseSha;

  final ComparisonSide side;
  final ShotCache cache;

  /// Relative path of the package config inside each checkout, for resolving
  /// `package:` imports. Null falls back to the conventional location.
  final String? packageConfig;

  /// Compare only these entry ids. A focus device rather than a performance
  /// one — the skip rule already renders nothing it does not have to.
  final List<String>? only;

  /// Called as each verdict is reached, so a host can fill a list in rather
  /// than wait for the whole run.
  final void Function(ComparedItem item)? onItem;

  /// Called once the plan is made — the moment the run's shape is known: how
  /// many entries there are, and which of them still owe a verdict.
  final void Function(ComparisonPlan plan)? onPlan;

  /// One sentence of what the run is doing right now, replaced as it moves.
  final void Function(String phase)? onProgress;

  /// Checked between stages and between frames. See [CancelToken].
  final CancelToken? cancel;

  /// Everything that can be decided without rendering anything.
  ///
  /// The whole skip rule, and none of the rendering. Split out of [run]
  /// because it is what makes a screen honest while it fills: every row that is
  /// added, removed or skipped is already settled here, so the list draws its
  /// full shape immediately and only the pictures arrive late.
  ///
  /// It is no longer split out so that a *tab* can be priced before it is
  /// opened. It was, and the price was the problem — see
  /// [ComparisonController].
  ///
  /// The deciding runs on an isolate, because its size is the *project's*
  /// and not ours: one sha1 per file in every entry's closure, plus the asset
  /// tree. This was once measured at 142ms, on this repository, which has a
  /// handful of previews and no assets to speak of; a real catalog of 90
  /// previews put the same loop at minutes, and on the UI isolate that is not a
  /// slow screen but a dead window — `plan` is one uninterruptible microtask,
  /// since nothing in the loop awaits.
  Future<ComparisonPlan> plan() async {
    // Keyed on the SDK this session runs under, which is the one both sides
    // are rendered with — so switching SDKs invalidates the cache rather than
    // handing back pictures the current engine would not draw.
    //
    // **It is not checked against what the base commit wanted, and that is a
    // known gap.** Two checkouts that pinned different Flutter versions differ
    // in every pixel for reasons that are not the branch's, and this used to
    // refuse the comparison over it. Detecting that meant resolving an SDK
    // from a pointer inside the base checkout — discovery, which flutterware
    // no longer does anywhere: the SDK is whichever one the invocation names.
    // Teaching a comparison how to *invoke* an older SDK (a `comparison`
    // entry in `tool/flutterware.dart` naming `fvm flutter`, say) is the real
    // fix, and it is not built. Until it is, a cross-version comparison runs
    // and reports SDK churn as change, unwarned.
    var sdkKey = (await FlutterSdkPath.findSdk())?.root ?? 'unknown';

    onProgress?.call('listing the entries on both sides');
    var headEntries = await side.entries(headRoot);
    var baseEntries = await side.entries(baseRoot);
    cancel?.check();
    if (only case var only?) {
      headEntries = [
        for (var id in headEntries)
          if (only.contains(id)) id,
      ];
      baseEntries = [
        for (var id in baseEntries)
          if (only.contains(id)) id,
      ];
    }

    var settled = <ComparedItem>[];
    var common = [
      for (var id in headEntries)
        if (baseEntries.contains(id)) id,
    ];
    for (var id in headEntries) {
      if (!baseEntries.contains(id)) {
        settled.add(ComparedItem(id: id, state: ComparedState.added));
      }
    }
    for (var id in baseEntries) {
      if (!headEntries.contains(id)) {
        settled.add(ComparedItem(id: id, state: ComparedState.removed));
      }
    }

    // `side` and `cache` are live objects and stay here; what crosses is the
    // ids, the paths and the one file each entry starts from. A tear-off of
    // `decide` sends its receiver, which is why the receiver is plain data.
    onProgress?.call(
      'deciding what changed — hashing ${common.length} '
      '${common.length == 1 ? 'closure' : 'closures'}',
    );
    var decided = await Isolate.run(
      _PlanInputs(
        ids: common,
        files: {for (var id in common) id: side.fileOf(id)},
        headRoot: headRoot,
        baseRoot: baseRoot,
        packagePath: side.packagePath,
        packageConfig: packageConfig,
        memoDirectory: cache.memo.directory,
        sdkKey: sdkKey,
      ).decide,
    );

    cancel?.check();
    for (var id in decided.skipped) {
      settled.add(ComparedItem(id: id, state: ComparedState.skipped));
    }
    return ComparisonPlan(
      settled: settled,
      toRender: decided.toRender,
      keys: decided.keys,
      total: settled.length + decided.toRender.length,
      because: decided.because,
    );
  }

  /// Renders what [plan] left and diffs it.
  ///
  /// Takes a plan when the caller already made one, since remaking it would
  /// hash every closure a second time to reach the same answer.
  ///
  /// A verdict lands the moment it is answerable rather than when the run ends.
  /// The settled rows come first, in a burst; an entry both sides already have
  /// cached is diffed before any render starts; and during the head pass each
  /// frame is diffed as it lands, because by then the base side is final. What
  /// waits until the end is only what has to: entries whose head render
  /// *failed* produce no frame, so their rows come last.
  Future<ComparisonResult> run({ComparisonPlan? from}) async {
    var watch = Stopwatch()..start();
    cancel?.check();
    var plan = from ?? await this.plan();
    onPlan?.call(plan);

    var items = <String, ComparedItem>{};
    void report(ComparedItem item) {
      items[item.id] = item;
      onItem?.call(item);
    }

    for (var item in plan.settled) {
      report(item);
    }
    var toRender = plan.toRender;
    var keys = plan.keys;

    // Only what is not already filed under its key. After the first
    // comparison against a base, that is the head side alone; after an
    // unrelated edit, it can be nothing at all.
    var wantedByBase = [
      for (var id in toRender)
        if (!cache.has(keys[id]!.base)) id,
    ];
    var wantedByHead = [
      for (var id in toRender)
        if (!cache.has(keys[id]!.head)) id,
    ];

    var rendered = wantedByBase.length + wantedByHead.length;
    // A side that will not compile ends the half with one sentence. Which side
    // is the reader's first question and the side cannot answer it, so it is
    // answered here.
    var baseFailures = const <String, String>{};
    var headFailures = const <String, String>{};

    /// Answers [id] from what is on hand, once — a failure on the side that
    /// was asked, or the diff. Callers only invoke this when the sides it
    /// reads are final for [id].
    void resolve(String id) {
      if (items.containsKey(id)) return;
      var key = keys[id]!;
      var baseOk = !baseFailures.containsKey(id) && cache.has(key.base);
      var headOk = !headFailures.containsKey(id) && cache.has(key.head);
      if (!baseOk || !headOk) {
        report(
          ComparedItem.of(
            id: id,
            baseRendered: baseOk,
            headRendered: headOk,
            note: headFailures[id] ?? baseFailures[id],
            // Even here: the side that *did* render is worth looking at, and
            // "renders on base, throws here" is a row somebody will want to
            // see the base of.
            shots: key,
          ),
        );
        return;
      }
      report(_compare(id, key));
    }

    // Both frames already in the cache: answerable before anything renders.
    for (var id in toRender) {
      if (!wantedByBase.contains(id) && !wantedByHead.contains(id)) {
        resolve(id);
      }
    }

    try {
      var done = 0;
      baseFailures = await _renderInto(
        baseRoot,
        wantedByBase,
        keys,
        isBase: true,
        onEntry: (id) {
          cancel?.check();
          done++;
          onProgress?.call(
            'rendering the base side · $done of ${wantedByBase.length}',
          );
        },
      );
    } on SideDidNotCompile catch (e) {
      throw ComparisonRefused(
        'the base checkout does not compile, so there is nothing to compare '
        'against: ${e.reason}',
      );
    }
    cancel?.check();

    // The base pass is over, so entries whose head frame was already cached
    // are final now — including the ones whose base render just failed.
    for (var id in toRender) {
      if (!wantedByHead.contains(id)) resolve(id);
    }

    try {
      var done = 0;
      headFailures = await _renderInto(
        headRoot,
        wantedByHead,
        keys,
        isBase: false,
        onEntry: (id) {
          cancel?.check();
          done++;
          onProgress?.call(
            'rendering this side · $done of ${wantedByHead.length}',
          );
          // This entry's head frame just landed and the base side is final:
          // the row is answerable while its neighbours are still rendering.
          resolve(id);
        },
      );
    } on SideDidNotCompile catch (e) {
      throw ComparisonRefused(
        'this worktree does not compile, so its previews cannot be '
        'rendered: ${e.reason}',
      );
    }
    cancel?.check();

    // What is left is the entries a render pass refused: they produced no
    // frame, so their failure is only known now the pass has returned.
    for (var id in toRender) {
      resolve(id);
    }

    var ordered = items.values.toList()
      ..sort((a, b) {
        var byState = a.state.index.compareTo(b.state.index);
        return byState != 0 ? byState : a.id.compareTo(b.id);
      });
    return ComparisonResult(
      items: ordered,
      baseSha: baseSha,
      headRoot: headRoot,
      elapsed: watch.elapsed,
      rendered: rendered,
      because: plan.because,
    );
  }

  ComparedItem _compare(String id, ({String base, String head}) key) {
    var baseMeta = cache.meta(key.base)!;
    var headMeta = cache.meta(key.head)!;
    // The head side's, or the base's said as the base's. A complaint present on
    // both is the state of the world rather than something this branch did; one
    // the *base* alone makes is usually a skew in the tooling that rendered it,
    // and that is the sentence which separates "the branch changed this" from
    // "the two sides were photographed by different rules".
    var complaint = headMeta.complaint;
    complaint ??= baseMeta.complaint == null
        ? null
        : 'on base: ${baseMeta.complaint}';
    return ComparedItem.of(
      id: id,
      shots: key,
      note: headMeta.complaint == baseMeta.complaint ? null : complaint,
      pixels: PixelDiff.of(
        base: cache.read(key.base)!,
        baseWidth: baseMeta.width,
        baseHeight: baseMeta.height,
        head: cache.read(key.head)!,
        headWidth: headMeta.width,
        headHeight: headMeta.height,
      ),
      tree: TreeDiff.of(_treeOf(key.base), _treeOf(key.head)),
    );
  }

  InspectNode? _treeOf(String key) {
    var json = cache.readTree(key);
    return json == null ? null : InspectNode.fromJson(json);
  }

  Future<Map<String, String>> _renderInto(
    String checkout,
    List<String> entryIds,
    Map<String, ({String base, String head})> keys, {
    required bool isBase,
    void Function(String entryId)? onEntry,
  }) async {
    if (entryIds.isEmpty) return const {};
    return side.render(
      checkout: checkout,
      entryIds: entryIds,
      onFrame: (frame) async {
        var key = keys[frame.entryId];
        if (key == null) return;
        cache.write(
          isBase ? key.base : key.head,
          frame.rgba,
          ShotRecord(
            format: 'raw',
            width: frame.width,
            height: frame.height,
            entryId: frame.entryId,
            complaint: frame.complaint,
          ),
        );
        if (frame.tree case var tree?) {
          cache.writeTree(isBase ? key.base : key.head, tree.toJson());
        }
        onEntry?.call(frame.entryId);
      },
    );
  }
}

/// [ComparisonRunner.plan]'s deciding half, as the plain data it needs.
///
/// A class rather than a closure because [Isolate.run] copies whatever the
/// closure captures, and a closure over the runner would capture `side` and
/// `cache` — a compiler, a guest and a cache handle, none of which can cross
/// and none of which the deciding wants.
///
/// The memo is opened here from its directory rather than sent: it is a file
/// on disk, and the isolate is the one writing it.
class _PlanInputs {
  _PlanInputs({
    required this.ids,
    required this.files,
    required this.headRoot,
    required this.baseRoot,
    required this.packagePath,
    required this.packageConfig,
    required this.memoDirectory,
    required this.sdkKey,
  });

  /// The entries both sides declare — the only ones a skip rule applies to.
  final List<String> ids;

  /// Entry id → its source file, relative to a checkout root. Resolved by the
  /// side before the hop, since only the side knows how.
  final Map<String, String> files;

  final String headRoot;
  final String baseRoot;
  final String packagePath;
  final String? packageConfig;
  final String memoDirectory;
  final String sdkKey;

  ({
    List<String> skipped,
    List<String> toRender,
    Map<String, ({String base, String head})> keys,
    Map<String, int> because,
  })
  decide() {
    var memo = ClosureMemo(memoDirectory);
    // Opened here and dropped at the end of this method, which is the whole
    // of its life: a digest is true of the file as it was read, and a plan is
    // the longest stretch over which that stays true.
    var digests = DigestCache();
    // The graphs are built once per side and reused across every entry: their
    // closures overlap almost entirely, so this is one parse of each package
    // rather than one per entry.
    var headGraph = _graphFor(headRoot);
    var baseGraph = _graphFor(baseRoot);

    // Listed and hashed once for the whole plan: the same lockfiles and assets
    // decide every entry's pixels, and they go into the skip rule and the shot
    // key together — a key that ignored what the skip rule watches would serve
    // a stale picture for exactly the change the skip rule re-rendered for.
    var pixels = PixelInputs.of(
      packagePath: packagePath,
      roots: [headRoot, baseRoot],
    );

    var skipped = <String>[];
    var toRender = <String>[];
    var reasons = <String>[];
    var keys = <String, ({String base, String head})>{};
    for (var id in ids) {
      var file = files[id]!;
      memo.remember(id, headGraph.closureOf(file));

      var decision = SkipDecision.of(
        entryId: id,
        memo: memo,
        baseRoot: baseRoot,
        headRoot: headRoot,
        pixels: pixels,
        digests: digests,
      );
      keys[id] = (
        base: _keyFor(id, baseGraph, baseRoot, file, pixels, digests),
        head: _keyFor(id, headGraph, headRoot, file, pixels, digests),
      );

      if (decision.skip) {
        skipped.add(id);
        continue;
      }
      toRender.add(id);
      if (decision.reason case var reason?) reasons.add(reason);
    }
    return (
      skipped: skipped,
      toRender: toRender,
      keys: keys,
      because: foldReasons(reasons),
    );
  }

  ImportGraph _graphFor(String checkout) => ImportGraph.read(
    root: checkout,
    packageConfig: p.join(
      checkout,
      packageConfig ?? p.join('.dart_tool', 'package_config.json'),
    ),
  );

  /// The entry's own sources hashed here, the pixel inputs folded in from the
  /// per-checkout closure. [SourceClosure.merge] makes that the same
  /// fingerprint hashing the union produced, so no key moves.
  String _keyFor(
    String id,
    ImportGraph graph,
    String root,
    String file,
    PixelInputs pixels,
    DigestCache digests,
  ) => ShotKey.of(
    kind: 'preview',
    entryId: id,
    closure: SourceClosure.of(
      graph.closureOf(file),
      root: root,
      digests: digests,
    ).merge(pixels.inRoot(root)).fingerprint,
    sdk: sdkKey,
  );
}
