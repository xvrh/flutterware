// The motion document model — the editor-plane half of the motion grammar
// (sketches 17–25). A motion names its scene, declares
// animation groups over that scene's nodes (typed targets, field-name
// identity — the same law the scene settled), arranges them on a mandatory
// `timeline`, and may keep unplaced groups as library assets fired on events.
import 'curves.dart';
import 'model.dart';
import 'props.dart';
import 'values.dart';

/// What a track's values are. Mirrors the scene's parameter kinds minus
/// string — words are not tweened.
enum TrackKind { number, color }

/// One keyframe. `value` is a double or a Color per the owning track's kind;
/// `curve` is one of [Curves] (null = linear); `paramRef` is
/// provenance — which motion parameter fed the value. The reference is the
/// stronger of the two: an edit to the key moves the parameter's default
/// ([reconcileMotionBindings]), and a save always spells the reference.
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

  /// Blocks instead of keys — see [MotionClip], kept sorted by start. A
  /// track has one or the other: a block's keys would be derived, so a key
  /// added to a block track replaces the blocks, and a block put on a key
  /// track replaces the keys. Two blocks that overlap crossfade over the
  /// overlap. The timeline draws bars for them; the file spells
  /// [ClipTrack] for one and [ClipBlocks] for several.
  final clips = <MotionClip>[];

  void sortClips() => clips.sort((a, b) => a.at.compareTo(b.at));

  Duration get duration => clips.isNotEmpty
      ? clips.map((c) => c.end).reduce((a, b) => a > b ? a : b)
      : keys.isEmpty
      ? Duration.zero
      : keys.last.at;

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

  MotionTrack copy() =>
      MotionTrack([for (var k in keys) k.copy()], kind: kind)
        ..clips.addAll([for (var c in clips) c.copy()]);
}

/// A run through a placement's clip, as one block on the timeline: from
/// [at] for [length], the clip's own time advancing at [speed] from
/// [offset] — backwards when [reverse]. It stands on a number track (a
/// placement's `animationTime`) and lowers to a straight ramp: the value at
/// a moment is where the clip's time has got to. Past the block's end the
/// value holds, like a track past its last key; how a time past the clip's
/// own end reads is the placement's `loop` row, which wraps it.
///
/// Which clip runs is [clip] — a name in the placement's asset — or, when
/// that is empty, whatever the placement's `animation` row names. Two
/// blocks on one track may overlap, and over the overlap the earlier fades
/// into the later: the runtime hands the placement both clips, both times
/// and a `blend` that runs 0 to 1 across the overlap.
class MotionClip {
  MotionClip({
    required this.at,
    required this.length,
    this.clip = '',
    this.speed = 1,
    this.offset = Duration.zero,
    this.reverse = false,
  }) : id = _nextId++;

  MotionClip._copy(
    this.id,
    this.at,
    this.length,
    this.clip,
    this.speed,
    this.offset,
    this.reverse,
  );

  static var _nextId = 1;

  /// Runtime identity, for the same reason a [MotionKey] has one: the
  /// timeline holds a selected block while a drag re-sorts the list and
  /// across an undo. Nothing on disk carries it.
  final int id;

  /// The clip's name in the asset, or empty for the placement's own row.
  String clip;

  /// Where the block starts, within its group.
  Duration at;

  /// How long it runs on the timeline.
  Duration length;

  /// Clip seconds per timeline second.
  double speed;

  /// Where in the clip the run starts.
  Duration offset;

  /// Whether the clip's time runs down instead of up.
  bool reverse;

  Duration get end => at + length;

  /// The clip's own time at timeline moment [t], in seconds — held at the
  /// block's ends.
  double timeAt(Duration t) {
    var into = t - at;
    if (into < Duration.zero) into = Duration.zero;
    if (into > length) into = length;
    var run = reverse ? length - into : into;
    return offset.inMicroseconds / 1e6 + run.inMicroseconds / 1e6 * speed;
  }

  MotionClip copy() =>
      MotionClip._copy(id, at, length, clip, speed, offset, reverse);
}

