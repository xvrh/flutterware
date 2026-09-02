// The motion document model — the editor-plane half of the motion grammar
// (sketches 17–25). A motion names its scene, declares
// animation groups over that scene's nodes (typed targets, field-name
// identity — the same law the scene settled), arranges them on a mandatory
// `timeline`, and may keep unplaced groups as library assets fired on events.
import 'model.dart';

/// What a track's values are. Mirrors the scene's parameter kinds minus
/// string — words are not tweened.
enum TrackKind { number, color }

/// One keyframe. `value` is a double or a Color per the owning track's kind;
/// `curve` is an allowlisted `Curves.<name>` (null = linear); `paramRef` is
/// provenance — which motion parameter fed the value — and survives a save
/// only while the value still equals that parameter's default.
class MotionKey {
  MotionKey({required this.at, required this.value, this.curve, this.paramRef})
    : id = _nextId++;

  MotionKey._copy(this.id, this.at, this.value, this.curve, this.paramRef);

  static var _nextId = 1;

  /// Runtime identity. A key has no name, so nothing on disk carries this —
  /// but the timeline must hold a selection while keys are dragged past one
  /// another (which re-sorts the list) and across an undo (which restores
  /// values into the same objects), and an index cannot do that.
  final int id;

  Duration at;
  Object value;
  String? curve;
  String? paramRef;

  MotionKey copy() => MotionKey._copy(id, at, value, curve, paramRef);
}

/// A mutable track with the door the probes demanded: key *values* retune
/// freely; key *time* moves, inserts and removes go through methods that
/// keep the list sorted — the everyday editor drag past a neighbour would
/// otherwise silently break the hold rule.
class MotionTrack {
  MotionTrack(this.kind, [List<MotionKey>? keys]) : keys = keys ?? [] {
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

  MotionTrack copy() => MotionTrack(kind, [for (var k in keys) k.copy()]);
}

/// One `late final <name> = scene.<target>.animate(…)` field. The field name
/// is the group's identity; the target is a scene node's field name, and the
/// legal properties come from [animatableProps] for that node's kind.
class AnimateGroup {
  AnimateGroup(this.name, this.target);

  final String name;
  final String target;

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

  AnimateGroup copy() => AnimateGroup(name, target)
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

class GroupRef extends TimelineExpr {
  GroupRef(this.name);
  final String name;
}

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

/// Names a motion class member may not take: the header's super field, the
/// mandatory arrangement, and the derived copy member.
const motionReservedNames = {'scene', 'timeline', 'copy'};

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

  AnimateGroup? groupNamed(String name) {
    for (var g in groups) {
      if (g.name == name) return g;
    }
    return null;
  }

  /// Every group reference in the timeline, in tree order.
  Iterable<GroupRef> placedRefs() sync* {
    Iterable<GroupRef> visit(TimelineExpr e) sync* {
      switch (e) {
        case GroupRef r:
          yield r;
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
  MotionSnapshot snapshot() => MotionSnapshot._(
    [...params],
    [for (var g in groups) g.copy()],
    _copyExpr(timeline),
  );

  /// Write [state] back. Groups are REVIVED by name and keys by id, the way
  /// the scene revives nodes: a bound motion holds group objects and a
  /// player holds its writers, and an undo must not detach them.
  void restore(MotionSnapshot state) {
    params
      ..clear()
      ..addAll(state._params);
    var live = {for (var g in groups) g.name: g};
    var revived = <AnimateGroup>[];
    for (var snap in state._groups) {
      var into = live[snap.name];
      if (into == null || into.target != snap.target) {
        revived.add(snap.copy());
        continue;
      }
      _restoreTracks(into.tracks, snap.tracks);
      _restoreTracks(into.args, snap.args);
      revived.add(into);
    }
    groups
      ..clear()
      ..addAll(revived);
    timeline = _copyExpr(state._timeline);
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
      var track = MotionTrack(entry.value.kind);
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
  MotionSnapshot._(this._params, this._groups, this._timeline);

  final List<SceneParamDecl> _params;
  final List<AnimateGroup> _groups;
  final TimelineExpr _timeline;
}

TimelineExpr _copyExpr(TimelineExpr e) => switch (e) {
  GroupRef r => GroupRef(r.name),
  ParExpr p => ParExpr([for (var c in p.children) _copyExpr(c)]),
  SeqExpr s => SeqExpr([for (var c in s.children) _copyExpr(c)]),
  AtExpr a => AtExpr(a.offset, _copyExpr(a.child)),
  SpeedExpr s => SpeedExpr(s.factor, _copyExpr(s.child)),
  RepeatExpr r => RepeatExpr(r.times, _copyExpr(r.child)),
};

/// The timeline expression, laid out: where each placed group starts and how
/// long the whole runs. What a timeline panel draws from, and what the
/// runtime computes for itself when it binds — the same arithmetic, kept here
/// so the picture and the playback cannot disagree.
extension MotionTimelineLayout on MotionDocument {
  /// How long [expr] runs, groups resolved against this document. A reference
  /// to a group that does not exist runs for no time rather than refusing:
  /// the timeline is edited live, and a dangling reference is a state the
  /// editor passes through.
  Duration durationOf(TimelineExpr expr) => switch (expr) {
    GroupRef r => groupNamed(r.name)?.duration ?? Duration.zero,
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
        case GroupRef r:
          out.putIfAbsent(r.name, () => at);
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
