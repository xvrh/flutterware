import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'values.dart';

/// Which body a scope builds.
///
/// A motion with a draft stage has two, and they are the same motion — the
/// switch chooses between `builder` and `MotionStageView` *inside* one scope,
/// so the playhead, the registry id and the tuned values all survive the flip.
///
/// This is deliberately not a knob in anybody's file. Draft-versus-real is a
/// view onto one motion rather than a property of the app, so the tool owns it:
/// a file says what bodies exist and the studio says which one to look at.
enum MotionHost {
  /// The `builder` — real widgets, real layout, intrinsic properties read at
  /// the call site. What ships.
  real,

  /// The `stage` — placeholders the tool owns, positioned absolutely. What
  /// `motion new` writes and what an editor can add to.
  draft,
}

/// What the transport needs from a mounted scope.
///
/// Narrow on purpose: the registry must not depend on the widget, or a guest
/// that only wants to be scrubbable would drag the whole scope in. `MotionScope`
/// implements this; nothing else should.
abstract class MotionSurface {
  MotionValues get motionValues;
  MotionController get controller;

  /// `target.property` pairs the last build read at a call site.
  Set<String> get reads;

  /// Pairs a blanket reader swept — available, not evidence of wiring.
  Set<String> get offered;

  Set<String> get targetsNamed;

  /// The current value of one property **without recording a read**. A panel
  /// asking what things are worth must not change what the panel is told is
  /// wired.
  Object? peek(String target, String property);

  /// Where a target is on screen, in the guest's own coordinates, or null when
  /// nothing has pointed at it. See `MotionExtent`.
  Rect? extentOf(String target);

  /// The bodies this scope has, in the order a control should offer them.
  ///
  /// One of them is the normal case and the panel must not draw a switch for
  /// it: a scope with no stage can only refuse `draft`, and an affordance whose
  /// every use is a refusal is worse than no affordance.
  List<MotionHost> get hosts;

  /// Which body is building.
  MotionHost get host;

  /// Builds the other one from the next frame. A host not in [hosts] is
  /// ignored here and refused at the extension, where there is somebody to
  /// tell.
  set host(MotionHost value);
}

/// The door a motion is driven through from outside it.
///
/// Two doors, one object. A *host* in another process drives the service
/// extensions below; a *test* in the same isolate holds the registry directly
/// and writes the playhead with no RPC and no frame to wait for. The extensions
/// exist because of the process boundary, not because of the driving.
///
/// Registered by the first `MotionScope` to mount rather than before `runApp`,
/// because a motion lives in somebody's screen and there is no entrypoint of
/// ours to hang it on. A host that connects first sees no extension and waits
/// for one — the same late-registration the catalog's guest already handles.
///
///   `ext.flutterware.motion.list`                    every mounted scope
///   `ext.flutterware.motion.seek`     `scope`, `t`   0..1, or `ms`
///   `ext.flutterware.motion.transport` `scope`, `verb`
///   `ext.flutterware.motion.host`     `scope`, `host` draft or real
///
/// `seek` answers **after the frame**, so a reply means the picture has caught
/// up. A scrubber that answered earlier would report positions the screen had
/// not reached, which is indistinguishable from a slow guest and much harder to
/// diagnose.
class MotionRegistry {
  MotionRegistry._();

  static final instance = MotionRegistry._();

  // [attach] and [detach] belong to `MotionScope` and nothing else should call
  // them; they are public only because Dart has no package-private. What this
  // is exported *for* is [resolve] and [ids] — a test in the same isolate
  // reaches a mounted motion through them rather than over the VM service,
  // which is what `MotionTester` in `package:flutterware/flutter_test.dart`
  // does.

  final _scopes = <String, MotionSurface>{};
  var _nextId = 0;
  var _registered = false;

  /// Mount order, which is also the order the panel lists them in.
  Iterable<String> get ids => _scopes.keys;

  String attach(MotionSurface scope) {
    var id = '${_nextId++}';
    _scopes[id] = scope;
    _registerExtensions();
    return id;
  }

  void detach(String id) => _scopes.remove(id);

  /// The scope an argument names, the only one when there is only one, or null.
  ///
  /// Defaulting to the sole scope is what lets `fw` and a panel drive the
  /// common case — one stage, one motion — without first asking for an id.
  MotionSurface? resolve(String? id) {
    if (id != null && id.isNotEmpty) return _scopes[id];
    return _scopes.length == 1 ? _scopes.values.first : null;
  }

