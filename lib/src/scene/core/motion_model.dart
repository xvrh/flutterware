// The motion document model — the editor-plane half of the motion grammar
// (sketches 17–25). A motion names its scene, declares
// animation groups over that scene's nodes (typed targets, field-name
// identity — the same law the scene settled), arranges them on a mandatory
// `timeline`, and may keep unplaced groups as library assets fired on events.
import 'curves.dart';
import 'model.dart';
import 'motion_runtime.dart';
import 'values.dart';

/// What a track's values are. Mirrors the scene's parameter kinds minus
/// string — words are not tweened.
enum TrackKind { number, color }

/// One keyframe. `value` is a double or a Color per the owning track's kind;
/// `curve` is one of [Curves] (null = linear); `paramRef` is
/// provenance — which motion parameter fed the value — and survives a save
/// only while the value still equals that parameter's default.
class MotionKey {
  MotionKey({
    required this.at,
    required Object value,
    this.curve,
    this.paramRef,
  }) : _value = _asValue(value),
       id = _nextId++;

  MotionKey._copy(this.id, this.at, Object value, this.curve, this.paramRef)
    : _value = _asValue(value);

  /// A number key holds a DOUBLE, whatever it arrived as.
  ///
  /// The file writes `value: 1` for one, because an integral double is
  /// spelled as an int literal — and a compiled file hands that straight
  /// over, where every reader casts to double. Coerced at the door rather
  /// than at each of them.
  static Object _asValue(Object value) =>
      value is int ? value.toDouble() : value;

  static var _nextId = 1;

  /// Runtime identity. A key has no name, so nothing on disk carries this —
  /// but the timeline must hold a selection while keys are dragged past one
  /// another (which re-sorts the list) and across an undo (which restores
  /// values into the same objects), and an index cannot do that.
  final int id;

  Duration at;

  Object _value;
  Object get value => _value;
  set value(Object v) => _value = _asValue(v);

  SceneCurve? curve;
  String? paramRef;

  MotionKey copy() => MotionKey._copy(id, at, value, curve, paramRef);
}

/// A mutable track with the door the probes demanded: key *values* retune
/// freely; key *time* moves, inserts and removes go through methods that
/// keep the list sorted — the everyday editor drag past a neighbour would
/// otherwise silently break the hold rule.
class MotionTrack {
  /// The kind is READ OFF THE KEYS unless it is given: a track of colours is
  /// a colour track, and a file that spells `MotionTrack([MotionKey(…)])`
  /// should not also have to say so. Given explicitly for an empty track,
  /// which has nothing to read.
  MotionTrack(List<MotionKey> keys, {TrackKind? kind})
    : keys = keys,
      kind =
          kind ??
          (keys.isNotEmpty && keys.first.value is SceneColor
              ? TrackKind.color
              : TrackKind.number) {
    _sort();
  }

  final TrackKind kind;
  final List<MotionKey> keys;

  Duration get duration => keys.isEmpty ? Duration.zero : keys.last.at;

  void insertKey(MotionKey k) {
    keys.add(k);
    _sort();
  }

  void moveKey(MotionKey k, Duration at) {
    k.at = at;
    _sort();
  }

  void removeKey(MotionKey k) => keys.remove(k);

  void _sort() => keys.sort((a, b) => a.at.compareTo(b.at));

  MotionTrack copy() => MotionTrack([for (var k in keys) k.copy()], kind: kind);
}

/// One `late final <name> = scene.<node>.animate(…)` field.
///
/// A group holds the NODE it animates, not its name: in a compiled scene
/// file `scene.headline` is a typed reference the compiler checks, and a
/// motion pointed at a node the scene does not have is a program that does
/// not build. Nothing resolves anything at play time.
///
/// It is also a [TimelineExpr] in its own right, because the file places it
/// by writing the field — `Par([headlineIn, …])` — so there is no third
/// thing standing between a group and its place in the arrangement.
class AnimateGroup extends TimelineExpr {
  AnimateGroup(this.node, {this.name = ''});

  /// The group's name — the field it is declared under, and SOURCE-LEVEL
  /// only, like a node's. Empty in a compiled motion, filled by the parser,
  /// and what the editor shows and the emitter writes.
  String name;

  /// The node this group animates.
  SceneNode node;

  /// Property → track, non-empty only: Save writes no empty tracks (an
  /// always-present empty track is a *runtime* affordance, not a file one).
  final tracks = <String, MotionTrack>{};

