# TUI Stage 4 — Widget layer

**Status:** Draft
**Date:** 2026-05-15
**Scope:** Add the stage 4 "widget layer" to the TUI framework — a transcription
of Flutter's framework layer: the immutable `Widget` tree, the mounted
`Element` tree, `StatelessWidget`/`StatefulWidget`/`State` with `setState`,
`BuildContext`, the element lifecycle and child reconciliation,
`InheritedWidget`, `RenderObjectWidget` as the bridge to the stage 3 render
tree, a `BuildOwner` rebuild scheduler, and a `runApp` entry point.

**Extends:** [`2026-05-15-tui-stage3-render-tree-design.md`](./2026-05-15-tui-stage3-render-tree-design.md)

---

## Context

Stages 1–3 delivered the bottom of the pipeline: the engine (`Terminal`,
`CellBuffer`, diff-to-ANSI, key parsing), the paint kit (`Painter`, geometry),
and the render tree (`RenderObject`/`RenderBox`, `BoxConstraints`,
`RenderFlex`/`RenderPadding`/`RenderText`/`RenderDecoratedBox`/
`RenderConstrainedBox`, `RenderTuiView`, `PipelineOwner`). The render tree is
constructed and mutated imperatively; there is no reactive layer.

Stage 4 adds that reactive layer — the part of Flutter that is genuinely worth
**transcribing** rather than reinventing. The roadmap's standing decision:
"reimplement the engine; transcribe the framework." The Widget/Element
machinery (rebuild scheduling, child reconciliation, the element lifecycle,
`InheritedWidget`) is rendering-backend agnostic and full of hard-won edge
cases. Stages 1–3 were written from scratch because Flutter's lower layers are
pixel/Skia-shaped; stage 4's upper layers are not, so they are copied closely.

After stage 4 the framework is complete enough to build real screens
declaratively. Stage 5 then replaces the flutterware CLI startup UX with one.

## Goals

1. **`Key`** — `Key`/`LocalKey`/`ValueKey`/`ObjectKey`/`UniqueKey`, used by
   `Widget.canUpdate` and child reconciliation.
2. **`Widget`** — the immutable configuration node: `StatelessWidget`,
   `StatefulWidget`/`State`, `ProxyWidget`, `ParentDataWidget`,
   `RenderObjectWidget`.
3. **`Element`** — the mounted instance; implements `BuildContext`. The full
   lifecycle: `mount` / `update` / `rebuild` / `unmount`,
   `activate`/`deactivate`, and child reconciliation via `updateChild`,
   `Widget.canUpdate`, and the keyed `updateChildren` list-diff.
4. **`State` + `setState`** — per-instance mutable state with the standard
   lifecycle (`initState`, `didChangeDependencies`, `didUpdateWidget`, `build`,
   `setState`, `deactivate`, `dispose`).
5. **`InheritedWidget`** — `O(1)` ancestor lookup via the per-element
   `_inheritedElements` map, `dependOnInheritedWidgetOfExactType`, and
   `updateShouldNotify`-driven dependent rebuilds.
6. **`RenderObjectWidget`** — the bridge: `Leaf`/`SingleChild`/`MultiChild`
   variants that create and update the stage 3 render objects and splice the
   render tree as the element tree changes.
7. **`BuildOwner`** — the rebuild scheduler: a depth-sorted dirty-element list,
   `scheduleBuildFor`, `buildScope`, and inactive-element finalization.
8. **`runApp` + `TuiBinding`** — an entry point that drives frames over the
   existing `Terminal` + `PipelineOwner` pipeline, plus a `TerminalApp`
   `InheritedWidget` exposing the key stream, terminal size, and an `exit()`
   hook to the tree.
9. **A starter set of concrete widgets** — `Text`, `Padding`, `ConstrainedBox`,
   `SizedBox`, `DecoratedBox`, `Flex`/`Row`/`Column`, `Expanded`/`Flexible`.
10. **A demo** (`widget_demo.dart`) rebuilding the stage 3 render-tree screen as
    `StatefulWidget`s driven by `setState`.

## Non-goals (for this round)

- **No `GlobalKey`.** Only the `LocalKey` family. `GlobalKey`'s global
  registry, cross-tree reparenting, and state retention are deferred — no
  stage 4/5 demo needs them.
