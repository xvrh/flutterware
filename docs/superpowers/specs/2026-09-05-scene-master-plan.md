# The scene editor becomes a design tool

**Date:** 2026-09-05
**Status:** direction. The five decisions below are taken; every milestone
still gets its own design before it is built. Nothing here is scheduled.
**Hardened 2026-09-05** by a second pass against the code — the corrections
are in place, and §8 lists what that pass found.
**Extended 2026-09-07** with §4.5 and M10 — the text model, decided in
discussion; §9 lists what that pass changed, including the reversal of §7.1.
**Leans on:** `2026-08-31-scene-v1-design.md` (parameters are the crux, the
mockup is the default), `2026-09-03-scene-as-dart-plan.md` (P1–P7 done — the
file is Dart and compiles), `2026-09-03-external-args-findings.md` (the
declaration pattern, and its two open questions),
`2026-08-31-scene-parameter-sketches.md`, `2026-08-31-motion-on-scene-ground.md`.

**The brief:** three asks — expose a scene's parameters with an editor for the
mockup values; shared and injected styles and tokens; enough properties to
reach parity with a design tool and import from one. Be maximally ambitious
about all three; ship in small useful steps.

---

## 1. The three asks are one question

**Where does a property's value come from, and who may change it?**

Today the entire answer is one map — `SceneNode.paramRefs`
(`model.dart:157`), `prop → parameter name`, editor-only. That is correct as
far as it goes: compiled, `fontSize: titleSize` is just Dart, and the runtime
needs no provenance at all. It is one level deep, and it is the seed of
everything asked for. Widen it into a **binding** and the three asks become
rows of one table:

| Provenance | The file spells | Ask |
| --- | --- | --- |
| a literal | `fontSize: 54` | today |
| this scene's parameter | `fontSize: titleSize` | **parameters** |
| a repeat item's field | `line.amount` | today |
| a shared token | `color: tokens.brand` | **tokens** |
| a style bundle | `style: tokens.title` — several properties at once | **styles** |
| the caller's value | a parameter, and the app passes it | **injection** |

A design tool's model is exactly these nouns: variables, styles, component
properties, instance overrides. So the importer is not a third feature — **it
is the acceptance test for the first two.** If a real design file imports, the
vocabulary was right; what it refuses is the list of what to build next.

## 2. The north star

**A design tool's model, in a Dart file that compiles and ships.** The design
file *is* the production code, and its motion is real Flutter animation.

That sentence settles arguments on its own. The loudest: import is **one-shot
into Dart**, never a live link, because the `.scene.dart` has to be the source
of truth the moment it lands. A round-trip back out is a different product and
is not this one.

## 3. What is already true

Measured on this checkout, so nobody re-derives it.

- **Provenance is fragile today.** `scene_file.dart:278` — a parameter
  reference survives a save only while the property still equals the
  parameter's default. So binding a property and then nudging it in the
  inspector **silently unbinds it**. Every ask above needs this inverted
  before anything else.
- **Half the property table already exists.** `ScenePropSpec`
  (`motion_model.dart:148`) carries name, track kind, identity, unit, soft
  range, angular, entrance, and `imposedProps` + `animatableProps(node)` drive
  the motion inspector from it. It covers the *animatable* subset only, and
  knows nothing of defaults, emit spelling, or whether a property is authored
  at all. Widening this is a smaller move than inventing a table.
- **A property costs about twenty places.** Grep hits across the seven files
  that would have to change: `opacity` 36, `corner` 28, `borderWidth` 23,
  `fontSize` 18. There are ~24 authored properties now; parity is ~50 more.
  Fifty times twenty-five is not a plan, which is why M4 comes before the
  widening rather than after it.
- **The declaration pattern is proven.** Externals: the app declares by hand
  in a file that names nothing generated, the tool reads it as text, generates
  typed classes, and refuses an undeclared name. Tokens are the same shape
  with values instead of widgets, and get the same machinery rather than a new
  one.
- **Parameters are already in the grammar and in codegen.** A scene header
  declares them, `scene_args.dart` generates `…Args`, and a nested instance's
  arguments *are* editable (`inspector.dart` `_sceneProps`). What is missing
  is an editor for a scene's **own** parameter list and its mockup values.
- **The imposed properties are fx-only.** `translateX`/`scale`/`rotate` exist
  in motion and not in the file; `opacity` is both. The authored set and the
  animatable set overlap and neither contains the other — so the unified table
  needs a per-property flag, not one list.
