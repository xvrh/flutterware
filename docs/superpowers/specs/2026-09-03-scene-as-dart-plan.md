# The scene file becomes Dart

A `.scene.dart` does not compile and never has. It is excluded from the
analyzer (`examples/example/analysis_options.yaml`), its vocabulary has no
library, and the only way a scene reaches a running app is
`sceneFileToJson` → a file → `sceneFileFromJson` → `SceneView`. That was
supposed to be a spike's scaffolding and it became the architecture.

The target this plan works towards, in one line: **the file the editor
writes is a real Dart file, analyzed like any other, that a `build()` method
instantiates with typed arguments — and a motion names its target with a
Dart identifier that the compiler checks.**

## What is already true

Measured 2026-09-03 on the pinned SDK (Dart 3.14.0-95.2.beta):

- **Primary constructors compile and run**, no experiment flag, from
  language version **3.13** — which is already the package's floor. The
  class header the emitter writes today is legal Dart.
- **A const list of records works** as a parameter default, and
  `lines.first.item` is typed. The list parameter needs no map.
- **Imports are already tolerated** by the parser (file-level comments and
  imports, before the class, are not parsed).
- **The motion grammar already spells its target as an identifier** —
  `late final pop = scene.headline.animate(…)`. The string in
  `AnimateGroup.target` is a parse artefact, not the file's shape.

So the gap is smaller than it looks. Four things stand in the way, and only
one of them is a redesign.

## 1. The vocabulary needs a library

`Frame`, `Text`, `Shape`, `Ext`, `Scene`, `NodeLayout`, `Track`, `Key`,
`Par`, `Seq`, `At`, `Speed`, `Repeat`, `.ms`, `SceneMotion`, `.animate(…)`,
plus `Color`, `FontWeight`, `TextAlign`, `CrossAxisAlignment`,
`MainAxisAlignment`, `Curves`.

**The node spellings are typedefs**, which costs nothing:

```dart
typedef Frame = FrameNode;
typedef Text = TextNode;
```

`Frame(x: 48, …)` then calls `FrameNode`'s constructor, so there is no
wrapper layer and no second representation. The constructors go all-named
(see §2).

**The value spellings are Flutter's own.** `Color(0xFF1B1210)`,
`FontWeight.w700`, `TextAlign.right`, `Curves.easeOut` already *mean*
Flutter's types; re-exporting them makes the file say what it means and
makes an IDE jump to the real definition. The pure-Dart core is untouched —
the DSL is a thin Flutter library over it, and the parser stays pure Dart
because it only ever reads lexemes.

`Text` collides with Flutter's `Text`, so the DSL cannot live in
`package:flutterware/scene.dart` — an app file mounting `SceneView` imports
material and would be shadowed. Two libraries: `scene.dart` stays the
app-facing half (`SceneView`, `MotionPlayer`, the host), and the file's
vocabulary gets its own, which is the only thing a `.scene.dart` needs.

The node constructors lose their positional name (Dart forbids mixing
optional positional with named), so `name` becomes an optional named
parameter with an empty default — and the *grammar* refuses `name:` as a
property, so the file can never carry one.

### Imports are the tool's, and there are more of them than one

Owner call 2026-09-03: a scene file **does** import, and the tool owns the
import list, prefixes included. It has to — an Ext names an app widget, and
that widget's type appears in the file.

Which kills the other magic string. Today `Ext(DrinkBadge)` is a key into a
`Map<String, SceneExternalBuilder>` the app hands to `SceneView`; the widget
and its mockup live on the far side of a string. Compiled, the file holds the
builder and the registry is deleted:

```dart
import 'package:flutterware/scene_dsl.dart';
import '../shop/drink_badge.dart' as app;

late final badge = Ext(
  args: (size: 56.0),
  build: (a) => app.DrinkBadge(app.drinks[1], size: a.size),
);
```

`args` is a record, so an ext argument is typed like everything else, and the
motion writes it as `badge.animate(args: (size: Track([…])))` — a record of
tracks. That retires what the motion grammar calls "the grammar's one
stringly boundary".

Consequences for the parser: prefixed identifiers become legal at value
positions, the import list is parsed and emitted rather than skipped, and an
import nobody references is a refusal like any other unreachable declaration.

## 2. Names are source, and the runtime does not need them

