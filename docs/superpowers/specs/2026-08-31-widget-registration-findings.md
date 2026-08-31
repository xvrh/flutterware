# External-widget registration — three real widgets, three mechanisms, one winner

**Date:** 2026-08-31
**Status:** findings from the third scene-editor discovery experiment. The
measurements are real (`app/tool/user_widget_probe.dart`, run against
`examples/example`); the mechanism sketches are speculative code, none of it
compiled. The recommendation at the end is argued, not decided.
**Constraints set by the owner:** registration should lean on code generation
from the project's entry point so the user supplies *minimal* information, and
nothing may require a resolved analyzer tree.
**Leans on:** `2026-08-31-scene-editor-discovery-findings.md` (the SDK mine —
same extractor, other corpus), `2026-08-31-canvas-toy-findings.md` (the opaque
node this registers content *for*).

## The question

A scene places widgets the editor has never seen — the coffee app's
`DrinkBadge` inside a store banner, a real `TextFormField` inside an
onboarding page. What must the project tell the tool before such a widget is
placeable, editable-where-possible, and renderable with sensible content? And
where does the project say it?

## What the scan gives free, measured on the coffee app

The SDK-mining extractor pointed at `examples/example/lib` (18 files, purely
syntactic, cross-file `this.x` field-type lookup within the package):

| widget | schema recovered | editor-tunable | registration owes |
|---|---|---|---|
| `MiniMarkdown` | full | `data`, `style`, `textAlign` | **nothing** |
| `DrinkBadge` | full | `size` (default 56 recovered) | `drink: Drink` |
| `DrinkScreen` | full | — | `drink: Drink` |
| `WelcomeScreen` | full | — | nothing |
| `DashboardTile` | full | 7 of 8 params | `logoStyle`\* |

\* a false negative that composes the spikes: `FlutterLogoStyle` *is* an enum,
declared in the SDK — the user-corpus scan just cannot see it. **Union the
user scan's enum set with the generated SDK catalog's and it disappears.** The
two extractors are one mechanism over two corpora, and they complete each
other.

The result to hold on to:

> **A registration owes only domain objects.** Every scalar, enum, child and
> default in these five widgets was recovered syntactically. What no scan can
> supply is a `Drink` — a value only project code can construct.

And one thing the constructor tells nobody: `DrinkScreen` compiles against
`ShopStrings`, `Theme`, `Cart` and `Navigator` *from context*. A one-regex
body scan (`X.of(context)`) recovered exactly that list. The scan cannot
*provide* context, but it can **warn** — "your wrapper must supply
`ShopStrings`" — which converts the worst registration failure (a widget that
throws in the render guest) into a named requirement before anything renders.

## The three mechanisms, written out

The discriminating specimen is `DrinkBadge` — one owed domain object, one
tunable scalar.

### A — annotation on the widget class

```dart
@SceneWidget(name: 'Drink badge', mockup: /* ??? */)
class DrinkBadge extends StatelessWidget { … }
```

Dies immediately, and on a familiar sword: **annotation arguments must be
const**, and the one thing a registration owes is a domain object — precisely
the value that in general is not const-constructible. This is motion v2's
finding 4 (const and expressiveness are one package) arriving a third time.
Even where a const mockup exists, the annotation puts tool concerns inside
product files. Rejected.

### B — declaration in the project config

```dart
// tool/flutterware.dart
fw.use(Scenes(widgets: [
  SceneWidget('Drink badge', build: () => DrinkBadge(Drink.mocha), wrap: wrapInApp),
]));
```

Ordinary Dart, so the mockup is expressible — but the closure is only
*executable* in a process that has the example package compiled in, and the
config file is the studio's to read, not the render guest's to import
(dragging `tool/flutterware.dart` and its `plugins.dart` import into a guest
harness is the wrong dependency direction entirely). Making B renderable means
scanning the declarations syntactically — which quietly imposes grammar
constraints on a hand-written config file — or generating a harness that
imports the config. Both are machinery the next mechanism gets for free. B
remains the right home for *project-wide* scene configuration (which packages
to scan, palette curation), not per-widget mockups.

### C — a preview entry is the registration

```dart
@Preview(name: 'Drink badge', wrapper: wrapInApp)
Widget drinkBadge() => DrinkBadge(Drink.mocha, size: 64);
```

Every requirement lands on something that already ships:

| need | supplied by | status |
|---|---|---|
| discovery | the previews scan | ships |
| guest instantiation | the previews harness codegen | ships |
| context | `wrapper:` — and `wrapInApp` already exists in the example | ships |
| schema | the syntactic extractor | measured above |
| mockups | the entry's body — ordinary Dart, non-const, callbacks stubbed naturally | free |
| rename safety | a scene references the entry by tear-off, so a rename is a compile error | the motion v2 `host:` pattern |

The one genuinely new idea C needs: **the entry body's shape decides
tunability.** `DrinkBadge(Drink.mocha, size: 64)` is a single constructor
invocation — grammar-shaped — so a syntactic read of the body tells the
editor which arguments the entry fixes (`drink`) and which a scene may
override (`size`, and anything unmentioned with a recovered default). The
generated bridge then writes the plumbing the user never does:

```dart
// generated — the "codegen in the entry point" the owner asked for
SceneBinding(
  entry: drinkBadge,
  schema: …,                       // from the scan
  build: (args) => DrinkBadge(
    Drink.mocha,                   // the entry's frozen mockup, verbatim
    size: args.d('size') ?? 64,    // tunable: scene overrides, entry default
  ),
)
```

A hostile body — knobs, helpers, conditionals — degrades *gracefully*: the
entry stays placeable as a fixed opaque node rendered exactly as written, with
nothing tunable. No refusal needed, because unlike a motion file nothing here
is round-tripped — the tool only ever reads.

## The registration ladder

Putting the measurement and the mechanism together, registration is not one
act but a ladder, and each rung is priced by what the widget withholds:

1. **Owes nothing** (`MiniMarkdown`, most of `DashboardTile`): auto-registered
   from the scan alone. No entry, no user action — this is the "insert any
   widget by name" long tail, and it works for the same reason 320 of 552 SDK
   widgets were instantiable from editor values alone.
2. **Owes a domain object or context** (`DrinkBadge`, `DrinkScreen`): one
   preview entry — which the demo culture writes anyway — and the body's
   grammar-shaped part becomes the tunable surface.
3. **Owes more than an entry can say** (needs a live server, a database):
   never placeable in a scene; a scenario capture is that content's transport,
   which is the video pipeline's job, not registration's.

The context warning threads through all rungs: `.of(context)` scanning names
the wrapper's obligations, and a missing one is reported *before* the guest
throws.

## What this experiment did not test

The override bridge is unwritten — its arg-passing shape (`args.d('size')` is
a placeholder, and typed spellings exist), and whether the previews harness
hosts it without surgery. Whether placeable entries are opt-in
(`@Preview(component: true)`?) or every entry is placeable. How the scene
grammar spells a reference to an entry (tear-off in an opaque-node
constructor, presumably, but unwritten). Positional parameters in overrides.
And the generated-bridge-imports-user-code direction wants the same leaf-file
cycle rule motion v2 already flagged for custom bundles.

## Verdict

**C, with B as its configuration layer and A rejected.** The registration
story becomes one sentence — *write a preview entry for it* — which is a
concept users already have, exercised by a scan and a harness that already
exist, delivering minimal-information registration through codegen exactly as
the owner asked. The experiment's strongest single result stays the measured
one: the scan recovers everything except domain objects, so the entry's only
irreducible job is to hold `Drink.mocha` — one expression of ordinary Dart in
a function the project probably wanted anyway.