- **There is no `visible`, and no `bool` parameter.** `SceneParamKind` is
  `string | number | color | list`; a node has `opacity` but nothing that
  takes it out of layout. A design tool's most common component property is
  a boolean that shows or hides a layer. This is the first thing an import
  hits, so it belongs in M2, not M9.
- **Drill-in edits the main component today.** `workspace.enter` switches the
  surface to the child's *file*; `resolveInstances` gives each `SceneRefNode`
  its own `instantiateScene(child, args)` copy, so instances are already
  distinct objects. What does not exist is a door that edits one instance's
  overrides from inside it.
- **A nested instance's document is a per-node copy, re-made on every
  resolve.** Which is what makes "edit the innermost override" cheap — the
  copy is the instance — and what makes the shared child file the only place
  a mockup lives.

## 4. Five decisions, taken at the ambitious end

### 4.1 A binding is a type, and an edit reaches its source

`Map<String, String> paramRefs` becomes `Map<String, SceneBinding>`, sealed:
`ParamRef | ItemRef | TokenRef | StyleRef`. Storage stays where `paramRefs`
is — read-plane, empty in a compiled scene.

Drop-on-edit is inverted: **editing a bound property writes what it is bound
to.** For a parameter that means the parameter's *default*, because the
default is the mockup — the law the whole design already rests on. For a
nested instance it means the instance's argument. That is the override
cascade of a design tool, arrived at from the other end: edit the innermost
override that exists, otherwise the default.

### 4.2 Injection is one `tokens` parameter, and modes come free

A token set reaches a scene as a single constructor parameter, not one formal
per token: `BannerScene(tokens: MyTheme.of(context).scene)`. One formal
regardless of how many tokens the scene reads; a mode is a different set, so
light/dark costs nothing new; the editor previews a mode by handing the canvas
a different set.

The parameter is **recognised by its type, never by its name.** The author
writes `class Banner({SceneTokens tokens = SceneTokens.light})` and calls it
what they like; the parser sees a formal whose type is the generated tokens
class and knows what `tokens.brand` means from that. This is the lesson of
`motionReservedNames`: a name the framework claims is a name the author has
lost, and the plan adds none.

`late final` reads its token once, so a mode change needs a fresh scene
instance — which is what a `build` method does anyway, and `SceneView` can be
the one that notices. A motion bound to the old instance has to be copied
onto the new one (`copy(scene)` exists for this) and a player mid-flight has
to be re-targeted; that is the one runtime cost of a theme that flips while
an intro is playing, and M6 owes a demonstration of it.

**Almost no new runtime.** In-file sharing is a non-node field of the scene
class; cross-scene sharing is the declaration file, imported; injection is a
parameter and ordinary Dart at the call site. The exception is styles — see
§4.3 — which do reach the constructors.

### 4.3 A style is a bundle, with inherit/override per property

Not "a style is several token references". A style names a **subset of the
property table** and applies it in one move, and a property may then be
overridden locally — which means the inspector grows a per-property state
(*from `title`* / *overridden here*) and a detach. This is the expensive
answer and the right one; it is also the reason M4 is a prerequisite rather
than a tidy, because a subset of the property table is unexpressible while
the property set is spread over 1800 lines of hand-written emit.

Two costs the first draft did not name:

- **Styles reach the runtime.** `TextNode('…', style: tokens.title,
  fontSize: 60)` has to compile, and a constructor cannot tell a passed
  argument from a defaulted one. So every styleable property becomes a
  nullable constructor parameter resolved as `fontSize ?? style?.fontSize ??
  16`. That is a change to every node constructor and to the compiled plane,
  bounded and mechanical, and it is the one place this plan adds runtime.
- **In the file, equal means inherited.** The emitter writes only the
  properties that differ from the style's values; a property overridden *to*
  the style's value is indistinguishable from one inheriting it, and follows
  the style when the style changes. Design tools keep an override flag to
  tell the two apart; a Dart file cannot carry one without noise. Decided:
  it does not, and the inspector says *from `title`* for both.

### 4.4 The importer is whole-file, and its refusals are the roadmap

Import the node tree, text, auto-layout, variables and component instances;
refuse the rest **per node, in a report**, never approximate silently. The
report is then what orders the widening — real files deciding which property
matters, instead of us guessing.

### 4.5 A text style is the whole treatment, and a node spells one

Decided 2026-09-07, in discussion. It reverses §7.1 and undefers one of §6's
three deferrals.

The ask that produced it: text rich enough to design with — a poster, a game
title — which means the paragraph is painted more than once. Once that is
true, four things fall out of it.

