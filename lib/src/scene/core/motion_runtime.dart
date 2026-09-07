// The motion runtime — the half that plays what the grammar persists. Every
// shape here was probed first (sketches 17–25): tracks evaluate under the
// hold rule with the curve riding the arriving key; a bound motion writes
// contributions into the scene nodes' fx plane (writer-keyed, stack-ordered,
// composed over the LIVE authored base); combinators are pure time
// transforms, so seek and backwards scrub cost nothing; Repeat's last frame
// holds the child's end, not cycle-0; and the player is the APPLICATOR —
// the ticker is almost incidental, and lives in the Flutter half
// (lib/src/scene/player.dart).
//
// Binding is the document-plane version of the pair: group targets resolve
// by name against the scene the motion is bound to, and a name the scene
// does not have refuses at bind — the copy-trap guard, one moment early.
import 'curves.dart';
import 'model.dart';
import 'motion_model.dart';
import 'values.dart';

extension MotionTrackEvaluate on MotionTrack {
  /// The hold rule: before the first key its value, after the last the
  /// last, and between neighbours a lerp shaped by the ARRIVING key's
  /// curve. Pure in [t] — backwards seek needs no history.
  Object evaluate(Duration t) {
    if (keys.isEmpty) {
      throw StateError(
        'an empty track has no value — it contributes '
        'nothing and should not be evaluated',
      );
    }
    if (t <= keys.first.at) return keys.first.value;
    if (t >= keys.last.at) return keys.last.value;
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i].at) {
        var a = keys[i - 1], b = keys[i];
        var u = (t - a.at).inMicroseconds / (b.at - a.at).inMicroseconds;
        var shaped = (b.curve ?? SceneCurves.linear).transform(u);
        return switch (kind) {
          TrackKind.number =>
            (a.value as double) +
                ((b.value as double) - (a.value as double)) * shaped,
          TrackKind.color => SceneColor.lerp(
            a.value as SceneColor,
            b.value as SceneColor,
            shaped,
          ),
        };
      }
    }
    return keys.last.value;
  }
}

/// Anything that can play: a duration and a total apply — a child before
/// its window applies at 0, after it at its end (the hold rule, one level
/// up). Groups, whole motions and combinators are all this one thing,
/// which is what makes independent play the same call as playing the
/// motion.
abstract class Playable {
  /// One driver at a time: two players ticking one playable is a per-frame
  /// double-write. Claimed by the player's play, released on stop, dispose
  /// or completion.
  Object? _driver;

  /// Claim exclusive drive. Refuses (with the fix) when another driver
  /// holds it; re-claiming by the same driver is a no-op.
  void claimDriver(Object driver) {
    var current = _driver;
    if (current != null && !identical(current, driver)) {
      throw StateError(
        'this playable is already driven by another player — one driver at '
        'a time (two would double-write every frame); stop the other '
        'player first',
      );
    }
    _driver = driver;
  }

  /// Release, if [driver] is the one holding it.
  void releaseDriver(Object driver) {
    if (identical(_driver, driver)) _driver = null;
  }

  Duration get duration;

  void apply(Duration t);

  /// Remove this playable's contributions — cancel semantics: the authored
  /// values were never touched (probed).
  void clearFx();
}

/// One group, bound to its node: the leaf writer. The group object itself
/// is the writer identity in the fx stack, so first write fixes its
/// position and re-writes stay put (probe M8).
class BoundGroup extends Playable {
  BoundGroup._(this.group) : node = group.node;

  final AnimateGroup group;
  final SceneNode node;

  @override
  Duration get duration => group.duration;

  @override
  void apply(Duration t) {
    for (var entry in group.tracks.entries) {
      node.writeFx(this, entry.key, entry.value.evaluate(t));
    }
    for (var entry in group.args.entries) {
      node.writeFx(this, 'args.${entry.key}', entry.value.evaluate(t));
    }
  }

  @override
  void clearFx() => node.clearFxWriter(this);
}

class _Par extends Playable {
  _Par(this.children);
  final List<Playable> children;
  @override
  Duration get duration =>
      children.fold(Duration.zero, (m, c) => c.duration > m ? c.duration : m);
  @override
  void apply(Duration t) {
    for (var c in children) {
      c.apply(_clamp(t, c.duration));
    }
  }

  @override
  void clearFx() {
    for (var c in children) {
      c.clearFx();
    }
  }
}

class _Seq extends Playable {
  _Seq(this.children);
  final List<Playable> children;
  @override
  Duration get duration =>
      children.fold(Duration.zero, (s, c) => s + c.duration);
  @override
  void apply(Duration t) {
    var start = Duration.zero;
    for (var c in children) {
      c.apply(_clamp(t - start, c.duration));
      start += c.duration;
    }
  }

  @override
  void clearFx() {
    for (var c in children) {
      c.clearFx();
    }
  }
}

