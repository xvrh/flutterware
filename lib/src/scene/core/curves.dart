// The 13-curve allowlist as evaluable objects — the runtime side of the
// motion grammar's `SceneCurves.<name>` spelling, pure Dart. Each implementation
// is ported verbatim from the pinned Flutter SDK (3.48.0-0.2.pre,
// animation/curves.dart) so a frame evaluated here matches one the framework
// would have shaped: same control points, same bisection, same error bound.
// A test in the app package holds all 13 to Flutter's across sampled inputs.
import 'dart:math' as math;

abstract class SceneCurve {
  const SceneCurve(this.name);

  /// The allowlisted spelling — `SceneCurves.<name>` in a file, and the string
  /// JSON carries. The curve is an OBJECT everywhere else: a key holds the
  /// one it eases with, so a name is never looked up to animate anything.
  final String name;

  double transform(double t) {
    assert(t >= 0.0 && t <= 1.0, 'curve input $t is outside 0..1');
    if (t == 0.0 || t == 1.0) return t;
    return transformInternal(t);
  }

  double transformInternal(double t);
}

class _Linear extends SceneCurve {
  const _Linear(super.name);

  @override
  double transformInternal(double t) => t;
}

class _Cubic extends SceneCurve {
  const _Cubic(super.name, this.a, this.b, this.c, this.d);

  final double a;
  final double b;
  final double c;
  final double d;

  static const _errorBound = 0.001;

  double _evaluate(double a, double b, double m) =>
      3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m;

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    var start = 0.0;
    var end = 1.0;
    while (true) {
      var midpoint = (start + end) / 2;
      var estimate = _evaluate(a, c, midpoint);
      if ((t - estimate).abs() < _errorBound) return _evaluate(b, d, midpoint);
      if (estimate < t) {
        start = midpoint;
      } else {
        end = midpoint;
      }
    }
  }
}

class _Decelerate extends SceneCurve {
  const _Decelerate(super.name);

  @override
  double transformInternal(double t) {
    t = 1.0 - t;
    return 1.0 - t * t;
  }
}

class _BounceOut extends SceneCurve {
  const _BounceOut(super.name);

  @override
  double transformInternal(double t) {
    if (t < 1.0 / 2.75) {
      return 7.5625 * t * t;
    } else if (t < 2 / 2.75) {
      t -= 1.5 / 2.75;
      return 7.5625 * t * t + 0.75;
    } else if (t < 2.5 / 2.75) {
      t -= 2.25 / 2.75;
      return 7.5625 * t * t + 0.9375;
    }
    t -= 2.625 / 2.75;
    return 7.5625 * t * t + 0.984375;
  }
}

class _ElasticOut extends SceneCurve {
  const _ElasticOut(super.name, this.period);

  final double period;

  @override
  double transformInternal(double t) {
    var s = period / 4.0;
    return math.pow(2.0, -10 * t) *
            math.sin((t - s) * (math.pi * 2.0) / period) +
        1.0;
  }
}

/// The curve allowlist, as the file spells it. `SceneCurves.easeOutBack` in a
/// scene file is exactly this constant — so a mistyped curve is a compile
/// error rather than a silent fall back to linear.
///
/// Named for Flutter's `Curves`, which each is ported from verbatim, and
/// prefixed like every other value in this vocabulary — a file that imports
/// both this and material must still be able to say which it means.
abstract final class SceneCurves {
  static const linear = _Linear('linear');
  static const ease = _Cubic('ease', 0.25, 0.1, 0.25, 1.0);
  static const easeIn = _Cubic('easeIn', 0.42, 0.0, 1.0, 1.0);
  static const easeOut = _Cubic('easeOut', 0.0, 0.0, 0.58, 1.0);
  static const easeInOut = _Cubic('easeInOut', 0.42, 0.0, 0.58, 1.0);
  static const easeInBack = _Cubic('easeInBack', 0.6, -0.28, 0.735, 0.045);
  static const easeOutBack = _Cubic('easeOutBack', 0.175, 0.885, 0.32, 1.275);
  static const easeInCubic = _Cubic('easeInCubic', 0.55, 0.055, 0.675, 0.19);
  static const easeOutCubic = _Cubic('easeOutCubic', 0.215, 0.61, 0.355, 1.0);
  static const decelerate = _Decelerate('decelerate');
  static const fastOutSlowIn = _Cubic('fastOutSlowIn', 0.4, 0.0, 0.2, 1.0);
  static const bounceOut = _BounceOut('bounceOut');
  static const elasticOut = _ElasticOut('elasticOut', 0.4);
}

/// The same thirteen by name — what JSON reads back, and what the parser
/// resolves `SceneCurves.<name>` through. A test holds this list to [Curves].
const sceneCurvesByName = <String, SceneCurve>{
  'linear': SceneCurves.linear,
  'ease': SceneCurves.ease,
  'easeIn': SceneCurves.easeIn,
  'easeOut': SceneCurves.easeOut,
  'easeInOut': SceneCurves.easeInOut,
  'easeInBack': SceneCurves.easeInBack,
  'easeOutBack': SceneCurves.easeOutBack,
  'easeInCubic': SceneCurves.easeInCubic,
  'easeOutCubic': SceneCurves.easeOutCubic,
  'decelerate': SceneCurves.decelerate,
  'fastOutSlowIn': SceneCurves.fastOutSlowIn,
  'bounceOut': SceneCurves.bounceOut,
  'elasticOut': SceneCurves.elasticOut,
};