  /// External-arg tracks — the one stringly boundary of the grammar: an
  /// external widget's args are discovered by scan, not declared here.
  final args = <String, MotionTrack>{};

  Duration get duration => [
    for (var t in tracks.values) t.duration,
    for (var t in args.values) t.duration,
  ].fold(Duration.zero, (m, d) => d > m ? d : m);

  AnimateGroup copy() => AnimateGroup(node, name: name)
    ..tracks.addAll({for (var e in tracks.entries) e.key: e.value.copy()})
    ..args.addAll({for (var e in args.entries) e.key: e.value.copy()});
}

/// What an editor needs to know about an animatable property without a
/// switch on its name: what it is, where it rests, how it reads, and where a
/// slider would mean something.
///
/// The metadata earns its place by deciding two things elsewhere — which
/// control a number gets (a bounded range is a slider, an angle is a dial,
/// everything else is a drag) and how much one pixel of that drag is worth,
/// which is what makes the same gesture sensible on a property running 0..1
/// and one running 0..64.
class ScenePropSpec {
  const ScenePropSpec(
    this.name,
    this.kind, {
    this.identity,
    this.unit,
    this.softMin,
    this.softMax,
    this.angular = false,
    this.entrance,
  });

  final String name;
  final TrackKind kind;

  /// The value the property has when nothing animates it — where a track
  /// should land so the scene looks right at the end.
  final double? identity;

  /// Shown beside the number, never parsed.
  final String? unit;

  /// Where a slider should sit. A hint, not a clamp: a scale of 40 is
  /// legitimate, it just is not what the drag should make easy.
  final double? softMin;
  final double? softMax;

  /// Stored in degrees and shown in degrees, but a dial rather than a number:
  /// degrees answer "how far", only a dial answers "which way".
  final bool angular;

  /// Where a newly created track starts, arriving at [identity]. An entrance
  /// is the common case, and landing on the resting value means the scene is
  /// *correct* at the end of a track the moment you make one.
  final double? entrance;
}

/// The imposed vocabulary: every node kind animates these.
const imposedProps = <ScenePropSpec>[
  ScenePropSpec(
    'opacity',
    TrackKind.number,
    identity: 1,
    softMin: 0,
    softMax: 1,
    entrance: 0,
  ),
  ScenePropSpec(
    'translateX',
    TrackKind.number,
    identity: 0,
    unit: 'px',
    softMin: -200,
    softMax: 200,
    entrance: 24,
  ),
  ScenePropSpec(
    'translateY',
    TrackKind.number,
    identity: 0,
    unit: 'px',
    softMin: -200,
    softMax: 200,
    entrance: 24,
  ),
  ScenePropSpec(
    'scale',
    TrackKind.number,
    identity: 1,
    softMin: 0,
    softMax: 2,
    entrance: 0.92,
  ),
  ScenePropSpec(
    'rotate',
    TrackKind.number,
    identity: 0,
    unit: '°',
    angular: true,
    softMin: -180,
    softMax: 180,
    entrance: -8,
  ),
];

/// Imposed plus the target kind's intrinsic properties, in canonical emit
/// order.
List<ScenePropSpec> animatableProps(SceneNode node) => [
  ...imposedProps,
  ...switch (node) {
    TextNode() => const [
      ScenePropSpec(
        'fontSize',
        TrackKind.number,
        unit: 'px',
        softMin: 8,
        softMax: 96,
      ),
      ScenePropSpec('color', TrackKind.color),
    ],
    FrameNode() => const [
      ScenePropSpec(
        'gap',
        TrackKind.number,
        unit: 'px',
        softMin: 0,
        softMax: 64,
      ),
      ScenePropSpec('fill', TrackKind.color),
    ],
    ShapeNode() => const [ScenePropSpec('fill', TrackKind.color)],
    ExternalNode() => const <ScenePropSpec>[],
    // The child's declared parameters, once somebody resolved it — a string
    // parameter has no in-between values and does not animate.
    SceneRefNode r => [
      for (var p in r.instance?.params ?? const <SceneParamDecl>[])
        if (p.kind == SceneParamKind.number)
          ScenePropSpec('args.${p.name}', TrackKind.number)
        else if (p.kind == SceneParamKind.color)
          ScenePropSpec('args.${p.name}', TrackKind.color),
    ],
  },
];

