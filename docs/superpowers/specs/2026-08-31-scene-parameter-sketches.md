# Scene parameters — seven sketches before any grammar

**Date:** 2026-08-31
**Status:** speculative sketches, in the format that served motion v2 (each
"file" is written in full and then made to bite). **Nothing here is
decided.** Every *finding* is a claim put to the owner; the two compile
probes quoted ran for real, the rest is unexecuted Dart written carefully.
**Leans on:** `2026-08-31-scene-v1-design.md` (parameters are the crux, the
mockup is the default), `2026-08-31-motion-on-scene-ground.md` + addendum
(fields are identity; the seam question; the clone/tweak requirement),
`2026-08-31-nesting-and-parameters-ux-research.md` (an instance's internals
are not addressable; nesting is a call), `2026-08-28-motion-v2-design.md`
(the draft API, tweak-by-argument, the const findings).

**The question:** what does a parameterized scene look like — declared,
called by the export matrix, called by the app, cloned and tweaked at
runtime, filled with structured data, nested? The owner's brief: experiment
with all the options, expect something more powerful than a flat
constructor, and hold every sketch against **heavy runtime copy/clone of a
scene and its motion**.

Two facts were compile-probed before anything else, because every sketch
stands on them:

- a `late final` node field **can** reference a constructor parameter and
  any sibling field, and each instance gets its own node objects
  (`identical(a.root, b.root) == false`);
- a class with a `late final` field **cannot** have a const constructor —
  the hot-reload canonicalization trap is unwritable, by the language.

---

## Sketch 1 — the declaration side

```dart
//@flutterware:scene=0.3
class BannerScene {
  BannerScene({
    this.title = 'Fresh coffee, faster',
    this.subtitle = 'Order ahead. Skip the line. Earn rewards.',
    this.ctaText = 'Get the app',
    this.accent = const Color(0xFFE8632B),
  });

  final String title;
  final String subtitle;
  final String ctaText;
  final Color accent;

  late final headline = Text(title, fontSize: 54, weight: FontWeight.w700);
  late final sub = Text(subtitle, fontSize: 20);
  late final ctaLabel = Text(ctaText, fontSize: 17);
  late final cta = Frame(fill: accent, corner: 28, children: [ctaLabel]);
  late final root = Frame(width: 1024, height: 500, children: [/* … */]);
}
```

**What writing it found:**

- **The grammar widens by exactly two items**: a constructor whose
  parameters are `this.` initializing formals with literal defaults, and
  *parameter identifiers as values* inside node invocations. The second is
  motion v2's grammar item 7 ("references to the enclosing class's own
  fields") arriving on schedule. The identifier refusal keeps its teeth —
  the allowlist grows by the class's own declared parameters, nothing else.
- **The mockup-is-the-default law lands with no machinery.** The default
  *is* the mockup, in the one place a default lives in Dart. The editor
  edits the default; a caller overrides it; nobody translates between two
  representations.
- The cost motion v2 predicted is real and bounded: **two lines per
  parameter** (formal + field). Tolerable at poster scale; worth watching
  at twenty parameters.
- A parameter's *type* is its editor affordance: `String` → text field,
  `double` → number, `Color` → swatches. An image/asset parameter needs a
  type this sketch does not have — deferred, flagged.

## Sketch 2 — the export matrix, and where the translation join lives

```dart
// A program (ordinary Dart), not a model:
Future<void> exportBanners(SceneMatrix matrix) => matrix.render(
  scene: BannerScene.new,
  axes: [Axis.languages(), Axis.devices(storeBanners)],
);
```

That is the *whole* caller, because of a fact this repo already measured:
**the translation index resolves by string identity at 97.7%.** A `String`
parameter's default is a real string from the app's language; the index
maps it to its translations with no key. So the matrix needs no per-key
caller code at all: for each language, each `String` parameter whose
default resolves in the index is replaced by its translation; one that does
not resolve stays the default and is *reported* (the 2.3% needs an explicit
override, which is caller code — `overrides: {'title': …}` — and rare).

**Findings:**

- **Translation-key provenance costs the scene grammar nothing.** The
  design doc's "text content gains a provenance — literal, parameter, or
  translation key" is a *display* fact the editor computes by looking a
  default up in the index, not a syntax the file carries. No `tr()`, no
  annotation, no key strings — consistent with no-magic-strings.
- The join lives in the *matrix machinery*, once — not in the scene (which
  stays translation-ignorant) and not in per-scene caller code.
- The matrix caller is a program: axes, overrides, output policy. This is
  the composition/model line holding — cardinality and schedule stay
  program-owned.