  void _registerExtensions() {
    if (_registered || kReleaseMode) return;
    _registered = true;

    developer.registerExtension('ext.flutterware.motion.list', (_, _) async {
      return developer.ServiceExtensionResponse.result(jsonEncode(describe()));
    });

    // The playhead alone, and nothing else.
    //
    // `list` walks every target and every segment, which is the wrong thing to
    // ask sixty times a second — and a transport bar that follows a playing
    // motion has to ask something at about that rate or it does not move. The
    // first panel polled `list` once a second and the bar simply jumped to the
    // end, because a 780ms motion is over before the second tick.
    developer.registerExtension('ext.flutterware.motion.progress', (
      _,
      args,
    ) async {
      var scope = resolve(args['scope']);
      if (scope == null) return _noScope(args['scope']);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'progress': scope.controller.progress,
          'ms': scope.controller.position.inMilliseconds,
          'playing': scope.controller.isAnimating,
        }),
      );
    });

    developer.registerExtension('ext.flutterware.motion.seek', (_, args) async {
      var scope = resolve(args['scope']);
      if (scope == null) return _noScope(args['scope']);
      var controller = scope.controller;
      if (args['ms'] case var raw? when double.tryParse(raw) != null) {
        controller.position = Duration(
          microseconds: (double.parse(raw) * 1000).round(),
        );
      } else if (args['t'] case var raw? when double.tryParse(raw) != null) {
        controller.progress = double.parse(raw);
      } else {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          jsonEncode({'error': 'seek wants t (0..1) or ms'}),
        );
      }
      // Drawn until it stops drawing, counting. One frame is the normal
      // answer. More means the screen applies the playhead in stages — a
      // `PageView` moved by `jumpTo` from a post-frame callback takes three:
      // the frame that moves the playhead, the one the jump schedules, and the
      // one the scroll position's own listeners schedule after it.
      //
      // The count is the useful part. A scrubber does not care, having drawn
      // again by the time anyone looks; a *render* takes one picture per stop
      // and needs to know how many frames a stop is really worth, or it
      // photographs a screen still on its way to where it was sent.
      var settleFrames = 1;
      await _settle();
      while (_stillArriving && settleFrames < 12) {
        await _settle();
        settleFrames++;
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'progress': controller.progress,
          'ms': controller.position.inMilliseconds,
          'settleFrames': settleFrames,
          // What a caller would otherwise ask `ext.flutterware.imagesSettled`
          // for, straight after this — and that question costs a *forced
          // frame*, twice, because the host wants two quiet ones in a row.
          // This reply already waited a frame, so the counts are true of the
          // picture it is reporting, and a caller that sees them quiet has no
          // reason to ask again. Measured: it is 33ms a frame of a render, on
          // every frame, at any resolution.
          'pending': PaintingBinding.instance.imageCache.pendingImageCount,
          'transient': SchedulerBinding.instance.transientCallbackCount,
          // Whether the frame this reply describes left another one *already
          // scheduled* behind it. A screen that applies the playhead from a
          // post-frame callback does — `PageView.jumpTo` cannot be called
          // during a build, so a flow driven by one is a frame behind its own
          // playhead. Harmless to a scrubber, which draws again immediately;
          // fatal to a render, which captures one frame per stop and would
          // photograph the previous one.
          'scheduled': SchedulerBinding.instance.hasScheduledFrame,
        }),
      );
    });

    // Which body a scope builds — the draft stage or the real screen.
    //
    // An extension rather than a knob in the user's file, because the choice is
    // the studio's: a `host` knob put the same twelve lines of `switch` in
    // every entry point, and shipped them.
    //
    // Reads with no `host`, which is how a panel syncs a control it did not
    // last set.
    developer.registerExtension('ext.flutterware.motion.host', (_, args) async {
      var scope = resolve(args['scope']);
      if (scope == null) return _noScope(args['scope']);
      if (args['host'] case var raw?) {
        var wanted = switch (raw) {
          'real' => MotionHost.real,
          'draft' => MotionHost.draft,
          _ => null,
        };
        if (wanted == null || !scope.hosts.contains(wanted)) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            jsonEncode({
              'error': 'no host "$raw" on this scope',
              'hosts': [for (var host in scope.hosts) host.name],
            }),
          );
        }
        scope.host = wanted;
        await _settle();
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'host': scope.host.name,
          'hosts': [for (var host in scope.hosts) host.name],
        }),
      );
    });

    // **The whole sequence, in one call.**
    //
    // `seek` is the right shape for a scrubber, where a person moves the
    // playhead once and looks. It is the wrong shape for a renderer, which
    // moves it eighteen hundred times for a minute of video and looks at every
    // one: each seek is a cross-process round trip, and each picture taken
    // after it is another. Measured at phone resolution, those two round trips
    // were 18 of the 22ms a frame cost, against 4ms of actual drawing.
    //
    // So the loop moves in here, where the playhead is. Nothing crosses the
    // process boundary per frame; the caller arms a capture *sequence* on the
    // side, and every frame this schedules is written as it lands.
    //
    // It renders exactly `stops.length` frames and says so, because the
    // caller's only way to pair a file with a stop is position. That holds
    // while nothing else schedules a frame — true of a parked motion, which is
    // what a render walks — and a caller that got fewer files than it asked
    // for must refuse rather than publish a video silently missing a moment.
    developer.registerExtension('ext.flutterware.motion.render', (
      _,
      args,
    ) async {
      var scope = resolve(args['scope']);
      if (scope == null) return _noScope(args['scope']);
      var stops = <double>[];
      for (var raw in (args['stops'] ?? '').split(',')) {
        var value = double.tryParse(raw.trim());
        if (value == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            jsonEncode({'error': 'render wants stops as comma-separated 0..1'}),
          );
        }
        stops.add(value.clamp(0.0, 1.0));
      }
      if (stops.isEmpty) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          jsonEncode({'error': 'render wants at least one stop'}),
        );
      }

      // How many frames each stop is given before its picture is taken.
      //
      // One is right for a screen that draws its playhead where it reads it.
      // Two is right for one that defers — a `PageView` driven by `jumpTo`
      // from a post-frame callback shows the *previous* offset on the frame
      // that moved the playhead, and a render taking one frame per stop
      // photographs a flow a slide behind itself. The caller chooses, from
      // what a seek told it; `unsettled` below is what catches it choosing
      // wrong.
      var perStop = int.tryParse(args['framesPerStop'] ?? '') ?? 1;
      if (perStop < 1) perStop = 1;

      var controller = scope.controller;
      var rendered = 0;
      var unsettled = 0;
      for (var t in stops) {
        controller.progress = t;
        // The frames are scheduled *because* the playhead moved — a controller
        // write marks the tree dirty — so nothing is forced here. Forcing one
        // as well would present an extra frame and shift every file after it.
        for (var i = 0; i < perStop; i++) {
          await _settle();
        }
        rendered++;
        // Still more to draw after its whole allowance: this stop's picture is
        // of a screen that had not finished arriving at it.
        if (_stillArriving) unsettled++;
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'rendered': rendered,
          'unsettled': unsettled,
          'framesPerStop': perStop,
          'durationMs': scope.motionValues.resolveDuration().inMilliseconds,
          'pending': PaintingBinding.instance.imageCache.pendingImageCount,
          'transient': SchedulerBinding.instance.transientCallbackCount,
        }),
      );
    });

    developer.registerExtension('ext.flutterware.motion.transport', (
      _,
      args,
    ) async {
      var scope = resolve(args['scope']);
      if (scope == null) return _noScope(args['scope']);
      var controller = scope.controller;
      switch (args['verb']) {
        case 'play':
          controller.play();
        case 'restart':
          controller.play(restart: true);
        case 'reverse':
          controller.reverse();
        case 'pause':
          controller.stop();
        case var verb:
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            jsonEncode({
              'error': 'unknown verb "$verb"; play, restart, reverse or pause',
            }),
          );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'progress': controller.progress}),
      );
    });
  }

  developer.ServiceExtensionResponse _noScope(String? asked) =>
      developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        jsonEncode({
          'error': asked == null || asked.isEmpty
              ? 'name a scope: ${_scopes.length} are mounted'
              : 'no mounted scope "$asked"',
          'scopes': _scopes.keys.toList(),
        }),
      );

  /// Bounded, because this is an RPC a panel waits on: a guest that has stopped
  /// drawing should make the scrubber late rather than stuck.
  Future<void> _settle() => WidgetsBinding.instance.endOfFrame.timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );

  /// Whether the screen is still on its way somewhere.
  ///
  /// **A scheduled frame is not enough to ask about.** A `PageView` moved by
  /// `jumpTo` lands on a page boundary and `pageSnapping` turns that into a
  /// ballistic spring, which is a *ticker*: it schedules its next frame from
  /// inside the current one, and between the two there is a moment when
  /// nothing is scheduled and the screen is nowhere near arrived. Measured on
  /// the onboarding flow, `hasScheduledFrame` alone said two frames where the
  /// picture needed five, and the filmstrip came out a slide early with every
  /// frame looking perfectly plausible.
  ///
  /// A running ticker is the other half of the question, and together they are
  /// the difference between "no frame is pending" and "nothing is moving".
  static bool get _stillArriving =>
      SchedulerBinding.instance.hasScheduledFrame ||
      SchedulerBinding.instance.transientCallbackCount > 0;

  /// Every mounted scope, and everything a panel draws a lane from.
  Map<String, Object?> describe() => {
    'scopes': [
      for (var entry in _scopes.entries) _describeScope(entry.key, entry.value),
    ],
  };
}