**Lay out once, paint many.** A stroke widens a glyph visually without
touching its metrics, so every pass stays registered. That is the whole
reason multi-pass works, and it is therefore a law: **a pass may change
paint, never layout.** It splits the text properties in two — the METRIC
ones (family, size, weight, axes, tracking, leading, case, italic, align,
maxLines), which are the paragraph, and the PAINT ones, which are a list of
passes over it. Let a pass carry its own tracking and there are two layouts,
and every effect drifts by a subpixel that grows along the line.

**The paint stack is one property, on the style.** `layers`, a new kind: an
ordered list of anonymous `FillLayer` / `StrokeLayer` values, painted back to
front, each with a paint, a width, a join, a blur, an offset, an opacity and
a blend. A drop shadow is a blurred offset fill; an outline is a stroke
beneath the fill; sticker type is stroke-stroke-fill; extruded arcade type is
a dozen offset fills under a gradient one; neon is two blurred fills under a
tight one. None of those is a code path — the effect space is combinatorial
rather than enumerated. Which is the argument against `shadows` and `stroke`
as scalar properties, considered and rejected: they are two points in a space
one list covers whole, and they would not compose, because you cannot put a
shadow BETWEEN two strokes if a shadow is a property.

Layers are anonymous, and they sit on the style rather than the node, because
**a named per-node stack cannot be shared** — a treatment spelled as fields
in one scene file is a treatment nobody else can have. On the style, one
token carries the whole look. The price is that an override replaces the list
whole: anonymous lists cannot merge. Taken.

They are immutable values — they have to be, to sit inside a `const
Token<SceneTextStyle>` — so an edit replaces the list, and an animation
composes a value at read time, which is what `fxRendered` already does for
`fontSize` and `color` (`view.dart:273`).

*Narrowed 2026-09-08, in discussion:* **`align` and `maxLines` came back out
of the style.** The line the two lists are drawn on is whether a property
describes the TYPE or the PARAGRAPH. A face, a size, a tracking, a stack of
paint passes are the treatment, and sharing them across a poster and a card
is the whole point of a style. Where the lines break and how they sit in the
box are the box's business: two texts in one display face routinely differ on
both, and a shared style that decided them would be one nobody could share.
Flutter draws the same line — `align` and `maxLines` are `Text`'s arguments,
not `TextStyle`'s. So the table's text rows split: `sceneTextOwnProps` (the
positional `text`, plus those two) and `sceneStyleProps`, and it is the
SECOND that is pinned to `sceneTextStyleFields`. `textCase` was considered
alongside them and kept: it is a treatment — a display style that is always
uppercase is a real thing to share — even though Flutter has no such field.

This is a **breaking change to the scene grammar**, and a scene file is real
Dart, so a file spelling `align:` inside its style stops compiling until it
is rewritten. The parser is deliberately lenient in the other direction: it
still reads both inside a style literal or a `copyWith`, puts them on the
node, and the next save writes them where they belong — the same courtesy
the 0.8 files get.

**`SceneTextStyle` is the style subset of the property table**, walked rather
than the five hand-written fields it is today. Then `values`, `sets`,
equality, the emitter's inherit test, the token literal, the token parse and
the inspector's *from `title`* row all walk one list, and a new text property
is a row instead of six edits across five files. The constructor stays
hand-written and pinned by a test — the table cannot derive a constructor,
and `copyWith` is constructor-shaped.

*Corrected while building M10a:* the first draft of this said **map-backed**,
storing the values in a `Map` keyed by the table's names. It cannot be done.
A style has to be `const` — `const Token<SceneTextStyle>('title', …)` is what
a declaration file spells and what a generated default needs — and **a const
constructor cannot build a map out of its own parameters** (`values = {…}` in
an initialiser is "not a constant expression"; only a `const` literal, which
cannot see the parameters, is allowed). So the fields stay fields, and the
one organ is a list beside them — `sceneTextStyleFields`, name plus accessor
— that `values`, `==` and `hashCode` walk. `scene_props_test.dart` pins it to
the table's text rows in both directions, which is what makes the two lists
one. The property that made the difference is `==`: a field forgotten there
is a silent bug, and it now cannot be forgotten.

**A node spells a style and its paragraph.** `TextNode(headline, style:
tokens.display.copyWith(letterSpacing: -6), align: SceneTextAlign.center)`. This is the reversal of §7.1:
an override is no longer the property spelled beside the style, it is a delta
ON the style — and an in-file `SceneTextStyle(…)` literal becomes legal,
because it is the only way to say a node's own type. Bindings survive
untouched, `color: tint` simply moving inside the copy call, where the
emitter writes a reference exactly as it does now.

