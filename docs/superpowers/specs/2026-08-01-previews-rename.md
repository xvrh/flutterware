# Previews: the rename, and the end of `@Demo`

**Date:** 2026-08-01
**Status:** **Implemented** 2026-08-01 — P0–P4. **Breaking, with no deprecation path** — `@Demo` is
deleted outright and `@Preview` becomes the only way to declare a preview.
**Cause:** the tool is named after a category (`UI catalog`) that you have to
already know to search for, and it requires an annotation of our own (`@Demo`)
to enter. Somebody who wrote `@Preview` because flutter.dev told them to, and
then hit "Chrome only, no plugins, no `dart:io`", does not find us and could not
use what they already wrote if they did.
**Evidence:** read from this checkout, 2026-08-01, and from the pinned SDK
(`3.47.0-0.1.pre`). Counts are `grep` over `examples/`, `app/`, `lib/`, `test/`.

## `@Demo` goes away

`Demo extends Preview` (`lib/src/ui_catalog/demo.dart`, deleted here) adds three fields, and all three
leave. The audit, in-tree:

| field | uses | verdict |
|---|---|---|
| `formFactor` | **7** | the whole form-factor system is removed for now, to be reintroduced properly later |
| `id` | **0** | derivable; needed only to disambiguate stacked annotations |
| `figma` | — | **unreachable.** `discovery.dart` never reads it, `CatalogEntry` has no field for it, and `transform()` drops it |

Against 91 `@Demo` sites. With all three gone the class has nothing left, so the
class goes too.

**`FormFactor` does not go with it** — corrected 2026-08-01, against the first
draft. The enum has a second life the audit missed: the legacy in-app catalog
uses it as its own device-bucket vocabulary, through `FormFactorPicker`
([`app.dart:21`](../../../lib/src/ui_catalog/app.dart)) and a mapping to `Devices.android.smallPhone` /
`Devices.windows.laptop` ([`index.dart:96`](../../../lib/src/ui_catalog/index.dart)). Neither reads `FormFactor.size`,
which exists only for `Demo.transform()`.

