# TUI Stage 4 — Widget Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reactive widget layer for the TUI framework — a transcription of Flutter's `framework.dart` (Widget/Element/State, `setState`, the element lifecycle, keyed reconciliation, `InheritedWidget`, `RenderObjectWidget`, `BuildOwner`) plus a `runApp` entry point that drives frames over the Stage 3 render tree.

**Architecture:** A new `part`-file library at `app/lib/src/tui/widgets/widgets.dart`, mirroring how `render/render.dart` is organized. The immutable `Widget` tree is rebuilt freely; the long-lived `Element` tree reconciles widget-to-widget changes and splices the Stage 3 `RenderObject` tree; a `BuildOwner` schedules depth-ordered rebuilds; a `TuiBinding` + `runApp` drive frames over the existing `Terminal` + `PipelineOwner`.

**Tech Stack:** Pure Dart (`dart:io` + `dart:async`), zero pub dependencies. Tests run with `flutter test` from the `app/` directory. The full design is in [`docs/superpowers/specs/2026-05-15-tui-stage4-widget-layer-design.md`](../specs/2026-05-15-tui-stage4-widget-layer-design.md) — read it before starting; it is the source of truth for every API surface below.

**Conventions** (from `CLAUDE.md` and `app/lib/src/tui/README.md`): prefer `var` for locals, no `final` on parameters, single quotes, wrap fire-and-forget futures in `unawaited(...)`, do not litter `const`. The render layer this drives is in `app/lib/src/tui/render/`; re-read `render_object.dart`, `render_box.dart`, `render_view.dart`, and `render_flex.dart` before Tasks 1 and 7.

**Reference:** This is a *transcription*. Where a class mirrors Flutter, consult `package:flutter`'s `framework.dart` (in the Flutter SDK at `packages/flutter/lib/src/widgets/framework.dart`) for the exact algorithm — especially `Element.updateChild`, `RenderObjectElement.updateChildren`, and the lifecycle. Substitute: cells for pixels, the Stage 3 render types for Flutter's, `KeyEvent` for pointer events. Drop anything in the non-goals list (GlobalKey, layers, focus, tickers).

---

## File Structure

All paths relative to repo root.