## Sketch 3 — the app mounts the pair, and the seam answers itself

The addendum left the seam open: merged surface
(`OnboardingScene(title:…, tempo:…)`) versus two surfaces. Writing the call
site settled it *against* my earlier lean:

```dart
// In the app's PageView, per page:
OnboardingIntro(
  OnboardingPage1(title: t.onboarding.welcome, hero: heroAsset),
  tempo: 0.8,
  drive: pageDrive(controller, page: 0),
)
```

**Findings:**

- **The merged constructor is dead on dependency direction.** The scene
  file must not know its motions (motions name the scene, never the
  reverse — several motions per scene). A merged surface therefore needs a
  *generated third artifact* that reads the pair, and the moment sketch 4
  makes the scene class itself the thing you construct, that generation
  step is the only codegen left in the design. Kill it.
- **Two surfaces are not noisy, because wrapping is the Flutter idiom.**
  `OnboardingIntro(OnboardingPage1(…), tempo: …)` is exactly how every
  decorator in the framework reads. The motion is constructed *over* the
  scene instance — which is precisely the fold's typed-reference story
  (`scene.headline` inside the motion) — and the no-motion case pays
  nothing.
- The driver rides the motion, where the drivers table always put it.

## Sketch 4 — clone and tweak, and the fork it forces

The owner's requirement, sketched with the model exactly as it now is
(mutable nodes, per-instance `late final` trees):

```dart
// Clone = construct. Tweak = reach in, typed, with cascades.
final dark = BannerScene()
  ..root.fill = const Color(0xFF14100C)
  ..headline.color = Colors.white70
  ..cta.fill = const Color(0xFFB44A1E);

// The pair: a motion constructed over the clone attaches to the clone's
// nodes through ordinary references — no registry, no rebind.
final intro = BannerIntro(dark, tempo: 1.2);
```

**Findings:**

- **The fields are the draft API.** No `edit()` closure, no parallel
  `BannerSceneDraft` hierarchy (the tax motion v2 rejected), no codegen:
  Dart's cascade over typed mutable nodes *is* clone-and-tweak, and it is
  the strongest form of the requirement — every property the editor can
  touch, code can touch, spelled identically.
- **But it costs the scene class the ability to be a `Widget`.** Sketch 3
  quietly assumed `OnboardingPage1(…)` mounts directly — the scene class
  extending some `Scene extends Widget` base, build() walking the nodes,
  no generation step at all. Mutable public nodes on a Widget violate
  `@immutable` (`must_be_immutable`), and philosophically: a widget *is*
  configuration, and this class is a live model. **The fork:**

  | | **(i) the scene class is a Widget** | **(ii) the scene class is a model; `SceneView(scene)` is the widget** |
  |---|---|---|
  | mounting | `BannerScene(title: …)` directly | one wrapper, everywhere |
  | clone/tweak | needs an edit story after all — immutable nodes, drafts | **cascades, free** (this sketch) |
  | runtime control | rebuild with new args only | mutate + notify (sketch 5) |
  | what the class is | configuration | the same live document the editor edits |

  Sketch 5 decides my recommendation.

## Sketch 5 — runtime control is the editor's own data plane, arriving third

The requirement said *controlled at runtime*, not just configured. Under
fork (ii) the spike has already built the mechanism — `SceneDocument` is a
`ChangeNotifier`, and the composited editor drives a live guest by mutating
the model:

```dart
// In the app, live — the same moves the editor makes on the canvas:
void onCartGrew(int items) {
  scene.badge.args['count'] = items;   // retune an injected widget
  scene.glow.opacity = items > 3 ? 1.0 : 0.6;
  scene.notify();                       // SceneView repaints
}
```

**Findings:**

- **One mutation API, three consumers.** The editor's canvas, a program's
  clone-and-tweak, and the app's live control are the same typed writes on
  the same model — motion v2's "the editor is a GUI over the same draft
  API a user can call," now with the app as the third caller. This is the
  "something more powerful" the flat-constructor framing was missing: the
  constructor *configures*; the model *stays controllable*.
- **Mutate-in-place is the primary runtime story; instance swap is the
  hazard.** A long-lived motion holds typed references into one scene
  instance; swap the scene and every reference dangles. Rebinding a motion
  to a fresh instance means transplanting machine state (the transition
  snapshots that are irreducibly stateful) — possible *because* states are
  enum-named, but machinery. Prefer the mutation; document the swap as the
  sharp edge; `SceneView` can hold the pair so the common case never sees
  it.