/// The spec for one property of one node, or null when that node does not
/// animate it.
ScenePropSpec? propSpecFor(SceneNode node, String prop) {
  for (var spec in animatableProps(node)) {
    if (spec.name == prop) return spec;
  }
  return null;
}

/// The arrangement — a pure time-transform tree over group references.
/// A group appears at most once in the whole tree; groups it never names are
/// library assets (independently playable, no autoplay).
sealed class TimelineExpr {}

class ParExpr extends TimelineExpr {
  ParExpr(this.children);
  final List<TimelineExpr> children;
}

class SeqExpr extends TimelineExpr {
  SeqExpr(this.children);
  final List<TimelineExpr> children;
}

class AtExpr extends TimelineExpr {
  AtExpr(this.offset, this.child);
  Duration offset;
  final TimelineExpr child;
}

class SpeedExpr extends TimelineExpr {
  SpeedExpr(this.factor, this.child);
  double factor;
  final TimelineExpr child;
}

class RepeatExpr extends TimelineExpr {
  RepeatExpr(this.times, this.child);
  int times;
  final TimelineExpr child;
}

/// Milliseconds, so a file can write `240.ms` — the only spelling the motion
/// grammar accepts for a time.
extension SceneMillis on int {
  Duration get ms => Duration(milliseconds: this);
}

/// What a `.scene.dart` motion class extends.
///
/// The scene is the TYPE parameter, so `scene.headline` inside a motion is a
/// typed reference the compiler checks: a motion pointed at a node the scene
/// does not declare is a program that does not build, and one pointed at the
/// wrong kind of node cannot name that kind's properties either.
abstract class SceneMotion<T extends SceneDefinition> extends Playable {
  SceneMotion(this.scene);

  final T scene;

  /// What plays. Groups place themselves in it, so nothing is looked up.
  TimelineExpr get timeline;

  /// The timeline as a playable tree, built once.
  ///
  /// A motion IS one — `MotionPlayer(BannerIntro(scene))` is the whole of
  /// starting it, and the same is true of the [BoundMotion] the editor
  /// makes from a file it read. Nothing about a compiled motion needs
  /// binding: the groups hold their nodes, and they are in the timeline
  /// expression itself.
  late final Playable _play = playTimeline(timeline);

  @override
  Duration get duration => _play.duration;

  @override
  void apply(Duration t) => _play.apply(t);

  @override
  void clearFx() => _play.clearFx();

  /// Carry this motion's live state into [other] and hand it back — what a
  /// generated `copy` calls to rebind onto another instance of the scene.
  ///
  /// Nothing is carried yet: a fresh motion over a fresh scene already
  /// evaluates to the same frames, and the editor's own state lives in its
  /// document. Kept because the generated member calls it, and because the
  /// day a motion holds runtime state this is where it goes.
  M copyStateInto<M extends SceneMotion<T>>(M other) => other;
}

/// The imposed properties, animatable on every node whatever its kind.
extension SceneNodeAnimate on SceneNode {
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
  });
}

extension TextNodeAnimate on TextNode {
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
    MotionTrack? fontSize,
    MotionTrack? color,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
    'fontSize': fontSize,
    'color': color,
  });
}

extension FrameNodeAnimate on FrameNode {
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
    MotionTrack? gap,
    MotionTrack? fill,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
    'gap': gap,
    'fill': fill,
  });
}

extension ShapeNodeAnimate on ShapeNode {
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
    MotionTrack? fill,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
    'fill': fill,
  });
}

/// The generated track object a motion carries — a slot per animatable
/// argument, so `args: {'progress': …}` for a parameter the widget does not
/// have is not refused but unwritable.
abstract class SceneExtTracks {
  const SceneExtTracks();

  Map<String, MotionTrack> toMap();
}

extension ExternalNodeAnimate on ExternalNode {
  /// [args] is the widget's generated tracks class — one slot per declared
  /// argument, so a track aimed at a parameter the widget does not take
  /// does not compile.
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
    SceneExtTracks? args,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
  }, args: args);
}

extension SceneRefNodeAnimate on SceneRefNode {
  AnimateGroup animate({
    MotionTrack? opacity,
    MotionTrack? translateX,
    MotionTrack? translateY,
    MotionTrack? scale,
    MotionTrack? rotate,
    SceneExtTracks? args,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
  }, args: args);
}