A node's identity is its field name, and Dart has no field-name reflection.
The answer is not to write the name back as a string argument — it is that
**at runtime the identity is the object**.

- `SceneNode.name` becomes assigned-by-parser, empty at runtime.
- `SceneView` keys its `GlobalKey`s and its measured rects by node identity,
  not by name. The editor, which parsed the source, maps object → name for
  the wire and for its own panels.
- `nodeNamed`, `uniqueName`, revive-by-name in `restore` — all editor
  machinery, and they stay in the editor.

The one that matters: **a motion binds to an object.** `scene.headline`
returns the real `TextNode`; `.animate(…)` holds it. `BoundMotion` stops
resolving a string against `nodeNamed`, and a typo stops being a runtime
refusal and becomes a compile error. `.animate()` is typed per node kind, so
`scene.headline.animate(gap: …)` will not compile either.

## 3. The repeater has to change shape

This is the redesign, and it is one I got wrong last round.
`Text(lines.item)` can never compile: a list has no `.item`. Even
`lines.first.item` — which does compile — loses the binding, because a
compiled expression cannot say *which* field it read.

The spelling that compiles **and** keeps the binding is a closure:

```dart
late final lineRow = FrameNode.repeating(
  over: lines,
  row: (line) => [
    TextNode(line.item, fontSize: 12),
    TextNode(line.qty, fontSize: 12, align: SceneTextAlign.right),
  ],
);
```

A static rather than a constructor, because it is generic in the item type
and a Dart constructor cannot be — and that generic is the whole point:
`T` is inferred from the list, so `line.item` is a record field the
compiler checks. The items are a `List<({String item, String qty})>`, and
the record type IS the field names.

There are two ways in and one way to draw. A compiled file supplies the
closure; a document that was READ — parsed, or decoded from JSON — supplies
only what a reader can record, which is which parameter the rows came from
and which property of which cell reads which field. `bindRepeats` turns that
back into the same closure, so nothing renders through a second path.

A number field is the one thing still awkward: a cell takes a `String`, so
`line.qty` has to be one. A numeric field would need `'${line.qty}'`, and
the grammar refuses interpolation.

Real Dart, fully typed, per-item nodes for free. What it costs: the cells are
no longer fields, so they have no identity — a cell cannot be selected or
animated individually. That is arguably correct (*which* cell of *which*
row?), and the editor edits the template by editing the closure body, which
the parser reads as an ordinary node list.

What it deletes: `applySceneItem`, the `#1` renaming in `expand`, the
`lines.field` ref grammar, and the item half of `paramRefs`.

It also breaks the flat "every node is a field, placed exactly once" law for
the first time. That law is what makes the format un-shreddable, so the
exception has to be written down rather than discovered.

## 4. Parameters stop being simulated

`applyArgs`, `paramRefs` and `_lists` exist to do by hand what a constructor
does. Compiled, `Invoice(number: 'INV-99')` sets the field, and
`late final invoiceNo = Text(number)` reads it. The runtime keeps none of it;
`paramRefs` survives in the editor as provenance — the thing that lets the
inspector say *this is bound to `number`* and lets Save drop a stale ref.

## Settled

- **A scene file imports**, the tool owns the list and the prefixes, and the
  externals registry dies with it (above).
- **The class extends `SceneDefinition`**, so `SceneView(Invoice())` is what
  an app writes.
- **A file that compiles but does not round-trip is refused**, with a line
  number, exactly as today. Two graders, and the parser is still allowed to
  be the stricter one.

## Phases

Each lands something that works. Ordered so the risky half comes early.

**P1 — the library, and one file that compiles.** *(done — 1c68b73f)*
Write the authoring surface; move the node constructors to all-named; make
`store_banner.scene.dart` (the simplest of the three targets) compile with
its exclusion removed. Prove it with a widget test that mounts
`SceneView(StoreBanner(headline: '…'))` and a check that
`flutter analyze` covers the file. Names still come from the parser; nothing
else moves yet.

**P2 — motions bind to objects.** *(done)*
`.animate(…)` per node kind, `AnimateGroup` holds a node, `BoundMotion` stops
looking anything up. The editor keeps the name for display and emit.

**P3 — the repeater becomes a closure.** *(done)*
Replace `repeat:`/`lines.item` with `repeat: … , row: (line) => […]`. Rewrite
the invoice on it. Delete what §3 lists.