So the enum **moves rather than dies**: out of `demo.dart` into the legacy tree,
losing its `Size`, and staying exported from `ui_catalog.dart` — which is
exactly [the split](#the-old-catalog-keeps-its-name-permanently) doing its job.
The annotation loses `formFactor`; the old catalog keeps a `FormFactor` that was
always its own.

The point is not the deletion, it is what the deletion buys: **a preview file
imports `package:flutter/widget_previews.dart` and nothing of ours.** A project
that already writes `@Preview` opens in flutterware with no edit to its source
and no line in its pubspec. Our dependency becomes incremental — you pay it when
you want a shell or knobs, not to see your first preview.

### And a plain `@Preview` does not work today

`previewAnnotations` defaults to `['Preview', 'Demo']`
([`authoring.dart:20`](../../../app/lib/src/previews/authoring.dart)), so a plain `@Preview` **is discovered** — and then
[`catalog_wrapper.dart:70`](../../../app/lib/src/previews/catalog_wrapper.dart) emits

```dart
Demo get fwDemo => Preview(name: 'x');   // compile error
```

Same in [`web_app_generator.dart:120`](../../../app/lib/src/previews/web_app_generator.dart), `_entry(Demo demo, …)`. Both call
nothing but `.transform()`, which is on `Preview`. `@Preview` appears exactly
once in the tree — in a discovery *unit test* ([`discovery_test.dart:100`](../../../app/test/previews/discovery_test.dart)) — so
the "one declaration serves both hosts" claim in [the 2026-07-26
findings](2026-07-26-widget-previews-integration-findings.md) has never been
exercised end to end. It holds in the direction that does not matter (our
`Demo` works in Flutter's previewer) and fails in the one that does.

Two type annotations are the whole fix, and it is the change with the most
leverage in this document.

## D1 — the name is `Previews`

The plugin becomes `flutterware.previews`, labelled **Previews**. An entry is
**a preview**. The annotation is `@Preview`. Two words, each with a job.

Rejected: **`Widget Previewer`** is Flutter's own product name verbatim
(`flutter widget-preview`, docs.flutter.dev/tools/widget-previewer) — taking it
reads as claiming to be theirs, and imports their churn, which the source still
advertises as *"this interface is not stable and will change"*.
**`Previewer`** is tool-shaped: a thing that previews, without saying what you
get. **Keeping `UI catalog`** loses the search path that people actually
arrive on.

`Previews` is also the only candidate that fits the naming system already in
use. Every sibling plugin is a plural content noun or a bare activity noun —
`Dependencies`, `Assets`, `Scenarios`, `Run` — the name of what is in there,
not the name of a tool.

| now | after |
|---|---|
| `flutterware.ui_catalog` | `flutterware.previews` |
| label `UI catalog` | `Previews` |
| `fw run ui_catalog entries\|new\|inspect` | `fw run previews …` |
| `UiCatalog(packages: [UiCatalogPackage(…)])` | `Previews(packages: [PreviewsPackage(…)])` |
| `@Demo`, "a demo" | `@Preview`, "a preview" |
| `CatalogShell` | `PreviewShell` |

### The old catalog keeps its name, permanently

Not a deprecation shim — a different thing that happens to have had the same
name. The in-app `UICatalog` widget, `Figma`, `package:flutterware/ui_catalog.dart`
and everything under `lib/src/ui_catalog/` **stay called `ui_catalog`**. That is
a browsable page you ship inside your own app, and *catalog* is the right word
for it. **Previews is the tool; the UI catalog is a widget that hosts previews
as a shippable page.**

Which means the two are told apart in this change rather than over a release,
and the published libraries split by *who writes them*:

| library | holds | written by |
|---|---|---|
| `previews.dart` | `PreviewShell`, `TopBarState`, `PreviewState`, `context.previews` | a preview author |
| `ui_catalog.dart` | `UICatalog`, `UICatalogStateProvider`, `Figma`, `FormFactor`, `context.uiCatalog` | an app shipping a ui_book page |
| `previews_guest.dart` (was `ui_catalog_guest.dart`) | guest plumbing | generated code only |

The dependency runs from the catalog to Previews, not the other way, and that is
already the architecture: [`web_app_generator.dart`](../../../app/lib/src/previews/web_app_generator.dart) hosts the old `UICatalog`
widget deliberately — *"It hosts the old `UICatalog` widget, and that is not a
stopgap"* — to render previews as a page. A host importing the authoring API is
the right direction.

**The one name that is genuinely shared is knobs.** `context.uiCatalog.parameters`
is written on both sides today: in [`ui_book.dart:36`](../../../examples/example/lib/ui_book.dart) (the old catalog) and in
previews like [`knobs.dart:18`](../../../app/tool/catalog/demos/knobs.dart). It resolves as one state class with two
accessors — `UICatalogState` becomes `PreviewState`, `previews.dart` adds
`context.previews`, and `ui_catalog.dart` keeps `context.uiCatalog` over the same
state. Three lines, and neither half reads wrong: a preview says `previews`, a
ui_book says `uiCatalog`, and no existing ui_book changes.

## D2 — `Demo` is deleted, not deprecated

No `@Deprecated` release. The class and the `show Demo` export from
[`ui_catalog.dart`](../../../lib/ui_catalog.dart) go in one change, and `previewAnnotations` defaults to
`['Preview']` alone. (`FormFactor` stays, relocated — see above.)

A deprecation window is worth its cost when it lets a large existing user base
move on its own schedule. Here it would keep two annotations, two dartdocs and
two answers to "which one do I write" alive across a release — while the entire
purpose of the change is that there is exactly one way to declare a preview.
The package is pre-1.0, and the migration is a rename plus dropping arguments.

`previewAnnotations` stays configurable, so nothing about this stops a project
declaring its own annotation (see [D5](#d5--the-class-goes-the-scanner-does-not-change)).

## D3 — `figma` is removed

Nothing reads it. The Figma feature that exists belongs to the legacy in-app
catalog and stores its links in a sidecar JSON ([`links_source_io.dart`](../../../lib/src/ui_catalog/figma/links_source_io.dart)), keyed
independently of the annotation. An annotation field nothing consumes is worse
than no field: it is a promise in the dartdoc that a reader will act on.

## D4 — `id` is removed; derivation covers the gap

Zero in-tree uses. `CatalogEntry.id` already derives `path#symbol`
([`catalog_entry.dart:62`](../../../app/lib/src/previews/catalog_entry.dart)) and `declaredId` only overrides it.

The one place `id:` is *forced* today is stacked annotations: two `@Demo`s on
one declaration derive the same id, and `_rejectDuplicateIds`
([`discovery.dart:248`](../../../app/lib/src/previews/discovery.dart)) escalates that to a scan error. Stacking is a supported
way to spell variants, so the requirement bites exactly where the feature is
used.

**Derive an ordinal instead:** the second and later annotations on one
declaration get `path#symbol#1`, `#2`. Deterministic, no declaration, and the
error stops existing. The cost, written down rather than smoothed over: **an
ordinal id changes if you reorder the stack**, so a stored address to the second
variant follows the position rather than the entry.

## D5 — the class goes, the scanner does not change

Deleting `Demo` removes three fields from our published surface. It removes
nothing from the *scanner*: `_literalString` asks for an argument by name and
does not care what class the annotation is ([`discovery.dart:287`](../../../app/lib/src/previews/discovery.dart)).
`declaredId` stays on `CatalogEntry`, and `id:` keeps being read.

So a project that wants any of it back writes its own five lines —

```dart
base class Demo extends Preview {
  const Demo({this.id, this.figma, super.name, super.group, super.wrapper});
  final String? id;
  final String? figma;
}
```

— and registers `'Demo'` in `previewAnnotations`, already plumbed from the
scanner to the wire. **A name we read, not a class we ship.** That is what makes
shrinking our published surface cost a project nothing, and it is the standing
answer to every future request for one more annotation field.

## The work

**P0 — plain `@Preview` compiles. Landed 2026-08-01.** `Preview` instead of `Demo` in
[`catalog_wrapper.dart:70`](../../../app/lib/src/previews/catalog_wrapper.dart) and [`web_app_generator.dart:120`](../../../app/lib/src/previews/web_app_generator.dart). A fixture with a
plain `@Preview` rendered end to end — through `entries`, `inspect` and a
capture — because the test that exists today asserts discovery and nothing
downstream of it.

Also here, same silent-failure class: an unregistered `MultiPreview` subclass is
never found, and a registered one produces
`Preview get fwDemo => BrightnessPreview()` — a compile error with no
explanation. A scan diagnostic naming it is a few lines.

**P1 — the class goes. Landed 2026-08-01.** `Demo` and `demo.dart`, the `show Demo` export, the
`['Preview', 'Demo']` default. `FormFactor` moves to the legacy tree without its
`Size` and keeps its export. `figma` and `id` stop being fields; ordinal
derivation lands in `discovery.dart`, and `_rejectDuplicateIds` keeps rejecting
two *declared* ids that collide while no longer rejecting derived ones.

The form-factor plumbing goes with it, end to end: `_enumName`
([`discovery.dart:302`](../../../app/lib/src/previews/discovery.dart)), `CatalogEntry.formFactor`, `defaultDeviceFor`
([`devices.dart:30`](../../../app/lib/src/previews/devices.dart)), the `formFactor` fields on
[`ui_catalog_results.dart`](../../../app/lib/src/plugins/native/previews_results.dart) and the generated action shapes. `resolveDevice`
collapses to `deviceById`. Dead code kept warm for a future feature is worse
than code deleted and rewritten when the feature arrives.

**P2 — the rename, and the split. Landed 2026-08-01**, including the internal paths that this originally deferred. Plugin id, label, action names,
`PreviewsPackage`. `CatalogShell` → `PreviewShell` immediately, no typedef.
`UICatalogState` → `PreviewState`.

New `package:flutterware/previews.dart` taking `PreviewShell`, `TopBarState`,
`PreviewState` and a `context.previews` accessor; `ui_catalog.dart` keeps
`UICatalog`, `UICatalogStateProvider`, `Figma` and `context.uiCatalog`, and
loses the `Demo` export with P1. `ui_catalog_guest.dart` →
`previews_guest.dart`, and its dartdoc stops naming `Demo` as the semver
commitment.

`docs/capabilities.md` regenerates from the action descriptions.
`app/lib/src/previews/` and `app/lib/src/plugins/native/previews_*.dart` are
**not** renamed here — nothing outside reads those paths, and folding a large
mechanical diff into a behavioural one buys nothing. Everything under
`lib/src/ui_catalog/` that stays with the old catalog keeps its path for the
better reason: that is its name.

**P3 — the words. Landed 2026-08-01.** Every message in [`authoring.dart`](../../../app/lib/src/previews/authoring.dart) says "preview", not
"demo": the empty state, the scan diagnostics, the daemon's refusal, and the
scaffold `fw run previews new` writes. The scaffold's annotation becomes
`@Preview` and its `package:flutterware` import disappears — **the file a first
run produces has no dependency on us at all.** README and `fw init`'s scaffolded
config follow.

**P4 — migration. Landed 2026-08-01.** In-tree: 91 `@Demo` → `@Preview`, and 7 `formFactor:`
arguments dropped. `wrapper:`, `name:` and `group:` are all `Preview`'s own and
change nothing. No migration document: the change is a rename plus dropped
arguments on a pre-1.0 package, and the README, the authoring hint and this spec
already say what moved where.
Both pubspec versions bump together, per the note in the root pubspec.

### The regression this accepts

Seven previews lose their declared starting device, and
[`home_page.dart`](../../../examples/example/demo/home_page.dart)'s `'On a phone'` entry is the visible case: it starts
on the panel, unframed, until form factor returns. Picking the iPhone in the
toolbar is one click and was always what outranked the declaration anyway
([`devices.dart:20`](../../../app/lib/src/previews/devices.dart) — a device is never stored, and a choice outranks a
default). Accepted knowingly rather than papered over with a stopgap that would
have to be unpicked.

## Later — form factor, properly

Removed here, to be reintroduced as its own design once the shape is settled.
Nothing is proposed in this document. Two facts verified on 2026-08-01, as
groundwork:

- `formFactor` fed exactly one function. The scan read the enum's *name*, carried
  it as a plain string, and handed it to `defaultDeviceFor` — a one-line policy:
  `mobile` starts on an iPhone 13, everything else starts on the panel.
- The `Size` on the enum, and the `size:` that `transform()` filled from it, were
  **never read in flutterware**. [`entrypoint_generator.dart:232`](../../../app/lib/src/previews/entrypoint_generator.dart): *"No
  `preview.size` here. The host sizes the guest's window to whatever device is
  chosen […] The annotation still chooses which device the picker starts on."*
  `size:` is meaningful in Flutter's previewer and inert in ours.

## Not in scope

**The whole-package scan.** ~~A separate change.~~ **Landed 2026-08-01**, in
the same branch — see
[2026-08-01-root-scan-listing-findings.md](2026-08-01-root-scan-listing-findings.md)
for the measurements and the decisions. The default `roots` is now `['']`, the
package itself, and `directory:` narrows it.

*Corrected 2026-08-01: this first said ids move, and sequenced the work around
that. They do not. `CatalogEntry.path` is relative to the project, never to the
scan root, so widening `roots` left every existing id spelled as it was.*

**`MultiPreview` support.** Not a `Preview` subclass, and its expansion is a
*runtime* value: how many entries an annotation produces, and what each is
called, is Dart code we deliberately do not interpret. Everything downstream of
the scan assumes entries are known statically — including the GUI answering an
empty catalog from its own scan before a daemon exists.

The shape when it is wanted: **one entry, N runtime variants.** The annotation
stays one static entry with one stable id; the guest reports the expansion as an
axis through `CatalogAxes`, which already pushes runtime-discovered axes to the
panel; the address gains `?variant=`. Demand is currently zero — the SDK ships
no `MultiPreview` subclass, only a doc example and test fixtures. The
*diagnostic* is in scope (P0); the support is not.