What that buys is that the cost §4.3 accepted and named — *"the one place
this plan adds runtime"* — is not paid. `TextNode` keeps `text` and `style`
and never grows another text parameter, whether the table carries six text
rows or thirty. The model does not move: the node keeps flat resolved fields,
so the read plane, the inspector's inherit/override display and the motion
tracks are untouched. The constructor and the file spelling are what change.

Three consequences, all accepted:

- **`copy` is taken.** `SceneMotion.copy(scene)` means *clone, rebound to a
  scene*. The style's is `copyWith`, so one word keeps one meaning.
- **The trivial case gets noisier.** `TextNode('☕', fontSize: 180)` becomes
  `TextNode('☕', style: SceneTextStyle(fontSize: 180))`, which is most nodes
  in every example file here. **No shorthand**, decided: two spellings for one
  thing means the emitter has to choose between them and the reader has to
  accept both forever.
- **Grammar 0.9.** Every scene file written so far spells `fontSize:` on the
  node. The reader accepts the old form and Save converges, the way the motion
  parser already converges its non-canonical spellings.

**Runs are the endgame, and the painter is written for them now.** §6 defers
*mixed styles inside one text*; this undefers it. A run is a string plus a
style delta — which the map-backed style makes a value type that already
exists rather than a new concept. So the renderer stops being `Text(style:)`
and becomes a painter over a run LIST, with today's `String` producing exactly
one run; runs then land as a model, grammar and inspector change with no
renderer work at all. Layers stay the paragraph's and runs carry metrics plus
a colour: a per-run stroke pass would need per-run geometry, and it is refused
rather than deferred.

## 5. Milestones

Each lands something usable on its own. Sized to be shipped and lived with
before the next is designed.

**M1 — a binding is a type, and an edit reaches its source.**
The sealed type, the wire, the round-trip, and the inversion of §4.1 — plus
the smallest possible *bound to `title` · unbind* affordance in the
inspector, because drop-on-edit was the unwitting unbind gesture and taking
it away without a replacement leaves the file as the only door. Lands: a
binding survives being edited, which today it does not.

**M2 — the parameters panel.**
Scene-level: declare, rename, retype, reorder, delete, edit the mockup. From
the node inspector: promote this property to a parameter, bind an existing
one, unbind. Refusals for deleting a bound parameter and for a name a node
already has. `bool` joins the parameter kinds and `visible` joins every node,
together, because a boolean that shows a layer is the parameter a component
most often has. The mockup editor for a `list` parameter is a small table —
rows by fields — and is scoped as its own piece inside this milestone. Lands:
the first ask, for a flat scene.

**M3 — parameters through the nesting.**
A parent's parameter reaches a child's argument (`PromoBadge(label: title)` —
a `ParamRef` on prop `args.label`, a namespace the model already has). Two
doors into an instance, both named: *edit this instance* writes its
overrides on the per-node copy; *go to main* is today's drill-in and edits
the child's file. The cascade is visible: *default* / *bound to `title`* /
*overridden here*. Lands: the first ask, for nested scenes.

**M4 — one property table, several hosts — proved by four properties.**
Widen `ScenePropSpec` into the authored plane (default, authorability, value
kinds beyond number/colour, control hint) and derive the wire, the emitter,
the parser allowlist and the inspector rows from it. One generic round-trip
property test replaces the per-property ones; a test pins the table to the
constructors, the way the bridge test pins enum order to Flutter's. Proved by
landing the four properties that are currently too expensive to bother with:
per-corner radius, clip, min/max size. What the table cannot derive is the
constructor — the file *is* a call to it — so an added property still costs
a row, a constructor parameter with its field, a renderer case, and a named
parameter on `animate()` when it animates. Four places, pinned to each other
by a test, instead of twenty-five pinned by nothing. Lands: four properties,
and the next fifty at that price.

**M5 — tokens.**
`scene_tokens.dart` written by hand, generated accessors, `TokenRef`, an
inspector picker, a refusal for an undeclared name. Two kinds from the start:
a **value** token the editor renders (`SceneColor`, `double`), and an
**opaque** token it can only name and pass — an `InputDecoration`, a
`TextStyle` the app already owns — which reaches an external widget as an
argument and never the canvas. Lands: a colour or a size shared across every
scene in the package, and the app's own decoration objects named in a scene.

**M5½ — variables come in from a design file.** The smallest slice of the
importer, pulled forward: a design file's variable collections become a
`scene_tokens.dart`, modes included. Needs no node import at all, and puts
real data against the token declaration before styles are built on it.
Lands: the first thing imported, and the token shape validated by a file
nobody here wrote.

