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

**Declarations of different widgets sit in one list**, through a
type-forgotten supertype the editor holds them by:

```dart
abstract class ExternalWidgetBase {
  String get entry;
  List<Arg<Object>> get args;
  Object buildFrom(Object args);
}

class ExternalWidget<A extends SceneExtArgs<A>> implements ExternalWidgetBase
```

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

### The app declares, once

```dart
final externals = <ExternalWidgetBase>[
  ExternalWidget<DrinkBadgeArgs>(
    'DrinkBadge',
    args: [const Arg<double>('size', 56)],
    build: (a) => DrinkBadge(drinks[1], size: a.size),
    read: (a) => const DrinkBadgeArgs().merge(a),
  ),
];
```

`build` is the one closure in the system and it belongs here, not in every
scene that places the widget: only the app knows `drinks[1]`.

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

## Nested scenes fall out for free

A nested scene's parameters are declared in its own file, which the tool
already parses. So `PromoBadgeArgs` can be generated from
`class PromoBadge({final String label = 'New'})` with no declaration file at
all — the schema was always there. The same generated shape serves both, and
`SceneRefNode`'s builder span retires with the Ext one.

## Open

- **Where generation runs**: a build step, or the tool on demand when the
  declaration changes. The previews catalog already generates an entrypoint,
  so there is precedent either way.
- **Whether `entry` survives.** The args type identifies the widget, so the
  label may be redundant — but something has to cross the wire, and a
  generated class name is as good a string as any.
- **What an undeclared arg does.** Refusing it is the point; the question is
  whether the scene file can even express one once `args:` is a typed
  constructor call. Probably not, which is the best kind of answer.