**Create — `app/lib/src/tui/widgets/`:**
- `widgets.dart` — `library;` + imports + `part` directives (no other code)
- `key.dart` — `Key`, `LocalKey`, `ValueKey`, `ObjectKey`, `UniqueKey`
- `widget.dart` — `Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `ProxyWidget`, `ParentDataWidget`
- `element.dart` — `BuildContext`, `_ElementLifecycle`, `Element`, `ComponentElement`, `StatelessElement`, `StatefulElement`, `ParentDataElement`, `_InactiveElements`
- `build_owner.dart` — `BuildOwner`
- `inherited.dart` — `ProxyElement`, `InheritedWidget`, `InheritedElement`
- `render_object_widget.dart` — `RenderObjectWidget` + `Leaf`/`SingleChild`/`MultiChild` widgets & elements, `updateChildren`
- `basic.dart` — `Text`, `Padding`, `ConstrainedBox`, `SizedBox`, `DecoratedBox`, `Flex`, `Row`, `Column`, `Expanded`, `Flexible`
- `binding.dart` — `TuiBinding`, `RootWidget`, `RootElement`, `TerminalApp`, `runApp`

**Create — demo & tests:**
- `app/examples/tui/widget_demo.dart`
- `app/test/tui/widgets/{key,element_lifecycle,reconciliation,build_owner,inherited_widget,render_object_widget,parent_data,basic_widgets,binding}_test.dart`

**Modify:**
- `app/lib/src/tui/render/render_flex.dart` — add `insert`/`move`
- `app/lib/src/tui/tui.dart` — export the widget surface
- `app/lib/src/tui/README.md`, `docs/superpowers/tui-roadmap.md` — mark Stage 4 done

**Library wiring:** `widgets.dart` is one library. Every other `widgets/*.dart` file starts with `part of 'widgets.dart';`. `widgets.dart` itself:

```dart
/// The TUI widget layer (stage 4): a transcription of Flutter's framework
/// layer. One library composed of [part] files so the tightly-coupled
/// Widget/Element/State classes share library-private lifecycle state.
library;

import 'dart:async';

import 'cell.dart';
import 'geometry.dart';
import 'painter.dart';
import 'terminal.dart';
import 'input.dart';
import 'render/render.dart';

part 'key.dart';
part 'widget.dart';
part 'element.dart';
part 'build_owner.dart';
part 'inherited.dart';
part 'render_object_widget.dart';
part 'basic.dart';
part 'binding.dart';
```

Note: `widgets.dart` lives in `app/lib/src/tui/`, so imports of `cell.dart` etc. are sibling-relative; `render/render.dart` is the Stage 3 library and exposes all `Render*`/`BoxConstraints`/`EdgeInsets`/`ParentData` types.

---

## Task 1: `RenderFlex` insert/move amendment

The only Stage 3 render change. `MultiChildRenderObjectElement` needs to splice children by previous-sibling.

**Files:**
- Modify: `app/lib/src/tui/render/render_flex.dart`
- Test: `app/test/tui/render/render_flex_test.dart` (existing — append)

- [ ] **Step 1: Write failing tests** — append to `app/test/tui/render/render_flex_test.dart`:

```dart
group('insert / move', () {
  test('insert after null places child first', () {
    var a = RenderText('a');
    var b = RenderText('b');
    var flex = RenderFlex(direction: Axis.vertical, children: [a]);
    flex.insert(b, after: null);
    expect(flex.children, [b, a]);
  });

  test('insert after a child places it immediately following', () {
    var a = RenderText('a');
    var b = RenderText('b');
    var c = RenderText('c');
    var flex = RenderFlex(direction: Axis.vertical, children: [a, b]);
    flex.insert(c, after: a);
    expect(flex.children, [a, c, b]);
  });

  test('move relocates an existing child without re-adopting', () {
    var a = RenderText('a');
    var b = RenderText('b');
    var c = RenderText('c');
    var flex = RenderFlex(direction: Axis.vertical, children: [a, b, c]);
    flex.move(c, after: null);
    expect(flex.children, [c, a, b]);
    expect(c.parent, flex);
  });
});
```

- [ ] **Step 2: Run, verify failure** — `cd app && flutter test test/tui/render/render_flex_test.dart` → FAIL (`insert`/`move` not defined).

- [ ] **Step 3: Implement** — add to `RenderFlex` in `render_flex.dart`, after `clearChildren`:

```dart
/// Inserts [child], placing it immediately after [after] (or first when
/// [after] is null). Adopts the child.
void insert(RenderBox child, {RenderBox? after}) {
  _insertIntoList(child, after);
  adoptChild(child);
}

/// Relocates an already-adopted [child] to immediately after [after] (or
/// first when [after] is null). Does not re-adopt.
void move(RenderBox child, {RenderBox? after}) {
  assert(_children.contains(child), 'move() child must already be present.');
  _children.remove(child);
  _insertIntoList(child, after);
  markNeedsLayout();
}

void _insertIntoList(RenderBox child, RenderBox? after) {
  if (after == null) {
    _children.insert(0, child);
  } else {
    var index = _children.indexOf(after);
    assert(index != -1, 'insert() `after` child is not in this RenderFlex.');
    _children.insert(index + 1, child);
  }
}
```

- [ ] **Step 4: Run, verify pass** — `cd app && flutter test test/tui/render/render_flex_test.dart` → PASS (all, including pre-existing).

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/render/render_flex.dart app/test/tui/render/render_flex_test.dart
git commit -m "Add RenderFlex.insert/move for stage 4 child splicing"
```

---

## Task 2: `Key` types + library skeleton

**Files:**
- Create: `app/lib/src/tui/widgets/widgets.dart`, `app/lib/src/tui/widgets/key.dart`
- Test: `app/test/tui/widgets/key_test.dart`

For the library to compile with only `key.dart` present, `widgets.dart` must list only the `part`s that exist. Build it incrementally: each task adds its `part` line. **Start `widgets.dart` with only `part 'key.dart';`** and the imports `dart:async` + the four sibling/render imports; add the rest as tasks land.

- [ ] **Step 1: Write failing test** — `app/test/tui/widgets/key_test.dart`:

```dart
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

void main() {
  group('ValueKey', () {
    test('equal when value and type match', () {
      expect(ValueKey('a'), ValueKey('a'));
      expect(ValueKey('a').hashCode, ValueKey('a').hashCode);
    });
    test('unequal across values', () {
      expect(ValueKey('a') == ValueKey('b'), isFalse);
    });
    test('unequal across value types', () {
      expect(ValueKey<Object>(1) == ValueKey<Object>('1'), isFalse);
    });
  });

  group('ObjectKey', () {
    test('equal only for identical objects', () {
      var o = Object();
      expect(ObjectKey(o), ObjectKey(o));
      expect(ObjectKey(Object()) == ObjectKey(Object()), isFalse);
    });
  });

  group('UniqueKey', () {
    test('never equal to another UniqueKey', () {
      expect(UniqueKey() == UniqueKey(), isFalse);
      var k = UniqueKey();
      expect(k, k);
    });
  });

  test('Key factory builds a ValueKey<String>', () {
    expect(Key('x'), ValueKey<String>('x'));
  });
}
```

- [ ] **Step 2: Run, verify failure** — `cd app && flutter test test/tui/widgets/key_test.dart` → FAIL (no `widgets.dart`).

- [ ] **Step 3: Implement** — create `widgets.dart` with imports + only `part 'key.dart';`. Create `key.dart`:

```dart
part of 'widgets.dart';

/// An identifier for a [Widget], used by [Widget.canUpdate] and child
/// reconciliation to match a widget to an existing element.
abstract class Key {
  const factory Key(String value) = ValueKey<String>;
  const Key._();
}

/// A [Key] scoped to its parent. The only key family in stage 4 (no GlobalKey).
abstract class LocalKey extends Key {
  const LocalKey() : super._();
}

/// A [LocalKey] backed by a value of type [T]; equal when type and value match.
class ValueKey<T> extends LocalKey {
  const ValueKey(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      other is ValueKey<T> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

/// A [LocalKey] backed by object identity.
class ObjectKey extends LocalKey {
  const ObjectKey(this.value);
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is ObjectKey && identical(other.value, value);

  @override
  int get hashCode => Object.hash(runtimeType, identityHashCode(value));
}

/// A [LocalKey] equal only to itself.
class UniqueKey extends LocalKey {
  UniqueKey();
}
```

- [ ] **Step 4: Run, verify pass** — `cd app && flutter test test/tui/widgets/key_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/widgets/widgets.dart app/lib/src/tui/widgets/key.dart app/test/tui/widgets/key_test.dart
git commit -m "Add TUI widget-layer Key types and library skeleton"
```

---

## Task 3: `Widget` base classes

`Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `ProxyWidget`, `ParentDataWidget`. These reference `Element` types defined in Task 4; because everything is one library, forward references compile as long as Task 4 lands before any test *runs* the element machinery. This task's test only checks `canUpdate` and field wiring, which need no elements.

**Files:**
- Create: `app/lib/src/tui/widgets/widget.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part 'widget.dart';`)
- Test: `app/test/tui/widgets/key_test.dart` (append a `canUpdate` group) — or a new file; append is fine.

- [ ] **Step 1: Write failing test** — append to `key_test.dart`:

```dart
class _W extends StatelessWidget {
  const _W({super.key});
  @override
  Widget build(BuildContext context) => this;
}
class _W2 extends StatelessWidget {
  const _W2({super.key});
  @override
  Widget build(BuildContext context) => this;
}

// inside main():
group('Widget.canUpdate', () {
  test('true for same type and key', () {
    expect(Widget.canUpdate(_W(key: Key('a')), _W(key: Key('a'))), isTrue);
  });
  test('false for different key', () {
    expect(Widget.canUpdate(_W(key: Key('a')), _W(key: Key('b'))), isFalse);
  });
  test('false for different runtimeType', () {
    expect(Widget.canUpdate(_W(), _W2()), isFalse);
  });
  test('true for same type, both keyless', () {
    expect(Widget.canUpdate(_W(), _W()), isTrue);
  });
});
```

- [ ] **Step 2: Run, verify failure** — `cd app && flutter test test/tui/widgets/key_test.dart` → FAIL (`StatelessWidget` undefined).

- [ ] **Step 3: Implement** — add `part 'widget.dart';` to `widgets.dart`. Create `widget.dart` per the spec's "`Widget`" section. Key points:
  - `Widget` — `const Widget({this.key})`, `final Key? key`, abstract `Element createElement()`, `static bool canUpdate(Widget a, Widget b) => a.runtimeType == b.runtimeType && a.key == b.key;`
  - `StatelessWidget` — `createElement() => StatelessElement(this);`, abstract `Widget build(BuildContext)`.
  - `StatefulWidget` — `createElement() => StatefulElement(this);`, abstract `State createState()`.
  - `State<T extends StatefulWidget>` — fields `_widget`/`_element`; getters `widget`, `context => _element!`, `mounted => _element != null`; no-op lifecycle hooks `initState`/`didChangeDependencies`/`didUpdateWidget`/`deactivate`/`dispose`; abstract `build`; and:

    ```dart
    void setState(void Function() fn) {
      assert(_element != null, 'setState() called on an unmounted State.');
      fn();
      _element!.markNeedsBuild();
    }
    ```
  - `ProxyWidget` — `const ProxyWidget({super.key, required this.child})`, `final Widget child`.
  - `ParentDataWidget<T extends ParentData>` — extends `ProxyWidget`; abstract `void applyParentData(RenderObject renderObject)`; `createElement() => ParentDataElement<T>(this);`.

- [ ] **Step 4: Run, verify pass** — `cd app && flutter test test/tui/widgets/key_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/widgets/widget.dart app/lib/src/tui/widgets/widgets.dart app/test/tui/widgets/key_test.dart
git commit -m "Add TUI widget-layer Widget/State base classes"
```

---

## Task 4: `Element` + lifecycle + `updateChild` + component elements

The spine. Transcribe from Flutter's `framework.dart`. This is large — implement in the order below, but it is one commit because the pieces do not compile independently.

**Files:**
- Create: `app/lib/src/tui/widgets/element.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part 'element.dart';`)
- Test: `app/test/tui/widgets/element_lifecycle_test.dart`

**Implement (in `element.dart`):**

- `BuildContext` — abstract interface: `Widget get widget;`, `BuildOwner? get owner;`, `RenderObject? findRenderObject();`, `InheritedWidget dependOnInheritedWidgetOfExactType<T extends InheritedWidget>();`, `T? getInheritedWidgetOfExactType<T extends InheritedWidget>();`.
- `enum _ElementLifecycle { initial, active, inactive, defunct }`.
- `Element implements BuildContext` — fields and methods per the spec's "`Element`" section. Transcribe these faithfully from Flutter:
  - `mount(Element? parent, Object? newSlot)` — set `_parent`, `_slot`, `_owner`, `_lifecycleState = active`, `_depth = parent==null ? 1 : parent._depth + 1`; copy `_inheritedElements` from parent (`_parent?._inheritedElements`); call `attachRenderObject(newSlot)`; then `_firstBuild()` (which calls `rebuild`).
  - `update(Widget newWidget)` — `_widget = newWidget;` (subclasses extend).
  - `rebuild()` — if `_lifecycleState == active && _dirty` → `performRebuild()`.
  - `performRebuild()` — clears `_dirty`; subclass-specific.
  - `markNeedsBuild()` — if `_lifecycleState != active` return; if `_dirty` return; set `_dirty = true`; `owner!.scheduleBuildFor(this)`.
  - `updateChild(Element? child, Widget? newWidget, Object? newSlot)` — the four-case table from the spec. Faithful to Flutter:
    - both null → `null`.
    - child null, widget set → `inflateWidget(newWidget, newSlot)`.
    - child set, widget null → `deactivateChild(child); return null;`.
    - both set → if `child.widget == newWidget` just `updateSlotForChild` if slot changed and return child; else if `Widget.canUpdate(child.widget, newWidget)` → `updateSlotForChild` if needed, `child.update(newWidget)`, return child; else `deactivateChild(child); return inflateWidget(newWidget, newSlot);`.
  - `inflateWidget(Widget newWidget, Object? newSlot)` — `var el = newWidget.createElement(); el.mount(this, newSlot); return el;` (no GlobalKey path).
  - `deactivateChild(Element child)` — `child._parent = null; child.detachRenderObject(); owner!._inactiveElements.add(child);` (`add` deactivates the subtree).
  - `forgetChild(Element child)` — subclasses drop the child from their bookkeeping.
  - `updateSlotForChild(Element child, Object? newSlot)` — set `child._slot`, call `child._updateSlot`-equivalent so render objects re-splice (see Task 7); base implementation walks to descendant render objects.
  - `activate()` / `deactivate()` — flip `_lifecycleState`; `activate` re-runs `didChangeDependencies` if there were dependencies and `markNeedsBuild`.
  - `unmount()` — `_lifecycleState = defunct;` subclasses release resources.
  - `attachRenderObject(Object? newSlot)` / `detachRenderObject()` — base: forward to children (overridden by `RenderObjectElement` in Task 7).
  - `visitChildren` — no-op base.
  - `findRenderObject()` — `renderObject` getter; base walks to first child with one.
  - `dependOnInheritedWidgetOfExactType` / `getInheritedWidgetOfExactType` — `_inheritedElements?[T]`; the `dependOn` variant also registers a dependency (calls `ancestor.updateDependencies(this, ...)`) — implemented fully in Task 6, stub here returning the lookup.
- `ComponentElement extends Element` — holds `Element? _child`; `performRebuild()` → `var built = build(); _child = updateChild(_child, built, slot);` (`slot` is `_slot`); abstract `Widget build()`; `visitChildren` visits `_child`; `forgetChild` nulls `_child`.
- `StatelessElement extends ComponentElement` — `build() => (widget as StatelessWidget).build(this);`.
- `StatefulElement extends ComponentElement` — creates `State` in constructor (`_state = widget.createState(); _state._element = this; _state._widget = widget;`); `mount` calls `state.initState()` then `state.didChangeDependencies()` before first build; `build() => state.build(this);`; `update` sets `state._widget`, calls `state.didUpdateWidget(old)`, marks needs build; `unmount` calls `state.dispose()`, nulls `state._element`; `activate`/`deactivate` forward to `state`.
- `ParentDataElement<T extends ParentData>` — see Task 6 (it depends on `ProxyElement`); declare in Task 6, not here. **Remove it from this file's scope** — `widget.dart`'s `ParentDataWidget.createElement` references it but that is a forward reference resolved when Task 6 lands.
- `_InactiveElements` — a `Set<Element>`; `add(Element e)` deactivates the subtree depth-first (`_deactivateRecursively`); `remove`; `_unmountAll()` unmounts everything still inactive.

**Note on `ParentDataElement`:** since `widget.dart` (Task 3) already names `ParentDataElement` in `ParentDataWidget.createElement`, and this file does not define it, the library will not compile until Task 6. To keep Task 4 independently testable, **add a minimal placeholder** in `element.dart`: `class ParentDataElement<T extends ParentData> extends Element { ... }` is *not* wanted — instead, defer `ParentDataWidget` itself: in Task 3 do **not** write `ParentDataWidget`; add it in Task 6 alongside `ParentDataElement`. **Action:** when doing Task 3, omit `ParentDataWidget`; this plan's Task 6 adds both. (If Task 3 was already done with `ParentDataWidget`, move it to Task 6's commit.)

- [ ] **Step 1: Write failing tests** — `app/test/tui/widgets/element_lifecycle_test.dart`. Use a `State` that records lifecycle calls into a shared list:

```dart
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

var log = <String>[];

class Probe extends StatefulWidget {
  const Probe(this.label, {super.key});
  final String label;
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  @override
  void initState() => log.add('initState ${widget.label}');
  @override
  void didChangeDependencies() => log.add('didChangeDependencies ${widget.label}');
  @override
  void didUpdateWidget(Probe old) => log.add('didUpdateWidget ${widget.label}<-${old.label}');
  @override
  void dispose() => log.add('dispose ${widget.label}');
  @override
  Widget build(BuildContext context) {
    log.add('build ${widget.label}');
    return const _Leaf();
  }
}

class _Leaf extends StatelessWidget {
  const _Leaf();
  @override
  Widget build(BuildContext context) => this;  // self-terminating leaf
}

void main() {
  setUp(() => log = <String>[]);

  test('mount runs initState, didChangeDependencies, then build', () {
    var owner = BuildOwner();
    var element = const Probe('a').createElement();
    element.mount(null, null);
    owner; // element.mount sets owner via parent; root mount path tested in Task 7
    expect(log, ['initState a', 'didChangeDependencies a', 'build a']);
  });
}
```

Because a bare `Element.mount(null, null)` has no `BuildOwner`, and full root mounting is Task 7, **scope this task's tests** to what works without a root: construct elements and assert constructor-time wiring (`State._element` set, `mounted` true), and assert `Widget.canUpdate`-driven `updateChild` behavior using a tiny harness. Replace the test above with tests that use `TuiBinding` *only after Task 9*; for Task 4, test the pure pieces:

```dart
test('StatefulElement wires State on construction', () {
  var element = const Probe('a').createElement() as StatefulElement;
  expect(element.state, isA<ProbeState>());
  expect(element.state.widget, isA<Probe>());
  expect(element.state.mounted, isFalse); // not mounted until mount()
});
```

> **Decision:** the deep lifecycle assertions (mount ordering, dispose, didUpdateWidget) require a working root, which is Task 9's `TuiBinding`. Task 4 commits the code; the lifecycle-ordering tests are written in **Task 9, Step 1b** against `TuiBinding`. Task 4's test file asserts only constructor wiring + `updateChild` via a minimal in-test root (see below).

- [ ] **Step 1b: Minimal `updateChild` test** — add a test that exercises `updateChild`'s four cases. Since `updateChild` is `protected`-by-convention, expose it through a tiny in-test `Element` subclass is awkward; instead **defer the `updateChild` reconciliation tests to Task 5** (`reconciliation_test.dart`), driven through `BuildOwner` + a test root. Task 4's test file therefore contains only the constructor-wiring test above plus:

```dart
test('canUpdate matches type and key (sanity)', () {
  expect(Widget.canUpdate(const Probe('a'), const Probe('b')), isTrue);
  expect(Widget.canUpdate(const Probe('a', key: ValueKey('k')),
      const Probe('b', key: ValueKey('k'))), isTrue);
});
```

- [ ] **Step 2: Run, verify failure** — `cd app && flutter test test/tui/widgets/element_lifecycle_test.dart` → FAIL (`BuildOwner`/elements undefined).

- [ ] **Step 3: Implement** — `element.dart` as specified above. `BuildOwner` is Task 5; for this task add a forward-declared `class BuildOwner` only if needed — better: **do Task 5's `BuildOwner` skeleton as part of this commit is not allowed (separate task).** Resolve by ordering: Task 4 references `BuildOwner` as a type only (fields/params); since it is one library, the type need only exist by the time tests *run*. So: Task 4 and Task 5 may be committed together if the library will not compile otherwise. **Practical rule:** implement `element.dart` AND `build_owner.dart` together, commit as Task 4+5 combined if the analyzer demands it; otherwise keep separate. Prefer separate commits; if `flutter analyze` fails between them, combine.

- [ ] **Step 4: Run, verify pass** — `cd app && flutter test test/tui/widgets/element_lifecycle_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/widgets/element.dart app/lib/src/tui/widgets/widgets.dart app/test/tui/widgets/element_lifecycle_test.dart
git commit -m "Add TUI widget-layer Element tree and lifecycle"
```

---

## Task 5: `BuildOwner`

**Files:**
- Create: `app/lib/src/tui/widgets/build_owner.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part 'build_owner.dart';`)
- Test: `app/test/tui/widgets/build_owner_test.dart`, `app/test/tui/widgets/reconciliation_test.dart`

**Implement** per the spec's "`BuildOwner`" section:

```dart
part of 'widgets.dart';

/// Owns the dirty elements and drives depth-ordered rebuilds.
class BuildOwner {
  final List<Element> _dirtyElements = [];
  bool _dirtyElementsNeedsResorting = false;
  bool _buildScopeActive = false;

  /// Called the first time an element is scheduled for build in an idle owner.
  /// The binding uses this to schedule a frame.
  void Function()? onBuildScheduled;

  final _InactiveElements _inactiveElements = _InactiveElements();

  void scheduleBuildFor(Element element) {
    if (element._inDirtyList) {
      _dirtyElementsNeedsResorting = true;
      return;
    }
    if (_dirtyElements.isEmpty) {
      onBuildScheduled?.call();
    }
    _dirtyElements.add(element);
    element._inDirtyList = true;
  }

  void buildScope(Element context, [void Function()? callback]) {
    if (callback == null && _dirtyElements.isEmpty) return;
    _buildScopeActive = true;
    try {
      if (callback != null) callback();
      _dirtyElements.sort((a, b) => a._depth - b._depth);
      _dirtyElementsNeedsResorting = false;
      var index = 0;
      while (index < _dirtyElements.length) {
        var element = _dirtyElements[index];
        if (element._lifecycleState == _ElementLifecycle.active) {
          element.rebuild();
        }
        index += 1;
        if (_dirtyElementsNeedsResorting) {
          _dirtyElements.sort((a, b) => a._depth - b._depth);
          _dirtyElementsNeedsResorting = false;
          // re-skip already-built clean prefix
          while (index > 0 && _dirtyElements[index - 1]._dirty) {
            index -= 1;
          }
        }
      }
    } finally {
      for (var e in _dirtyElements) {
        e._inDirtyList = false;
      }
      _dirtyElements.clear();
      _buildScopeActive = false;
    }
  }

  /// Unmounts every element deactivated this frame and not reactivated.
  void finalizeTree() => _inactiveElements._unmountAll();
}
```

(Consult Flutter's `BuildOwner.buildScope` for the resort/skip subtlety; the above is a faithful reduction.)

- [ ] **Step 1: Write failing tests** — `build_owner_test.dart`: assert (a) `scheduleBuildFor` calls `onBuildScheduled` only on the first dirty element of an idle owner; (b) `buildScope` rebuilds dirty elements shallowest-depth-first (use elements with set `_depth` via a test root from Task 9 — *defer the depth-ordering test to Task 9*); (c) for now, test `scheduleBuildFor`/`onBuildScheduled` counting with stub elements is hard without elements — so **Task 5's `build_owner_test.dart` tests only `onBuildScheduled` fires once**, using a real tiny tree via `TuiBinding` — again Task 9. **Conclusion:** `build_owner_test.dart` and `reconciliation_test.dart` are *written* in Task 9 once `TuiBinding` exists. Task 5 commits `build_owner.dart` with no new test file; its behavior is covered by Task 9's suites. Note this explicitly in the commit message.

- [ ] **Step 2: Run analyze** — `cd app && flutter analyze` → no errors (the library now compiles end-to-end through `build_owner.dart`).

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/tui/widgets/build_owner.dart app/lib/src/tui/widgets/widgets.dart
git commit -m "Add TUI widget-layer BuildOwner rebuild scheduler"
```

---

## Task 6: `InheritedWidget`, `ProxyElement`, `ParentDataWidget`/`ParentDataElement`

**Files:**
- Create: `app/lib/src/tui/widgets/inherited.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part 'inherited.dart';`), `widget.dart` (add `ParentDataWidget` if it was deferred from Task 3)
- Test: `app/test/tui/widgets/inherited_widget_test.dart` (written in Task 9), `parent_data_test.dart` (Task 9)

**Implement** per the spec's "`InheritedWidget`" section:
- `ProxyWidget` already exists (Task 3). `ProxyElement extends ComponentElement` — `build() => (widget as ProxyWidget).child;`; `update` calls `updated(oldWidget)` after `super.update`; `notifyClients` hook.
- `InheritedWidget extends ProxyWidget` — abstract `bool updateShouldNotify(covariant InheritedWidget oldWidget)`; `createElement() => InheritedElement(this);`.
- `InheritedElement extends ProxyElement`:
  - `_dependents` — `Map<Element, Object?>`.
  - `mount` — after `super.mount`, register self into `_inheritedElements`: build a new map = `{...?parent._inheritedElements, widget.runtimeType: this}` and assign to `this._inheritedElements` so descendants inherit it.
  - `updateDependencies(Element dependent, Object? aspect)` — `_dependents[dependent] = aspect;` and add `this` to `dependent._dependencies`.
  - `notifyClients(InheritedWidget oldWidget)` — if `widget.updateShouldNotify(oldWidget)`, for each `dependent` call `dependent.didChangeDependencies()` then `dependent.markNeedsBuild()`.
  - `update` (via `ProxyElement.updated`) — call `notifyClients(oldWidget)`.
- Wire `Element.dependOnInheritedWidgetOfExactType<T>()` fully now: `var ancestor = _inheritedElements?[T]; if (ancestor != null) { ancestor.updateDependencies(this, null); return ancestor.widget as T; } throw ...` — actually return type is `InheritedWidget`; faithfully: register and return. (No-ancestor case: Flutter returns `null` from `dependOnInheritedWidgetOfExactType` — make the return type `T?`.)  **Correction:** make `dependOnInheritedWidgetOfExactType<T extends InheritedWidget>()` return `T?`. Update the `BuildContext` interface and `element.dart` accordingly.
- `ParentDataWidget<T extends ParentData>` (move here if deferred from Task 3) and `ParentDataElement<T extends ParentData> extends ProxyElement`:
  - after mount/update, call `_applyParentData(widget)`: `void _applyParentData(ParentDataWidget widget) { void apply(Element child) { if (child is RenderObjectElement) { widget.applyParentData(child.renderObject); } else { child.visitChildren(apply); } } visitChildren(apply); }` then mark the affected render object's parent needs layout.

- [ ] **Step 1: Implement** `inherited.dart`; update `element.dart`'s `dependOn...` return type to `T?`; ensure `ParentDataWidget`/`ParentDataElement` exist.
- [ ] **Step 2: Run analyze** — `cd app && flutter analyze` → clean.
- [ ] **Step 3: Commit**

```bash
git add app/lib/src/tui/widgets/inherited.dart app/lib/src/tui/widgets/widget.dart app/lib/src/tui/widgets/element.dart app/lib/src/tui/widgets/widgets.dart
git commit -m "Add TUI widget-layer InheritedWidget and ParentDataWidget"
```

---

## Task 7: `RenderObjectWidget` + the render-tree bridge

**Files:**
- Create: `app/lib/src/tui/widgets/render_object_widget.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part`)
- Test: `app/test/tui/widgets/render_object_widget_test.dart` (Task 9)

**Implement** per the spec's "`RenderObjectWidget`" section:
- `RenderObjectWidget extends Widget` — abstract `RenderObject createRenderObject(BuildContext)`, `void updateRenderObject(BuildContext, RenderObject)`, `void didUnmountRenderObject(RenderObject) {}`.
- `RenderObjectElement extends Element` — holds `RenderObject? _renderObject`; `renderObject` getter returns it; `mount` → `_renderObject = widget.createRenderObject(this); attachRenderObject(slot);` then `super`-equivalent build-less (`performRebuild` just clears dirty); `update` → `widget.updateRenderObject(this, _renderObject!);`; `unmount` → `widget.didUnmountRenderObject(_renderObject!)`.
  - `attachRenderObject(Object? newSlot)` — `_slot = newSlot; var ancestor = _findAncestorRenderObjectElement(); ancestor?.insertRenderObjectChild(_renderObject!, newSlot);`.
  - `detachRenderObject()` — `_ancestorRenderObjectElement?.removeRenderObjectChild(_renderObject!, slot); _slot = null;`.
  - `_findAncestorRenderObjectElement()` — walk `_parent` until a `RenderObjectElement`.
  - abstract `insertRenderObjectChild(RenderObject child, Object? slot)`, `moveRenderObjectChild(child, oldSlot, newSlot)`, `removeRenderObjectChild(child, slot)`.
- `LeafRenderObjectWidget extends RenderObjectWidget` / `LeafRenderObjectElement` — `visitChildren` no-op; insert/move/remove `assert(false)`.
- `SingleChildRenderObjectWidget` (field `Widget? child`) / `SingleChildRenderObjectElement`:
  - holds `Element? _child`; `mount` after super → `_child = updateChild(_child, widget.child, null);`; `performRebuild` → `super` then `_child = updateChild(_child, widget.child, null);` — actually `RenderObjectElement.performRebuild` clears dirty; the child update happens in `_performRebuild`. Faithful structure: override `performRebuild()` to `widget.updateRenderObject(...)`? No — `update()` does that. `performRebuild` for single-child re-runs `updateChild`. Follow Flutter: `mount` calls `_child = updateChild(...)`; `update` calls `super.update` (which calls `updateRenderObject`) then `_child = updateChild(_child, widget.child, null)`.
  - `insertRenderObjectChild(child, slot)` → `(renderObject as RenderBoxWithChild).child = child as RenderBox;`
  - `removeRenderObjectChild(child, slot)` → `(renderObject as RenderBoxWithChild).child = null;`
  - `moveRenderObjectChild` → `assert(false)` (single child never moves).
  - `visitChildren` visits `_child`; `forgetChild` nulls it.
- `MultiChildRenderObjectWidget` (field `List<Widget> children`) / `MultiChildRenderObjectElement`:
  - holds `List<Element> _children = []`; a `Set<Element> _forgottenChildren = {}`.
  - **slot = the previous-sibling `Element`** (`null` for the first child).
  - `mount` — inflate each child in order, slot = previous element; collect into `_children`.
  - `update` — `super.update`, then `_children = updateChildren(_children, widget.children, forgottenChildren: _forgottenChildren); _forgottenChildren.clear();`.
  - `insertRenderObjectChild(RenderObject child, Element? slot)` → `(renderObject as RenderFlex).insert(child as RenderBox, after: slot?.renderObject as RenderBox?);`
  - `moveRenderObjectChild(child, Element? oldSlot, Element? newSlot)` → `(renderObject as RenderFlex).move(child as RenderBox, after: newSlot?.renderObject as RenderBox?);`
  - `removeRenderObjectChild(child, slot)` → `(renderObject as RenderFlex).remove(child as RenderBox);`
  - `visitChildren` visits each non-forgotten `_children`; `forgetChild` adds to `_forgottenChildren` and removes from `_children` lazily.
- `updateChildren(List<Element> oldChildren, List<Widget> newWidgets, {Set<Element> forgottenChildren})` — **transcribe Flutter's `RenderObjectElement.updateChildren` verbatim** (the prefix scan, suffix scan, old-keyed-middle map, inflate/update middle, slot fixup so each surviving child's slot is its new previous sibling). This is the canonical hard algorithm; do not paraphrase it — copy the structure and adapt only the slot type (previous-sibling `Element`) and `updateChild` calls.

- [ ] **Step 1: Implement** `render_object_widget.dart`.
- [ ] **Step 2: Run analyze** — `cd app && flutter analyze` → clean.
- [ ] **Step 3: Commit**

```bash
git add app/lib/src/tui/widgets/render_object_widget.dart app/lib/src/tui/widgets/widgets.dart
git commit -m "Add TUI widget-layer RenderObjectWidget bridge and reconciler"
```

---

## Task 8: Concrete widgets — `basic.dart`

**Files:**
- Create: `app/lib/src/tui/widgets/basic.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part`)
- Test: `app/test/tui/widgets/basic_widgets_test.dart` (Task 9)

**Implement** per the spec's "Concrete widgets" table. Each `RenderObjectWidget` subclass implements `createRenderObject` (build the Stage 3 render object from widget fields) and `updateRenderObject` (assign each field through the Stage 3 setter):

- `Text extends LeafRenderObjectWidget` — fields `text`, `fg`, `bg`, `style`, `hAlign`, `vAlign`, `wrap` (defaults matching `RenderText`'s constructor). `createRenderObject` → `RenderText(text, fg: fg, bg: bg, style: style, hAlign: hAlign, vAlign: vAlign, wrap: wrap)`. `updateRenderObject` → `ro..text = text..fg = fg..bg = bg..style = style..hAlign = hAlign..vAlign = vAlign..wrap = wrap`.
- `Padding extends SingleChildRenderObjectWidget` — field `EdgeInsets padding`. create → `RenderPadding(padding: padding)`; update → `ro.padding = padding`.
- `ConstrainedBox extends SingleChildRenderObjectWidget` — field `BoxConstraints constraints`. create → `RenderConstrainedBox(additionalConstraints: constraints)`; update → `ro.additionalConstraints = constraints`.
- `SizedBox extends StatelessWidget` — fields `int? width`, `int? height`, `Widget? child`. `build` → `ConstrainedBox(constraints: BoxConstraints.tightFor(width: width, height: height), child: child)`.
- `DecoratedBox extends SingleChildRenderObjectWidget` — field `BoxDecoration decoration`. create → `RenderDecoratedBox(decoration: decoration)`; update → `ro.decoration = decoration`.
- `Flex extends MultiChildRenderObjectWidget` — fields `Axis direction`, `MainAxisAlignment mainAxisAlignment`, `CrossAxisAlignment crossAxisAlignment`, `MainAxisSize mainAxisSize`, `List<Widget> children`. create → `RenderFlex(direction: direction, mainAxisAlignment: ..., crossAxisAlignment: ..., mainAxisSize: ...)`; update → assign those four fields. (Children are managed by `MultiChildRenderObjectElement`; flex factors by `Expanded`/`Flexible`.)
- `Row extends Flex` — `const Row({...}) : super(direction: Axis.horizontal)`. `Column` → `Axis.vertical`.
- `Flexible extends ParentDataWidget<FlexParentData>` — fields `int flex` (default 1), `FlexFit fit` (default `FlexFit.loose`). `applyParentData(RenderObject ro)` → `var pd = ro.parentData as FlexParentData; if (pd.flex != flex || pd.fit != fit) { pd.flex = flex; pd.fit = fit; (ro.parent as RenderObject?)... }` — after mutating, mark the parent `RenderFlex` needs layout: `if (ro.parent is RenderFlex) (ro.parent! as RenderFlex).markNeedsLayout();`. (`markNeedsLayout` is library-private to `render/` — expose a public method or have `ParentDataElement` mark it. **Resolution:** `RenderObject.markNeedsLayout` is already public within `render/`; it is *not* exported. Add it to the `tui.dart` export of `RenderObject`'s surface is wrong — instead, `Flexible.applyParentData` lives in the same app and imports `render/render.dart` which makes `markNeedsLayout` visible. Confirm: `markNeedsLayout` is a public method on `RenderObject` — yes (see `render_object.dart:127`). It is callable from `widgets.dart` since that file imports `render/render.dart`. Good — no export change needed.)
- `Expanded extends Flexible` — `const Expanded({super.key, super.flex, required super.child}) : super(fit: FlexFit.tight);`

- [ ] **Step 1: Implement** `basic.dart`.
- [ ] **Step 2: Run analyze** — `cd app && flutter analyze` → clean.
- [ ] **Step 3: Commit**

```bash
git add app/lib/src/tui/widgets/basic.dart app/lib/src/tui/widgets/widgets.dart
git commit -m "Add TUI widget-layer concrete widgets (Text, Flex, Padding, ...)"
```

---

## Task 9: `binding.dart` — `TuiBinding`, `runApp`, `TerminalApp` + full test suite

This task wires the root and writes **all** the headless test suites that earlier tasks deferred.

**Files:**
- Create: `app/lib/src/tui/widgets/binding.dart`
- Modify: `app/lib/src/tui/widgets/widgets.dart` (add `part`), `app/lib/src/tui/tui.dart` (exports)
- Test: `binding_test.dart`, `reconciliation_test.dart`, `build_owner_test.dart`, `inherited_widget_test.dart`, `render_object_widget_test.dart`, `parent_data_test.dart`, `basic_widgets_test.dart`, and the deferred lifecycle assertions in `element_lifecycle_test.dart`.

**Implement** per the spec's "`TuiBinding`, `runApp`, `TerminalApp`" section:
- `RootWidget extends RenderObjectWidget` — wraps one `Widget child`; `createRenderObject` returns the binding's existing `RenderTuiView` (passed in via constructor — `RootWidget(this.view, {required this.child})`); `updateRenderObject` is a no-op. Its element `RootElement extends RenderObjectElement`:
  - holds `Element? _child`; `mount` → set render object = `view`; `_child = updateChild(_child, widget.child, null)`.
  - `insertRenderObjectChild(child, slot)` → `(renderObject as RenderTuiView).child = child as RenderBox;`
  - `removeRenderObjectChild` → `view.child = null;`
  - `_depth` is 1 (root); `attachRenderObject` does nothing (no ancestor).
  - expose `void mountAsRoot(BuildOwner owner)` — sets `_owner`, `mount(null, null)`, `view.prepareInitialFrame()` is already done by the binding.
- `TuiBinding`:
  - fields `buildOwner` (`BuildOwner`), `pipelineOwner` (`PipelineOwner`), `renderView` (`RenderTuiView`), `_rootElement` (`RootElement?`), `onFrameNeeded` (`void Function()?`).
  - constructor: `renderView = RenderTuiView(CellSize.zero); renderView.attach(pipelineOwner);`.
  - `attachRootWidget(Widget app)` — `var rw = RootWidget(renderView, child: app); _rootElement = rw.createElement() as RootElement; renderView.prepareInitialFrame(); buildOwner.onBuildScheduled = () => onFrameNeeded?.call(); buildOwner.buildScope(_rootElement!, () => _rootElement!.mountAsRoot(buildOwner));`.
  - `drawFrame(Painter painter)` — `buildOwner.buildScope(_rootElement!); buildOwner.finalizeTree(); renderView.compositeFrame(painter);`.
  - `handleResize(CellSize size)` — `renderView.configuration = size;`.
- `TerminalApp extends InheritedWidget` — fields `Stream<KeyEvent> keys`, `CellSize size`, `void Function() exit`; `static TerminalApp of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<TerminalApp>()!;`; `updateShouldNotify(old) => old.size != size;`.
- `runApp(Widget app)` — per the spec snippet: open `Terminal.run`, create `TuiBinding`, an exit `Completer`, attach `RootWidget` wrapping `TerminalApp(keys: terminal.keys, size: <current>, exit: completer.complete, child: app)`. Frame closure calls `terminal.draw((b) { binding.handleResize(CellSize(b.rows, b.cols)); binding.drawFrame(Painter(b)); })`. Set `binding.onFrameNeeded` to a microtask-coalesced wrapper around the frame closure (a `_frameScheduled` bool + `scheduleMicrotask`). Run one frame, listen to `terminal.resizes` → re-wrap `TerminalApp` with new size and rebuild the root (call `binding.attachRootWidget`-equivalent update, or simpler: keep the root, and have `runApp` rebuild by calling a `binding.updateRootWidget(newTerminalApp)` that does `updateChild` on the root). **Simplest faithful path:** `TuiBinding.updateRootWidget(Widget app)` — `buildOwner.buildScope(_rootElement!, () => _rootElement!.update(RootWidget(renderView, child: app)));`. On resize, `runApp` calls `binding.handleResize` + `binding.updateRootWidget(TerminalApp(... size: newSize ...))` + frame. `await completer.future` then cancel the resize sub.

**Headless test harness** (used by every suite below): build a `TuiBinding`, `attachRootWidget(widget)`, set `renderView.configuration` via `handleResize(CellSize(rows, cols))`, allocate a `CellBuffer(rows, cols)`, `binding.drawFrame(Painter(buffer))`, then read cells with `buffer.get(row, col)` or inspect `binding.renderView.child` render objects. To pump a rebuild after `setState`, call `binding.drawFrame` again (in tests, drive frames synchronously — ignore `onFrameNeeded`).

- [ ] **Step 1: Implement** `binding.dart`; add exports to `tui.dart` (see Task 10 — do exports here so tests can import from `tui.dart` or directly from `widgets.dart`; tests import `widgets.dart` directly).

- [ ] **Step 2: Run analyze** — `cd app && flutter analyze` → clean.

- [ ] **Step 3: Write the test suites.** Each is a normal `flutter test` file importing `package:flutterware_app/src/tui/widgets/widgets.dart` and `package:flutterware_app/src/tui/tui.dart` (for `CellBuffer`, `Painter`, geometry). Write, run (`cd app && flutter test test/tui/widgets/<file>`), and confirm PASS for each:

  - **`element_lifecycle_test.dart`** (extend Task 4's file): mount a `Probe` tree via `TuiBinding`; assert `log` order `initState → didChangeDependencies → build`. Rebuild with a new `Probe` of same type → `didUpdateWidget` then `build`. Remove the `Probe` from the tree → `deactivate` then `dispose`. Assert `mounted` flips false after dispose.
  - **`reconciliation_test.dart`**: a `Column` whose children list changes between frames. (a) reorder keyed `Text`s (`ValueKey`) — assert the `RenderText` instances are reused (capture identity via `binding.renderView` walk). (b) insert in the middle. (c) remove. (d) replace a child with a different type — old render object gone, new one present. (e) keyless same-type children update in place.
  - **`build_owner_test.dart`**: (a) a `StatefulWidget` calling `setState` marks exactly its element dirty; after `drawFrame` only that subtree rebuilt (sibling `build` count unchanged — use a build-counter `State`). (b) depth ordering: two nested dirty `StatefulWidget`s rebuild parent-before-child once. (c) `onBuildScheduled` fires once per idle→dirty transition.
  - **`inherited_widget_test.dart`**: a custom `InheritedWidget` over an `int`; a descendant that `dependOnInheritedWidgetOfExactType`. Changing the value with `updateShouldNotify == true` rebuilds the dependent; with `false` does not; a non-dependent sibling never rebuilds. `getInheritedWidgetOfExactType` does not register a dependency.
  - **`render_object_widget_test.dart`**: `Column(children: [Text('a'), Text('b')])` → `binding.renderView.child` is a `RenderFlex` with two `RenderText` children, texts `'a'`/`'b'`, in order. Rebuild with `Text('a2')` first → same `RenderText` instance, `.text == 'a2'`.
  - **`parent_data_test.dart`**: `Row(children: [Expanded(flex: 2, child: Text('x'))])` → the wrapped `RenderText`'s `parentData` is a `FlexParentData` with `flex == 2`, `fit == FlexFit.tight`. `Flexible(flex: 3, ...)` → `flex == 3`, `fit == loose`. Rebuild with a new flex → updated.
  - **`basic_widgets_test.dart`**: each widget produces the expected render object with expected fields; paint a small tree into a `CellBuffer` and read back cells (e.g. `Padding(EdgeInsets.all(1), child: Text('hi'))` puts `'h'` at `(1,1)`).
  - **`binding_test.dart`**: `drawFrame` runs build→layout→paint end to end; a `setState`-driven counter `StatefulWidget`, after a second `drawFrame`, shows the new value in the buffer; `handleResize` changes `renderView.configuration` and the next frame re-lays out.

- [ ] **Step 4: Run the whole widgets suite** — `cd app && flutter test test/tui/widgets/` → all PASS. Also `cd app && flutter test` → all pre-existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/widgets/binding.dart app/lib/src/tui/widgets/widgets.dart app/lib/src/tui/tui.dart app/test/tui/widgets/
git commit -m "Add TUI widget-layer binding, runApp, and full test suite"
```

---

## Task 10: Public exports + docs

**Files:**
- Modify: `app/lib/src/tui/tui.dart`, `app/lib/src/tui/README.md`, `docs/superpowers/tui-roadmap.md`

- [ ] **Step 1: Exports** — append to `tui.dart` an `export 'widgets/widgets.dart' show ...` listing the public surface: `Key`, `LocalKey`, `ValueKey`, `ObjectKey`, `UniqueKey`, `Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `BuildContext`, `ProxyWidget`, `ParentDataWidget`, `InheritedWidget`, `Element`, `BuildOwner`, `RenderObjectWidget`, `LeafRenderObjectWidget`, `SingleChildRenderObjectWidget`, `MultiChildRenderObjectWidget`, `Text`, `Padding`, `ConstrainedBox`, `SizedBox`, `DecoratedBox`, `Flex`, `Row`, `Column`, `Expanded`, `Flexible`, `TuiBinding`, `TerminalApp`, `runApp`. (If Task 9 already added these, verify completeness here.)

- [ ] **Step 2: README** — in `app/lib/src/tui/README.md`: change "currently at stage 3" → "stage 4: ... and widget layer"; add a `widgets/` row to the file table; update the "Current limitations" list (remove "No widget layer yet"; keep whole-tree repaint; add "No GlobalKey, focus system, or animation/tickers — later stages"). Add a short "Widgets" quick-start using `runApp`.

- [ ] **Step 3: Roadmap** — in `docs/superpowers/tui-roadmap.md`: set Stage 4 status to ✅ Done; add the Stage 4 spec/plan links under "Detailed docs per stage"; move the now-resolved "No widget layer" note.

- [ ] **Step 4: Verify** — `cd app && flutter analyze` → clean; `dart tool/prepare_submit.dart` → no diff.

- [ ] **Step 5: Commit**

```bash
git add app/lib/src/tui/tui.dart app/lib/src/tui/README.md docs/superpowers/tui-roadmap.md
git commit -m "Export TUI widget layer and mark stage 4 done in docs"
```

---

## Task 11: Demo — `widget_demo.dart`

Rebuild the Stage 3 render-tree demo as `StatefulWidget`s.

**Files:**
- Create: `app/examples/tui/widget_demo.dart`

- [ ] **Step 1: Implement** — mirror `app/examples/tui/render_tree_demo.dart`'s screen, declaratively:
  - `main() => runApp(const Demo());`
  - `Demo` — `StatelessWidget`; `build` returns a `Column(crossAxisAlignment: stretch, children: [header, Expanded(flex: 1, child: bodyRow), footer])`.
  - header — `ConstrainedBox(constraints: BoxConstraints.tightFor(height: 1), child: DecoratedBox(decoration: BoxDecoration(fill: Cell(rune: 0x20, bg: Color.blue)), child: Text('flutterware — widget demo', fg: Color.brightWhite, bg: Color.blue, style: TextStyle.bold, hAlign: HorizontalAlign.center)))`.
  - bodyRow — `Row(crossAxisAlignment: stretch, children: [Expanded(flex: 1, child: LeftPanel()), Expanded(flex: 2, child: RightPanel())])`.
  - `LeftPanel` — `StatefulWidget`. Its `State`: in `initState`, subscribe to `TerminalApp.of(context).keys` — **but `context` is not safe in `initState` for inherited lookups**; do the subscription in `didChangeDependencies` (guard with a `bool _subscribed`). On a non-`'q'` `CharKey`, `setState(() => _counter++)`. On `'q'` (`rune == 0x71`), call `TerminalApp.of(context).exit()`. In `dispose`, cancel the subscription. `build` returns the bordered panel (a `DecoratedBox` + `Padding(EdgeInsets.all(1))` + `Column` of a bold title `Text` and a body `Text` showing the counter).
  - `RightPanel` — `StatelessWidget`; static bordered panel with explanatory text.
  - footer — `ConstrainedBox(tightFor height: 1, child: Text("Press any key to update the left panel · 'q' to quit", fg: Color.brightBlack))`.

- [ ] **Step 2: Smoke test** — `cd app && dart run examples/tui/widget_demo.dart` in a real terminal. Verify: screen renders; a keypress updates only the left panel; resize re-lays out; `q` exits cleanly and the terminal is restored. (Manual — no automated test for the demo.)

- [ ] **Step 3: Final full check** — `cd app && flutter test` → all PASS; `cd app && flutter analyze` → clean; `dart tool/prepare_submit.dart` → no diff (run from repo root).

- [ ] **Step 4: Commit**

```bash
git add app/examples/tui/widget_demo.dart
git commit -m "Add stage 4 widget demo rebuilding the render-tree screen"
```

---

## Self-Review notes

- **Spec coverage:** Keys (T2), Widget/State (T3), Element/lifecycle/`updateChild` (T4), `BuildOwner` (T5), `InheritedWidget`/`ParentDataWidget` (T6), `RenderObjectWidget`/`updateChildren` (T7), concrete widgets (T8), `TuiBinding`/`runApp`/`TerminalApp` (T9), `RenderFlex` amendment (T1), exports/docs (T10), demo (T11). All spec sections mapped.
- **Test deferral:** Tasks 4–8 build classes that cannot be exercised without a root; their tests are concentrated in Task 9 against `TuiBinding`. This is deliberate and called out per task — it is not a placeholder gap. `flutter analyze` is the per-task gate for the untested-until-T9 tasks.
- **Type consistency:** slot for multi-child = previous-sibling `Element`; `RenderFlex.insert/move` take `{RenderBox? after}`; `dependOnInheritedWidgetOfExactType` returns `T?`; `markNeedsLayout` is public on `RenderObject` and reachable from `widgets.dart`.
- **Library-compile ordering:** because `widgets.dart` is one `part` library, each task adds its `part` line and must leave the library analyzable. If Task 4 and Task 5 cannot analyze independently (Element references `BuildOwner`), commit them together — noted in Task 4 Step 3.
