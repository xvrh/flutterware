# Top-bar axes: app-wide switches a project declares in its shell

**Status.** Design, agreed in outline, not built. The one load-bearing
assumption — that a wrapper can grow parameters and stay a `WidgetWrapper` —
has been verified against the SDK rather than assumed.

## What a project writes

```dart
// demo/shell.dart
enum Flavor { dev, staging, prod }
enum Language { english, french }

@CatalogShell()
Widget wrapInApp(
  Widget child, {
  Flavor flavor = Flavor.dev,
  Language language = Language.english,
}) => MyApp(flavor: flavor, language: language, home: child);
```

And nothing else. `@Demo(wrapper: wrapInApp)` is unchanged, every demo keeps
naming it, and the axes are the shell's own named parameters.

## Why the wrapper can grow parameters

Flutter defines `typedef WidgetWrapper = Widget Function(Widget)` and `Preview`
holds one in a typed field, so a wrapper's signature is not ours to change.
Extra **optional named** parameters are the exception: Dart's function subtyping
allows them, so the tear-off is still assignable.

Verified, not reasoned about:

```dart
typedef WidgetWrapper = String Function(String);
String wrapInApp(String child, {Flavor flavor = Flavor.dev}) => …;
WidgetWrapper asWrapper = wrapInApp;            // compiles, runs
wrapInApp('demo', flavor: Flavor.prod);         // and the axes are still there
```

This is what makes the whole design cheap. It means:

- **Flutter's own previewer is unaffected.** It calls the wrapper through the
  typedef, with one argument, and gets the shell exactly as it is today —
  including whatever dependency injection the shell does. A demo that reaches
  for something the shell provides keeps working there.
- **The real app is unaffected.** `wrapInApp(child)` is a normal function call
  with defaults.
- **The catalog goes around the typedef** by calling the function *by name*,
  which is the one place the named parameters are still visible.

## Several shells

A project has as many shells as it needs, and the top bar shows the axes of the
shell the *current entry* uses. Switching to an entry with a different wrapper
changes the top bar with it.

- A shell is identified the way an entry is: path plus symbol.
- An entry's shell is whatever its `@Demo(wrapper:)` names, when that names an
  annotated shell. An entry with no wrapper, or a wrapper that is not a shell,
  has no axes and the top bar shows none.
- Selections are held **per shell**, so leaving a shell and coming back finds
  the flavor you had chosen rather than the default.

## Who owns what

The **selection** is the host's. It is UI state, it has to outlive the entry
you are looking at and the guest itself, and only the host knows what you
clicked. It is pushed down, and it can be pushed *before* the reload that
switches entries, so no frame renders with the previous shell's values.

The **set of axes and their options** is reported by the guest, like a knob —
see the section above for why.

What still separates an axis from a knob, and is the reason they stay two
things rather than one:

- An axis is declared by a **signature**, not by a build, so it cannot appear or
  disappear as a side effect of building. There is no pass, no sweep, no
  ordering question — the list is whatever the parameter list said.
- An axis belongs to a **shell**, not to an entry, so the selection persists
  across entry switches instead of resetting with them.
- An axis is above the entry in the tree, so changing one rebuilds the shell
  rather than the demo alone.

## Discovery

The scanner already sweeps the roots for annotations, so `@CatalogShell` is
found the same way `@Demo` is — in the file where the shell is declared, with
its parameter list right there. From a purely syntactic read it yields, per
axis: the name, the type name, and the default's source text.

`Preview` allows a wrapper to be a top-level function *or* a public static
member, so discovery has to handle `MyShell.wrap` as well as `wrapInApp`.

## Two different static reads, and only one of them is worth having

**The signature is read statically.** A syntactic parse of the shell's
parameter list gives, per axis, the name, the type name, and the default's
source text. That is free, needs no resolution, and is all the generator needs.

**The enum's options are not.** A syntactic scan sees `Flavor` and cannot know
it is an enum or what its values are. Parsing enums declared beside the shell
would cover the common case, and resolving the file with `package:analyzer`
would cover all of it at the cost of pulling the analyzer into the daemon and
breaking the scanner's deliberately syntactic property.

We do neither. The guest is handed `Flavor.values` by the generated call, so it
knows the whole set at runtime and **reports it** — the same report shape as a
picker knob, over the same extension, through the same read-back the knob panel
already uses.

This is the same problem `parameters.picker` has, and the same answer. Its
option values are arbitrary Dart, only labels cross the wire, and the demo maps
a label back. Nothing about an axis is different.

### What that costs

Nothing can list a project's axes without booting a guest. That is a smaller
cost than it sounds: every operation that would use the answer boots a guest
anyway — `fw screenshot tile --flavor=prod` has to render — so learning the axes
costs it nothing extra. The only thing it hurts is a pure query that then does
nothing, which is a cache away if it ever matters.

Smaller and real: a mistyped `--flavor=prd` cannot be rejected until a guest is
up, and a malformed axis is a runtime omission rather than a scan diagnostic.
Both are what knobs already do. And with several shells, a shell's axes appear
only once an entry using it has rendered — one reload, the same beat the knob
panel already has.

### What it buys

Static could only ever have given us enum identifiers as labels: `english`,
`staging`. Read-back gives real ones, because the guest holds the actual values
— an enum implementing a `label` getter, or carrying a swatch colour or an icon,
can say so at runtime. `PickerParameter` already carries `swatch` and `icon`,
and `pickerOptionWidget` already renders them, so the top bar gets this for
free.

`bool` is worth allowing as a toggle. Nothing beyond enum and bool: anything
else has no closed set for the guest to report.

## What the generator emits

For an entry whose wrapper is a shell, the host calls the shell directly instead
of through `preview.wrapper`:

```dart
wrapInApp(child,
  flavor: CatalogAxes.instance.pick('flavor', Flavor.values, Flavor.dev),
  language: CatalogAxes.instance.pick('language', Language.values, Language.english),
)
```

`pick<T extends Enum>(String name, List<T> values, T fallback)` maps the
selected *name* to a value, falling back when the name is not one of them —
which is also what makes a stale selection from another shell harmless.

The type argument is the check: if `Flavor` is not an enum the compile fails,
in one function in one file, with an error that says so. That is the trade
accepted in place of resolution.

`preview.wrapper` is still evaluated and still correct; the catalog simply does
not route its own render through it.

## Wire

Two directions, both reusing what knobs established.

`ext.flutterware.axes` reports the axes the current shell declared and the
options each has, in the shape a picker knob is already reported in. Read after
a switch, like the knob report, and subject to the same rule: a report naming
another shell is a report from before the switch landed, not an empty top bar.

`ext.flutterware.setAxes` takes the active shell's selections as JSON — axis
name to selected enum name. Called when a value changes, and before a switch
that changes shells. Nothing comes back: the host already knows what it sent.

## Still to decide

- **Persistence across sessions.** The selection is host state, so it can be
  saved with the project's UI state the way the selected entry is. Probably
  yes; not required for a first cut.
- **Whether `@CatalogShell` needs any arguments.** Bare to start. A display
  name for the top bar's grouping is the obvious first one if it needs any.

## Order of work

1. `@CatalogShell` and discovery: find shells, read their parameter lists,
   report them alongside entries.
2. `CatalogAxes` in the published package, its `pick`, and both extensions.
3. The generator: call the shell by name with `pick(...)` per axis.
4. The top bar: render the reported axes, hold the selection per shell, push on
   change.

Each step is checkable in the headless harness before the one after it: (1) in
discovery's own tests, (2) and (3) by asserting what the guest reports for a
demo whose shell declares axes, (4) in widget tests.