**M6 — tokens are injected, and modes come free.**
The `tokens` parameter recognised by type, a mode switch in the canvas, an
app that passes its own set, a nested scene that receives its parent's set
without the author threading it (the generated `…Args` carries it). And the
demonstration §4.2 owes: a theme flipped while an intro plays. Lands: light
and dark on the artboard, and a scene that follows the app's theme.

**M7 — styles.**
A named subset of the table; apply, override one property, detach. Lands: text
styles, which is the sharing that actually hurts today.

**M8 — the importer and its report.**
A design file becomes a `.scene.dart` plus tokens plus styles, with a per-node
report of everything refused. Built and tested against **saved file JSON**,
so CI never needs a credential; the network lane is a thin fetch in front of
it. Lands: a real imported file on the canvas, and an ordered list of what to
build next.

**M9… — widen, guided by the report.**
Expected order, to be overruled by the report: paints (several fills,
gradients, images), effects (shadows, blur), text (family, letter spacing,
line height, decoration — `maxLines` is already there), strokes (alignment, dash), constraints.
Each is a table row and a renderer case. The text row is superseded: §4.5 took
it out of here and made it M10.

**M10 — text becomes a type system, in four slices.**
Pulled out of M9's widening list, which named text as one row among several.
§4.5 makes it the largest thing on the roadmap, so it gets its own chain.

**M10a — the foundation, and the typography that comes with it.**
`SceneTextStyle` map-backed over the table's text rows; `copyWith`; `TextNode`
loses its text parameters; grammar 0.9 with a converging read; the painter
rewritten over a run list. Then the flat properties, a table row each:
`fontFamily`, `letterSpacing`, `wordSpacing`, `lineHeight`, `italic`,
`textCase`, `decoration` with its colour, thickness and style. `lineHeight` is
a bug fix as much as a property — `view.dart:276` hardcodes `height: 1.15` and
no file can reach it. The font picker's source already exists:
`asset_catalog.dart` parses the pubspec's families with their declared
per-face weights, so the picker can offer the project's own faces and grey out
a weight that has no face. Lands: a scene can name a typeface and set its
tracking, which today it cannot.

**M10b — layers, paint, and the style library.**
`ScenePropKind.layers`; `ScenePaint` (solid and the gradients) built here,
because a gradient fill pass is table stakes for poster type, and shaped so
`fill` can adopt it the day §6's one breaking change is taken; the painter's
multi-pass loop with a cache keyed on the METRIC properties only; blur through
a `MaskFilter` on the pass's own paint rather than a `saveLayer` per pass. A
preset is a style applied and detached — a seeded library, not a mechanism,
which is what collapses it into this milestone instead of being its own.
Lands: the poster.

*Extended 2026-09-10:* a text pass now paints with a linear gradient of any
length — a three-colour gradient with no stops used to throw, since the
engine refuses a gradient with anything but two colours and no stops — and
with two shapes beyond linear: radial, stretched to the text's box rather
than Flutter's shortest-side radius, and sweep, in degrees from twelve
o'clock. A pass can lay its gradient across each line (`SceneLayerBox.line`)
instead of the whole text, so a two-line title in gold gets the gold twice
rather than once with the second line stuck in its darker half. A pass also
takes one of sixteen blend modes, for how it lands on what is beneath it.
The inspector edits all of it — a kind picker, a stop bar for a gradient's
colours and positions, the shape's own fields (an angle, a centre and a
radius, or a centre and two angles), the "Laid across" picker and the blend
picker — and a Gloss preset demonstrates the per-line gradient with a sheen
that fades to nothing over the top half of each line. Shaders are Phase 3 of
`docs/superpowers/plans/2026-09-10-scene-text-layer-gradients.md`, planned
separately after a spike. *Shipped 2026-09-10:* a pass can paint with a
project's own fragment shader, animated by scene time and reloaded in place —
`docs/superpowers/specs/2026-09-10-scene-shader-paint-design.md`.

**M10c — variable axes.**
`axes` as a tag → number map, discovered from the font's `fvar` table so the
inspector draws real sliders with the font's own min, default and max rather
than asking for four-letter tags. `weight` writes `wght` when the family is
variable, so one control means one thing. Tracks are `TrackKind.number`
already, which makes a continuously morphing headline nearly free once the
axis exists — the thing a discrete `FontWeight` can never do. An OFL variable
face is bundled in `examples/example` for it. Lands: the demo animates.

**M10d — runs.**
Text becomes a list of runs, each a string and a style delta. Every open
question here is grammar, not rendering: how a run list is spelled in a `late
final` field, whether a run is addressable in the tree, whether motion or a
parameter may target one. Lands: a bold word inside a paragraph that still
wraps as one paragraph.