Map<String, Object?> _describeScope(String id, MotionSurface scope) {
  var values = scope.motionValues;
  var controller = scope.controller;

  // Tuned *or* named by the last build. A target with values nobody reads is
  // as much a thing the panel must show as one that is read and untuned —
  // those are two of the three states, and dropping either would hide exactly
  // the mistakes the panel exists to surface.
  var names = <String>{...values.targets.keys, ...scope.targetsNamed}.toList()
    ..sort();

  return {
    'id': id,
    'durationMs': values.resolveDuration().inMilliseconds,
    'host': scope.host.name,
    'hosts': [for (var host in scope.hosts) host.name],
    'ms': controller.position.inMilliseconds,
    'progress': controller.progress,
    'playing': controller.isAnimating,
    'targets': [
      for (var name in names)
        _describeTarget(
          name,
          tuned: values.targets[name] ?? const {},
          named: scope.targetsNamed.contains(name),
          scope: scope,
        ),
    ],
  };
}

Map<String, Object?> _describeTarget(
  String name, {
  required Map<String, List<Seg<Object?>>> tuned,
  required bool named,
  required MotionSurface scope,
}) {
  var properties = <String>{
    ...tuned.keys,
    for (var read in scope.reads)
      if (read.startsWith('$name.')) read.substring(name.length + 1),
  }.toList()..sort();

  var offered = {
    for (var offer in scope.offered)
      if (offer.startsWith('$name.')) offer.substring(name.length + 1),
  };

  // The guest's own coordinates, which is what a host painting into a surface
  // of the guest's logical size expects — the same contract the inspect layer
  // already draws node rects under.
  var extent = scope.extentOf(name);

  return {
    'name': name,
    'named': named,
    'extent': ?switch (extent) {
      null => null,
      var rect => {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      },
    },
    'offered': offered.toList()..sort(),
    'properties': [
      for (var property in properties)
        {
          'name': property,
          'read': scope.reads.contains('$name.$property'),
          'offered': offered.contains(property),
          'state': _stateOf(
            isTuned: tuned[property]?.isNotEmpty ?? false,
            isRead: scope.reads.contains('$name.$property'),
            isOffered: offered.contains(property),
          ),
          'value': _encode(scope.peek(name, property)),
          'segments': [
            for (var segment in tuned[property] ?? const <Seg<Object?>>[])
              {
                'startMs': segment.start.inMilliseconds,
                'endMs': segment.end.inMilliseconds,
                'from': _encode(segment.from),
                'to': _encode(segment.to),
                'curve': ?curveName(segment.curve),
              },
          ],
        },
    ],
  };
}