- **No repaint boundaries / layer model.** `markNeedsPaint` stays whole-tree,
  as in stage 3. The engine already cell-diffs at the ANSI layer, so there is
  no flicker and output is already minimal; a compositing model is large work
  for no visible gain at TUI scale. Re-layout *is* localized (stage 3).
- **No focus or key-routing system.** The widget layer *exposes* the key stream
  via `TerminalApp`; `StatefulWidget`s subscribe themselves. A `Focus`/
  `FocusNode` system that routes events to a focused widget is its own later
  stage.
- **No `Ticker` / `SchedulerBinding` / animation.** Frame scheduling is a
  single microtask-coalesced flag. Animation controllers, tickers, and a real
  scheduler binding are a later stage.
- **No `ContainerRenderObjectMixin`.** Multi-child render objects keep the
  stage 3 plain `List`. `RenderFlex` gains `insert(child, {after})` and
  `move(child, {after})` so `MultiChildRenderObjectElement` can splice; the
  intrusive linked list is still deferred.
- **No new render objects.** `RenderAlign`, `RenderClipRect`, `RenderStack`,
  etc. are not added — the demo does not need them. Stage 4 widgets wrap only
  the stage 3 render objects.
- **No `GlobalKey`-dependent widgets**, no `Builder`/`LayoutBuilder`, no
  `MediaQuery` beyond what `TerminalApp` exposes.
- **No changes to the stage 1–3 engine, paint kit, or render objects** other
  than the two additive `RenderFlex` methods named above.
- **No fix for the non-tty `StdinException`** carried forward from stage 1 —
  an engine concern, out of scope here.

## Architecture

```
Widget (immutable config)        createElement()
   └── StatelessWidget / StatefulWidget        ─┐
   └── ProxyWidget                              │
   │     └── InheritedWidget                    │  configure
   │     └── ParentDataWidget                   │
   └── RenderObjectWidget                       │
         └── LeafRenderObjectWidget             │
         └── SingleChildRenderObjectWidget      │
         └── MultiChildRenderObjectWidget      ─┘
                         │
                         ▼
Element (mounted instance; implements BuildContext)
   └── ComponentElement
   │     └── StatelessElement
   │     └── StatefulElement   ── owns a State
   └── ProxyElement
   │     └── InheritedElement
   │     └── ParentDataElement
   └── RenderObjectElement
         └── LeafRenderObjectElement
         └── SingleChildRenderObjectElement
         └── MultiChildRenderObjectElement
                         │  creates / updates / splices
                         ▼
RenderObject tree (stage 3)  ── RenderTuiView at the root

BuildOwner   owns dirty elements; buildScope() rebuilds them depth-first
TuiBinding   owns BuildOwner + PipelineOwner + RenderTuiView; drives frames
runApp       Terminal-driving shell around TuiBinding
```

New code lives under a new subdirectory `app/lib/src/tui/widgets/`, organized
the same way as `render/`: one library composed of `part` files so the
tightly-coupled classes share library-private lifecycle state.

### The three trees

- **Widget** — immutable, cheap, rebuilt freely. Pure configuration.
- **Element** — the long-lived mounted instance. Holds the parent/child
  structure, the `State` (for `StatefulWidget`), the `BuildOwner`, dirty flags,
  and the inherited-widget lookup map. Implements `BuildContext`.
- **RenderObject** — stage 3, unchanged. `RenderObjectElement`s create, update,
  and splice it.

A frame turns a new Widget tree into Element-tree mutations (`updateChild`),
which turn into RenderObject mutations, which `PipelineOwner.flushLayout` and
`RenderTuiView.compositeFrame` turn into painted cells.

## `Key` — `key.dart`

```dart
abstract class Key {
  const factory Key(String value) = ValueKey<String>;
  const Key.empty();
}
abstract class LocalKey extends Key {
  const LocalKey() : super.empty();
}
class ValueKey<T> extends LocalKey {
  const ValueKey(this.value);
  final T value;
  // == / hashCode over (runtimeType, value)
}
class ObjectKey extends LocalKey {
  const ObjectKey(this.value);
  final Object? value;
  // == / hashCode over (runtimeType, identical(value))
}
class UniqueKey extends LocalKey {
  UniqueKey();   // identity equality only
}
```

