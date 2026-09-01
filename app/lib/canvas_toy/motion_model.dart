// Disposable spike: the motion document model — the editor-plane half of the
// motion grammar rewrite (sketches 17–25). A motion names its scene, declares
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
  MotionKey({required this.at, required this.value, this.curve, this.paramRef});

  Duration at;
  Object value;
  String? curve;
  String? paramRef;
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
}

/// The imposed vocabulary: every node kind animates these.
const imposedProps = <(String, TrackKind)>[
  ('opacity', TrackKind.number),
  ('translateX', TrackKind.number),
  ('translateY', TrackKind.number),
  ('scale', TrackKind.number),
  ('rotate', TrackKind.number),
];

/// Imposed plus the target kind's intrinsic properties, in canonical emit
/// order.
List<(String, TrackKind)> animatableProps(SceneNode node) => [
  ...imposedProps,
  ...switch (node) {
    TextNode() => const [
      ('fontSize', TrackKind.number),
      ('color', TrackKind.color),
    ],
    FrameNode() => const [('gap', TrackKind.number), ('fill', TrackKind.color)],
    ShapeNode() => const [('fill', TrackKind.color)],
    ExternalNode() => const <(String, TrackKind)>[],
  },
];

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
}

/// The hard-coded "agent draft" intro for the coffee banner — the motion
/// sibling of [coffeeBannerDraft], target names matching its node fields.
MotionDocument coffeeIntroDraft() {
  var doc = MotionDocument(sceneClassName: 'BannerScene');
  doc.params.add(SceneParamDecl('slideFrom', SceneParamKind.number, 24.0));

  var headlineIn = AnimateGroup('headlineIn', 'headline');
  headlineIn.tracks['opacity'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.0),
    MotionKey(
      at: const Duration(milliseconds: 260),
      value: 1.0,
      curve: 'easeOut',
    ),
  ]);
  headlineIn.tracks['translateY'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 24.0, paramRef: 'slideFrom'),
    MotionKey(
      at: const Duration(milliseconds: 260),
      value: 0.0,
      curve: 'easeOut',
    ),
  ]);

  var glowMood = AnimateGroup('glowMood', 'glow');
  glowMood.tracks['opacity'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 1.0),
    MotionKey(at: const Duration(milliseconds: 900), value: 0.85),
    MotionKey(at: const Duration(milliseconds: 1800), value: 1.0),
  ]);

  var badgePop = AnimateGroup('badgePop', 'badge');
  badgePop.tracks['scale'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.6),
    MotionKey(
      at: const Duration(milliseconds: 240),
      value: 1.0,
      curve: 'easeOutBack',
    ),
  ]);
  badgePop.args['progress'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 0.0),
    MotionKey(at: const Duration(milliseconds: 300), value: 1.0),
  ]);

  // A library asset: not in the timeline, fired on events by its own player.
  var tapPulse = AnimateGroup('tapPulse', 'cta');
  tapPulse.tracks['scale'] = MotionTrack(TrackKind.number, [
    MotionKey(at: Duration.zero, value: 1.0),
    MotionKey(at: const Duration(milliseconds: 120), value: 1.06),
    MotionKey(at: const Duration(milliseconds: 240), value: 1.0),
  ]);

  doc.groups.addAll([headlineIn, glowMood, badgePop, tapPulse]);
  doc.timeline = ParExpr([
    GroupRef('headlineIn'),
    AtExpr(const Duration(milliseconds: 400), GroupRef('badgePop')),
    GroupRef('glowMood'),
  ]);
  return doc;
}
