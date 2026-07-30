# Monorepo packages, and laziness by subscription

**Date:** 2026-07-26
**Status:** Design agreed in discussion. Slice 1 below is the committed scope.
**Extends:** `2026-07-25-overhaul-master-plan.md` (decisions 1–9 still hold).
**Prompted by:** M1's shell opening the wrong directory, and a dependency
count that was already wrong for a workspace.

## Why now

Two bugs, both from the same wrong assumption — that one directory is one
package is one project.

**1. The shell opened the repo, not the project.** `ShellController.start`
matched the launch directory against `git worktree list`. Launched at
`examples/example`, git reports the *repo's* worktrees, nothing matched, and it
fell back to the repo root — which has no `tool/flutterware.dart`. Result: a tab
named after the repo branch and an empty sidebar.

**2. Dependencies reports nonsense in a workspace.** This repo is a pub
workspace: one `pubspec.lock` and one `.dart_tool/package_config.json` at the
root, none in the members. `DependenciesService` does
`PubspecLock.load(<package dir>)`, finds nothing, so `lockDependency` is null
for every package, so:

```dart
bool get isTransitive => lockDependency?.type == DependencyType.transitive;
bool get isDirect => !isTransitive;   // ⇒ everything is "direct"
```

Pointed at `examples/example` it reports **170 direct, 0 transitive**. The real
answer is 14 direct; 170 is the whole workspace's resolution. The existing
`//TODO(xha): upgrade for workspace support` is this.

So a plugin is *already* wrong because it assumes one package per directory.
Encoding that assumption into three more plugins is the thing to avoid.

## The model

### The unit is the repo root

A worktree tab is a **worktree root**, not a project subdirectory. Launching
from anywhere inside the repo **walks up** to the root — the same idiom the
distribution design already uses to find `flutter_version`. One window per repo,
regardless of where you started.

`tool/flutterware.dart` lives at that root. One config file.

### Packages are declared, not inferred

Discovery still runs (from `workspace:`, else a bounded scan) but only as
**reference data**: it validates declared paths and warns on a typo. Nothing is
active unless the config names it.

```dart
const admin  = Pkg('packages/admin',  tags: ['client-a', 'ui']);
const app    = Pkg('packages/app',    tags: ['client-a']);
const server = Pkg('packages/server', tags: ['client-a']);
```

Declared once as values, so a path is written once and a typo is a compile
error. Tags live here — not on the per-plugin entries, where they would drift.

### Each plugin defines its own per-package entry type

Because per-package configuration is plugin-specific: a catalog needs an
entrypoint, a server needs a start command. The framework requires exactly one
field, `path`, which is the join key for validation and (later) tag filtering.

```dart
abstract class PluginPackage {
  const PluginPackage(this.pkg);
  final Pkg pkg;
  String get path => pkg.path;
  Map<String, Object?> toJson();
}
```

Everything else is the plugin's business, and it serialises through the existing
`Plugin.config` map — no framework change.

> **Superseded 2026-07-30.** `fw.packages([...])` is gone. It was a second
> declaration of what the plugins below already name, and the host filtered each
> plugin's packages against it — so a package the list forgot was *silently
> dropped* from a plugin that had been explicitly configured with it, which is
> the one failure a declaration list exists to prevent. `PluginManifest.packages`
> is now derived from the plugin entries, and the typo check covers every path
> any plugin names. `Pkg.tags` went with it: nothing ever read it, and with the
> package list derived there was no longer anywhere for it to travel. Tag
> filtering, if it lands, adds the field back and rewrites the config files that
> want it — which the original "ship the syntax early" argument was trying to
> avoid, and which is cheap next to carrying an unread field indefinitely. The
> `Pkg` values and per-plugin lists below are otherwise unchanged.

