# External widget args: what is possible without resolving

Owner steer 2026-09-03: **do not resolve** the app package — too costly, too
early. Declare instead. The app says what a widget takes, once, and the tool
generates the typed args class scene files use.

This is what was measured against that, in plain Dart, before proposing
anything. Everything below compiles and runs.

## First, the thing that started it

`args: {'size': 140}` on an Ext node means *build `DrinkBadge` with
`size: 140`*. `size` is a real constructor parameter:

```dart
const DrinkBadge(this.drink, {super.key, this.size = 56});
```

**`progress` is not.** It appears in exactly two places — the motion in
`banner.scene.dart` that animates it, and the fixture that does the same.
`DrinkBadge` has no such parameter, nothing reads it, and the renderer folds
it into `renderedArgs` every frame for a builder that throws it away. A
fixture invented it to exercise "you can animate an ext arg", and nothing
ever noticed it was addressing a hole.

That is the cost of the tool not knowing what a widget takes, and it is the
thing this design is for. **A declaration would have refused it.**

## The shape, measured

Four things had to be true. All four are.

**A generated args class keeps its type through an animation.** F-bounded, so
`merge` returns the same type:

```dart
abstract class SceneExtArgs<A extends SceneExtArgs<A>> {
  A merge(SceneArgs fx);
  Map<String, Object?> toMap();
}
```

**Declarations of different widgets sit in one list** — trivially, once the
declaration stopped being generic (see the cycle, below).

**The schema is readable at runtime** — `Arg<T>` carries `Type get type => T`,
so the editor can be told `size` is a `double` without compiling anything.

**And the round trip works**: authored → drawn, animated → drawn, both typed
the whole way.

```
DrinkBadge(size: 140.0)
DrinkBadge(size: 88.0)
DrinkBadge: size double
Spinner: label String
```

## What each side would write

Owner steer, second pass: **no strings in the scene file at all.** They are
gathered in the declaration, which is what stands in for the analyzer, and
that is the end of them.

### The app declares, once — and never names what is generated

The first draft of this had a cycle in it: the declaration was typed by
`DrinkBadgeArgs`, which the generator produces *from* the declaration. The
file would not compile until it had been generated from, which is the
ordinary codegen bootstrap and still a bad property for a file a person
writes by hand.

It goes away by keeping the declaration **untyped**. It is the one stringly
place by decision, so `build` may read its args by name like everything else
here:

```dart
final externals = [
  ExternalWidget(
    'DrinkBadge',
    args: [const Arg<double>('size', 56)],
    build: (a) => DrinkBadge(drinks[1], size: a.number('size') ?? 56),
  ),
];
```

Written first, compiles alone, mentions nothing generated. And it made the
framework smaller: `ExternalWidget` needs no type parameter, so the
F-bounded supertype and the type-forgotten `ExternalWidgetBase` both go —
they existed only to carry a generic the declaration no longer has.

The price is that `'size'` appears twice in this file: once as the schema,
once in the build that reads it. Both mentions sit two lines apart, in the
file whose job is to be the stringly one.

### The tool generates two classes per declaration

```dart
class DrinkBadgeArgs extends SceneExtArgs<DrinkBadgeArgs> {
  const DrinkBadgeArgs({this.size = 56});
  final double size;
  @override String get entry => 'DrinkBadge';
  @override DrinkBadgeArgs merge(SceneArgs fx) =>
      DrinkBadgeArgs(size: fx.number('size') ?? size);
  @override Map<String, Object?> toMap() => {'size': size};
}

class DrinkBadgeTracks extends SceneExtTracks {
  const DrinkBadgeTracks({this.size});
  final MotionTrack? size;
  @override Map<String, MotionTrack> toMap() =>
      {if (size != null) 'size': size!};
}
```

Every string in the system that is not in the declaration is in here, and
nobody types it.

### A scene file has none

```dart
late final badge = ExternalNode(
  const DrinkBadgeArgs(size: 140),
  x: 560,
  y: 290,
);
```