## 6. Known hazards

- **`fill` is one colour.** Several fills, gradients and images make it a list
  of paints — the one breaking model change in the whole plan. Take it early
  in M9, deliberately, not by accident in the middle of something else.
- **Vector paths are not in this plan.** Import them as an asset and say so in
  the report; a path editor is a different product.
- **The round-trip invariant gets harder with every property.** M4 is what
  keeps it one test instead of fifty, which is the real argument for doing it
  before the widening.
- **A changed declaration has no migration story.** The open question from
  `2026-09-03-external-args-findings.md` — a removed or renamed argument —
  gets worse with tokens and styles pointing at names too. Solve it once, in
  M5, for all four binding kinds.
- **A package with no declaration file silently gets no second grader.** Same
  document, same standing. The editor should say so rather than let it read as
  checked.
- **Three concepts a component import will ask for that this plan defers**,
  each named so the report can name it too — and one of which §4.5 has since
  undeferred (see §9): a **slot** (a parameter whose
  value is content — another scene or a widget — which is how a component
  takes its children; today a parameter is data), a **variant** (one class
  per variant or an enum parameter — undecided), and **mixed styles inside
  one text** (a `TextNode` is one style; a run of styled spans is not in the
  model). Slots are the largest of the three and probably the first real
  addition after M9 begins.
- **Multi-pass wants a cache before it wants features.** Eight passes with a
  blur at 60fps on an editor canvas means one `TextPainter` per pass, keyed on
  the METRIC properties alone — rebuilt when the metrics change and not when a
  colour does. Get that key wrong and the canvas re-lays-out the paragraph
  once per pass per frame.
- **`ScenePaint` arrives in text before `fill` is ready for it.** The one
  breaking model change above is `fill` becoming a list of paints; M10b needs
  the paint VALUE first, for text layers. Shape it for both, or the day `fill`
  widens there are two notions of paint to reconcile.
- **Scene export is raster today.** `export/filmstrip.dart` and
  `export/video.dart` composite images, and nothing in this plugin goes
  through `captureSvg`/`capturePdf`. A multi-pass painter keeps text as vector
  operations rather than pixels, so that stays true — but a stroke pass and a
  blurred pass are the first two things a vector export would have to answer
  for.

## 7. Open

1. ~~**How a style with one property overridden is spelled in the file**~~
   Answered in M7, 2026-09-06: **the override is the property, spelled.**
   `TextNode('Sub', style: tokens.body, fontSize: 24)` — the style first,
   applied whole; anything the node spells beside it is an override and
   read after. Inherited is absent. The emitter compares each text property
   against the style's value where the style sets one (the table's default
   elsewhere) and writes only what differs — so a property overridden back
   to the style's own value stops being written and follows the style, the
   §4.3 decision made concrete. The compiled node resolves the same way,
   `fontSize ?? style?.fontSize ?? 16`, so a file the tool wrote and a scene
   the compiler built agree. A style is a token (`Token<SceneTextStyle>`),
   never an in-file literal: a bundle nothing else could share is not a
   style. Modes on styles are not built yet; the reader refuses them.

   **Reversed 2026-09-07** by §4.5, which is where the reasoning now lives.
   The override moves inside the style — `style: tokens.body.copyWith(fontSize:
   24)` — so a node spells one slot and never grows a text parameter again,
   and an in-file `SceneTextStyle(…)` literal is legal because it is the only
   way to say a node's own type. What survives the reversal is the rule
   underneath it: equal is inherited, there is no override flag, and the
   emitter writes only what differs from the style. What changed is where the
   difference is spelled. The reversal is what makes `layers` affordable:
   a list-valued property would have been a node parameter under the old
   spelling, and a treatment nobody could share.