```dart
void main() => Flutterware.configure((fw) {
  fw.use(Git());                                    // repo-scoped, no packages
  fw.use(UiCatalog(packages: [
    .new(admin, entrypoint: 'lib/catalog.dart'),    // dot shorthand, verified
    UiCatalogPackage(app),                          // or explicit — same API
  ]));
  fw.use(Server(packages: [
    .new(server, command: 'dart run bin/server.dart', port: 8080),
  ]));
  fw.use(Dependencies(packages: DependenciesPackage.each([admin, app, server])));
});
```

`.each(...)` is an **auto-include affordance offered per plugin**, not a
framework rule: `UiCatalog` and `Dependencies` can default sensibly, `Server`
cannot, so `Server` does not offer it.

Dot shorthand was verified against the pinned SDK (3.13.0-103.1.beta); `.new`
and named constructors both compile. It is a call-site choice, so the API is the
same either way.

### Composing several config files

Not a mechanism — the config is Dart:

```dart
import '../packages/app/tool/flutterware_part.dart' as app;

void main() => Flutterware.configure((fw) {
  fw.use(Git());
  app.configure(fw);          // the package contributes its own plugins
});
```

One entry point, one manifest, no merge rules.

## Laziness is subscription

An earlier draft of this design had a `PluginDemand` object with per-package
`DemandLevel`s pushed by the shell. **Dropped** — it was a hand-rolled, worse
`Listenable`. The codebase already has the right idiom
(`async_value.dart:165`):

```dart
void addListener(VoidCallback listener) {
  _value.addListener(listener);
  if (!_isInitialized) refresh();   // work starts on first listener
}
```

So the whole model is:

> **Work starts when something subscribes to a source, and stops when the last
> subscriber leaves.** In the GUI, widget lifecycle supplies that for free.

Which gives the required behaviour with no framework at all:

| What | Why it is lazy |
|---|---|
| Non-selected worktree | its sidebar rows are not mounted, so nothing subscribes |
| Non-selected plugin | its panel is not mounted |
| Non-selected package | the panel subscribes only to the package it shows |
| Switching package | old subscription released, new one started |

### The one rule that makes it hold

> **`PluginReport` is a pure read of cached state. It must never trigger work.**

That is what makes it safe to call `report` for every plugin × package ×
open worktree — which the sidebar, the tab glyphs, `fw` and an agent all do.
A plugin with nothing cached reports "not computed" rather than computing on
the spot.

Two consequences to accept honestly:

- A tab glyph for a worktree nobody has looked at shows nothing, not a status.
- `DependenciesPlugin` is currently wrong twice: it subscribes **in its
  constructor**, and its `report` therefore reflects work it started eagerly.
  The subscription moves into the widget.

Demand says what work is *justified*, not what must be *discarded*. A plugin may
keep a warm cache after its last subscriber leaves — S1 measured a warm embedder
guest at ~120ms versus a cold start, so dropping it on every tab switch would be
self-defeating. "Keep the last N warm" is a plugin policy, not a framework rule.

## Sidebar children

`PluginReport` gains sub-entries so a plugin with N packages can show a
breakdown. Pure data, so the CLI and an agent get it too.

```dart
class PluginChild {
  final String id;        // the package path
  final String label;
  final Status status;
  final Badge badge;
}
```

`Tests · 3 failing` collapsed; `admin ✓ / app 3 failing / server ✓` expanded.
Selecting a child is what mounts that package's view — so children and laziness
are the same mechanism seen from two sides.

## What changes in the code

| | |
|---|---|
| `ShellController.start` | walk up to the repo root instead of matching the launch dir |
| `PluginHost.project` | → `workspace` (root + declared/validated packages) |
| `Workspace` | new: package identity only, **no services**; `projectFor(pkg)` builds and caches a `Project` on demand |
| `Project` | stays per-package; constructed lazily rather than one-per-worktree |
| `PluginReport` | gains `children`; documented non-triggering |
| `NativePlugin` | no work in constructors |
| `DependenciesPlugin` | workspace-aware resolution; subscribe from the widget |
| `package:flutterware` | `Pkg`, `PluginPackage`, per-plugin package types |

