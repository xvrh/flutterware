# Knobs: the runtime API we have, and the static one worth exploring

**Status.** The runtime path is built and in use. **The static path's discovery
half is built as of 2026-08-13** — `CatalogScanner` now reads a demo's parameter
list into `CatalogEntry.knobs`, enums included, via
`app/lib/src/utils/parameter_knobs.dart` and `enum_lookup.dart`, shared with run
entry points (`2026-08-12-run-knobs-design.md` § K7, which decided the enum
question this note left open). **What is still undecided is § Should they
coexist? in the panel** — see the note at the end of that section. This note
still exists so that decision is made deliberately rather than by whoever
touches parameters next.

## What exists

A demo declares its controls by *reading* them while it builds:

```dart
@Demo(name: 'Tile', wrapper: wrapInApp)
Widget tile() => Builder(builder: (context) {
  var parameters = context.uiCatalog.parameters;
  var label = parameters.string('label', 'Hello');
  var count = parameters.int('count', 2, min: 0, max: 9);
  return Tile(label: label, count: count);
});
```

There is no list of knobs anywhere. The set is whatever calls the last build
made, recorded by `EditableParameters`, reported to the panel over the guest's
VM service (`ext.flutterware.parameters`), and set the same way
(`ext.flutterware.setParameter`). Setting a value rebuilds the demo in place —
no compile, no reload, no lost state.

This is a published API and it stays. Outside the catalog
`context.uiCatalog.parameters` answers with defaults, so the same widget works
in the real app, which is the property that makes it worth having at all.

### What it costs

1. **Nothing can know a demo's knobs without running it.** Not the CLI, not an
   agent, not an index building a grid of variants. Answering "what can I vary
   here" requires booting a guest, compiling the entry, and rendering a frame.
2. **Conditional knobs appear and disappear.** A knob read inside
   `if (dense) …` exists only while `dense` is true. Correct, and unsettling to
   look at.
3. **The set is only ever as right as the last build**, which is why the panel
   re-reads after every switch and every set.

(1) is the one that matters. It is in tension with the AI-legibility goal in
the master plan: an agent that must render a demo to learn it has a `severity`
knob cannot cheaply ask "show me this at every severity".

## The static idea

Let a demo declare its knobs as its own parameter list:

```dart
@Demo(name: 'Tile')
Widget tile({String label = 'Hello', int count = 2, Severity level = Severity.warn})
    => Tile(label: label, count: count, level: level);
```

Discovery already holds the `FormalParameterList` — it reads it today to reject
entries with *required* parameters — so names, type names and default source
text are available from a parse, with no analysis and no execution. The
generated wrapper passes values in; calling the function directly still works,
because every parameter has a default.

The entry contract does not change: "callable with no arguments" already
allows this.

### Why it fits Dart specifically

Storybook needs `args` as a separate data blob because a story is a render
function taking a props object; there is nowhere else for names and defaults to
live. In Dart the signature *is* that blob. Nothing has to be repeated, and
nothing can drift between the declaration and the read.

### What has no home in a signature

Storybook's `argTypes` — control kind, option lists, ranges. In Dart these
would be parameter annotations:

```dart
Widget tile({@Range(0, 9) int count = 2})
```

which is the part that needs designing rather than deciding.

Open questions, roughly in order of how much they hurt:

- **Enums.** `Severity level = Severity.warn` should give a picker for free,
  but a syntactic scan sees the type *name*, not that it is an enum or what its
  values are. The generated wrapper could emit `Severity.values` and let the
  compile fail if it is not an enum — fragile. Resolving properly means the
  scanner stops being purely syntactic, which is a deliberate property it has
  today (see `CatalogScanner`).
- **Defaults must be constant expressions.** A Dart rule, not a design flaw,
  and the same one `@Preview` states for its own arguments. `DateTime d =
  DateTime.now()` will never be a static knob. The runtime API has no such
  limit.
- **Ordering and grouping** come from the signature, which is probably right.
- **Addressing values headlessly.** `fw screenshot tile --label=Overdue` only
  means something once knobs are named without running. That is the payoff.

## Prior art, checked rather than recalled

- **Flutter `@Preview`** (read in the SDK, `widget_previews.dart`): no knobs at
  all. It carries `group`, `name`, `size`, `textScaleFactor`, `wrapper`,
  `theme`, `brightness`, `localizations`, and the target must be callable with
  no arguments. Variation is expressed by writing more previews, or by
  `MultiPreview` — one annotation expanding into several fixed ones. Its doc
  states all annotation values must be constant.
- **Widgetbook** (docs.widgetbook.io/knobs/overview): runtime, and all but
  identical to ours — `context.knobs.string(label: …, initialValue: …)` read
  during build.
- **Storybook** (storybook.js.org/docs/writing-stories/args): static. `args`
  are data on the story export; `argTypes` carries the control kind, options
  and ranges.

So nobody in the Flutter ecosystem does the static thing. That is a genuine
differentiator and a genuine warning: there is no precedent for how it feels to
write a hundred of these.

## Should they coexist?

Yes, and not as a migration.

**Open, and now load-bearing (2026-08-13).** Discovery produces static knobs, so
`describe` *could* answer `--knobs` from them without the compile and the frame
its own doc comment charges for. It deliberately does not yet: an entry may
declare parameters *and* read `context.uiCatalog.parameters`, and short-circuiting
would silently under-report the second. The choice — substitute, merge, or report
them as two lists — is the coexistence question below, and it is exactly what
this note asks not be settled in passing.

They answer different questions. The static path says *what an entry varies
over* — legible without running, addressable from a CLI, enumerable by an
index, const-limited. The runtime path says *what this build happens to
expose* — unlimited in type, reachable from deep inside a tree, conditional.

A demo would be able to use both, and `KnobDescriptor` is already the shape
they would both produce: it lives in the published package, has no Flutter in
it, and the panel switches on `KnobKind` without asking where a knob came
from. The report a panel renders would become the union of the two, with the
static ones known before the first frame and the runtime ones arriving with it.

The one thing to avoid is a knob declared twice, in the signature and in a
`parameters.string` call with the same name. Whichever way that resolves, it
should be an error the scanner reports, not a silent winner.

## If we do it

Rough order, all additive:

1. Discovery reads the parameter list into `List<KnobDescriptor>` on
   `CatalogEntry`, string/int/double/bool only, defaults as parsed literals.
2. The generated wrapper takes the values it was given and calls the demo with
   them; the host sends them the way it sends a selection.
3. The panel merges the static descriptors with the guest's report.
4. `fw` grows `--knob name=value`, which is the point of the exercise.
5. Enums and `@Range`, once 1–4 have been lived with.