**P4 — Ext becomes a typed builder.** *(merged into P6, owner call
2026-09-03 — see the two findings below. The prerequisite landed on its own:
the parser now owns the import list, which it was silently dropping.)*

**P5 — the runtime stops carrying the editor's machinery.** *(done —
79d19a12; keys-by-identity landed earlier, forced by a duplicate-GlobalKey
crash the moment a compiled scene mounted.)*

`_sweep` reporting objects turned out to be a bug fix rather than a tidy:
a compiled scene has no names, so the name-keyed report collided every node
onto the empty string and anything asking what a compiled scene measured got
one meaningless entry. `namedRects()` is the step back, taken at the edge
that has names — the guest, whose document came over the wire carrying them.

The read plane moved to `read_plane.dart`, a *part* of `model.dart` rather
than its own library: it works on the document's private state, and the
alternative is widening that for the editor's sake. Its STORAGE stays with
the nodes — `paramRefs`, the list table, a repeat's `source` — because one
`SceneDocument` serves both planes. Giving the compiled plane a thinner
document is a real change and a bigger one than this phase scoped; what is
true today is that a shipped app populates none of those fields and calls
none of that code, and every one of them now says so.

**P6 — the file holds its widgets, and the app registers scenes.** *(done,
except the export lane — see below.)*

Two things killed the P4 sketch, both measured rather than argued:

- **The args cannot be a typed record.** Animating one means producing a
  record with a field changed, and Dart cannot: no `copyWith`, no generic
  field update. `Map.of(args)` then overwrite is expressible, which is why
  the current shape works. So arg NAMES stay strings — the motion grammar
  already calls this its one stringly boundary — and `SceneArgs` reads them
  by kind so the file never writes a cast.
- **A closure cannot cross the wire.** The editor sends a scene as data; a
  builder is a closure. So the app registers its scene CLASSES
  (`SceneCanvasHost(scenes: [BannerScene.new])`) and the host learns the
  builders by instantiating each and walking it. One line per scene rather
  than one per widget, each compiler-checked.

And one thing the grammar gained: `build:` is an OPAQUE SPAN. The tool does
not read it, keeps it verbatim and writes it back, because it is the
author's code — the tool cannot author it and must not lose it. Everything
else in the file is still understood or refused.

**The export lane still speaks JSON, and that may be correct.** The pair
JSON is no longer an *app* path — an app writes `SceneView(Invoice().scene)`
and touches none of it. What remains is flutterware's own transport between
the editor and the tester lane, which is the same category as the
editor→guest wire that stays by design. Compiling the scene file in the
export lane would additionally catch a file that does not build, which is
worth something; it is an improvement to tooling rather than a correctness
fix for a consumer.

**P6 (old) — kill the JSON app path.**
A nested scene becomes a constructor call (`PromoBadge(title: …)`) instead of
a class-name lookup. The video/preview export instantiates the class through
a generated entrypoint — the previews plugin already generates one that
imports every entry, so there is precedent to copy rather than invent.
`sceneFileToJson` retires to the editor's own wire.

**P7 — every scene file compiles.** *(done; the exclusion list in
`examples/example/analysis_options.yaml` is empty and all seven demos are
ported.)* No separate test: CI's workspace `flutter analyze` already fails
if a `.scene.dart` stops compiling, which is the guard this asked for.

## What stays JSON, on purpose

The **editor → guest push** is not the runtime. It is a live-editing
transport that has to carry an unsaved document sixty times a second, and it
is a *picture* by design. It stays. Everything an app or an export touches
becomes Dart.

## Open

1. **What the DSL library is called.** It needs to be separate from
   `scene.dart` for the `Text` collision; the name is a one-line change and
   nobody has picked it.
2. **Whether a repeated row's cells can be reached at all.** The closure
   makes them anonymous by construction. If a cell ever has to be styled
   individually, the answer is a variant on the item, not a name.

## Measured, so nobody re-derives it

On Dart 3.14.0-95.2.beta, all in one file, running:

- a primary constructor `class Invoice({…}) extends SceneDefinition`
- `@override late final root = Frame(…)` over an abstract getter
- `typedef Frame = FrameNode;` used as a constructor
- a const list of records as a parameter default
- `late final` fields referencing each other in any order
- a constructor argument reaching a node's property

Primary constructors need **language version 3.13**, which the package
already floors at.