`Project` is deliberately **not** dismantled in this slice. It is a god-object
holding every service eagerly, and per-package × per-worktree that is a lot of
objects — but making `Workspace` construct them on demand gets the laziness
property without the churn. Revisit when a second package-scoped plugin exists.

## Slice 1 — the committed scope

**In:**

1. Repo root as the unit, with walk-up. Fixes the empty-sidebar bug.
2. `Pkg`, `PluginPackage`, per-plugin package lists, `fw.packages([...])`.
   *(2026-07-30: the `fw.packages([...])` call is removed — see the note above.)*
3. Package discovery as reference data + typo warnings.
4. `Workspace` on `PluginHost`, lazily building `Project`s.
5. The non-triggering `report` rule, enforced by moving subscriptions into
   widgets. Fix `DependenciesPlugin`.
6. `DependenciesPlugin` reads workspace resolution correctly — the 170/0 bug.
7. A root `tool/flutterware.dart` for this repo, declaring its three members.
   flutterware's own repo becomes the monorepo test case.

**Out, deliberately:**

- `PluginReport.children` and per-package sidebar rows → slice 2, with the UI
  catalog, which is the first plugin that genuinely needs them. Dependencies
  aggregates for now.
- Tag **filtering**. The `tags:` syntax ships in slice 1 so config files do not
  need rewriting; the filter itself is host-side and additive.
- Dismantling `Project`.
- Anything CLI — see below.

## The AI layer — what we preserve, and what we cannot yet know

There is no `fw` CLI, so reasoning about the AI layer in the abstract is
speculation. This slice therefore commits to **preserving** it rather than
building it:

- `report`, `PluginView`, `PluginChild` stay pure data with no colours, widgets
  or closures (decision 2).
- Work is reachable by *subscription*, and a widget is only one kind of
  subscriber. A CLI can subscribe for the duration of a request and release —
  same source, same laziness, no GUI required. That is what keeps decision 1
  ("no renderer is privileged") true rather than aspirational.
- ~~The honest consequence: `fw status` on a cold app reports "not computed" for
  anything nobody has looked at. Eager computation should be explicit
  (`--compute`), never implicit — a CLI invocation must not silently compile 30
  packages.~~

  **Wrong, and corrected in the code on 2026-07-28. Do not reinstate it.** This
  was written before `fw` existed, and it guessed at a cost that no core has.
  A `fw` process starts cold *every* time, so "report only what is cached" meant
  `status` printed "not computed" for every package on every run — the config
  file read back rather than a status. The flag did not gate expensive work; it
  gated whether the command answered at all.

  Measured once both cores existed: `computeAll()` across this repo is **~430ms**
  — three packages of pubspec parsing plus two catalog scans — against **~4.2s**
  of `dart run` startup to invoke the command offering the flag. It never
  compiled 30 packages because it never compiles anything: the compile loop is
  panel-side (`UiCatalogCore.track` declines to start it), and screenshots, pub
  scores and import graphs are all behind actions.

  `fw status` and `flutterware_status` now load, then report. The rule that
  survives is the one above about `report` itself — reading is free, which is
  what the GUI needs to read one per sidebar row per frame. That was never a
  reason to make a CLI caller ask twice. `computeAll()`'s budget is stated on
  the method: parse files, never compile, spawn nothing, no network.

**The cheap way to stop speculating:** a ~50-line dev tool that loads a
worktree's manifest and prints every plugin's `report.toText()`. It needs no
daemon and no GUI, and it would tell us within an hour whether the projection is
actually useful to read or whether it needs different bones. Proposed as the
first thing in slice 2, before any real CLI design.

## Open questions

1. Does a package sub-view get its own panel, or does the panel switch content
   internally? Agreed to discover this while building slice 2.
2. Whether `Workspace` should expose discovered-but-undeclared packages at all
   (to offer "add this to your config"), or stay silent about them.
3. What a plugin shows when its declared package list is empty — settled as
   shown-but-idle, same reasoning as `MissingPlugin`.