AnimateGroup _group(
  SceneNode node,
  Map<String, MotionTrack?> tracks, {
  SceneExtTracks? args,
}) {
  var group = AnimateGroup(node);
  for (var entry in tracks.entries) {
    // Save writes no empty tracks, and neither does a hand-written file:
    // a property nobody animated is a property the group does not carry.
    if (entry.value case var track?) group.tracks[entry.key] = track;
  }
  if (args != null) group.args.addAll(args.toMap());
  return group;
}

/// Names a motion class member may not take: the header's super field, the
/// mandatory arrangement, the derived copy member, and what a motion
/// inherits from [Playable] — because a motion IS one, and a group that
/// shadowed `duration` or `apply` would not compile.
const motionReservedNames = {
  'scene',
  'timeline',
  'copy',
  'duration',
  'apply',
  'clearFx',
  'claimDriver',
  'releaseDriver',
};

class MotionDocument {
  MotionDocument({required this.sceneClassName});

  /// The scene class this motion animates — `extends SceneMotion<X>` and the
  /// type of `super.scene`.
  final String sceneClassName;

  /// Declared parameters (shared kinds with the scene's), referenced by key
  /// values.
  final params = <SceneParamDecl>[];

  /// Declaration order — the file's group fields.
  final groups = <AnimateGroup>[];

  /// Mandatory: what plays. `Par` of everything is the tool's default.
  TimelineExpr timeline = ParExpr([]);

  /// Re-resolve every group's target against [scene], by name.
  ///
  /// The editor's door, and only the editor's: a group holds a node object,
  /// and an undo that brings a deleted node back brings back a NEW object,
  /// leaving the group pointed at the one that went away. Names exist only
  /// where the source was read, which is exactly here.
  void repoint(SceneDocument scene) {
    for (var g in groups) {
      var node = scene.nodeNamed(g.node.name);
      if (node != null) g.node = node;
    }
  }

  AnimateGroup? groupNamed(String name) {
    for (var g in groups) {
      if (g.name == name) return g;
    }
    return null;
  }

  /// Every group placed in the timeline, in tree order.
  Iterable<AnimateGroup> placedRefs() sync* {
    Iterable<AnimateGroup> visit(TimelineExpr e) sync* {
      switch (e) {
        case AnimateGroup g:
          yield g;
        case ParExpr p:
          for (var c in p.children) {
            yield* visit(c);
          }
        case SeqExpr s:
          for (var c in s.children) {
            yield* visit(c);
          }
        case AtExpr a:
          yield* visit(a.child);
        case SpeedExpr s:
          yield* visit(s.child);
        case RepeatExpr r:
          yield* visit(r.child);
      }
    }

    yield* visit(timeline);
  }

  /// The motion at one moment, deep-copied — the other half of the editor's
  /// undo journal (the scene's is [SceneDocument.snapshot]).
  MotionSnapshot snapshot() {
    // The timeline places group OBJECTS, so a snapshot's arrangement has to
    // point at the snapshot's own copies rather than at the live ones.
    var copies = {for (var g in groups) g: g.copy()};
    return MotionSnapshot._(
      [...params],
      copies.values.toList(),
      _copyExpr(timeline, copies),
      // The target's name AS IT WAS, captured rather than read back off the
      // node: a rename between snapshot and restore moves the node's name,
      // and this is the string that has to survive it.
      [for (var g in groups) g.node.name],
    );
  }

  /// Write [state] back. Groups are REVIVED by name and keys by id, the way
  /// the scene revives nodes: a bound motion holds group objects and a
  /// player holds its writers, and an undo must not detach them.
  /// Write [state] back, re-pointing each group at [scene] by the name the
  /// snapshot recorded.
  ///
  /// [scene] is what makes an undo across a rename work. The scene's own
  /// restore revives nodes by name, so a node renamed since the snapshot
  /// comes back as a NEW object and a group left holding the old one would
  /// animate something nobody is drawing.
  void restore(MotionSnapshot state, {SceneDocument? scene}) {
    params
      ..clear()
      ..addAll(state._params);
    var live = {for (var g in groups) g.name: g};
    var revived = <AnimateGroup>[];
    for (var snap in state._groups) {
      var into = live[snap.name];
      if (into == null || !identical(into.node, snap.node)) {
        revived.add(snap.copy());
        continue;
      }
      _restoreTracks(into.tracks, snap.tracks);
      _restoreTracks(into.args, snap.args);
      revived.add(into);
    }
    if (scene != null) {
      for (var (index, g) in revived.indexed) {
        if (index >= state._targets.length) continue;
        var node = scene.nodeNamed(state._targets[index]);
        if (node != null) g.node = node;
      }
    }
    groups
      ..clear()
      ..addAll(revived);
    // Same mapping in the other direction: the snapshot's arrangement names
    // the snapshot's groups, and what plays has to be the live ones.
    var back = <AnimateGroup, AnimateGroup>{};
    for (var (index, snap) in state._groups.indexed) {
      if (index < revived.length) back[snap] = revived[index];
    }
    timeline = _copyExpr(state._timeline, back);
  }