`Widget.canUpdate(old, new)` is `old.runtimeType == new.runtimeType &&
old.key == new.key`. Keys let reconciliation match a moved child to its old
element instead of tearing it down.

## `Widget` — `widget.dart`

```dart
abstract class Widget {
  const Widget({this.key});
  final Key? key;
  Element createElement();
  static bool canUpdate(Widget oldWidget, Widget newWidget) =>
      oldWidget.runtimeType == newWidget.runtimeType &&
      oldWidget.key == newWidget.key;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});
  @override StatelessElement createElement();
  Widget build(BuildContext context);
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  @override StatefulElement createElement();
  State createState();
}

abstract class State<T extends StatefulWidget> {
  T get widget;                 // set by the element
  BuildContext get context;     // the StatefulElement
  bool get mounted;
  void initState() {}
  void didChangeDependencies() {}
  void didUpdateWidget(covariant T oldWidget) {}
  void setState(void Function() fn);
  void deactivate() {}
  void dispose() {}
  Widget build(BuildContext context);
}

abstract class ProxyWidget extends Widget {
  const ProxyWidget({super.key, required this.child});
  final Widget child;
}

abstract class ParentDataWidget<T extends ParentData> extends ProxyWidget {
  const ParentDataWidget({super.key, required super.child});
  void applyParentData(RenderObject renderObject);   // mutates child's parentData
  @override ParentDataElement<T> createElement();
}
```

`State.setState` runs `fn`, then marks the owning `StatefulElement` dirty via
`element.markNeedsBuild()`. Calling it on an unmounted state, or before
`initState` completes, is an assertion error — transcribed from Flutter.

## `Element` + `BuildContext` — `element.dart`

`Element` is the spine. It implements `BuildContext`, so a widget's `build`
method receives its own element.

```dart
abstract class Element implements BuildContext {
  Element(this._widget);
  Widget? _widget;
  Element? _parent;
  Object? _slot;                       // position within the parent
  int _depth = 0;
  BuildOwner? _owner;
  _ElementLifecycle _lifecycleState = _ElementLifecycle.initial;
  bool _dirty = true;
  bool _inDirtyList = false;
  Map<Type, InheritedElement>? _inheritedElements;
  Set<InheritedElement>? _dependencies;

  @override Widget get widget => _widget!;
  BuildOwner? get owner => _owner;
  bool get mounted => _widget != null;

  void mount(Element? parent, Object? newSlot);
  void update(covariant Widget newWidget);
  void rebuild();                      // if dirty && active: performRebuild()
  void performRebuild();               // subclass-specific
  void unmount();
  void activate();
  void deactivate();

  void markNeedsBuild();               // → owner.scheduleBuildFor(this)

  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot);
  Element inflateWidget(Widget newWidget, Object? newSlot);
  void deactivateChild(Element child);
  void forgetChild(Element child);
  void updateSlotForChild(Element child, Object? newSlot);

  void visitChildren(void Function(Element child) visitor) {}
  void attachRenderObject(Object? newSlot);
  void detachRenderObject();
  RenderObject? get renderObject;      // nearest descendant render object

  // BuildContext / InheritedWidget
  @override InheritedWidget dependOnInheritedWidgetOfExactType<T>();
  @override T? getInheritedWidgetOfExactType<T extends InheritedWidget>();
}
```

`_ElementLifecycle` is `initial → active → inactive → defunct`.

### `updateChild` — the reconciliation core

The four-case function every `performRebuild` leans on:

| old child | new widget | action |
|-----------|-----------|--------|
| `null`    | `null`    | nothing — return `null` |
| `null`    | widget    | `inflateWidget(newWidget, slot)` |
| element   | `null`    | `deactivateChild(child)`, return `null` |
| element   | widget    | `canUpdate`? `child.update(newWidget)` (+ slot fixup) : `deactivateChild` then `inflateWidget` |

`inflateWidget` first checks the new widget's key against an inactive element
with the same key (local de-dup within a parent only — no `GlobalKey`
registry); otherwise `newWidget.createElement()..mount(this, slot)`.