2. ~~**Whether a token set is a class or a map.**~~ Decided in M5, 2026-09-05:
   **a class**, generated. `scene_tokens.dart` declares `final sceneTokens =
   [Token<SceneColor>('brand', SceneColor(0xFF…)), …]`; the generator writes a
   const `SceneTokens` into `scene_args.dart` with one typed field per token
   and the declared value as its default. A scene reads them through a header
   formal **recognised by its type** — `final SceneTokens tokens = const
   SceneTokens()`, called whatever the author likes — so `tokens.brand` is a
   field the compiler checks and an undeclared name does not compile. That is
   the north star applied (a Dart file that compiles); a map would be
   late-bound and lose it. The formal therefore lands in M5 rather than M6:
   without it there is no spelling for a token read that M6 would not have to
   migrate. M6 adds the modes (other argument lists of the same class), the
   canvas switch, and the parent passing its set down.

   Two more things M5 settled. **An edit detaches.** Tokens are declared by
   hand in a file the tool only reads and shared by every scene of the
   package, so editing a token-bound property does not move the token (the
   parameter rule) — the property detaches and keeps its value, the way a
   design tool detaches a variable when you type over it; the inspector
   offers the token back one click away. **Opaque tokens landed as M5b**,
   the same day. `Token<ButtonStyle>('cta', FilledButton.styleFrom(…))` is
   read as a name and a type, never a value; the generated class gets a
   getter (`ButtonStyle get cta => _token('cta')! as ButtonStyle`) that
   reads the declaration list at the moment a scene asks, the way
   `_external` does, and the generated file copies the declaration files'
   own imports so the type is spelled as it was spelled there. An external
   argument of any type (`Arg<ButtonStyle>('style')`, no default) is the only
   thing an opaque token can fill; the node's argument carries the MARKER
   `{'token': 'cta'}` over the wire and the guest — the process that compiled
   the declaration — resolves it in `bindExternals` before the builder sees
   it. An edit cannot detach an opaque binding (there is no value to edit);
   unbinding clears the argument, and a token gone from the declaration
   clears it too. The compiler stays the last grader for the type match
   between a token and the argument it fills.
3. **Whether the importer runs in the studio or the CLI.** It needs network and
   credentials, which is a first for this plugin. M5½ (2026-09-06) settled
   the shape without deciding the lane: the import is a **plugin action**,
   `scene importTokens --file=<saved JSON>`, so `fw`, the MCP server and the
   studio all reach the same door, and the network lane (M8) is whatever
   produces that file. Modes reached the declaration grammar here —
   `Token<T>('name', value, modes: {'dark': …})` — and the generated class
   carries one static set per mode name (`SceneTokens.dark`, `SceneTokens.
   modes`), which is what M6's switch flips. A mode name that is a keyword
   ("Default") is suffixed (`defaultMode`) rather than refused, because a
   mode is a whole set and refusing it would take every variable with it; a
   variable whose name makes no identifier, or collides once one is made, is
   refused by name with the reason. The fixture is shaped after the
   variables endpoint's documented answer, not a captured one — the first
   real export is the acceptance test the plan promised, still owed.

   **M6 landed 2026-09-06.** A mode is view state on the document
   (`tokenMode`), never written: the canvas bar's `mode ▾` puts the mode's
   values behind every token reference (`applyTokenMode`), reconcile compares
   against the mode's value so an edit in dark mode keeps its binding, and
   undo re-applies the mode over the snapshot it restores. A nested scene
   receives the parent's set as `BadgeArgs(label: title, tk: t)` — the
   child's own formal name — threaded by the workspace whenever both sides
   declare a formal and never by the author; the generated `…Args` carries
   the set as a field that never reaches the wire. The runtime demonstration:
   a theme change is a fresh instance (`SampleScene(tokens:
   SceneTokens.dark)`), the motion's generated `copy(scene)` rebinds, and
   `MotionPlayer.retarget` carries the playhead across at the same moment;
   `SceneView` follows a new definition through `didUpdateWidget`. What M6
   did NOT build: an app-side widget that watches `Theme.of(context)` and
   does the copy for you — the pieces are public and one app will show the
   idiom before it is framed.
4. ~~**How a layer animates.**~~ Decided 2026-09-07: **a style-valued
   track.** Anonymous layers have no address, so `scene.<layer>.animate(width:
   …)` cannot exist; index-addressed tracks (`layers[2].width`) were rejected
   because reordering a stack would silently repoint the animation —
   precisely the failure `AnimateGroup` holding a NODE rather than a name was
   built to avoid — and a static treatment was rejected because varying
   stroke widths are what motivated layers in the first place. So a track's
   value is a whole `SceneTextStyle`, lerped between two keys: key
   `tokens.display` at 0ms and a heavier, wider variant at 600ms, and the
   metrics and the paint stack move together. It is the decision above
   applied to time — the treatment is one value, so one value is what
   animates.

   What it opens, to be designed in M10b rather than assumed:
   - **A new `TrackKind`.** Today a track is `number | color` and both lerp
     a scalar. A style track lerps a struct: numbers interpolate, colours
     through `SceneColor.lerp`, and the discrete fields (weight, align,
     case, decoration, family, maxLines) snap at the midpoint — which is
     what `TextStyle.lerp` itself does, so the rule is borrowed rather than
     invented.
   - **A compatibility rule for stacks of unequal length.** Flutter's
     `Shadow.lerpList` pads the shorter list with transparent shadows, and
     the same shape works for a missing layer. A kind mismatch at one index
     — a fill against a stroke — cannot lerp, and snaps.
   - **How it composes with the per-property tracks.** `fxRendered` folds
     contributions per property, so a style track has to EXPAND into
     per-property contributions rather than sit beside them; otherwise a
     `fontSize` track and a `style` track fight over one field with the
     winner decided by stack order.
   - **What a key's value is spelled as.** A number key is a literal or a
     parameter name. A style key is a token reference or a literal style,
     which is a shape the motion grammar has not carried before.