  void _restoreTracks(
    Map<String, MotionTrack> into,
    Map<String, MotionTrack> from,
  ) {
    var liveKeys = {
      for (var track in into.values)
        for (var k in track.keys) k.id: k,
    };
    into.clear();
    for (var entry in from.entries) {
      var track = MotionTrack([], kind: entry.value.kind);
      for (var snap in entry.value.keys) {
        var key = liveKeys[snap.id];
        if (key == null) {
          track.keys.add(snap.copy());
        } else {
          key
            ..at = snap.at
            ..value = snap.value
            ..curve = snap.curve
            ..paramRef = snap.paramRef;
          track.keys.add(key);
        }
      }
      into[entry.key] = track;
    }
  }
}

/// One motion's state at a moment: opaque, made by
/// [MotionDocument.snapshot], consumed by [MotionDocument.restore].
class MotionSnapshot {
  MotionSnapshot._(this._params, this._groups, this._timeline, this._targets);

  final List<SceneParamDecl> _params;
  final List<AnimateGroup> _groups;
  final TimelineExpr _timeline;

  /// One node name per group, in [_groups] order — see [MotionDocument.restore].
  final List<String> _targets;
}

/// A copy of the arrangement with every placed group swapped through [map].
/// The shape is copied; the groups are not — they are looked up, because a
/// group placed in a timeline IS the group.
TimelineExpr _copyExpr(TimelineExpr e, Map<AnimateGroup, AnimateGroup> map) =>
    switch (e) {
      AnimateGroup g => map[g] ?? g,
      ParExpr p => ParExpr([for (var c in p.children) _copyExpr(c, map)]),
      SeqExpr s => SeqExpr([for (var c in s.children) _copyExpr(c, map)]),
      AtExpr a => AtExpr(a.offset, _copyExpr(a.child, map)),
      SpeedExpr s => SpeedExpr(s.factor, _copyExpr(s.child, map)),
      RepeatExpr r => RepeatExpr(r.times, _copyExpr(r.child, map)),
    };

/// The timeline expression, laid out: where each placed group starts and how
/// long the whole runs. What a timeline panel draws from, and what the
/// runtime computes for itself when it binds — the same arithmetic, kept here
/// so the picture and the playback cannot disagree.
extension MotionTimelineLayout on MotionDocument {
  /// How long [expr] runs. A group placed here is the group, so there is
  /// nothing to resolve and nothing that can dangle.
  Duration durationOf(TimelineExpr expr) => switch (expr) {
    AnimateGroup g => g.duration,
    ParExpr p => p.children.fold(
      Duration.zero,
      (m, c) => durationOf(c) > m ? durationOf(c) : m,
    ),
    SeqExpr s => s.children.fold(Duration.zero, (m, c) => m + durationOf(c)),
    AtExpr a => a.offset + durationOf(a.child),
    SpeedExpr s => Duration(
      microseconds: (durationOf(s.child).inMicroseconds / s.factor).round(),
    ),
    RepeatExpr r => durationOf(r.child) * r.times,
  };

  Duration get duration => durationOf(timeline);

  /// Where each placed group starts, by name. A group placed twice keeps its
  /// first placement; a `speed` scales nothing here yet, so a group inside one
  /// is drawn at its unscaled offset.
  Map<String, Duration> get placements {
    var out = <String, Duration>{};
    void visit(TimelineExpr e, Duration at) {
      switch (e) {
        case AnimateGroup g:
          out.putIfAbsent(g.name, () => at);
        case ParExpr p:
          for (var c in p.children) {
            visit(c, at);
          }
        case SeqExpr s:
          var t = at;
          for (var c in s.children) {
            visit(c, t);
            t += durationOf(c);
          }
        case AtExpr a:
          visit(a.child, at + a.offset);
        case SpeedExpr s:
          visit(s.child, at);
        case RepeatExpr r:
          visit(r.child, at);
      }
    }

    visit(timeline, Duration.zero);
    return out;
  }
}
