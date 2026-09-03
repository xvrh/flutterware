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

**The app declares, once, beside its widgets:**

```dart
final externals = <ExternalWidgetBase>[
  ExternalWidget<DrinkBadgeArgs>(
    'DrinkBadge',
    args: [const Arg<double>('size', 56)],
    build: (a) => DrinkBadge(drinks[1], size: a.size),
  ),
];
```

**The tool generates** one class per declaration — the constructor, the
fields, `merge` and `toMap`. This is where every string ends up, derived
from the declaration and written by nobody.

**A scene file then has no strings and no closures at all:**

```dart
late final badge = ExternalNode.of(
  'DrinkBadge',
  args: DrinkBadgeArgs(size: 140),
);
```

## What it changes about today

- **The `build:` opaque span goes away** for Ext. The scene file stops
  carrying app code, so the tool understands or refuses every construct in
  it again — the exception this session introduced is retired rather than
  entrenched.
- **`scenes: [BannerScene.new]` stops being how externals are found.** The
  guest holds the declarations, which it compiles; the wire carries `entry`
  plus the args map, and the declaration turns that back into the typed
  object. (Nested scenes still need their own answer — see below.)
- **The inspector gets real types.** `size` is a double because the
  declaration says so, not because somebody wrote a number once.
- **A motion targeting a parameter that does not exist is refused.**

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
