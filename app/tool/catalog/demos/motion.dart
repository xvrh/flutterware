import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/motion.dart';
import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Spike S5, now driving the published runtime rather than a sketch of it.
///
/// The const below stands in for what the editor will write to
/// `<screen>.motion.dart`; everything else is `package:flutterware/motion.dart`.
/// The transport extensions are the spike's own — the real ones belong in the
/// guest half of the plugin, which does not exist yet.
///
/// Extensions the host drives:
///   `ext.flutterware.motion.seek`   `t=<ms>`      → sets the playhead
///   `ext.flutterware.motion.probe`                → builds, reads, clock
///   `ext.flutterware.motion.dilate` `value=<n>`   → timeDilation

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
      'translateY': [
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
      'translateY': [
        Seg<double>(
          start: Duration(milliseconds: 250),
          end: Duration(milliseconds: 600),
          from: 16,
          to: 0,
          curve: Curves.easeOutCubic,
        ),
      ],
      'blur': [
        Seg<double>(
          start: Duration(milliseconds: 250),
          end: Duration(milliseconds: 600),
          from: 6,
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
          curve: Curves.easeOutBack,
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

// ------------------------------------------------------------ the host's door

final _scopeKey = GlobalKey<MotionScopeState>();
final _controller = MotionController(autoplay: false);
var _registered = false;
var _builds = 0;

/// Driven by a ticker nobody rebuilds on — the S5b clock probe.
var _freeRunning = 0.0;
var _freeTicks = 0;

void _registerExtensions() {
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.flutterware.motion.seek', (
    method,
    parameters,
  ) async {
    _controller.position = Duration(
      microseconds: (double.parse(parameters['t'] ?? '0') * 1000).round(),
    );
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'ok': true, 'progress': _controller.progress}),
    );
  });

  developer.registerExtension('ext.flutterware.motion.probe', (
    method,
    parameters,
  ) async {
    var state = _scopeKey.currentState;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'builds': _builds,
        't': _controller.position.inMilliseconds,
        'progress': _controller.progress,
        'reads': state?.reads.toList(),
        'offered': state?.offered.toList(),
        'anchors': state?.anchorsNamed.toList(),
        'lastFrameMs': 0,
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

// ------------------------------------------------------------------ the stage

@Demo(name: 'Onboarding', group: 'Motion', wrapper: wrapInApp)
Widget motionOnboarding() => const _Stage();

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  /// Nothing rebuilds on this. It answers S5b: does the guest's clock run free?
  ///
  /// Constructed here rather than as a `late final` initialiser, because lazy
  /// initialisation meant it was never built at all — and the obvious fix,
  /// touching `_free.value`, calls `stop()` in its setter and killed the ticker
  /// instead. Two spike runs.
  late final AnimationController _free;

  var _wide = false;

  @override
  void initState() {
    super.initState();
    _registerExtensions();
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
    return MotionScope(
      key: _scopeKey,
      motion: onboardingMotion,
      controller: _controller,
      builder: (m) {
        _builds++;
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
                MotionBox(
                  title,
                  child: const Text(
                    'Welcome back',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
                  ),
                ),
                MotionBox(
                  field,
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                MotionBox(
                  cta,
                  child: FilledButton(
                    onPressed: () => setState(() => _wide = !_wide),
                    style: FilledButton.styleFrom(
                      backgroundColor: cta.color ?? Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
                // S5b's implicit animation, which the Motion does not own and
                // cannot see. `timeDilation` is the lever that freezes it.
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