5. **The type panel.** Twenty metric properties plus a layer list cannot be a
   flat column, and a flat column is what the text section is today
   (`inspector.dart` `_textProps`). The intended shape: a summary row in the
   inspector — `Inter · 54 · Bold · -2%` — opening a real type panel, with the
   rare knobs in the panel and never in the sidebar; the layer stack as an
   add / remove / reorder list, the pattern every design tool already teaches;
   axes shown only when the family is variable. To be designed against
   rendered catalog demos rather than in prose, per the house rule about
   looking at what you built.

   **M10a stopped at the scope line here, deliberately.** It ships the
   properties in a grouped column with a `Disclosure` (`ui/disclosure.dart`)
   over the rare half, and the typeface as a plain field whose empty state is
   *the app's own*. What it does NOT ship is the family PICKER: the source is
   identified — `asset_catalog.dart` already parses the pubspec's families
   with their declared per-face weights, so the picker can offer the
   project's own faces and grey out a weight that has no face — but reaching
   it from the scene panel is a plugin → workspace → inspector wiring that
   belongs with the panel, not in front of it. Until then a typo in a family
   name falls back to the app's font silently, which is the one rough edge
   M10a knowingly leaves.

## 8. What the second pass changed

Read against the code on 2026-09-05, after the first draft. Kept here so the
corrections are not mistaken for the original claims.

- **"No new runtime" was overstated.** Styles reach every node constructor
  (§4.3). Tokens do not. The plan now says which.
- **The tokens parameter had a reserved name waiting in it.** Recognised by
  type instead (§4.2) — the `motionReservedNames` lesson applied before it
  was re-learned.
- **"A table row each" was oversold.** Four places, pinned (M4).
- **M3 asserted one door where two are needed**, and the one it asserted was
  not the one that exists. Both named now.
- **`visible` and `bool` were missing entirely**, and are the first thing a
  component import needs. Moved to M2.
- **M1 removed an unbind gesture without replacing it.** Fixed in M1.
- **Tokens were value-only.** Opaque app-side tokens are what make an
  `InputDecoration` shareable, which was in the brief (M5).
- **Import could start earlier than M8.** Variables need no node import and
  validate the token shape against real data — M5½.
- **The importer needed no network to be built.** Saved file JSON is the
  fixture; the fetch is a wrapper (M8).
- **`maxLines` was listed as missing.** It is not.

Not changed, on purpose: the order M4 → M5. Tokens on colour and number
would work without the table, and a reader will want them sooner; but every
inspector row built by hand before M4 is a row M4 rewrites, and the
generic round-trip test is what makes every token and style property cheap to
prove. If the wait for M4 gets long, M5 without the picker is the fallback,
and this line is where that was weighed.

## 9. What the 2026-09-07 text pass changed

Decided in discussion, against the code. Kept here so the corrections are not
mistaken for the original claims.

- **§7.1's answer is reversed.** The M7 record stays in place; the reversal
  sits beneath it and the reasoning is §4.5.
- **§4.3's runtime cost is not paid.** It named the nullable constructor
  parameter per styleable property as "the one place this plan adds runtime".
  Overrides moved into the style, so no node constructor grows one.
- **§6 deferred mixed styles inside one text.** Undeferred: M10d, and the
  painter M10a builds is written for a run list from the start so that landing
  needs no renderer work.
- **M9's text row is superseded.** "text (family, letter spacing, line height,
  decoration)" was one row in the widening list. It is M10 now, and the
  widening it was listed beside is not what orders it.
- **`shadows` and `stroke` as properties were the wrong build.** Considered
  and rejected: two points in the space `layers` covers whole, and they do not
  compose.
- **A named per-node layer stack was the first draft, and it was unshareable.**
  Layers went onto the style for that reason, which also collapsed presets
  into "a style applied and detached" rather than a mechanism of their own.
- **`SceneTextStyle` was assumed to be five hand-written fields for good.**
  §4.3 already said a style is a subset of the property table; the map-backed
  reading makes that literal, and it is what makes every text property a row.