/// The file's word for one block among several — see [ClipBlocks].
typedef ClipBlock = MotionClip;

/// What a motion file spells for a block: `animationTime: ClipTrack(at:
/// 0.ms, length: 2400.ms)`. A [MotionTrack] with the block and no keys, so
/// the typed `animate()` signatures take it where they take any track.
class ClipTrack extends MotionTrack {
  ClipTrack({
    required Duration at,
    required Duration length,
    String clip = '',
    double speed = 1,
    Duration offset = Duration.zero,
    bool reverse = false,
  }) : super([], kind: TrackKind.number) {
    clips.add(
      MotionClip(
        at: at,
        length: length,
        clip: clip,
        speed: speed,
        offset: offset,
        reverse: reverse,
      ),
    );
  }
}

/// Several blocks on one track — `animationTime: ClipBlocks([ClipBlock(clip:
/// 'Walk', at: 0.ms, length: 1000.ms), ClipBlock(clip: 'Run', at: 700.ms,
/// length: 1700.ms)])` — crossfading where they overlap.
class ClipBlocks extends MotionTrack {
  ClipBlocks(List<MotionClip> blocks) : super([], kind: TrackKind.number) {
    clips.addAll(blocks);
    sortClips();
  }
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

  /// Key → track, non-empty only: Save writes no empty tracks (an
  /// always-present empty track is a *runtime* affordance, not a file one).
  ///
  /// Keyed by the SCENE'S OWN key space, so a part of a property is a track
  /// like any other: `args.headline` for a widget's argument, `axes.wght`
  /// for a face's weight. The FILE spells those two differently — a dotted
  /// name cannot be a Dart named argument, so each rides a map of its own —
  /// but that is the grammar's problem, and one map here is what lets a
  /// track be looked up, written and reconciled without asking which sort
  /// it is.
  final tracks = <String, MotionTrack>{};

  Duration get duration =>
      [for (var t in tracks.values) t.duration]
          .fold(Duration.zero, (m, d) => d > m ? d : m);