The widget's identity IS the args type. No entry label, no `build:`, no
`args:` map, no closure — so `ExternalNode` needs no generic and the sealed
model does not move.

### And a motion has none either

```dart
late final badgePop = scene.badge.animate(
  args: const DrinkBadgeTracks(size: MotionTrack([…])),
);
```

Which is the part that decides it. `args: {'progress': …}` was the last
stringly corner of the motion grammar, and a tracks class closes it: a slot
per animatable arg, typed, generated from the same declaration. **There is
no way to write `progress` any more.**

### Nested scenes need no declaration at all

A scene's parameters are declared in its own file, which the tool already
parses. So `PromoBadgeArgs` generates from
`class PromoBadge({final String label = 'New'})` with nothing else written,
and the generated class can build it too:

```dart
SceneDefinition build() => PromoBadge(label: label);
```

giving `SceneRefNode(const PromoBadgeArgs(label: 'Now open'))` — same shape,
zero strings, and no declaration list.

### Measured

The whole path runs, in plain Dart: authored, animated at t, read back from
a wire map, and the schema listed for an inspector.

```
DrinkBadge(size: 140.0)   // authored
DrinkBadge(size: 90.0)    // the motion at t=0.5, typed throughout
DrinkBadge(size: 99.0)    // built from what the wire carried
DrinkBadge: size double   // what the inspector is told
```

## The rest of it, end to end

Run as one program, with every part marked for the file it would live in.
Output at the bottom is real.

### The generated class knows its own declaration

This is the piece that makes everything else fall out. `build()` lives on
the generated args:

```dart
@override Object build() => _declared(entry).build(SceneArgs(toMap()));
```

So a node can draw itself, and **a shipped app passes nothing**:

```dart
SceneView(BannerScene().scene)
```

`SceneView.externals` is deleted rather than replaced. The declaration list
is reached from the generated file, which the app already compiles.

### Rendering, including a motion

```dart
Object render(double t) => args
    .merge(SceneArgs({for (var e in fx.entries) e.key: e.value.at(t)}))
    .build();
```

Typed the whole way: `merge` returns `DrinkBadgeArgs`, and `build` reads
`a.size`.

### The wire, and the guest

The wire carries a name, a label and a map — no closure and no generated
type, so nothing about it is new:

```
{name: badge, entry: DrinkBadge, args: {size: 140.0}}
```

The guest turns it back through a generated lookup:

```dart
final sceneExtArgsByEntry = <String, SceneExtArgs Function(SceneArgs)>{
  'DrinkBadge': DrinkBadgeArgs.read,
};
```

### The inspector

Straight off the declaration — name, type, and the default a field falls
back to. This is the part that replaces resolving.

### Emit

The tool writes the constructor call back, skipping anything still equal to
the declared default:

```dart
ExternalNode(const DrinkBadgeArgs(size: 140))
```

### What the parser must learn

Reading `DrinkBadgeArgs(size: 140)` needs three things, all cheap: the class
name gives the entry (`…Args` stripped), the named arguments give the
values, and the declaration gives their types — so an argument the widget
does not declare is refused with a line number.

**This puts declarations before scene files in the load order.** A scene
parsed with none available can still be read structurally, but nothing about
its args can be checked; the editor should say so rather than pretend.

### And the same thing twice over

A motion targeting an undeclared arg is stopped in both graders, which is
the property worth having:

```dart
scene.badge.animate(args: DrinkBadgeTracks(progress: …))  // does not compile
```

and the parser refuses it too, because `DrinkBadgeTracks` has no such field.

### Measured

```
— the shipped app, nothing passed to it
  t=0.0  DrinkBadge(flat white, size: 140.0)
  t=0.5  DrinkBadge(flat white, size: 90.0)
— the editor: what the inspector is told
  size: double (default 56.0)
— the wire, and the guest on the far side of it
  carries {name: badge, entry: DrinkBadge, args: {size: 140.0}}
  guest draws DrinkBadge(flat white, size: 140.0)
— emit: what the tool writes back into the scene file
  ExternalNode(const DrinkBadgeArgs(size: 140.0))
```

