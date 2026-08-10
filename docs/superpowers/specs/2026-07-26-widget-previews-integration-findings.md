# Flutter widget previews — integration findings

**Date:** 2026-07-26
**Status:** Investigation complete. Feeds `2026-07-26-ui-catalog-entry-model.md`.
**SDK under test:** `3.45.0-0.1.pre` (`/Users/xavier/fvm/versions/3.45.0-0.1.pre`)
**Question:** should the UI catalog align behind
[`@Preview`](https://docs.flutter.dev/tools/widget-previewer), and if so, at
which layer?

## Verdict

**Align at the annotation layer. Do not align at the discovery or runtime
layers.**

"Align behind the Flutter team's work" turns out to be three separable
decisions, and they have different answers:

| layer | adopt? | why |
|---|---|---|
| **annotation syntax** | **yes** | converges vocabulary, gets the IDE preview tab for free, and `transform()` is a better extension hook than anything we would have invented |
| **discovery mechanism** | **no** | theirs is resolved analysis — **17.3s** for the first unit on a real project; ours is a **478ms** syntactic parse of the whole package |
| **runtime** | **no** | theirs is web/Chrome only — no `dart:io`, no `dart:ffi`, no plugins, no screenshots, no programmatic driving. Adopting it discards everything S1 established |

## What `@Preview` actually is

`packages/flutter/lib/src/widget_previews/widget_previews.dart`, 437 lines. The
annotation carries **eight** fields:

```dart
const Preview({
  String group = 'Default',
  String? name,
  Size? size,
  double? textScaleFactor,
  WidgetWrapper? wrapper,        // Widget Function(Widget) — no BuildContext
  PreviewTheme? theme,
  Brightness? brightness,
  PreviewLocalizations? localizations,
});
```

Plus `MultiPreview` (one annotation → many previews), `PreviewBuilder` (with
`addWrapper()`, which **composes** rather than replaces), and `transform()`.

Constraints, from the doc comments:

- applies to top-level functions, static methods, or public constructors and
  factories **with no required arguments**;
- must return `Widget` or `WidgetBuilder`;
- all annotation values must be **const**, and callback parameters must be
  **static and non-private**.

And, in the source at line 23:

> `NOTE: this interface is not stable and **will change**.`

*Owner's call, 2026-07-26: accepted. `Demo` ships in `package:flutterware`
anyway — stability is not a concern at this stage. The consequences to keep in
view are an SDK floor of 3.35+ on the published package, and upstream churn
surfacing as a break in our public API. Both are revisitable by moving the class
to a companion package later; nothing in the design depends on where it lives.*

## The finding that decided the architecture

`preview_code_generator.dart` has **two** paths, and neither one interprets the
annotation's meaning statically:

```dart
// resolved path, line 292 — DartObject converted BACK into a source expression
_kTransformedPreview: preview.previewAnnotation.toExpression().property('transform').call([])

// LSP path, line 333 — the annotation's raw SOURCE TEXT, emitted verbatim
_kTransformedPreview: cb.CodeExpression(cb.Code(preview.previewAnnotation))
    .property('transform').call([])
```

The resolved path constant-evaluates the annotation into a `DartObject`
(`preview_details.dart:50`), then an `extension on DartObject { Expression
toExpression() }` converts those values **back into literal source**, emits them
into generated code, and calls `.transform()` at runtime. The static values are
discarded.

So resolution buys them exactly two things — knowing the annotation is a
`Preview` subtype (**identity**), and being able to reconstruct an expression.
Not **semantics**.

The LSP path skips even that: annotation as text, evaluated by the app.

> **Nobody interprets `@Preview` statically — not us, not Flutter.** Semantics
> are always evaluated as Dart, at render time. Our design is their second
> implementation, not a divergence from their first.

This is what makes syntactic discovery viable, and it is why custom annotation
subclasses and shared `const`s cost us nothing despite refusing resolved
analysis.

## Measurements

All on the reference project's web-app package — a real ~300-entry catalog.

| operation | scope | cost |
|---|---|---|
| syntactic prefilter (read + substring) | 180 files | **20ms** |
| **full syntactic parse** (`parseString`, no resolution) | **778 files** (`demo/` + `lib/`) | **478ms**, 0 parse errors |
| `AnalysisContextCollection` setup | — | 175ms |
| **first resolved unit** | 1 file | **17 299ms** |
| each subsequent resolved unit | 179 files | ~26ms (4653ms total) |

Resolving *any* file requires the linked element model of its whole transitive
closure — the same `package:server` closure that costs 9s in the CFE, paid again
in the analyzer. **Resolved analysis is not a cheap alternative to compilation;
it is more expensive than compiling the entire catalog** (12.9s, see S3).

The 478ms parse also yields, from the same traversal, **1177 `class X extends Y`
edges** and a full annotation histogram (`override(2180)`, `immutable(7)`, …) —
which is what makes registration-diagnostics free.

## Declaration-shape hazard (measured)

An alternative to annotations was a named top-level declaration
(`final myDemo = Demo(...)`). It is **incompatible with hot reload**:

```
before : final[cfg=CFG-1 build=built-V1]  getter[cfg=CFG-1 build=built-V1]
after  : final[cfg=CFG-1 build=built-V1]  getter[cfg=CFG-2 build=built-V2]
```

A top-level `final` is lazily initialised once, and **hot reload does not re-run
the initialiser of an already-initialised static**. The entire declaration
freezes — config, variants, and builder. A getter is fully live.

Annotations are `const` and re-evaluated per render, so they sidestep this
entirely. The hazard remains worth documenting for anything a *project* holds in
a top-level `final` (mock data, fixtures) — it is the same trap
`starting-ui-task` records for `late final` instance fields, one scope up.

## What widgetbook does, and why we differ

Annotation plus codegen: `@UseCase(name:, type:)`, `build_runner` generates
`widgetbook.directories.g.dart` next to the entrypoint, and **hierarchy is
derived from folder structure** — the navigation mirrors the app's directory
layout. ([generator](https://pub.dev/packages/widgetbook_generator),
[annotations](https://docs.widgetbook.io/guides/annotations))

The structural difference: **widgetbook needs codegen because it has no
daemon.** Its app is a plain Flutter app, so the entry list must exist as a
checked-in file. We generate the entrypoint lazily anyway, so the dev loop needs
no `build_runner` and no `.g.dart`.

Their path-derived hierarchy is also evidence for dropping our map: the reference project's
folders already mirror its hand-written tree.

| map path | file |
|---|---|
| `Desktop / Developer Console / List / Environments table` | `desktop/developer_console/list/environments_table.dart` |
| `Mobile / Team / Avatar tile` | `mobile/team/avatar_tile.dart` |

## `@Preview`-only: what survives, what doesn't

Explored as the *sole* model, then refined. Most objections dissolved:

| concern | outcome |
|---|---|
| global axes (theme, locale) have no `@Preview` equivalent | **solved** — the `const` restriction applies to the annotation *argument*, not the wrapper's body. `wrapper: DemoApp.wrap` constructs a widget whose `build` has a `BuildContext` and can read live pickers |
| depending on an unstable, 3.35+ API | **solved architecturally** — syntactic discovery means the *tool* never imports `widget_previews.dart`. (We now import it anyway for `Demo`, by choice, not necessity) |
| knobs (`parameters.*`) | **solved** — same wrapper mechanism; they no-op outside our host |
| device frames / orientation | **mostly solved** — device is a runtime axis chosen in the toolbar, not per-entry context; only `size` is layout-determining |
| curated hierarchy depth | recovered by path-derivation |
| stable ids | **real** — `@Preview` has no id field; hence `id:` on our subclass |
| arbitrary metadata (Figma) | **real** — hence `figma:` on our subclass |
| migration cost | **real** — no-required-args forces parameterised demos into zero-arg functions |

**Graceful degradation already ships.** `Parameters` (the base class) returns
`defaultValue` from every method, and `UICatalogState.of(context)` falls back to
`UICatalogState.empty` when no provider is present. `ui_catalog_test.dart`
already depends on this to render every entry headlessly. Flutter's previewer
becomes a *third* host of the same mechanism at zero cost.

**Precondition for dual-host:** the demo closure must be web-safe — Flutter's
previewer is Chrome-only and `dart:io`/`dart:ffi` throw there. the reference project already
satisfies this, since it builds the whole catalog to web for per-PR links.

## Honest limits

- Recognising project-defined annotation subclasses syntactically is an
  **approximation**. Bare-name matching can collide; import prefixes need the
  file's import list; type aliases are not `extends` edges; and classes declared
  in pub-hosted dependencies are outside the scanned roots. Flutter's
  `DartObject.type` handles all of these correctly — that is what the 17.3s
  buys. Our answer is registration (deterministic) plus a closure-based
  diagnostic (catches omissions).
- Nothing here was run against Flutter's actual previewer. The dual-host claim
  is derived from reading `flutter_tools`, not demonstrated end to end.
- `transform()` was read, not exercised. The claim that both code-gen paths call
  it is from source (lines 292, 333), not from a running previewer.
