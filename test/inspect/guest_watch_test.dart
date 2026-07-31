import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/inspect/guest_inspect.dart';
import 'package:flutterware/src/inspect/guest_watch.dart';
import 'package:flutterware/src/inspect/watch.dart';

/// The half of the watch that needs no guest: **when it decides to speak**.
///
/// That is the whole design. Pushing the tree every frame was the obvious thing
/// and the wrong one — an animation almost never changes tree structure, it
/// changes geometry — so what this class is for is telling those two apart and
/// staying quiet when neither happened. Every test here is about silence or the
/// end of it.
///
/// The geometry tier is only half-reachable from here, and the reason is worth
/// stating rather than working around: resolving a node id needs
/// `WidgetInspectorService`'s summary tree, which is filtered by pub roots that
/// a unit test does not have. So the rect-watching half is asserted against a
/// real guest in `app/tool/catalog/watch_spike.dart`, and what is asserted here
/// is that it neither fires nor throws when there is nothing to resolve.
void main() {
  group('GuestWatch', () {
    testWidgets('says nothing while nothing changes', (tester) async {
      var probe = await _Probe.start(tester);

      await probe.rebuild();
      await probe.rebuild();
      await probe.rebuild();

      expect(probe.pushes, isEmpty);
      expect(probe.watch.describe().frames, greaterThan(2));
    });

    testWidgets('an idle guest is never walked at all', (tester) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();
      var walked = probe.watch.describe().frames;

      // Pumping without dirtying anything draws no frame, so the re-armed
      // callback never fires. That is load-bearing rather than incidental: it
      // is the whole of "a guest nobody is inspecting pays nothing" for the
      // much commoner case of a guest somebody *is* inspecting that simply is
      // not moving. A persistent frame callback would have had to build this;
      // a post-frame one gets it for free.
      await tester.pump();
      await tester.pump();

      expect(probe.watch.describe().frames, walked);
    });

    testWidgets('reports a shape change once, not once per frame', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      await probe.rebuild(extra: 1);

      expect(probe.pushes.map((p) => p.structureChanged), [true]);

      // The frames after it are silent again — a change reported for as long as
      // it is *different from the start* rather than from the previous frame
      // would turn one edit into a permanent stream.
      await probe.rebuild();
      await probe.rebuild();
      expect(probe.pushes, hasLength(1));
    });

    testWidgets('a change of depth counts, not only a change of type', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // The same widgets, one level deeper. A hash folding only types in walk
      // order would call this identical.
      await probe.rebuild(wrap: true);

      expect(probe.pushes.map((p) => p.structureChanged), [true]);
    });

    testWidgets('a rebuild that keeps the shape is not a change', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // Different text, same tree. This is the case the whole design turns on:
      // the overwhelmingly common rebuild moves pixels and nothing else, and a
      // watch that reported it would be a watch nobody could leave on.
      await probe.rebuild(label: 'moved');

      expect(probe.pushes, isEmpty);
    });

    testWidgets('unwatch stops it, and watching again starts from scratch', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      probe.watch.unwatch();
      await probe.rebuild(extra: 2);
      expect(probe.pushes, isEmpty, reason: 'a stopped watch is stopped');

      probe.watch.watch();
      // The first frame after a start has nothing to compare against, so it is
      // silent by construction — otherwise every open of the panel would
      // announce a structure change that had not happened.
      await probe.rebuild();
      expect(probe.pushes, isEmpty);

      await probe.rebuild(extra: 3);
      expect(probe.pushes.map((p) => p.structureChanged), [true]);
    });

    testWidgets('a debounce swallows the pushes inside its window', (
      tester,
    ) async {
      var probe = await _Probe.start(
        tester,
        minInterval: const Duration(seconds: 10),
      );
      await probe.rebuild();

      await probe.rebuild(extra: 1);
      expect(probe.pushes, hasLength(1), reason: 'the first one always lands');

      await probe.rebuild(extra: 2);
      await probe.rebuild(extra: 3);
      expect(probe.pushes, hasLength(1), reason: 'and the rest wait');

      // The comparison still ran on every one of those frames — the debounce
      // drops the *report*, never the read. Dropping the read would leave the
      // next frame compared against a state three frames old, and a change that
      // reverted inside the window would vanish for good.
      expect(probe.watch.describe().frames, greaterThan(3));
    });

    testWidgets('a resize is reported, and is not a shape change', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // Not one widget changed. Every rect did. This is what dragging the panel
      // divider does, and the shape hash cannot see it by construction — which
      // is why it is a tier and not an afterthought.
      await probe.resize(const Size(300, 300));

      expect(probe.pushes, hasLength(1));
      expect(probe.pushes.single.resized, isTrue);
      expect(probe.pushes.single.structureChanged, isFalse);

      // And it settles: holding a size is not resizing.
      await probe.rebuild();
      expect(probe.pushes, hasLength(1));
    });

    testWidgets('a scroll is reported, and is neither of the other two', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // The case the tier exists for: the same widgets at the same depths in a
      // demo of the same size, and every rect under the scrollable somewhere
      // else. Both the tiers above are blind to it by construction.
      probe.scrolls++;
      await probe.rebuild();

      expect(probe.pushes, hasLength(1));
      expect(probe.pushes.single.scrolled, isTrue);
      expect(probe.pushes.single.structureChanged, isFalse);
      expect(probe.pushes.single.resized, isFalse);

      // And a frame that scrolls no further is silence again: the host reads
      // once the pushes stop, so a tier that kept reporting would be a tier
      // that never let it.
      await probe.rebuild();
      expect(probe.pushes, hasLength(1));
    });

    testWidgets('a scroll dropped by the debounce is reported after it', (
      tester,
    ) async {
      // Real milliseconds, waited out with a real delay: the window is a
      // [Stopwatch], which reads the wall clock and which `pump` does not move.
      var probe = await _Probe.start(
        tester,
        minInterval: const Duration(milliseconds: 50),
      );
      await probe.rebuild();

      // Spends the window on a shape change, so the scroll that follows lands
      // inside it and is dropped.
      await probe.rebuild(extra: 1);
      expect(probe.pushes, hasLength(1));
      probe.scrolls++;
      await probe.rebuild();
      expect(probe.pushes, hasLength(1), reason: 'inside the window');

      // Held rather than forgotten, which the other tiers do not do — and here
      // it matters: a scroll nobody was told about leaves the panel drawing the
      // picker's rectangle over what used to be there, with nothing else ever
      // coming to correct it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await probe.rebuild();

      expect(probe.pushes.map((p) => p.scrolled), [false, true]);
    });

    testWidgets('an entry switch is not a scroll', (tester) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // The counter belongs to the guest rather than to the entry, so it does
      // not restart with the demo. The frame it is compared against does: a
      // demo scrolled on its way out would otherwise be reported as the next
      // one scrolling on its way in, and the host would read a tree it had just
      // read.
      probe.scrolls++;
      probe.entryId = 'demo.dart#second';
      await probe.rebuild();

      expect(probe.pushes, isEmpty);
    });

    testWidgets('an entry switch is not a structure change', (tester) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      // A different demo has a different shape, and saying so would be true and
      // useless: the host is already rebuilding everything it knows about the
      // entry, and a push telling it to re-read the tree it is already
      // re-reading is a wasted walk on the busiest frame there is.
      probe.entryId = 'demo.dart#second';
      await probe.rebuild(extra: 4);

      expect(probe.pushes, isEmpty);

      // And the frame after settles into the new shape rather than reporting it
      // late.
      await probe.rebuild(extra: 4);
      expect(probe.pushes, isEmpty);
    });

    testWidgets('an unresolvable node is silence, not a throw', (tester) async {
      var probe = await _Probe.start(tester, nodeId: 'not/a/node');

      await probe.rebuild();
      await probe.rebuild();

      expect(probe.pushes, isEmpty);
      expect(probe.watch.describe().resolved, isFalse);
    });

    testWidgets('and is looked up once, not on every frame', (tester) async {
      var probe = await _Probe.start(tester, nodeId: 'not/a/node');

      // The bug this pins: `_node == null` meant both "not looked up yet" and
      // "looked up, names nothing", so an id naming nothing was re-resolved
      // every frame — and a resolve is a whole summary-tree walk, 4–8ms
      // measured. On an animating demo that is half a core spent re-deciding
      // that a stale id is still stale. The test above passed throughout,
      // because not throwing was never the property at risk.
      for (var i = 0; i < 5; i++) {
        await probe.rebuild();
      }

      expect(probe.lookups, 1);
    });

    testWidgets('and is looked up again once the shape moves', (tester) async {
      var probe = await _Probe.start(tester, nodeId: 'not/a/node');
      await probe.rebuild();
      expect(probe.lookups, 1);

      // Caching the miss must not outlive the tree it was a miss in. An id that
      // named nothing before an edit may name something after one, and a watch
      // that never asked again would go quiet for good.
      await probe.rebuild(extra: 1);

      expect(probe.lookups, 2);
    });

    testWidgets('the walk touches every element and says how many', (
      tester,
    ) async {
      var probe = await _Probe.start(tester);
      await probe.rebuild();

      var before = probe.watch.describe().nodes;
      await probe.rebuild(extra: 5);
      expect(probe.watch.describe().nodes, greaterThan(before));
      expect(probe.pushes.single.nodes, probe.watch.describe().nodes);
    });
  });

  group('the wire', () {
    test('a push survives the round trip', () {
      var push = const WatchPush(
        entryId: 'demo.dart#one',
        frame: 42,
        nodes: 200,
        hashMicros: 137,
        structureChanged: true,
        resized: true,
        scrolled: true,
        geometry: WatchBox(id: '0/1', x: 4, y: 8, width: 120, height: 40),
      );
      var back = WatchPush.fromJson(push.toJson());

      expect(back.entryId, 'demo.dart#one');
      expect(back.frame, 42);
      expect(back.nodes, 200);
      expect(back.hashMicros, 137);
      expect(back.structureChanged, isTrue);
      expect(back.resized, isTrue);
      expect(back.scrolled, isTrue);
      expect(back.geometry?.id, '0/1');
      expect(back.geometry?.width, 120);
    });

    test('a push with nothing to report decodes as nothing to report', () {
      var back = WatchPush.fromJson(
        const WatchPush(
          entryId: null,
          frame: 1,
          nodes: 3,
          hashMicros: 0,
        ).toJson(),
      );

      expect(back.structureChanged, isFalse);
      expect(back.resized, isFalse);
      expect(back.scrolled, isFalse);
      expect(back.geometry, isNull);
    });

    test('stats survive the round trip', () {
      var stats = const WatchStats(
        watching: true,
        entryId: 'demo.dart#one',
        node: '0/1',
        frames: 300,
        pushes: 12,
        nodes: 695,
        hashMicrosLast: 90,
        hashMicrosMean: 95,
        hashMicrosMax: 400,
        resolveMicrosLast: 8200,
        resolved: true,
        minIntervalMillis: 0,
      );
      var back = WatchStats.fromJson(stats.toJson());

      expect(back.watching, isTrue);
      expect(back.nodes, 695);
      expect(back.hashMicrosMean, 95);
      expect(back.resolveMicrosLast, 8200);
      expect(back.resolved, isTrue);
    });
  });
}