### `ComponentElement` / `StatelessElement` / `StatefulElement`

`ComponentElement` holds one `_child`; `performRebuild` calls `build()` then
`_child = updateChild(_child, built, slot)`.

- `StatelessElement.build()` → `widget.build(this)`.
- `StatefulElement` owns a `State`; `build()` → `state.build(this)`. `mount`
  calls `state.initState()` then `state.didChangeDependencies()`; `update`
  calls `state.didUpdateWidget(old)`; `unmount` calls `state.dispose()`.

### `ParentDataElement`

A `ProxyElement` for `ParentDataWidget`. After mount/update it walks down to
the nearest descendant `RenderObjectElement`(s) and calls
`widget.applyParentData(renderObject)`, then marks that render object's parent
needing layout. This is how `Expanded` writes a `flex` factor into a child's
`FlexParentData`.

## `BuildOwner` — `build_owner.dart`

```dart
class BuildOwner {
  final List<Element> _dirtyElements = [];
  bool _scheduledFlush = false;
  void Function()? onBuildScheduled;          // set by TuiBinding

  void scheduleBuildFor(Element element);     // adds to _dirtyElements
  void buildScope(Element context, [void Function()? callback]);
  void finalizeTree();                        // unmounts inactive elements
  final _InactiveElements _inactiveElements = _InactiveElements();
}
```

`scheduleBuildFor` enqueues a dirty element and, on the first dirty element of
a frame, invokes `onBuildScheduled` (the binding schedules a frame).
`buildScope` sorts `_dirtyElements` by `depth` (shallowest first), rebuilds
each still-dirty element, and tolerates elements dirtied *during* the pass by
re-sorting — transcribed from Flutter. `finalizeTree` unmounts everything
parked in `_inactiveElements` (elements deactivated this frame and not
reactivated).

## `InheritedWidget` — `inherited.dart`

```dart
abstract class ProxyElement extends ComponentElement { /* builds widget.child */ }

abstract class InheritedWidget extends ProxyWidget {
  const InheritedWidget({super.key, required super.child});
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
  @override InheritedElement createElement();
}

class InheritedElement extends ProxyElement {
  final Map<Element, Object?> _dependents = {};
  // on mount: copy parent._inheritedElements, add self keyed by widget type
  // on update: if updateShouldNotify, mark every dependent needing build
}
```

Each `Element` carries `_inheritedElements` — a `Map<Type, InheritedElement>`
inherited from its parent (copied, with the parent's own entry added if the
parent is an `InheritedElement`). `dependOnInheritedWidgetOfExactType<T>()`
does an `O(1)` map lookup, registers the calling element as a dependent, and
returns the widget. When an `InheritedWidget` updates and `updateShouldNotify`
returns true, every dependent is marked needing build.

## `RenderObjectWidget` — `render_object_widget.dart`

The bridge to stage 3.

```dart
abstract class RenderObjectWidget extends Widget {
  const RenderObjectWidget({super.key});
  @override RenderObjectElement createElement();
  RenderObject createRenderObject(BuildContext context);
  void updateRenderObject(BuildContext context, covariant RenderObject ro);
}

abstract class LeafRenderObjectWidget extends RenderObjectWidget { ... }
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  const SingleChildRenderObjectWidget({super.key, this.child});
  final Widget? child;
}
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  const MultiChildRenderObjectWidget({super.key, this.children = const []});
  final List<Widget> children;
}
```

`RenderObjectElement`:

- `mount` — `widget.createRenderObject(this)`, store it, then
  `attachRenderObject(slot)` which finds the nearest ancestor
  `RenderObjectElement` and calls its `insertRenderObjectChild(child, slot)`.
- `update` — `widget.updateRenderObject(this, renderObject)`.
- `unmount` — drops the render object from its parent.
- Subclasses implement `insertRenderObjectChild` / `moveRenderObjectChild` /
  `removeRenderObjectChild`:
  - `LeafRenderObjectElement` — no children.
  - `SingleChildRenderObjectElement` — sets `renderObject.child` (the stage 3
    `RenderBoxWithChild.child` setter). `performRebuild` runs
    `updateChild(_child, widget.child, null)` — slot is unused.
  - `MultiChildRenderObjectElement` — keeps a `List<Element>`;
    `performRebuild` runs the keyed `updateChildren` list-diff. The slot for
    each child is its **previous-sibling `Element`** (or `null` for the
    first); `insertRenderObjectChild` translates that to
    `RenderFlex.insert(childRO, after: prevSiblingRO)`.