class _At extends Playable {
  _At(this.offset, this.child);
  final Duration offset;
  final Playable child;
  @override
  Duration get duration => offset + child.duration;
  @override
  void apply(Duration t) => child.apply(_clamp(t - offset, child.duration));
  @override
  void clearFx() => child.clearFx();
}

class _Speed extends Playable {
  _Speed(this.factor, this.child);
  final double factor;
  final Playable child;
  @override
  Duration get duration =>
      Duration(microseconds: (child.duration.inMicroseconds / factor).round());
  @override
  void apply(Duration t) => child.apply(_clamp(t * factor, child.duration));
  @override
  void clearFx() => child.clearFx();
}

class _Repeat extends Playable {
  _Repeat(this.times, this.child);
  final int times;
  final Playable child;
  @override
  Duration get duration => child.duration * times;
  @override
  void apply(Duration t) {
    // The last frame holds the child's END, not cycle-0 (probed: naive
    // modulo snaps a finished repeat back to its first frame).
    var one = child.duration.inMicroseconds;
    var local = t >= duration
        ? child.duration
        : Duration(microseconds: t.inMicroseconds % one);
    child.apply(local);
  }

  @override
  void clearFx() => child.clearFx();
}

Duration _clamp(Duration t, Duration max) =>
    t < Duration.zero ? Duration.zero : (t > max ? max : t);

/// An arrangement as something that plays.
///
/// Nothing is resolved here: a placed group IS the group, and a group holds
/// the node it animates. Binding is building the tree, which is why a
/// compiled motion needs no document and no scene to play — it hands its
/// own `timeline` over.
///
/// [into] caches one [BoundGroup] per group, so a group placed twice writes
/// through one writer rather than two that fight.
Playable playTimeline(
  TimelineExpr expr, {
  Map<AnimateGroup, BoundGroup>? into,
}) {
  var bound = into ?? <AnimateGroup, BoundGroup>{};
  Playable build(TimelineExpr e) => switch (e) {
    AnimateGroup g => bound.putIfAbsent(g, () => BoundGroup._(g)),
    ParExpr p => _Par([for (var c in p.children) build(c)]),
    SeqExpr s => _Seq([for (var c in s.children) build(c)]),
    AtExpr a => _At(a.offset, build(a.child)),
    SpeedExpr s => _Speed(s.factor, build(s.child)),
    RepeatExpr r => _Repeat(r.times, build(r.child)),
  };
  return build(expr);
}

/// A compiled motion's timeline as a playable tree, built once per motion.
///
/// An EXTENSION rather than a member of [SceneMotion], and that is the
/// point: a motion class's field names are the AUTHOR's — every name the
/// base class owns is a group they cannot declare — so the runtime reaches
/// a motion from outside instead of being inherited into their namespace.
/// A group called `duration` is now merely a group called `duration`.
///
/// Built once because a playable tree is an fx WRITER: two trees over one
/// motion would both contribute every frame, and stopping one would leave
/// the other's contribution behind.
extension SceneMotionPlay on SceneMotion {
  Playable get playable => _plays[this] ??= playTimeline(timeline);
}

final _plays = Expando<Playable>();

/// A motion document bound to one scene: the timeline built as a playable
/// tree, and the pair guarded. Unplaced groups bind too — [group] hands
/// them out for independent play — but only the timeline plays through
/// [apply].
class BoundMotion extends Playable {
  BoundMotion._(this.doc, this.scene, this._groups, this._root);

  factory BoundMotion.bind(MotionDocument doc, SceneDocument scene) {
    var nodes = {for (var (n, _) in scene.walk()) n};
    var bound = <AnimateGroup, BoundGroup>{};
    for (var g in doc.groups) {
      // The guard survives even though nothing is resolved: a motion still
      // has to be played against the scene it was authored against, and a
      // group pointing outside it is a wiring mistake worth naming.
      if (!nodes.contains(g.node)) {
        throw StateError(
          'the motion animates a node this scene does not have '
          '("${g.node.name}", from group "${g.name}") — bound against a '
          'different scene? Bind the pair that was authored together.',
        );
      }
      bound[g] = BoundGroup._(g);
    }
    return BoundMotion._(
      doc,
      scene,
      bound,
      playTimeline(doc.timeline, into: bound),
    );
  }

  final MotionDocument doc;
  final SceneDocument scene;
  final Map<AnimateGroup, BoundGroup> _groups;
  final Playable _root;

  /// A bound group by name — placed or library asset alike; hand it to its
  /// own player for independent play. Names are the editor's, so this is
  /// the editor's door; a compiled motion holds its groups as fields.
  BoundGroup group(String name) {
    for (var entry in _groups.entries) {
      if (entry.key.name == name) return entry.value;
    }
    throw ArgumentError('"$name" is not a group of this motion');
  }

  @override
  Duration get duration => _root.duration;

  @override
  void apply(Duration t) => _root.apply(t);

  @override
  void clearFx() => _root.clearFx();
}