/// A tree whose shape this test controls, with the watch pointed at it.
class _Probe {
  _Probe(this.tester);

  static Future<_Probe> start(
    WidgetTester tester, {
    String? nodeId,
    Duration minInterval = Duration.zero,
  }) async {
    var probe = _Probe(tester);
    // Mounted first: a watch is pointed at a root element, and there is no
    // element until something has been pumped.
    await probe.rebuild();

    Element? root() => probe._root.currentContext as Element?;
    probe.watch = GuestWatch(
      inspector: _CountingInspector(probe, rootOf: root),
      rootOf: root,
      entryIdOf: () => probe.entryId,
      emit: probe.pushes.add,
      scrollsOf: () => probe.scrolls,
    )..watch(nodeId: nodeId, minInterval: minInterval);
    return probe;
  }

  final WidgetTester tester;
  late final GuestWatch watch;
  final pushes = <WatchPush>[];

  final _root = GlobalKey();
  String? entryId = 'demo.dart#one';

  /// How many times the watch asked what a node id points at. The expensive
  /// half, so the number of times it is paid is the thing worth asserting.
  var lookups = 0;

  /// What the demo has scrolled, stood in for. The real counter is bumped by a
  /// `NotificationListener` above the demo; driving it by hand here is what
  /// lets a scroll be told apart from a rebuild that happens to follow one.
  var scrolls = 0;

