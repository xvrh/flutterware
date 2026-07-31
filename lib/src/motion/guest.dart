import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'values.dart';

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
}

/// The door a host drives a motion through.
///
/// Registered by the first `MotionScope` to mount rather than before `runApp`,
/// because a motion lives in somebody's screen and there is no entrypoint of
/// ours to hang it on. A host that connects first sees no extension and waits
/// for one — the same late-registration the catalog's guest already handles.
///
///   `ext.flutterware.motion.list`                    every mounted scope
///   `ext.flutterware.motion.seek`     `scope`, `t`   0..1, or `ms`
///   `ext.flutterware.motion.transport` `scope`, `verb`
///
/// `seek` answers **after the frame**, so a reply means the picture has caught
/// up. A scrubber that answered earlier would report positions the screen had
/// not reached, which is indistinguishable from a slow guest and much harder to
/// diagnose.
class MotionRegistry {
  MotionRegistry._();

  static final instance = MotionRegistry._();

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
      await _settle();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'progress': controller.progress,
          'ms': controller.position.inMilliseconds,
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

  return {
    'name': name,
    'named': named,
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