- Fork (ii) wins my recommendation: sketch 4's cascades and this sketch's
  live control both come free, and the widget wrapper is one line that
  also gives the runtime a place for reassemble-rebuild and motion state.

## Sketch 6 — structured parameters, refused where the law says

The tempting sketch — one scene, data-driven pages:

```dart
OnboardingScene(pages: [                      // ✗ does not survive
  PageData(title: 'Welcome', hero: a1),
  PageData(title: 'Order ahead', hero: a2),
])
```

A list parameter that *creates nodes* is `Repeat` — the tier-3 slide motion
v2 refused for compositions, now knocking at the scene door. It stays
refused, and the refusal costs nothing because **cardinality already has a
home**: the app's `PageView` loops over data constructing scenes (sketch
3), a composition loops constructing clips, the matrix loops over axes.
Programs own cardinality; the model owns one artboard's shape. (The same
line, fourth arrival: studio owns shape, program owns schedule.)

The honest limit stated now rather than discovered: a *within-scene*
repetition (a bullet list, a row of feature cards) cannot be data-driven in
v1 — you declare three bullets and parameterize their texts, or the
repeating region is an external node whose widget loops in real code.

## Sketch 7 — nesting is a call, and it unifies with Ext

```dart
class OnboardingPage1 /* … */ {
  OnboardingPage1({this.title = 'Welcome back', this.punchline = 'Skip the line'});
  final String title;
  final String punchline;

  // A nested scene: a call site. Overrides are arguments; parameter
  // plumbing is spelled exactly as code spells it.
  late final hero = Use(HeroCard(title: title, badgeCount: 3));
  late final root = Frame(children: [hero, caption]);
  late final caption = Text(punchline);
}
```

**Findings:**

- **The grammar widening is one item**: inside `Use(…)`, an invocation of a
  *known scene class* whose arguments come from the value grammar plus this
  class's parameters. Unknown class → the usual teaching refusal.
  Internals sealed, overrides only through declared parameters — the
  research doc's law falls out of the spelling; the Figma failure mode is
  unrepresentable.
- **A nested scene and an external node are converging on one shape.**
  `Use(HeroCard(title: …))` and `Ext(DrinkBadge, args: {'size': 140})` are
  both "sealed thing, declared surface, call with args" — and the
  registration work was already heading toward constructor-shaped entries.
  Whether Ext's spelling migrates to `Use(DrinkBadge(size: 140))` is a
  registration-side question; the model underneath should be one node kind
  wearing two sources.
- **The motion bridge falls out**: a track targeting a nested scene's
  parameter (`hero.badgeCount` over time) is Rive's parent-drives-inputs
  arriving through our own front door — the same write as sketch 5's
  runtime mutation, driven by `evaluate(t)` instead of an event. No new
  mechanism; noted for the motion grammar rewrite.

---

## The round's scoreboard

**Died in the writing:** the merged parameter surface (dependency direction
+ it was the last codegen standing); structured node-creating parameters
(tier-3 slide); translation keys in the scene file (string identity makes
them redundant).

**Reversed:** my lean to the merged surface (sketch 3) — two surfaces are
idiomatic wrapping, not noise.

**The fork for the owner (the round's one real decision):** sketch 4 —
scene class as Widget (i) versus scene class as live model behind
`SceneView` (ii). My recommendation is **(ii)**: clone/tweak by cascade and
live runtime control both come free, the app's control API is literally the
editor's data plane, and the one-line wrapper is where motion state and
reassemble live anyway. What (i) offers — wrapper-free mounting — is one
line of ceremony saved at the cost of an entire draft subsystem.

**Held throughout:** mockup-as-default; no magic strings (parameters are
identifiers, entries are identifiers, nested scenes are constructor calls);
internals sealed at every boundary; programs own cardinality.

**Newly open:**

1. The asset/image parameter type (sketch 1) — the hero image needs one.
2. Parameter *removal* with live call sites — in-repo callers break at
   compile (good); scene-to-scene references (`Use`) need the parse door's
   cross-file refusal, same shape as motion targets.
3. Whether `Ext` and `Use` merge into one spelling (sketch 7) — decide
   with the registration bridge, not before.
4. The motion-state transplant on instance swap (sketch 5) — design only
   if a real consumer hits it; mutate-in-place is the documented path.

**Next:** if the fork lands on (ii), the parameter grammar is now fully
specified by sketches 1, 2 and 7 — initializing formals with literal
defaults, parameter identifiers as values, `Use` of known scene classes —
and can be written into the round-trip engine the way the field grammar
just was, with the banner as the first parameterized scene rendered at two
argument sets.
