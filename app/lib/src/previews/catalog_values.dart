// The knob types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart` and would make
// `fw` unlinkable. `knob.dart` is plain Dart by design and says so.
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/axis.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

import 'catalog_params.dart';

/// Turning what a caller *wrote* into what a guest can be told.
///
/// Both halves are the same shape and neither is about an engine: a flag, a
/// JSON object and a URL query all arrive as text, the build that declared the
/// knob is the only authority on what kind it is, and a name nobody declared
/// has to be refused rather than dropped. What differs between the backends is
/// only how the resolved payload is delivered — a service extension to a
/// guest, an in-body call under `flutter_tester` — so the resolving lives
/// here, once, and the refusals are worded once with it.

/// Every declared knob, with [values] applied to the ones named.
///
/// One payload carrying **every** declared knob, not one entry per value: a
/// write is the whole state, and a name absent from it is what says "leave
/// this at its default". The panel builds the same shape in `paramPayloadFor`.
///
/// Refuses a name the entry does not declare, naming the ones it does. A
/// silently ignored knob produces a picture that looks right and is not.
Map<String, Object?> knobPayloadFor(
  KnobReport declared,
  Map<String, String> values, {
  required String entryId,
}) {
  var known = {for (var knob in declared.knobs) knob.name: knob};
  for (var name in values.keys) {
    if (known.containsKey(name)) continue;
    throw ArgumentError.value(
      name,
      'knob',
      known.isEmpty
          ? 'this entry declares no knobs'
          : 'no such knob on $entryId. Declared: ${known.keys.join(', ')}',
    );
  }
  return {
    for (var knob in declared.knobs)
      knob.name: switch (values[knob.name]) {
        var raw? => coerceKnob(knob, raw),
        null => null,
      },
  };
}

/// Turns a knob value written as text into whatever kind the demo declared.
///
/// Everything arrives as text: a shell flag has no types, and a JSON object
/// from an agent may disagree with the demo about int versus double. The demo
/// is the authority, so this follows [KnobDescriptor.kind] rather than guessing
/// from the characters — `count=5` is an int for a demo that declared an int
/// and a string for one that declared a string.
Object? coerceKnob(KnobDescriptor knob, String value) => switch (knob.kind) {
  KnobKind.boolean => switch (value.toLowerCase()) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => throw ArgumentError.value(value, knob.name, 'expected true or false'),
  },
  KnobKind.integer =>
    int.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected an integer')),
  KnobKind.number =>
    num.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected a number')),
  KnobKind.picker =>
    knob.options.contains(value)
        ? value
        : throw ArgumentError.value(
            value,
            knob.name,
            'expected one of: ${knob.options.join(', ')}',
          ),
  KnobKind.string => value,
};

/// [values] resolved against what the shell on screen declared, keyed by that
/// shell — the shape `CatalogAxes.apply` reads.
///
/// Nested by shell because selections belong to the shell rather than to the
/// entry: two shells that both call something `flavor` must not inherit each
/// other's.
///
/// Null when there is nothing to set, so a caller with no axes never has to
/// find a shell id.
Map<String, Map<String, Object?>>? axisPayloadFor(
  AxisReport declared,
  Map<String, String> values,
) {
  if (values.isEmpty) return null;
  var shellId = declared.shellId;
  if (shellId == null) {
    throw ArgumentError.value(
      values.keys.join(', '),
      'axes',
      'this entry has no shell, so it offers no axes. Axes are declared by a '
          'PreviewShell around the demo.',
    );
  }

  var known = {for (var axis in declared.axes) axis.name: axis};
  for (var name in values.keys) {
    if (known.containsKey(name)) continue;
    throw ArgumentError.value(
      name,
      'axes',
      'no such axis on this shell. Declared: ${known.keys.join(', ')}',
    );
  }

  return {
    shellId: {
      for (var axis in declared.axes)
        axis.name: switch (values[axis.name]) {
          var raw? =>
            paramOptionFor(axis, paramSlug(raw)) ??
                paramOptionFor(axis, raw) ??
                (throw ArgumentError.value(
                  raw,
                  axis.name,
                  axis.options.isEmpty
                      ? 'not a ${axis.kind.name}'
                      : 'no such option. Declared: ${axis.options.join(', ')}',
                )),
          null => null,
        },
    },
  };
}