## What it changes about today

It **retires** more than it adds:

- **The `build:` opaque span goes away** from scene files. They stop carrying
  app code, so every construct in them is understood or refused again — the
  exception this session introduced is undone rather than entrenched. The one
  remaining closure moves to the declaration, where it is the app's own code
  in the app's own file.
- **`scenes: [BannerScene.new]` stops being how externals are found.** The
  guest compiles the declarations; the wire carries the entry and the args
  map, and `read` turns that back into the typed object. The
  closure-cannot-cross-the-wire problem does not arise.
- **`SceneArgs` leaves the scene file.** It becomes an internal type the
  generated `merge`/`read` use, never something an author writes.
- **The inspector gets real types**, because `Arg<double>` said so.
- **A motion cannot target a parameter that does not exist.** Not refused —
  unwritable.

## What the tool has to gain

1. **Parse the declaration file.** A new grammar, small, in the same
   discipline as the scene one: read `entry`, the arg names, their types and
   fallbacks; keep `build:` as this file's opaque span, since it is the
   author's code and belongs here rather than in every scene that places the
   widget.
2. **Generate the args classes**, into one file per package.
3. **Read `args: DrinkBadgeArgs(size: 140)`** in a scene — a constructor call
   with named arguments whose types the declaration already told it.
4. **Generate `read`** alongside `merge`, so the guest can turn the wire's
   map back into the typed object.

Nothing the tool generates is ever named by a file a person writes, which is
what keeps the bootstrap honest: the declaration and the app compile before
the generator has ever run, and only scene and motion files depend on its
output.

## Nested scenes fall out for free

A nested scene's parameters are declared in its own file, which the tool
already parses. So `PromoBadgeArgs` can be generated from
`class PromoBadge({final String label = 'New'})` with no declaration file at
all — the schema was always there. The same generated shape serves both, and
`SceneRefNode`'s builder span retires with the Ext one.

## Built 2026-09-04

All of the above, with three answers the design did not have.

**Where generation runs: on the scene scan.** `SceneCore`'s scan calls
`generateSceneArgsIn(root)` and *then* discovers scenes, which is the load
order the grammar needs — a scan that listed scenes without regenerating
would hand the panel files naming classes that no longer exist. It writes
only when the output differs, so the common scan writes nothing.

**The wire kept its shape, and `SceneView.externals` really did go.** A
compiled node reaches the declaration through its own generated class. A
node that arrived as data — the guest's wire, a saved pair — is given its
builder by `bindExternals(doc, declarations)`, and the app hands its
declaration list to `SceneCanvasHost(externals: sceneExternals)` instead of
the old `scenes: [BannerScene.new]`. One list, no instantiate-and-walk.

**There are two declaration types, on purpose.** `ExternalWidget` is the
app's, with the closure; `ExternalWidgetDecl` is the tool's, read from the
file as text, where a default arrives as source rather than as a value.
`describeExternals` bridges them for anything that already holds the real
objects (the catalog demo, a test).

Measured in the running studio: the file opens, the three external widgets
draw through their declarations, the inspector shows `size 40.00` for a
scene that overrode it and `label "Order now"` for one that never set it,
and typing in that field wrote `const OrderButtonArgs(label: 'Order now')`
back into the scene file, which still analyzes.

### Not carried over

**Emit does not skip declared defaults.** It writes every argument the node
carries, which round-trips exactly and needs no declarations at emit time.
The visible consequence: an argument left at its default becomes explicit
in the file the first time somebody touches it in the inspector.

## Open

- **What happens when a declaration changes.** Removing an arg makes every
  scene that set it invalid; renaming one silently drops its value unless
  the tool notices. Regeneration is the easy half — the migration is not,
  and it is the same question the scene grammar answers with refusals.
- **A package with no declaration file gets no second grader.** The parser
  checks an argument only against an entry the declarations name, so a
  project that has not written one parses exactly as before. The editor
  should say so rather than let it read as checked.