/// What a panel draws, decided **here** rather than by each consumer.
///
/// The design called this three states, and it is three states — but only once
/// `offered` is read correctly, and the first live run of the transport got it
/// wrong in the obvious way. `MotionBox` records its sweep as offered rather
/// than read, so every property it applies looked *tuned and unread*, which is
/// the state that means "nothing uses this, prune it". Seven of nine targets on
/// the first demo were reported prunable while visibly animating.
///
/// The rule the sweep did not break: **offered counts as wiring for a property
/// that is tuned, and does not create a lane for one that is not.** Those are
/// different questions, and `offered` is the right answer to both.
///
/// - `wired` — tuned, and something applies it. A lane.
/// - `dead` — tuned, and nothing reads or offers it. A lane, marked prunable.
/// - `untuned` — applied but never tuned. A dashed lane; this is the creation
///   path, and it is how a property gets tuned in the first place.
String _stateOf({
  required bool isTuned,
  required bool isRead,
  required bool isOffered,
}) => switch ((isTuned, isRead || isOffered)) {
  (true, true) => 'wired',
  (true, false) => 'dead',
  (false, _) => 'untuned',
};

/// A colour crosses as an ARGB int under a key that says so, a number as
/// itself. That is the whole of the wire format, because two kinds is the whole
/// of the value model — see [MotionValueKind].
Object? _encode(Object? value) => switch (value) {
  Color() => {'color': value.toARGB32()},
  double() => value,
  _ => null,
};

