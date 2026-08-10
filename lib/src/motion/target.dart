import 'package:flutter/widgets.dart';

import 'values.dart';

/// What `MotionScope`'s builder hands you.
///
/// Holds the playhead and the tuned values, and records what was read — the
/// last of which is not instrumentation. A panel cannot show which properties
/// are wired without it, and a getter on a plain object is the whole mechanism:
/// no annotation, no analysis, no registration.
class Motion {
  Motion(this.values);

  MotionValues values;

  /// Where the playhead is, in the same units the segments are written in.
  Duration position = Duration.zero;

  /// `target.property` pairs read at a call site during the current build.
  ///
  /// A panel shows one lane per entry here: tuned or not, somebody asked for
  /// this value and it reaches a widget.
  final reads = <String>{};

  /// Pairs read by a blanket reader — [MotionBox] sweeps its whole frozen set
  /// every build so that what it applies never depends on what happens to be
  /// tuned right now.
  ///
  /// Kept apart from [reads] because otherwise a single `MotionBox` would
  /// report eight wired properties and a panel would show eight empty lanes
  /// for an element that animates one thing. These are *available*, not wired.
  final offered = <String>{};

  var _offering = false;

  /// Targets named by [target] during the current build, whether or not any of
  /// their properties were read. A panel needs the difference: a target with
  /// no reads is a wiring mistake, a target that was never named is gone.
  final named = <String>{};

  MotionTarget target(String name) {
    named.add(name);
    return MotionTarget._(this, name);
  }

  void beginBuild() {
    reads.clear();
    offered.clear();
    named.clear();
  }

  /// Runs [body] with its reads recorded as [offered] rather than [reads].
  ///
  /// For helpers that read a fixed set regardless of what is tuned. Nothing a
  /// project writes should need this; `MotionBox` does.
  T offering<T>(T Function() body) {
    var was = _offering;
    _offering = true;
    try {
      return body();
    } finally {
      _offering = was;
    }
  }

  Object? read(String target, String property) {
    (_offering ? offered : reads).add('$target.$property');
    return peek(target, property);
  }

  /// Widgets that have said where a target is.
  ///
  /// **Not build-scoped**, unlike [reads] and [named]: a widget registers when
  /// it mounts and leaves when it is disposed, so this survives the
  /// [beginBuild] that clears the rest.
  ///
  /// Nothing here can be inferred. A target is not a widget — `art.width` goes
  /// on a `SizedBox`, `art.rotate` on a `Transform`, `art.elevation` inside a
  /// `BoxShadow` — so there is no element that *is* `art`, and somebody has to
  /// point. `MotionExtent` and `MotionBox` are how.
  final _extents = <String, Set<BuildContext>>{};

  void addExtent(String target, BuildContext context) =>
      (_extents[target] ??= {}).add(context);

  void removeExtent(String target, BuildContext context) {
    var registered = _extents[target];
    if (registered == null) return;
    registered.remove(context);
    if (registered.isEmpty) _extents.remove(target);
  }

  /// The targets something has pointed at, whether or not they laid out.
  Set<String> get extents => _extents.keys.toSet();

  /// Where [target] is, in the root's coordinates, or null when nothing has
  /// pointed at it or nothing it points to has been laid out.
  ///
  /// The union rather than the first, because a target read once per row of a
  /// list is several widgets and the honest answer is the box containing them.
  ///
  /// Transformed rather than measured: `getTransformTo(null)` walks the whole
  /// chain to the root, so a target inside a `MotionBox` reports where it has
  /// been *moved and scaled to* rather than where it was laid out. Reporting
  /// the layout box would leave the ring behind during the one thing a motion
  /// editor exists to watch.
  Rect? extentOf(String target) {
    Rect? bounds;
    for (var context in _extents[target] ?? const <BuildContext>{}) {
      if (!context.mounted) continue;
      var render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) continue;
      var rect = MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds;
  }

  /// What a property is worth right now, **without recording a read**.
  ///
  /// For a host asking what things are currently worth. Going through [read]
  /// would make the panel's own questions look like wiring, so the answer to
  /// "which properties reach a widget" would depend on whether anyone was
  /// looking.
  Object? peek(String target, String property) {
    var segments = values.segmentsFor(target, property);
    if (segments == null || segments.isEmpty) return null;
    return evaluateSegments(segments, position);
  }
}

/// One animated element, and the whole vocabulary it could carry.
///
/// Every property is declared here rather than generated, which is what lets
/// `title.` offer the full set the moment you have a target, and is why
/// nothing about this API needs a build step.
class MotionTarget {
  MotionTarget._(this._motion, this.name);

  final Motion _motion;
  final String name;

  /// The scope this target belongs to. Widgets that read a fixed set of
  /// properties wrap themselves in [Motion.offering] through this.
  Motion get motion => _motion;

  // Identity-having — a resting value, so never null.
  double get opacity => _number('opacity', 1);
  double get translateX => _number('translateX', 0);
  double get translateY => _number('translateY', 0);
  double get scale => _number('scale', 1);
  double get scaleX => _number('scaleX', 1);
  double get scaleY => _number('scaleY', 1);

  /// Radians, matching `Transform.rotate`. The panel shows degrees.
  double get rotate => _number('rotate', 0);

  double get blur => _number('blur', 0);
  double get elevation => _number('elevation', 0);
  double get padding => _number('padding', 0);

  /// A tuned number with no semantics, for everything the vocabulary does not
  /// name. This is the extension point, and it is deliberately one line rather
  /// than a plugin system.
  double get progress => _number('progress', 0);

  // No resting value — `?? base` at the read site is where you state it.
  Color? get color {
    var value = _motion.read(name, 'color');
    return value is Color ? value : null;
  }

  double? get width => _nullableNumber('width');
  double? get height => _nullableNumber('height');
  double? get borderRadius => _nullableNumber('borderRadius');
  double? get fontSize => _nullableNumber('fontSize');

  /// Composed, not tuned: `translateX` and `translateY` assembled.
  ///
  /// Exists because writing `Offset(0, title.translateY)` and having to
  /// remember which argument is the axis was the one thing that read badly
  /// when these call sites were first written by hand.
  Offset get translate => Offset(translateX, translateY);

  double _number(String property, double fallback) {
    var value = _motion.read(name, property);
    return value is double ? value : fallback;
  }

  double? _nullableNumber(String property) {
    var value = _motion.read(name, property);
    return value is double ? value : null;
  }

  @override
  String toString() => 'MotionTarget($name)';
}