### `updateChildren` — the keyed list-diff

Transcribed faithfully from Flutter's `RenderObjectElement.updateChildren`: a
forward scan over the matching prefix, a backward scan over the matching
suffix, a key-map of the old middle so moved/keyed children are matched rather
than rebuilt, then inflate/update/deactivate of the middle. This is the
single most edge-case-dense piece of the framework and the strongest reason to
transcribe rather than reinvent. Slots are fixed up so each surviving child's
slot is its new previous sibling.

## Concrete widgets — `basic.dart`

| Widget | Kind | Render object | Notes |
|--------|------|---------------|-------|
| `Text` | `LeafRenderObjectWidget` | `RenderText` | text, `fg`, `bg`, `style`, `hAlign`, `vAlign`, `wrap` |
| `Padding` | `SingleChildRenderObjectWidget` | `RenderPadding` | `EdgeInsets` |
| `ConstrainedBox` | `SingleChildRenderObjectWidget` | `RenderConstrainedBox` | `BoxConstraints` |
| `SizedBox` | `StatelessWidget` | — | thin wrapper: `ConstrainedBox` with tight constraints |
| `DecoratedBox` | `SingleChildRenderObjectWidget` | `RenderDecoratedBox` | `BoxDecoration` |
| `Flex` | `MultiChildRenderObjectWidget` | `RenderFlex` | `direction`, alignments, `mainAxisSize` |
| `Row` / `Column` | `Flex` subclasses | `RenderFlex` | fixed `direction` |
| `Expanded` / `Flexible` | `ParentDataWidget<FlexParentData>` | — | write `flex`/`fit` into `FlexParentData`; `Expanded` is `Flexible` with `FlexFit.tight` |

`updateRenderObject` copies each widget field onto the render object via the
stage 3 setters, so a rebuilt `Text('hi')` calls `renderText.text = 'hi'`,
which already marks needs-layout/paint. `BoxDecoration`/`BoxBorder`/`EdgeInsets`
are the stage 3 types, re-exported.

## `TuiBinding`, `runApp`, `TerminalApp` — `binding.dart`

```dart
class TuiBinding {
  TuiBinding();
  final BuildOwner buildOwner = BuildOwner();
  final PipelineOwner pipelineOwner = PipelineOwner();
  late final RenderTuiView renderView;
  RootElement? _rootElement;

  void attachRootWidget(Widget rootWidget);   // builds RootElement, first frame
  void drawFrame(Painter painter);            // buildScope → flushLayout → paint
  void handleResize(CellSize size);
  bool get needsFrame;
}
```

