import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'channels.dart';
import 'closure.dart';
import 'import_graph.dart';
import 'pixel_diff.dart';
import 'sdk_match.dart';
import 'shot_cache.dart';
import 'shot_key.dart';
import 'skip.dart';
import 'tree_diff.dart';

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
  });

  final String entryId;
  final Uint8List rgba;
  final int width;
  final int height;
  final InspectNode? tree;
}

/// Everything a comparison concluded.
class ComparisonResult {
  ComparisonResult({
    required this.items,
    required this.baseSha,
    required this.headRoot,
    required this.elapsed,
    required this.rendered,
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

  int countOf(ComparedState state) =>
      items.where((item) => item.state == state).length;

  Map<String, Object?> toJson() => {
    'base': baseSha,
    'head': headRoot,
    'ms': elapsed.inMilliseconds,
    'rendered': rendered,
    'counts': {
      for (var state in ComparedState.values)
        if (countOf(state) > 0) state.name: countOf(state),
    },
    'items': [for (var item in items) item.toJson()],
  };
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

  Future<ComparisonResult> run() async {
    var watch = Stopwatch()..start();

    // Before anything: two checkouts on different Flutter versions differ in
    // every pixel for reasons that are not the branch's, and there is no
    // threshold that separates that from a real change.
    var sdk = await SdkMatch.of(baseRoot: baseRoot, headRoot: headRoot);
    if (!sdk.same) throw ComparisonRefused(sdk.reason!);
    var sdkKey = sdk.head!.engineHash ?? sdk.head!.root;

    var headEntries = await side.entries(headRoot);
    var baseEntries = await side.entries(baseRoot);
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

    var items = <String, ComparedItem>{};
    void report(ComparedItem item) {
      items[item.id] = item;
      onItem?.call(item);
    }

    var common = [
      for (var id in headEntries)
        if (baseEntries.contains(id)) id,
    ];
    for (var id in headEntries) {
      if (!baseEntries.contains(id)) {
        report(ComparedItem(id: id, state: ComparedState.added));
      }
    }
    for (var id in baseEntries) {
      if (!headEntries.contains(id)) {
        report(ComparedItem(id: id, state: ComparedState.removed));
      }
    }

    // The graphs are built once per side and reused across every entry: their
    // closures overlap almost entirely, so this is one parse of each package
    // rather than one per entry.
    var headGraph = _graphFor(headRoot);
    var baseGraph = _graphFor(baseRoot);

    var toRender = <String>[];
    var keys = <String, ({String base, String head})>{};
    for (var id in common) {
      var file = side.fileOf(id);
      var closure = headGraph.closureOf(file);
      cache.memo.remember(id, closure);

      var decision = SkipDecision.of(
        entryId: id,
        memo: cache.memo,
        baseRoot: baseRoot,
        headRoot: headRoot,
      );
      var key = (
        base: _keyFor(id, baseGraph, baseRoot, file, sdkKey),
        head: _keyFor(id, headGraph, headRoot, file, sdkKey),
      );
      keys[id] = key;

      if (decision.skip) {
        report(ComparedItem(id: id, state: ComparedState.skipped));
        continue;
      }
      toRender.add(id);
    }

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
    var baseFailures = await _renderInto(
      baseRoot,
      wantedByBase,
      keys,
      isBase: true,
    );
    var headFailures = await _renderInto(
      headRoot,
      wantedByHead,
      keys,
      isBase: false,
    );

    for (var id in toRender) {
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
          ),
        );
        continue;
      }
      report(_compare(id, key));
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
    );
  }

  /// Writes the artifact: the whole verdict as one file, which the GUI, an
  /// agent and a static page all read rather than each computing their own.
  static File writeIndex(ComparisonResult result, String path) {
    var file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
    return file;
  }

  ComparedItem _compare(String id, ({String base, String head}) key) {
    var baseMeta = cache.meta(key.base)!;
    var headMeta = cache.meta(key.head)!;
    return ComparedItem.of(
      id: id,
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
          ),
        );
        if (frame.tree case var tree?) {
          cache.writeTree(isBase ? key.base : key.head, tree.toJson());
        }
      },
    );
  }

  ImportGraph _graphFor(String checkout) => ImportGraph.read(
    root: checkout,
    packageConfig: p.join(
      checkout,
      packageConfig ?? p.join('.dart_tool', 'package_config.json'),
    ),
  );

  String _keyFor(
    String id,
    ImportGraph graph,
    String root,
    String file,
    String sdkKey,
  ) => ShotKey.of(
    kind: 'preview',
    entryId: id,
    closure: SourceClosure.of(graph.closureOf(file), root: root).fingerprint,
    sdk: sdkKey,
  );
}