  var _extra = 0;
  var _wrap = false;
  var _label = 'start';
  var _size = const Size(200, 200);

  /// Gives the demo a different box without touching a widget in it.
  Future<void> resize(Size size) async {
    _size = size;
    await rebuild();
  }

  /// Rebuilds and pumps one frame, so the post-frame callback runs exactly
  /// once per call.
  Future<void> rebuild({int? extra, bool? wrap, String? label}) async {
    _extra = extra ?? _extra;
    _wrap = wrap ?? _wrap;
    _label = label ?? _label;

    Widget body = Column(
      children: [
        Text(_label),
        for (var i = 0; i < _extra; i++)
          SizedBox(key: ValueKey(i), width: 10, height: 10),
      ],
    );
    if (_wrap) body = Padding(padding: const EdgeInsets.all(4), child: body);

    // The `SizedBox` is what makes the demo's own box something this test can
    // change — the watch reads it off the root element's render object, and a
    // `Column` filling the test surface has the same size for ever.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: KeyedSubtree(
            key: _root,
            child: SizedBox.fromSize(size: _size, child: body),
          ),
        ),
      ),
    );
  }
}

/// A [GuestInspector] that counts resolves and finds nothing.
///
/// Finding nothing is the case under test: the summary tree is filtered by pub
/// roots a unit test does not have, so a real lookup here would answer null
/// anyway — this only makes the answer deliberate and the count visible.
class _CountingInspector extends GuestInspector {
  _CountingInspector(this._probe, {required super.rootOf})
    : super(entryIdOf: () => null);

  final _Probe _probe;

  @override
  RenderObject? renderObjectFor(String id) {
    _probe.lookups++;
    return null;
  }
}
