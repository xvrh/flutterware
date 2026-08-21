/// How a demo's knobs and a shell's axes are written into an address, and read
/// back out.
///
/// One encoder for both, because they are the same thing seen twice: a
/// [KnobDescriptor] declared by running the project's own code. What separates
/// them is where they are declared and how long they live — an axis belongs to
/// the shell and survives moving between entries, a knob belongs to the entry
/// and goes with it — and that difference is carried by which namespace they
/// sit under, `axis.` or `knob.`, not by having two of everything.
///
/// Names and picker options are **display strings** — `Theme`, `Dark mode`,
/// `Français`. An address is typed, pasted into terminals and written by
/// agents, so it cannot carry them as they are. Everything here is that
/// translation, in both directions, with nothing stored between them.
///
/// Project vocabulary, deliberately: nothing is enumerated in the docs and
/// nothing is validated against a fixed list. `theme` gets no more standing
/// than `flavor` — the project decides what either means, so flutterware
/// naming one would be claiming a semantics it cannot enforce.
library;

// The knob types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart`.
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

/// A display label as it appears in an address.
///
/// `Dark mode` becomes `dark-mode`. Lossy on purpose: two labels that slug the
/// same are a collision the caller has to notice, which is what
/// [axisOptionFor] returning null is for.
String paramSlug(String label) {
  var slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? label.toLowerCase() : slug;
}

/// The address key an axis is written under — `axis.theme` for a `Theme` axis.
///
/// The `axis.` prefix separates the project's vocabulary from flutterware's own
/// un-namespaced parameters, and separates it from `knob.` — which is the same
/// kind of thing with a different lifetime: a knob belongs to the entry and
/// goes with it, an axis belongs to the shell and does not.
String paramKeyFor(KnobDescriptor param) => paramSlug(param.name);

/// What an address should say for [value] of [param], or null when it is on
/// the default the demo wrote — which is written as *nothing*, so an address
/// only ever names a deliberate choice.
///
/// Silence carrying the default is what lets a demo change its own mind about
/// one without silently reinterpreting every link ever saved.
String? paramValueSlug(KnobDescriptor param, Object? value) {
  if (value == null || value == param.defaultValue) return null;
  return switch (param.kind) {
    KnobKind.boolean => value == true ? 'true' : 'false',
    // Verbatim. A string knob holds arbitrary text — a name, a sentence — and
    // slugging it would destroy the very thing being set. The address does its
    // own percent-encoding, so nothing here has to.
    KnobKind.string => '$value',
    KnobKind.integer => '${(value as num).round()}',
    KnobKind.number => '$value',
    // A label, so the same rule as an axis: only the demo knows what is behind
    // it, and only its own strings mean anything to it.
    KnobKind.picker => paramSlug('$value'),
  };
}

/// What [slug] means to the demo — the label, bool or number it declared.
///
/// Null when nothing matches: a parameter for something this build does not
/// declare, or one whose options changed under an edit. That is not an error.
/// This is the project's vocabulary, and a demo that has not built yet
/// legitimately claims none of it, so an unmatched parameter is preserved in
/// the address and ignored here rather than complained about or stripped.
Object? paramOptionFor(KnobDescriptor param, String slug) {
  switch (param.kind) {
    case KnobKind.boolean:
      return switch (slug) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    case KnobKind.string:
      return slug;
    case KnobKind.integer:
      return int.tryParse(slug);
    case KnobKind.number:
      return double.tryParse(slug);
    case KnobKind.picker:
      for (var option in param.options) {
        if (paramSlug(option) == slug) return option;
      }
      return null;
  }
}

/// What [param] should be **drawn** as, given what the address asked for.
///
/// A function of the address and the *declaration* — never of
/// [KnobDescriptor.value], which is only what the guest last confirmed. That is
/// all the optimistic update amounts to: a control follows the pointer at once,
/// the report catching up a round trip later changes nothing on screen, and
/// nothing is mutated to achieve it.
///
/// Silence means the default, because silence is how a default is written:
/// [paramValueSlug] returns null for it, so choosing Light removes the parameter
/// rather than spelling it out. Falling back to the confirmed value instead
/// looked reasonable and was the bug — the report still said `Dark mode`, so
/// choosing the default put the control straight back where it had been and the
/// top bar froze.
Object? paramDisplayValue(
  KnobDescriptor param,
  Map<String, String> selections,
) {
  var slug = selections[paramKeyFor(param)];
  if (slug == null) return param.defaultValue;
  return paramOptionFor(param, slug) ?? param.defaultValue;
}

/// The payload the guest is sent: **the whole truth** for what [declared]
/// contains, by the names the guest itself declared.
///
/// Every declared parameter appears. One the address does not name is sent as
/// null — an instruction to go back to its own default — rather than left out.
/// Leaving it out was the bug that made the top bar look stuck: the address
/// writes a default as nothing at all, the guest merged what it received, and
/// so nothing ever told it to forget.
///
/// The guest is not asked about parameters it has not declared. A stale one
/// stays in the address, ignored, until something claims it.
Map<String, Object?> paramPayloadFor(
  List<KnobDescriptor> declared,
  Map<String, String> selections,
) => {
  for (var param in declared)
    param.name: switch (selections[paramKeyFor(param)]) {
      var slug? => paramOptionFor(param, slug),
      null => null,
    },
};
