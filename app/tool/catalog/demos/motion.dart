import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Spike S5 — hardcoded Motion, driven from the host.
///
/// Everything here is throwaway per the spike brief in
/// `docs/superpowers/specs/2026-07-31-motion-design.md`: no plugin, no scan, no
/// file writer, no generated code. The const below stands in for what the
/// editor would write; the call sites in [_Stage] are the real proposal, and
/// are the whole of spike A.
///
/// Extensions the host drives:
///   `ext.flutterware.motion.seek`   `t=<ms>`      → sets the playhead
///   `ext.flutterware.motion.probe`                → builds, reads, clock
///   `ext.flutterware.motion.dilate` `value=<n>`   → timeDilation

// ---------------------------------------------------------------- the runtime

class Seg<T> {
  final Duration start;
  final Duration end;
  final T from;
  final T to;
  final Curve curve;

  const Seg({
    required this.start,
    required this.end,
    required this.from,
    required this.to,
    this.curve = Curves.linear,
  });
}

class MotionValues {
  final Duration duration;

  /// anchor → property → segments. Heterogeneous on purpose: the doc claims
  /// this costs exactly one cast at the lookup boundary, and this is where
  /// that claim is either true or not.
  final Map<String, Map<String, List<Seg<Object?>>>> anchors;

  const MotionValues({required this.duration, required this.anchors});
}

/// What `builder: (m)` hands you.
class MotionRuntime {
  MotionRuntime(this.values);

  final MotionValues values;
  double t = 0;

  /// Which `anchor.property` pairs the last build actually read — the
  /// three-state panel depends on this being observable, so the spike records
  /// it rather than assuming it.
  final reads = <String>{};

  /// Never cleared, so an empty [reads] can be told apart from a read that
  /// never happened.
  final readsEver = <String>{};

  MotionAnchor anchor(String name) => MotionAnchor._(this, name);

  Object? _valueAt(String anchor, String property) {
    reads.add('$anchor.$property');
    readsEver.add('$anchor.$property');
    var segs = values.anchors[anchor]?[property];
    if (segs == null || segs.isEmpty) return null;

    var ms = t;
    var first = segs.first;
    var last = segs.last;
    // Hold: before the first segment a property is its `from`, after the last
    // it is its `to`.
    if (ms <= first.start.inMilliseconds) return first.from;
    if (ms >= last.end.inMilliseconds) return last.to;

    for (var seg in segs) {
      var a = seg.start.inMilliseconds.toDouble();
      var b = seg.end.inMilliseconds.toDouble();
      if (ms >= a && ms <= b) {
        var u = b == a ? 1.0 : seg.curve.transform((ms - a) / (b - a));
        return _lerp(seg.from, seg.to, u);
      }
    }
    // In a gap between two segments, hold the earlier one's end.
    Seg<Object?>? previous;
    for (var seg in segs) {
      if (seg.end.inMilliseconds <= ms) previous = seg;
    }
    return previous?.to ?? first.from;
  }

  static Object? _lerp(Object? a, Object? b, double u) {
    if (a is double && b is double) return a + (b - a) * u;
    if (a is Color && b is Color) return Color.lerp(a, b, u);
    if (a is Offset && b is Offset) return Offset.lerp(a, b, u);
    throw StateError('no interpolation for ${a.runtimeType}');
  }
}

/// The framework class that declares the whole vocabulary, so `title.` offers
/// everything and nothing has to be generated.
class MotionAnchor {
  MotionAnchor._(this._runtime, this.name);

  final MotionRuntime _runtime;
  final String name;

  double get opacity => _number('opacity', 1);
  double get translate => _number('translate', 0);
  double get scale => _number('scale', 1);
  double get rotate => _number('rotate', 0);

  /// No natural identity, so nullable — `?? Colors.white` at the read site is
  /// where the un-animated value is stated.
  Color? get color {
    var value = _runtime._valueAt(name, 'color');
    return value is Color ? value : null;
  }

  double _number(String property, double fallback) {
    var value = _runtime._valueAt(name, property);
    return value is double ? value : fallback;
  }
}

class MotionScope extends StatefulWidget {
  const MotionScope({super.key, required this.motion, required this.builder});

  final MotionValues motion;
  final Widget Function(MotionRuntime m) builder;

  @override
  State<MotionScope> createState() => _MotionScopeState();
}

class _MotionScopeState extends State<MotionScope> {
  late final _runtime = MotionRuntime(widget.motion);
  var builds = 0;
  var lastFrameMs = 0;

  @override
  void initState() {
    super.initState();
    _registerExtensions(this);
  }

  void seek(double ms) => setState(() => _runtime.t = ms);