`RootWidget` is a `RenderObjectWidget` whose render object **is** the
`RenderTuiView` (via a small adapter — it does not create a new one, it adopts
the binding's view as `child`). `RootElement` is the element-tree root;
`attachRootWidget` mounts it, registers `buildOwner.onBuildScheduled`, and runs
the first `drawFrame`.

`drawFrame(painter)` = `buildOwner.buildScope(rootElement)` →
`buildOwner.finalizeTree()` → `renderView.compositeFrame(painter)` (which
itself flushes layout). It is pure given a `Painter`, so it is **headlessly
testable** against a `CellBuffer`.

`runApp` is the Terminal-driving shell:

```dart
Future<void> runApp(Widget app) async {
  await Terminal.run((terminal) async {
    var binding = TuiBinding();
    var exit = Completer<void>();
    // wrap the app so the tree can reach key events / size / exit()
    binding.attachRootWidget(TerminalApp(
      keys: terminal.keys,
      size: /* current */,
      exit: () => exit.complete(),
      child: app,
    ));
    void frame() => terminal.draw((b) {
      binding.handleResize(CellSize(b.rows, b.cols));
      binding.drawFrame(Painter(b));
    });
    binding.onFrameNeeded = frame;          // microtask-coalesced
    frame();
    var sub = terminal.resizes.listen((_) => frame());
    try { await exit.future; } finally { await sub.cancel(); }
  });
}
```

`TerminalApp` is an `InheritedWidget` exposing `Stream<KeyEvent> keys`,
`CellSize size`, and `void exit()`. `TerminalApp.of(context)` registers a
dependency, so a widget that reads `size` rebuilds on resize.
`updateShouldNotify` is true when `size` changes (the `keys` stream and `exit`
closure are stable).

### Frame scheduling

A frame is needed when `buildOwner` has dirty elements or `pipelineOwner`
needs layout/paint. `BuildOwner.onBuildScheduled` fires on the first dirty
element of a frame; the binding sets a `_frameScheduled` flag and
`scheduleMicrotask`s one frame, which clears the flag. Multiple `setState`s in
one turn coalesce into one frame. No `Ticker`, no periodic timer — the tree is
event-driven (input, resize, `setState`).

## Files touched

**Create — `app/lib/src/tui/widgets/`:**

- `widgets.dart` — library declaration, imports, `part` directives
- `key.dart` — `Key`, `LocalKey`, `ValueKey`, `ObjectKey`, `UniqueKey`
- `widget.dart` — `Widget`, `StatelessWidget`, `StatefulWidget`, `State`,
  `ProxyWidget`, `ParentDataWidget`
- `element.dart` — `Element`, `BuildContext`, `_ElementLifecycle`,
  `ComponentElement`, `StatelessElement`, `StatefulElement`,
  `ParentDataElement`, `_InactiveElements`
- `build_owner.dart` — `BuildOwner`
- `inherited.dart` — `ProxyElement`, `InheritedWidget`, `InheritedElement`
- `render_object_widget.dart` — `RenderObjectWidget`, `LeafRenderObjectWidget`,
  `SingleChildRenderObjectWidget`, `MultiChildRenderObjectWidget` and their
  elements, the keyed `updateChildren`
- `basic.dart` — `Text`, `Padding`, `ConstrainedBox`, `SizedBox`,
  `DecoratedBox`, `Flex`, `Row`, `Column`, `Expanded`, `Flexible`
- `binding.dart` — `TuiBinding`, `RootWidget`, `RootElement`, `TerminalApp`,
  `runApp`

**Create — demo & tests:**

- `app/examples/tui/widget_demo.dart`
- `app/test/tui/widgets/key_test.dart`
- `app/test/tui/widgets/element_lifecycle_test.dart` — mount/update/unmount,
  `State` lifecycle ordering, activate/deactivate
- `app/test/tui/widgets/reconciliation_test.dart` — `updateChild` four cases,
  keyed `updateChildren` reorder/insert/remove
- `app/test/tui/widgets/build_owner_test.dart` — depth ordering,
  `setState` → rebuild, element dirtied during a build pass
- `app/test/tui/widgets/inherited_widget_test.dart` — dependency registration,
  `updateShouldNotify`, dependent rebuilds, `O(1)` lookup map
- `app/test/tui/widgets/render_object_widget_test.dart` —
  create/update render objects, render-tree splicing
- `app/test/tui/widgets/parent_data_test.dart` — `Expanded`/`Flexible` write
  `flex`/`fit` into `FlexParentData`
- `app/test/tui/widgets/basic_widgets_test.dart` — each widget builds the right
  render object with the right fields
- `app/test/tui/widgets/binding_test.dart` — `TuiBinding.drawFrame` runs a full
  build → layout → paint into a `CellBuffer`; `setState` triggers a new frame

**Modify:**

- `app/lib/src/tui/render/render_flex.dart` — add `insert(RenderBox child,
  {RenderBox? after})` and `move(RenderBox child, {RenderBox? after})`
- `app/lib/src/tui/tui.dart` — export the public widget surface
- `app/lib/src/tui/README.md` — note stage 4 is done; update the file table and
  limitations
- `docs/superpowers/tui-roadmap.md` — mark stage 4 done, link this spec

## Testing strategy

The whole widget layer is testable without a tty, the same way stage 3 was.
The key harness: a `TuiBinding` (or a bare `BuildOwner` + `RootElement` +
`RenderTuiView`) driven against a `CellBuffer` wrapped in a `Painter`. Build a
widget tree, call `drawFrame`, assert on render-object sizes/offsets and on
cells read back from the buffer.

Key cases:

- **`Key`** — `ValueKey`/`ObjectKey` equality and hashing; `UniqueKey`
  identity; `Widget.canUpdate` true/false matrix.
- **Element lifecycle** — `mount` sets parent/depth/owner; `State.initState`
  runs before first `build`; `didChangeDependencies` after; `update` calls
  `didUpdateWidget`; `unmount` calls `dispose`; `mounted` flips correctly.
- **`updateChild`** — all four cases; `canUpdate` mismatch tears down and
  re-inflates; a matching widget updates the child element in place.
- **`updateChildren`** — keyed reorder reuses elements (asserted by element
  identity); insertion in the middle; removal; prefix/suffix fast paths.
- **`BuildOwner`** — dirty elements rebuild shallowest-first; `setState`
  enqueues exactly its element; an element dirtied during `buildScope` is still
  built that pass; a clean element is skipped.
- **`InheritedWidget`** — `dependOnInheritedWidgetOfExactType` returns the
  nearest ancestor and registers a dependency; `updateShouldNotify == false`
  skips dependent rebuilds; `== true` rebuilds exactly the dependents;
  non-dependent descendants are untouched.
- **`RenderObjectWidget`** — `createRenderObject` builds the right type;
  `updateRenderObject` pushes changed fields; the render tree is spliced so a
  `Column` of `Text`s yields a `RenderFlex` with the right `RenderText`
  children in order.
- **`ParentDataWidget`** — `Expanded(flex: 2)` sets `FlexParentData.flex == 2`
  and `fit == tight` on the wrapped child's render object; changing the flex
  on rebuild updates it.
- **Concrete widgets** — `Text`/`Padding`/`ConstrainedBox`/`SizedBox`/
  `DecoratedBox`/`Row`/`Column` each produce the expected render object and
  propagate field changes on rebuild.
- **`TuiBinding`** — a `StatefulWidget` whose `State` calls `setState` produces
  an updated frame; `drawFrame` paints expected cells into a `CellBuffer`;
  whole pipeline (build → layout → paint) runs end to end headlessly.

The only thing requiring a real terminal is the demo, covered by manual smoke.

## Success criteria

1. All existing tests still pass; `flutter analyze` is clean.
2. Every new `app/test/tui/widgets/` suite passes.
3. `dart tool/prepare_submit.dart` produces no diff.
4. `widget_demo.dart` runs in a real terminal:
   - The stage 3 multi-panel screen renders, now built from widgets: a
     fixed-height header, a `Row` of two `Expanded` panels (left `flex: 1`,
     right `flex: 2`), a footer.
   - The left panel is a `StatefulWidget`; pressing a key calls `setState` and
     only the left subtree rebuilds — the right panel's element and render
     object are untouched.
   - The left panel reads the key stream through the `TerminalApp`
     `InheritedWidget` (no out-of-band wiring).
   - Resizing the terminal re-lays out the whole screen.
   - Pressing `q` calls `TerminalApp.of(context).exit()`; `runApp` returns and
     the terminal is restored cleanly.

## Open questions deferred

- **`GlobalKey`** — global registry, reparenting, state retention. Add when a
  widget genuinely needs to move subtrees or reach state across the tree.
- **Repaint boundaries / layer model** — still deferred; needs a compositing
  tree. The ANSI cell-diff makes it low-value at TUI scale.
- **Focus / key routing** — a `Focus`/`FocusNode` system that routes key
  events to a focused widget. Its own stage; stage 4 only exposes the raw
  stream.
- **`Ticker` / `SchedulerBinding` / animation** — real frame scheduling with
  animation controllers. Stage 4's microtask-coalesced flag is enough for an
  event-driven UI.
- **`ContainerRenderObjectMixin`** — the intrusive child linked list. The plain
  `List` plus `insert(after:)`/`move(after:)` suffices at TUI scale.
- **More render objects / widgets** — `Align`, `Stack`, `ClipRect`,
  `LayoutBuilder`, `Builder`, `MediaQuery` — add as stage 5 screens demand
  them.
- **Non-tty `StdinException`** — an engine-level graceful-failure fix carried
  from stage 1; unrelated to the widget layer.
