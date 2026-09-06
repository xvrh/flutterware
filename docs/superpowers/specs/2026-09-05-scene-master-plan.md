# The scene editor becomes a design tool

**Date:** 2026-09-05
**Status:** direction. The four decisions below are taken; every milestone
still gets its own design before it is built. Nothing here is scheduled.
**Hardened 2026-09-05** by a second pass against the code — the corrections
are in place, and §8 lists what that pass found.
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

## 4. Four decisions, taken at the ambitious end

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
Each is a table row and a renderer case.

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
  each named so the report can name it too: a **slot** (a parameter whose
  value is content — another scene or a widget — which is how a component
  takes its children; today a parameter is data), a **variant** (one class
  per variant or an enum parameter — undecided), and **mixed styles inside
  one text** (a `TextNode` is one style; a run of styled spans is not in the
  model). Slots are the largest of the three and probably the first real
  addition after M9 begins.

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