  @override
  Widget build(BuildContext context) {
    builds++;
    // NOT `currentFrameTimeStamp` — it asserts when no frame is in flight, and
    // in this guest builds happen outside the frame pipeline, so reading it
    // here threw and cost a spike run.
    lastFrameMs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMilliseconds;
    _runtime.reads.clear();
    return widget.builder(_runtime);
  }
}

// ------------------------------------------------------------ the host's door

_MotionScopeState? _live;
var _registered = false;

/// Set by a free-running ticker nobody rebuilds on — the clock probe. If this
/// advances between two host calls with no seek in between, the guest's clock
/// runs on wall time and the stage's own animations are not ours to freeze.
var _freeRunning = 0.0;
var _freeTicks = 0;

void _registerExtensions(_MotionScopeState state) {
  _live = state;
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.flutterware.motion.seek', (
    method,
    parameters,
  ) async {
    var live = _live;
    if (live == null) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': false}),
      );
    }
    live.seek(double.parse(parameters['t'] ?? '0'));
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'ok': true, 'builds': live.builds}),
    );
  });

  developer.registerExtension('ext.flutterware.motion.probe', (
    method,
    parameters,
  ) async {
    var live = _live;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'builds': live?.builds,
        't': live?._runtime.t,
        'reads': live?._runtime.reads.toList(),
        'readsEver': live?._runtime.readsEver.toList(),
        'anchors': live?._runtime.values.anchors.keys.toList(),
        'lastFrameMs': live?.lastFrameMs,
        'freeRunning': _freeRunning,
        'freeTicks': _freeTicks,
        'timeDilation': timeDilation,
      }),
    );
  });

  developer.registerExtension('ext.flutterware.motion.dilate', (
    method,
    parameters,
  ) async {
    timeDilation = double.parse(parameters['value'] ?? '1');
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'timeDilation': timeDilation}),
    );
  });
}

// ------------------------------------------------------- the generated values

/// Stands in for `onboarding.motion.dart` — the only thing the editor writes.
const onboardingMotion = MotionValues(
  duration: Duration(milliseconds: 700),
  anchors: {
    'title': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 400),
          from: 0,
          to: 1,
          curve: Curves.easeInOutCubic,
        ),
      ],
      'translate': [
        Seg<double>(
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 500),
          from: 24,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'field': {
      'opacity': [
        Seg<double>(
          start: Duration(milliseconds: 250),
          end: Duration(milliseconds: 600),
          from: 0,
          to: 1,
          curve: Curves.easeInOutCubic,
        ),
      ],
      'translate': [
        Seg<double>(
          start: Duration(milliseconds: 250),
          end: Duration(milliseconds: 600),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    'cta': {
      'scale': [
        Seg<double>(
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 700),
          from: 0.92,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
      'color': [
        Seg<Color>(
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 700),
          from: Color(0xFFC4C7CD),
          to: Color(0xFF2F9E63),
          curve: Curves.easeInOutCubic,
        ),
      ],
    },
  },
);

// ------------------------------------------------------------------ the stage

@Demo(name: 'Onboarding', group: 'Motion', wrapper: wrapInApp)
Widget motionOnboarding() => const _Stage();

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  /// Nothing rebuilds on this. It exists to answer S5b: is the guest's clock
  /// ours, or does it run free?
  ///
  /// Constructed in [initState] rather than as a `late final` initializer,
  /// because lazy initialisation meant it was never built at all — and the
  /// obvious fix, touching `_free.value`, calls `stop()` in its setter and
  /// killed the ticker instead. Two spike runs.
  late final AnimationController _free;

  var _wide = false;

  @override
  void initState() {
    super.initState();
    _free =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(() {
            _freeRunning = _free.value;
            _freeTicks++;
          })
          ..repeat();
  }

  @override
  void dispose() {
    _free.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ---- spike A starts here: this is the proposal, written by hand ----
    return MotionScope(
      motion: onboardingMotion,
      builder: (m) {
        var title = m.anchor('title');
        var field = m.anchor('field');
        var cta = m.anchor('cta');

        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 20,
              children: [
                Opacity(
                  opacity: title.opacity,
                  child: Transform.translate(
                    offset: Offset(0, title.translate),
                    child: const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: field.opacity,
                  child: Transform.translate(
                    offset: Offset(0, field.translate),
                    child: const TextField(
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: cta.scale,
                  child: FilledButton(
                    onPressed: () => setState(() => _wide = !_wide),
                    style: FilledButton.styleFrom(
                      backgroundColor: cta.color ?? Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
                // ---- spike A ends. Below is S5b's implicit animation, which
                // the Motion does not own and cannot see. ----
                AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  width: _wide ? 240 : 80,
                  height: 6,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void main() => runApp(wrapInApp(motionOnboarding()));