/// The name of a standard curve, or null.
///
/// Identity, and that is not a limitation: `Curves.easeOutCubic` is a const
/// `Cubic`, so a hand-written `Cubic` with the same control points canonicalises
/// to the same instance and gets the same name — which is the right answer, not
/// a false positive.
String? curveName(Curve curve) => _curveNames[curve];

/// The curve a name refers to, or null for a name this runtime cannot write.
///
/// The inverse of [curveName], and it lives beside the table rather than in the
/// editor because an editor that offers a curve has to plot the curve it is
/// offering. A second table in the GUI would be a second table to drift, and
/// the failure would be silent: a picker listing a name the writer then refuses.
Curve? curveByName(String name) => _curvesByName[name];

/// Every curve the editor may write, in the order a picker should offer them —
/// linear and the eases first, the theatrical ones last.
List<String> get motionCurveNames =>
    List<String>.unmodifiable(_curveNames.values);

final _curvesByName = {
  for (var entry in _curveNames.entries) entry.value: entry.key,
};

final _curveNames = <Curve, String>{
  Curves.linear: 'linear',
  Curves.decelerate: 'decelerate',
  Curves.ease: 'ease',
  Curves.easeIn: 'easeIn',
  Curves.easeInSine: 'easeInSine',
  Curves.easeInQuad: 'easeInQuad',
  Curves.easeInCubic: 'easeInCubic',
  Curves.easeInQuart: 'easeInQuart',
  Curves.easeInQuint: 'easeInQuint',
  Curves.easeInExpo: 'easeInExpo',
  Curves.easeInCirc: 'easeInCirc',
  Curves.easeInBack: 'easeInBack',
  Curves.easeOut: 'easeOut',
  Curves.easeOutSine: 'easeOutSine',
  Curves.easeOutQuad: 'easeOutQuad',
  Curves.easeOutCubic: 'easeOutCubic',
  Curves.easeOutQuart: 'easeOutQuart',
  Curves.easeOutQuint: 'easeOutQuint',
  Curves.easeOutExpo: 'easeOutExpo',
  Curves.easeOutCirc: 'easeOutCirc',
  Curves.easeOutBack: 'easeOutBack',
  Curves.easeInOut: 'easeInOut',
  Curves.easeInOutSine: 'easeInOutSine',
  Curves.easeInOutQuad: 'easeInOutQuad',
  Curves.easeInOutCubic: 'easeInOutCubic',
  Curves.easeInOutQuart: 'easeInOutQuart',
  Curves.easeInOutQuint: 'easeInOutQuint',
  Curves.easeInOutExpo: 'easeInOutExpo',
  Curves.easeInOutCirc: 'easeInOutCirc',
  Curves.easeInOutBack: 'easeInOutBack',
  Curves.fastOutSlowIn: 'fastOutSlowIn',
  Curves.slowMiddle: 'slowMiddle',
  Curves.bounceIn: 'bounceIn',
  Curves.bounceOut: 'bounceOut',
  Curves.bounceInOut: 'bounceInOut',
  Curves.elasticIn: 'elasticIn',
  Curves.elasticOut: 'elasticOut',
  Curves.elasticInOut: 'elasticInOut',
};