  AnimateGroup copy() =>
      AnimateGroup(node, name: name)
        ..tracks.addAll({for (var e in tracks.entries) e.key: e.value.copy()});
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
      // Tracking is the one a display size wants animated, and it wants it
      // negative: a title that tightens as it lands.
      ScenePropSpec(
        'letterSpacing',
        TrackKind.number,
        identity: 0,
        unit: 'px',
        softMin: -8,
        softMax: 24,
        entrance: 12,
      ),
      ScenePropSpec(
        'wordSpacing',
        TrackKind.number,
        identity: 0,
        unit: 'px',
        softMin: -8,
        softMax: 24,
      ),
      ScenePropSpec(
        'lineHeight',
        TrackKind.number,
        identity: 1.15,
        softMin: 0.8,
        softMax: 2,
      ),
      ScenePropSpec(
        'decorationThickness',
        TrackKind.number,
        identity: 1,
        softMin: 0,
        softMax: 6,
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
    // A registered kind's rows, with the hints the row carries.
    KindNode k => [
      for (var p in k.kind.props)
        if (p.animatable)
          ScenePropSpec(
            p.name,
            p.kind == ScenePropKind.color ? TrackKind.color : TrackKind.number,
            identity: p.identity,
            unit: p.unit,
            softMin: p.softMin,
            softMax: p.softMax,
            angular: p.angular,
          ),
    ],
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
abstract class SceneMotion<T extends SceneDefinition> {
  SceneMotion(this.scene);

  final T scene;

  /// What plays. Groups place themselves in it, so nothing is looked up.
  TimelineExpr get timeline;

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
    MotionTrack? letterSpacing,
    MotionTrack? wordSpacing,
    MotionTrack? lineHeight,
    MotionTrack? decorationThickness,
    MotionTrack? color,

    /// The face's variable axes, by tag — `{'wght': MotionTrack([…])}`. A
    /// map rather than named arguments because the tags come from the font,
    /// not from this table, which is the same reason an external widget's
    /// arguments arrive as one.
    Map<String, MotionTrack>? axes,
  }) => _group(this, {
    'opacity': opacity,
    'translateX': translateX,
    'translateY': translateY,
    'scale': scale,
    'rotate': rotate,
    'fontSize': fontSize,
    'letterSpacing': letterSpacing,
    'wordSpacing': wordSpacing,
    'lineHeight': lineHeight,
    'decorationThickness': decorationThickness,
    'color': color,
  }, axes: axes);
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

/// The door a registered kind's typed `animate()` goes through — the same
/// one the hand-written kinds use, named so it can be called from outside.
AnimateGroup animateNode(SceneNode node, Map<String, MotionTrack?> tracks) =>
    _group(node, tracks);

AnimateGroup _group(
  SceneNode node,
  Map<String, MotionTrack?> tracks, {
  SceneExtTracks? args,
  Map<String, MotionTrack>? axes,
}) {
  var group = AnimateGroup(node);
  for (var entry in tracks.entries) {
    // Save writes no empty tracks, and neither does a hand-written file:
    // a property nobody animated is a property the group does not carry.
    if (entry.value case var track?) group.tracks[entry.key] = track;
  }
  // The two that arrive as maps take the key they are filed under: a part
  // of a property is a track like any other once it is in.
  for (var e
      in args?.toMap().entries ?? const <MapEntry<String, MotionTrack>>[]) {
    group.tracks['$sceneArgsPrefix${e.key}'] = e.value;
  }
  for (var e in axes?.entries ?? const <MapEntry<String, MotionTrack>>[]) {
    group.tracks['$sceneAxesPrefix${e.key}'] = e.value;
  }
  return group;
}

/// Names a motion class member may not take: the header's super field, the
/// mandatory arrangement, and the derived copy member.
///
/// Three, and it stays three. Every name this class owns is a group name
/// the author cannot use, so the runtime reaches a motion from OUTSIDE —
/// `SceneMotionPlay.playable`, an extension — rather than being inherited
/// into their namespace. A base class that grew a member would take a name
/// away from every motion ever written.
const motionReservedNames = {'scene', 'timeline', 'copy'};

class MotionDocument {
  MotionDocument({required this.sceneClassName});

  /// The scene class this motion animates — `extends SceneMotion<X>` and the
  /// type of `super.scene`.
  final String sceneClassName;

  /// Declared parameters (shared kinds with the scene's), referenced by key
  /// values.
  final params = <SceneParamDecl>[];

  /// Every key reading [param] — what a rename follows and a delete names.
  List<MotionKey> keysReading(String param) => [
    for (var g in groups)
      for (var t in g.tracks.values)
        for (var k in t.keys)
          if (k.paramRef == param) k,
  ];

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
      var track = MotionTrack([], kind: entry.value.kind)
        ..clips.addAll([for (var c in entry.value.clips) c.copy()]);
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

/// The motion half of the binding rule: a key whose value moved off its
/// parameter's default moves the default, and every other key reading that
/// parameter follows. A key reading a parameter that is no longer declared
/// loses the reference in the same edit, reported by group and property,
/// rather than at save. Run by the editor after each mutation.
List<String> reconcileMotionBindings(MotionDocument motion) {
  var dropped = <String>[];
  for (var g in motion.groups) {
    for (var e in g.tracks.entries) {
      for (var k in e.value.keys) {
        var name = k.paramRef;
        if (name == null) continue;
        var i = motion.params.indexWhere((p) => p.name == name);
        var decl = i < 0 ? null : motion.params[i];
        var kind = e.value.kind == TrackKind.color
            ? SceneParamKind.color
            : SceneParamKind.number;
        if (decl == null || decl.kind != kind) {
          k.paramRef = null;
          dropped.add('${g.name}.${e.key}');
        } else if (decl.defaultValue != k.value) {
          motion.params[i] = decl.withDefault(k.value);
          for (var other in motion.keysReading(name)) {
            if (!identical(other, k)) other.value = k.value;
          }
        }
      }
    }
  }
  return dropped;
}
