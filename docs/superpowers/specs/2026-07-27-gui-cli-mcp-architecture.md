# GUI / CLI / MCP — the shared architecture

**Date:** 2026-07-27, updated 2026-07-28
**Status:** Decisions 1–6 agreed in discussion. **1, 2, 4 and 6 are
implemented** — `Address`, `Artifact`, `ValueStream`, and the `Session` that
`fw` and the MCP server both render. **3** (the daemon contract) and **5**
(`reveal` vs `capture`) are pinned but unbuilt: there is no daemon holding a
run log yet, and no viewer to reveal into. See the "landed" sections at the
end for what exists.

**2026-07-28 session, in one line:** `fw` and MCP now run actions through one
`Session.invoke` — *not* the GUI, which dispatches nothing and calls its core
directly, as the landed section below already records (this line claimed "the GUI
included"; corrected 2026-07-30); the two actions we had turned out to do
nothing and were replaced by queries people actually wanted; a test now drives
`fw` and MCP over the same session and found three ways they disagreed; and what
an action returns is a typed class whose shape is read out of the source and
published to the document, to MCP and to `--help`. See "What running it taught
us" near the end. `docs/capabilities.md` is generated and lists what exists
today.
**Extends:** `2026-07-25-overhaul-master-plan.md` (decisions 1–10 hold),
`2026-07-26-packages-and-laziness.md`.

## Why now

The master plan's M2 ("the AI surface") sits after the shell and before the
flagship plugins, on the argument that a contract an agent already reads is
cheaper than a retrofit. This document is the same argument applied one level
down: the UI catalog is being built *today* with its own daemon and its own
entry addressing. Three primitives — an address, an artifact, a notification
type — cost almost nothing to adopt while it is being written, and cost a
migration afterwards.

It does **not** settle where plugin logic runs. That question is deferred on
purpose; nothing here depends on it.

## The parity rule, stated so it can be wrong

The requirement is usually phrased "everything doable in the GUI must be doable
from the CLI and MCP". That phrasing cannot be checked. This one can:

> **The GUI is not a required participant in anything except being looked at.**

Capabilities then sort themselves by which process they need, and only the last
row needs a window:

| Tier | Needs | Examples |
|---|---|---|
| **Manifest** | nothing — `dart run tool/flutterware.dart` | plugin list, actions, parameters, packages |
| **Report** | a client with the plugin logic linked | `PluginReport`, `PluginView` |
| **Job** | the daemon | compile, run a suite, capture a frame |
| **Viewer** | a running GUI window | "show the human this", "screenshot the window" |

The consequence worth naming: **"screenshot this catalog entry" is a job, not a
viewer capability.** `app/tool/catalog/headless_check.dart` already drives a real
guest with no window. An agent capturing an entry must never touch the human's
window, and the two must therefore be different verbs (decision 5).

## Locked decisions

### 1. `Address` — one URI for everything

```
fw:///worktrees/<worktree>/<plugin>/<plugin-specific path…>?<axes>
```

> **The framework parses up to and including `<plugin>`. Everything after is
> opaque to it and owned by the plugin.**

That rule is what keeps the address parser from growing a case per plugin. The
catalog picks its own entry addressing (a `Demo(id:)`, or a library path plus
symbol) without the framework knowing.

- **Path segments are identity. Query parameters are applied axes.** `theme`,
  `locale` and `device` are query, because the entry is the same entry seen
  differently. This answers master-plan open question 5 — *"screenshot an entry
  is under-specified without the resolved axis assignment"* — by construction:
  an address with its axes resolved **is** a complete capture spec.
- **Session-relative by default.** `fw:///ui_catalog/…` means "the session I am
  connected to, current worktree". The worktree segment, when present, is the
  worktree **directory name**, which git guarantees is distinct within a repo. A
  cross-repo absolute form is not specified until something needs one.
  *(Superseded: the relative form was never built and is deleted — see
  `2026-07-29-address-router-merge.md` §3 — and the worktree is now reached
  through a space segment, `2026-08-10-address-spaces-brief.md`. That spelling
  parses today as a space named `ui_catalog`.)*

One value class, a parser and a `toString`, in `package:flutterware` beside the
other pure-data plugin types. Consumed by: GUI routing (`router_outlet`), search
hits, `Artifact.address`, `fw show <address>`, MCP `show({address})`.

### 2. `Artifact` — what a job returns

The revised thesis of the master plan is that the real asks are *commands that
produce artifacts*. So an artifact is the return type, not a side effect.

```dart
class Artifact {
  final String kind;          // image/png, text/plain, widget-tree, application/json
  final String? path;         // .flutterware/artifacts/<id>
  final String? text;         // small ones inline
  final Address address;      // what it is of — axes included
  final Map<String, Object?> meta;  // timings, compile stats, exit code
}
```

The CLI prints the path, MCP returns an image content block, the GUI shows a
thumbnail. One object, three renderings. `address` is mandatory: an artifact that
cannot say what it is of is not reproducible.

### 3. The daemon executes and holds live resources. It does not remember.

> **The daemon may hold live processes, in-flight job registrations, and an
> append-only run log. Nothing else.** A field that is none of those three is a
> bug.

- **Live processes** — the resident compiler, guest engines, watchers, wrapped
  `flutter run` children. These are what is genuinely expensive to recreate.
- **In-flight jobs** — two clients asking for the same run join one execution
  rather than starting two. This is also what gives "the human watches the
  agent's test run" for free.
- **The run log** — append-only, one record per run: command, address, started,
  ended, exit code, artifacts. The shape `2026-05-15-wrapper-tool-architecture.md`
  §6 already specified for process supervision.

**Explicitly rejected: a keyed cache of derived results with invalidation.** It
was proposed in discussion and dropped. Two reasons:

1. **The warm process is the cache.** Measured (S3, and
   `2026-07-27-gui-slice-findings.md`): compile 5–10ms, reload 85–107ms, ~12ms
   on revisit, once the resident compiler is up. A result cache buys ~100ms and
   costs a generation-counter invalidation model with its own bug surface.
2. **Nobody asks for a stale result without knowing when it ran.** The queries
   that look like they need a cache — "are the tests passing?" — are really
   either *run them* or *what did the last run say, and when*. The first is a
   job. The second is a run-log read. Neither needs invalidation, because a run
   is a fact that happened; it gets old, it does not become wrong.

Consequence, accepted: a badge for a worktree nobody has run anything in shows
the last run and its age, or nothing. Nothing is computed to produce it. This
answers master-plan open question 4.

**Revised 2026-07-28, after reading the daemon that exists.** Three obligations
are listed here as if they belong to one process. They have three homes:

- **Live processes** — already the catalog's compiler daemon. Its address is
  derived from the whole `DaemonConfig`, so it *fragments* on every input that
  changes its output, which is right for a compiler and wrong for a run log:
  bump the SDK and a log living inside it has silently moved. So that daemon
  grows into a job executor, one of several, not into the registry.
- **In-flight dedup** — belongs inside whichever daemon owns the resource. In
  the compiler daemon that is a map of in-flight futures keyed by the request,
  replacing the bare `Future _queue`; `ifChanged` is today's poor-man's version.
- **The run log** — needs no process at all. Append-only JSONL with `O_APPEND`
  is safe for concurrent `fw`, MCP and GUI writers as long as no record needs
  two syscalls. Its embryo already exists in `wrap/session_sink.dart`, whose own
  comment promises the daemon will replace it; the promise is the wrong way
  round.

**So the first real daemon looks like less than a daemon**, and the per-repo
process arrives with the wrapper (PTY streaming, heartbeats, orphan sweeps),
where a resident writer is genuinely required. A screenshot does not need one.

**And the rule as stated flags correct code.** The daemon holds `_discovered`,
`_quarantine`, `_baseline`, `_hostPath` — none of them one of the three, none of
them wrong. They describe the live compiler, not memoised answers. What survives
contact: **no answer outlives the request that produced it; state describing a
live process is part of that process.**

Sequencing, after the 2026-07-28 session: this is the *least* urgent of the
three open threads. Nobody has asked "what did the last run say", and nothing is
slow enough for two clients to collide over. Pick it up when something concrete
asks.

### 4. `ValueStream` — one notification primitive, ours, stream-based

`AsyncValue` currently implements `flutter/foundation`'s `ChangeNotifier` /
`ValueListenable`, which is the single reason the plugin core cannot be loaded by
a plain Dart VM (`package:flutter` needs `dart:ui`). Measured on
`xha/overhaulrework`: of 235 files in `app/lib`, 101 import `package:flutter/*`,
and **14** import only `foundation`. What those 14 use:

| symbol | files | pure-Dart replacement |
|---|---|---|
| `ChangeNotifier` / `ValueNotifier` / `ValueListenable` | 12 | `ValueStream` |
| `compute` | 3 | `Isolate.run` |
| `ByteData` / `Uint8List` | 1 | `dart:typed_data` (foundation only re-exports it) |
| `debugPrint` | 1 | logger |
| `kDebugMode` | 1 | `bool.fromEnvironment` |
| `VoidCallback` | 1 | `void Function()` |

`package:listen` (flutter.dev, pure Dart, depends only on `meta`, 1.0.0-beta.4)
provides drop-in `ChangeNotifier` / `ValueNotifier` / `Listenable.merge` and was
the other candidate. **Rejected in favour of our own stream-based type**, for
three reasons in order of weight:

1. **The laziness rule of `2026-07-26-packages-and-laziness.md` is a broadcast
   stream's contract.** That document hand-rolls "work starts on first listener"
   in `AsyncValue.addListener`. `StreamController.broadcast(onListen:, onCancel:)`
   is that rule, built in, including the re-subscribe case. When the primitive
   you were about to hand-roll is already in the SDK, take the SDK's.
2. **Every interesting boundary here is a stream.** The daemon streams job
   events; clients merge them; GUI, CLI and MCP consume the same feeds. A
   callback `Listenable` crosses neither an isolate nor a socket, so choosing it
   means writing a stream adapter at every boundary and adapting back.
3. **Composition.** `switchMap` for "the selected worktree's results",
   combine-latest for a sidebar aggregating N packages. Notifiers do not compose
   without hand-written merge logic.

Costs accepted, and the shape that pays them:

- Broadcast controllers deliver in a microtask and drop events for late
  subscribers. So `ValueStream` is **not** raw broadcast: it keeps the latest
  value, replays it on subscribe, and exposes a synchronously readable `.value`.
- `Snapshot<T>{data, error, isLoading}` is kept as-is — it is the harder half and
  it is already right. This is `AsyncValue` turned inside out, not a new concept.
  11 files import it.
- One `ValueStreamBuilder` widget in the GUI layer. An adapter of this size was
  needed under `package:listen` too, since Flutter 3.45's foundation does not
  re-export it and `ListenableBuilder` would not accept its type.
- **Do not also take the `package:listen` dependency.** One primitive.

**`ValueStream` does not replace `AsyncValue`; it goes underneath it.** Reading
the code settled this. `AsyncValue` is not a notifier — it is a *loader-backed
value*: a `Future<T> Function()`, a `Pool(1)` serialising refreshes, three
`LoadingMode`s, `refreshOrThrow` / `refreshSilently` / `invalidate`, and a
`Disposable` chain that disposes the previous value when a new one lands. All of
that is worth keeping and none of it is notification. So the layering is:

```
ValueStream<T>              the primitive — latest value, sync read, onListen/onCancel
AsyncValue<T>               a loader over ValueStream<Snapshot<T>>
```

Worth recording, because it is an argument the earlier documents make and the
code does not yet keep: **`AsyncValue` implements only half the laziness rule.**
`addListener` starts work on the first listener; nothing stops on the last
`removeListener`. `StreamController.broadcast`'s `onCancel` is the missing half,
so this is a capability gain rather than a like-for-like port.

**Done 2026-07-27.** `AsyncValue` now holds a `ValueStream<Snapshot<T>>` and
imports no Flutter; `ValueStreamBuilder` is the one place the primitive meets
widgets. The migration also removed `compute` in favour of `Isolate.run` in the
three service files it touched — with the path read out into a local first, so
the closure captures a `String` rather than `this` (`Isolate.run` sends the
closure, and a `Project` cannot go).

Two behaviours preserved deliberately, because the UI is tuned against them:
`_setValue` still uses `value =` rather than `emit`, so an identical snapshot is
skipped exactly as `ValueNotifier` did; and the `Disposable` chain still
disposes the outgoing value.

One improvement fell out. `DependenciesPlugin.untrack` previously needed a
`host.workspace.isRealised(path)` guard, because removing the listener meant
calling `_sourceFor(path)` again — which would *realise* the package's services
just to unsubscribe from them. Holding a `StreamSubscription` removes the call,
so the guard is gone and untracking can no longer start the work it is trying to
release.

### 5. `reveal` and `capture` are different verbs

The GUI attaches to the daemon and registers a **viewer** capability.

| call | for | touches the human's window |
|---|---|---|
| `session.capture(address)` | agents | no — daemon renders in its own guest |
| `viewer.reveal(address)` | humans | yes — navigates the window there |
| `viewer.capture({window \| panel \| guest})` | agents, deliberately | no, reads only |
| `viewer.state()` → `Address` + `PluginView` | agents | no |

"One compiler, several guests" (S3) is what makes this affordable: the agent's
guest and the human's guest share the warm compiler, so an agent works without
stealing the viewport and the human can watch.

Two rules, because an agent silently moving someone's window is how a tool gets
uninstalled:

- `reveal` is **visibly attributed** in the GUI.
- `reveal` does not steal OS focus by default.
- `reveal` with no viewer attached is a **normal outcome**, not an error. The
  adapter reports "no viewer attached"; it is never why a task fails.

**Measured 2026-07-30: `viewer.capture({window})` is two captures composited,
not one.** The table above leaves `window`, `panel` and `guest` looking like
three framings of one screenshot. They are not, because a panel showing a guest
is **not in the host's layer tree**. `catalog_view.dart` renders it as
`Texture(textureId:)`, an external texture the platform compositor resolves at
raster time; `RenderRepaintBoundary.toImage()` rasterizes a layer tree
offscreen. A throwaway probe on macOS (chrome + border around a live guest, dpr
2.0, texture rect 1172×980 physical) confirmed the consequence: of 71785 samples
inside that rect, **1 distinct colour and 0 with alpha above zero**. Fully
transparent — the texture contributes nothing.

So `window` is:

1. `toImage()` for everything the host drew, which comes back with a hole;
2. the guest's own frame, over the embedder's existing `kMsgCapture` — the
   same message the headless catalog uses, aimed at the guest already on
   screen. This is now `EmbeddedEngine.capture`, ~20 lines, because the C host
   already armed a capture on request and only the Dart side was missing;
3. the second pasted into the first at the `Texture`'s rect, from its
   `RenderObject`.

Both frames came back at 1172×980 in the probe, so the paste is 1:1 with no
resampling, and the transparent hole means no clearing step. Worth taking
deliberately: **capture the guest at its own scale, not the host's.** The frame
is the guest's, so a doc screenshot can ask for 2× guest pixels inside a 1×
host raster.

**The OS-level alternative is rejected.** macOS `ScreenCaptureKit` captures the
real composited result and would need none of the above, at the cost of a
Screen Recording permission prompt, a window that must be visible and
unoccluded, and screen-scale dependence. That is a bad fit for `viewer.capture`
(the point of which is *"no, reads only"*) and a worse one for an unattended
script or CI. The composite needs no permission and does not care whether the
window is on screen.

Not established: this is macOS. Linux and Windows external-texture paths could
differ, though the reason is the same on all three. And the probe used the
fixed harness scene, not a catalog entry — the mechanism is identical, but no
catalog-specific layout was exercised.

### 6. One session library; `fw` and MCP are adapters over it

A pure-Dart `flutterware_session` that both `bin/fw` and the MCP server link.
There is never a second implementation of anything below.

```
connect(repoRoot) → Session          // auto-spawn; the DaemonAddress lock pattern
  .manifest()                        // tier 1, no daemon
  .report(plugin)                    // tier 2
  .invoke(plugin, action, args) → Stream<Event> → List<Artifact>
  .capture(address)                  // tier 3
  .viewer                            // tier 4, null when no window is attached
```

`DaemonAddress` already states the principle for the catalog daemon — *"every
consumer that wants the same catalog arrives at the same socket without being
told about each other"*. Generalise it; do not invent a second discovery
mechanism.

**Enforcement of the parity rule**, strongest to weakest, and we want the first
two:

1. **Structural.** A panel widget never calls plugin methods directly; every
   button dispatches `session.invoke(plugin, action, args)`. A GUI capability
   that is not a declared `PluginAction` is then not expressible. The lint-able
   form: *a panel widget with business logic in `onPressed` is a bug.*
2. **A contract test.** Walk every plugin's manifest; assert every declared
   action is invocable through `fw` and through MCP, and every address the GUI
   can route to resolves headlessly.

**Both landed on 2026-07-28.** `NativePlugin` has no `report` and no `invoke` to
override, so (1) is structural rather than a convention; and
`surface_parity_test.dart` is (2), walking the manifest and driving both
surfaces over one session. It found three ways they disagreed on its first runs
— see "A test that drives both surfaces". The addresses half of (2) waits on the
viewer. Note what it does *not* cover: reads. Both surfaces answering the same
way is checked; whether a plugin's data is reachable at all is not, which is how
two actions managed to do nothing for a week.

**Sequencing:** `Session` + `fw` together, against the two plugins that exist
today, before more plugins are written. MCP within days, not weeks — it is a thin
adapter, and having it early changes how actions get *designed*, because it shows
immediately which ones an agent cannot use from a name and a parameter list.

## Deliberately open

- **Where plugin logic runs.** Whether the pure-Dart core is instantiated
  per-client or hosted once. Nothing above depends on it, and it is easier to
  answer once `fw` exists and the cost of a cold client is a measurement rather
  than a guess.
- **The MCP tool surface.** One tool per action is the obvious mapping and
  probably wrong — 8 plugins × 6 actions is 50 tools in an agent's context on
  every request. The likely shape is a small fixed set (`status`, `search`,
  `actions`, `invoke`, `capture`, `show`, `read`) plus a few hand-written
  promoted tools for high-traffic actions, where a good name beats a discovery
  round-trip. Decide with a real client in front of us.
- **Cross-repo addresses.** Not specified until something needs one.

## Deferred

**Global search**, until the CLI exists. One constraint is worth carrying: the
rule is **not** "search reads only cached data" — that would be a bad search
engine.

This section used to elevate that into an aphorism — *a keystroke may never
start work, an intent may* — and it is **not load-bearing. Do not build on it.**
Read literally it is either trivial or wrong: it does not say what an intent is,
and the obvious reading (opening the palette is "just" a keystroke, so it must
not load anything) leads straight to a phantom tier of "cheap warming" methods
alongside `computeAll()` that separate things the code already separates. That
was attempted on 2026-07-28 and thrown away.

The concrete mechanics, which is all there ever was:

- **Opening the palette loads.** It is a deliberate act, it happens once per
  worktree per session, and `computeAll()` is bounded to parsing by its own
  contract (~430ms across this repo). Results **stream and merge** so a slow
  provider never blocks a fast one.
- **Typing filters.** Not because a rule forbids more, but because scans are
  cached and idempotent — re-running them per character would be pointless work,
  not dangerous work.
- **Enter escalates.** Compiling, screenshotting and grepping source are
  actions; they are invoked by name, and they were never inside `computeAll()`.

The line that actually matters is the one on `computeAll()`: parse files, never
compile, spawn nothing, no network. That is enforceable and it is where the
budget belongs. `fw search` and MCP `search` go straight to full — an agent
typing a query once has already expressed intent.

Search hits carry an `Address`, which is what makes them equally actionable in
all three surfaces — and is the reason search can be deferred without being
designed into a corner.

## Answered while building

**1. `ValueStream` vs `AsyncValue` — neither replace nor wrap: layer.** See the
end of decision 4.

**2. The run log is global; artifacts are repo-local.** The two were conflated in
the first draft and they have opposite requirements.

- The **run log** goes global, at `~/.cache/flutterware/registry/`, filtered by
  `project_root` — the shape `2026-05-15-wrapper-tool-architecture.md` §6 already
  specified. Its reason holds: interesting runs exist that belong to no project
  (a one-off script, a global CLI), and a per-repo log cannot hold them.
- **Artifacts** go repo-local, at `.flutterware/artifacts/`, because the consumer
  is an agent whose file tools are usually scoped to the repo. A screenshot in
  `~/.cache` is a path an agent frequently cannot open; one in the worktree is a
  path it already has. `Artifact.path` is therefore relative to the worktree root
  (`lib/src/plugins/artifact.dart`).

**3. A job's identity is `(executor, address, canonical args)` — with the full
address, axes included.** Two clients join one execution when all three match.
Axes are part of it: a dark-theme capture is not a light-theme capture, and
merging them would hand a client someone else's frame. This is exactly the split
`Address.bare` exists for — **`bare` keys trees and lists, the full address keys
work.** Canonicalisation is already handled: axes are sorted at construction, so
two clients that wrote them in different orders produce the same key.

## Open questions

1. Does a job's identity need to include an input generation, so that a client
   arriving mid-run against changed sources starts a new run rather than joining
   a doomed one? Deferred until a job slow enough to matter exists.
2. `.flutterware/` needs a `.gitignore` policy — artifacts are build output, but
   the directory may later hold committed things.

## First steps, landed

The three primitives, and nothing else. Each is pure data or pure `dart:async`,
so none of them commits to where plugin logic runs.

| | |
|---|---|
| `lib/src/plugins/address.dart` | `Address`, exported from `package:flutterware`'s `plugins.dart` |
| `lib/src/plugins/artifact.dart` | `Artifact` |
| `app/lib/src/utils/value_stream.dart` | `ValueStream` |
| `test/plugins/address_test.dart`, `test/plugins/artifact_test.dart` | 23 tests |
| `app/test/utils/value_stream_test.dart` | 13 tests, including the laziness rule |

Two decisions made at the keyboard rather than in the design:

- **`Address` is parsed by hand, not by `Uri`.** `Uri.parse` lowercases the
  authority, and a worktree directory may legitimately have capitals — a
  worktree named `Feature-X` would silently become `feature-x` and stop
  resolving. Covered by a test.
- **Axes use `Uri.encodeComponent`, not `encodeQueryComponent`.** The latter is
  HTML form encoding, where a space becomes `+`; `+` only decodes back to a
  space for a reader who knows the convention, and an address is pasted into
  logs, filenames and terminals. `%20` is unambiguous everywhere.

A raw `#` is **rejected** by the parser rather than treated as a fragment: a
catalog entry id looks like `team.dart#TeamList`, and silently truncating there
would lose half of it. It has to arrive percent-encoded.

### The AsyncValue migration, landed

| | |
|---|---|
| `app/lib/src/utils/async_value.dart` | rewritten on `ValueStream`; no Flutter import |
| `app/lib/src/utils/value_stream_builder.dart` | new — `ValueListenableBuilder`'s counterpart |
| `project.dart`, `overview/service.dart`, `dependencies/model/service.dart` | expose `ValueStream<Snapshot<T>>`; `compute` → `Isolate.run` |
| 6 widget files, 17 call sites | `ValueListenableBuilder<Snapshot<T>>` → `ValueStreamBuilder<Snapshot<T>>` |
| `plugins/native/dependencies_plugin.dart` | `addListener`/`removeListener` → `StreamSubscription` |
| `app/test/utils/async_value_test.dart` | 14 tests, laziness contract included |

`package:flutter/foundation.dart` is now gone from all four files this touched.

### The purity guardrail, and what it revealed

`app/test/utils/entry_point_purity_test.dart` walks the transitive import graph
of each entry point that must stay pure and fails if it reaches
`package:flutter` or `dart:ui`, printing the chain. `ImportWalker`
(`app/lib/src/utils/import_walker.dart`) is ported from a sibling project
(`packages/server/lib/src/tools/import_walker/`), including its resolution of
conditional imports against a simulated build environment.

Why a test when decision 9 already says `dart compile exe` is the guardrail:
that fires at distribution time, only for entry points that get compiled, and
the recorded symptom of getting it wrong was a **compiler fork bomb that filled
the machine in seconds** (`2026-07-27-gui-slice-findings.md`). This fires in
milliseconds.

Guarded today — all passing:

| entry point | reachable URIs |
|---|---|
| `app/bin/flutterware.dart` | 137 |
| `app/bin/wrap.dart` | 52 |
| `app/bin/passthrough.dart` | 31 |
| `app/tool/catalog/compiler_daemon.dart` | 741 |
| `app/tool/catalog/headless_check.dart` | 128 |

Two tests guard the guard, because a walker that silently resolved nothing would
look green: `lib/main.dart` **must** reach `package:flutter`, and a fixture
proves `package:flutter` does not prefix-match `package:flutterware`.

**The finding: the guardrail is already green, and the remaining migration is
blocked on an architecture decision rather than effort.** Not one
foundation-importing file is reachable from any guarded entry point. Of the 15:

| | files | status |
|---|---|---|
| Genuinely Flutter — `ImageProvider`, `ThemeData`, widgets | `icon/image_provider.dart`, `utils/raw_image_provider.dart`, `ui/theme.dart`, `test_runner/ui/phone_status_bar.dart` | cannot and should not change |
| Documented as the non-pure half of decision 9 | `embedder/embedded_engine.dart` | leave |
| Reaches Flutter **transitively** anyway | `plugins/worktree_session.dart`, `shell/shell_controller.dart`, `catalog/catalog_session.dart` | blocked |
| Legacy models slated for replacement | `drawing/model/*` ×4, `test_runner/model/*` ×2 | defer |
| Migrated | `icon/model/icons.dart` | done |

The blocked three are the interesting ones. `WorktreeSession` holds
`List<NativePlugin>`, and `NativePlugin.buildPanel` returns a `Widget` — so
`native_plugin.dart` imports `package:flutter/widgets.dart` **by design**, and
dropping `ChangeNotifier` from `WorktreeSession` would remove a direct import
while leaving a transitive one. Pure churn. `ShellController` imports
`WorktreeSession`; `CatalogSession` holds an `EmbeddedEngine`. Same shape.

Making those pure requires splitting the plugin **core** from its **panel** —
which is exactly the "where plugin logic runs" question this document leaves
deliberately open. So it is not a migration that was skipped; it is one that
cannot be done until that decision is made, and doing it early would prejudge
the decision.

`test_runner/model/*` is deferred on separate grounds: M4 is a rewrite, not a
port, and master-plan decision 7's rule against reworking code that is about to
be deleted applies.

### `Session` and `fw`, landed

`PluginCore` (`app/lib/src/plugins/plugin_core.dart`) is decision 2 made
literal: behaviour with no Flutter in it, and **only the panel forks**. It is a
new type rather than a refactoring of `NativePlugin`, because `buildPanel`
returns a `Widget` and that class can therefore never be linked into a pure
entry point. Change notification is a `ValueStream`, not a `ChangeNotifier`,
for the same reason.

`DependenciesCore` holds everything the plugin used to; `DependenciesPlugin` is
now a panel and nothing else — since 2026-07-28 it does not even delegate,
having no `report` or `invoke` to delegate with. `Session` resolves a manifest into cores.
`app/bin/fw.dart` renders them, and is in `_pureEntryPoints`.

```
cd app && dart run bin/fw.dart status [--json]
                                actions [--json]
                                run <plugin> <action> [--k=v]
```

**Two registries on purpose.** `PluginRegistry` produces panels and cannot be
linked into `fw`; `PluginCoreRegistry` produces behaviour and is linked into
both. A plugin joins the second one when its behaviour is separable from its
panel. Until then it resolves to `MissingPluginCore` and `fw` prints

```
UI catalog  no implementation
  No core is registered for "flutterware.ui_catalog" in this build.
```

rather than omitting the row — a `fw status` that silently skipped a declared
plugin would read as "this project has one plugin", which is a lie.

### How it runs, and what is deliberately unsolved

**`dart run bin/fw.dart`, and nothing else.** Verified in this session:
`dart compile exe` fails from `flutterware_app` —

```
'dart compile' does not support build hooks, use 'dart build' instead.
Packages with build hooks: objective_c.
```

`objective_c` arrives via `path_provider_foundation` ← `path_provider`, a
Flutter plugin dependency. **Build hooks are a property of the dependency
resolution, not the import closure**, so no amount of entry-point purity fixes
this, and master-plan decision 9's premise — a pure entry point inside the
Flutter package, compiled with `dart compile exe` — does not hold as written.
The compile guardrail it describes cannot be armed from here; the walker test
is what enforces purity instead.

**The install story is explicitly not solved**, and an earlier draft of this
document was wrong about it. that project's `bin/fw` calls itself frozen, but that was
an aspiration in a design doc, not a shipped mechanism: flutterware has no
`bin/fw`, and the only reason `fw` resolves anywhere is a hand-written alias in
one developer's `.zshrc` pointing into another project's repo. Nothing is
frozen and nothing is installed. `dart run` needs none of it, which is why it
is the way in for now.

### MCP, landed

`app/bin/mcp.dart` + `app/lib/src/session/mcp_server.dart`, on
`package:dart_mcp` (labs.dart.dev, pure Dart; two new transitive deps). It is
an adapter and nothing else — every tool opens the same `Session` and reads the
same cores `fw` does, so a capability added to a core reaches all three
surfaces without being written three times.

**Deliberately open question 2 is now answered: a small fixed tool set.**

| tool | |
|---|---|
| `flutterware_status` | every plugin's report; `compute` off by default |
| `flutterware_actions` | discovery — what can be invoked, with what parameters |
| `flutterware_invoke` | run one action; returns the result **and** the report after it |

One tool per plugin action was the obvious mapping and is rejected: it puts
every action of every plugin into an agent's context on every request, and 8
plugins × 6 actions is 50 tool descriptions to carry before answering a
question about one. Promotion of an individual action to its own tool is
reserved for where a good name beats a discovery round-trip; nothing has
earned it yet.

Two conventions worth keeping:

- **Errors are tool results with `isError`, not protocol errors.** "You named a
  plugin that does not exist" is something a model should read and correct, and
  the message carries the recovery path — it lists what *is* declared.
- **`invoke` returns the report alongside the result**, so seeing what changed
  costs no second round-trip.

`bin/mcp.dart` is in `_pureEntryPoints`. Tested through a real `MCPClient` over
an in-memory channel, so the assertions are about what a client receives —
tool schemas included — rather than the shape of a Dart method.

Note for whoever wires this to a client: **stdout belongs to the protocol.**
Anything said to a human goes to stderr or it corrupts the JSON-RPC stream.

### `UiCatalogCore`, landed — and parity is real

Both plugins now have cores, so `fw` and MCP have the same capabilities as the
GUI for everything except drawing pixels on screen. The catalog split fell
along a line that already existed:

| | |
|---|---|
| **Core** (pure) | the scan, entries, report, `entries`, **and `screenshot`** |
| **Panel** (Flutter) | `CatalogSession` — the live compile loop driving a guest engine into a texture |

`screenshot` is in the core because `catalog/screenshot.dart` was already
Flutter-free; only the *live* loop is Flutter-bound. So the master plan's
flagship AI capability works from the CLI today:

```
$ dart run bin/fw.dart run ui_catalog screenshot \
      --entry='tool/catalog/demos/counter.dart#counter'
…/build/catalog/screenshots/tool_catalog_demos_counter_dart_counter.png
```

**5.5s cold, 900×700 PNG, no GUI involved.** This is the master plan's
"screenshot an entry is a job, not a viewer capability" made real.

**`computeAll()` moved onto `PluginCore`** with a do-nothing default, so eager
loading stopped being `if (core is DependenciesCore)` in two renderers.
A capability belongs on the contract or nowhere.

(It was reached by a `--compute` flag at the time. The flag is gone since
2026-07-28 — `status` computes — but the point about the contract stands, and is
in fact what made removing the flag a two-line change.)

**The session's progress reaches the report through a hook.** `busyStatusFor`
is a `Status? Function(String path)?` the GUI sets and a CLI leaves null —
correctly, since there is no compile loop in a CLI to be busy. Without it the
sidebar would lose the only status here that takes seconds.

Two pre-existing bugs surfaced by running it for real, both fixed:

- **The screenshot socket was under the project's `build/`.** A unix socket
  path is capped at 104 bytes; this worktree's path is long enough to overflow
  it, and the error names the limit rather than the cause. `run_dir.dart`
  already existed for exactly this and its doc comment predicted the failure —
  `screenshot.dart` simply was not using it.
- **`CatalogScreenshot` took a `hostPath` the caller guessed**, while the
  daemon builds the host and reports where it put it in the handshake. Removed:
  it now uses `ready.hostPath`, so there is one answer to "where is the host
  binary" and it is the one that was actually built.

### `Address` and `Artifact`, wired

Pinned in the first commit and unused until now — `screenshot` returned a bare
path, which was exactly the retrofit this document said to avoid. Closed.

`UiCatalogCore.addressFor` builds the identity, and `screenshot` returns an
`Artifact` carrying it:

```
fw:///worktrees/<worktree>/flutterware.ui_catalog/app/tool/catalog/demos/counter.dart%23counter?height=320&width=420
```

- **The entry id is split on `/`**, not carried as one opaque segment, so the
  path stays a path and only the `#` needs escaping.
- **The package is a segment**, because two packages may declare the same entry
  id and an address that cannot tell them apart is not an identity.
- **Size is a query parameter**, because it is applied rather than identity —
  and `bare` strips it back to the entry.

Rendering, per surface:

| | |
|---|---|
| `fw run` | prints `path` — so `\| xargs open` still works and no script parses anything |
| `fw run --json` | the whole artifact: address, resolved axes, meta |
| MCP `invoke` | **the PNG as `ImageContent`**, plus the JSON alongside |

The MCP one is the point: an agent asked to screenshot something wants to
*see* it, and a path it cannot open is the difference between a working tool
and a plausible one.

**A bug the address found immediately.** The default output path was derived
from the entry id alone, so capturing the same entry at two sizes wrote both to
one file and the second silently overwrote the first — two distinct addresses
pointing at one artifact. The file name now carries the axes
(`…counter__height-320_width-420.png`), derived from the address so any axis
added later is included without revisiting this. That is the sort of thing an
identity type is *for*: the collision existed before, and was invisible until
something was required to name it.

### What running it taught us — 2026-07-28

Three things landed and one assumption broke. The assumption is the important
part.

#### `Session.invoke` is the only way an action runs

`fw` and MCP each resolved a plugin and called `core.invoke` themselves — the
same six lines twice, each with its own copy of the "Declared: …" recovery
message — and the GUI dispatched nothing at all. Three doors into one room, so
anything that must happen on *every* invocation costs three edits and the
forgotten renderer drifts silently.

```dart
Job invoke(String plugin, String action, {Map<String, Object?> arguments})
```

`Job` carries an id, a replaying event stream and a `JobResult` that **never
completes with an error** — a failed run is still a run, with a duration and a
line in the log to come. Two rules worth keeping:

- **An unknown plugin throws; an unknown action is a failed job.** The line
  [`Address`](#1-address--one-uri-for-everything) already draws: the framework
  owns the namespace up to and including the plugin, the plugin owns the rest.
  Naming a plugin that does not exist means nothing ran. Naming a bad action is
  a real invocation of a real plugin that returned an error, and an agent
  guessing action names should leave a trail that says so.
- **`Job.events` replays.** Nobody can subscribe before `invoke` returns, so a
  plain broadcast stream would never deliver `JobStarted` to anyone. Same trap
  `ValueStream` exists to avoid.

`JobEvent` is sealed and has three cases, because nothing emits progress yet.
`JobLog`/`JobProgress` arrive when a `PluginCore` can report either, which
needs a sink threaded into `PluginCore.invoke`.

#### The GUI joins by construction, not by discipline

`WorktreeSession` held a plugin list, a `reports` and a lookup — a parallel
implementation of `Session` over panels instead of cores. It now *holds* a
session. `NativePlugin` is a panel over a `PluginCore` with **no `report` and
no `invoke`**: Dart cannot seal a member, so the only way to stop a panel
answering differently from its core is not to give it one to override.
`PluginRegistry` maps a core to a panel and no longer resolves manifests —
which plugins a worktree has is decided once, by the session.

Both plugins already had this shape (`UiCatalogPlugin` wrapped `UiCatalogCore`,
`DependenciesPlugin` wrapped `DependenciesCore`); this made it the contract.

Three smaller things fell out:

- **`fw` never set an exit code.** `main` returned an `int`, which Dart ignores,
  so every invocation exited 0 — including the ones that printed an error.
- **Constructing a panel notified the shell.** `ValueStream` replays its latest
  value to every new subscriber and "what it already was" is not a change.
- **A core with no panel keeps its real report.** The sidebar shows the plugin's
  true status and only the panel says anything is missing, which beats hiding a
  working plugin behind an error.

#### The assumption that broke: two of our three actions did nothing

`dependencies reload` and `ui_catalog rescan` were the only actions besides
`screenshot`. Timed from `fw`: **0.86s and 0.75s, which is exactly the cost of
starting the process and reading the config** — against 1.27s for
`status` doing real work. They were no-ops.

They iterate what is *being watched* and what has *already been scanned* — sets
filled by a panel mounting. `fw` and MCP open a session per request and hold
nothing, so both sets are empty and the loops have no iterations. No GUI code
called either: the panels refresh through `CatalogSession` and the dependencies
service directly. They were the GUI's refresh button declared as a capability.

**The category error, stated so it is not repeated.** There are three kinds of
thing a plugin does, and only two of them are capabilities:

| | wanted by | we had |
|---|---|---|
| **Queries** — "list me that" | every surface | none |
| **Commands** — "do that" | every surface | one (`screenshot`) |
| **Cache management** — "you are stale" | only a process that persists | two |

Replaced with `dependencies list [--package] [--transitive]` and
`ui_catalog entries [--package]`, both returning the *whole* list — the report's
projection stops at 12 rows and 20 entries, and `screenshot`'s options inline at
most 50, which is right for something meant to be read and useless for "what can
I screenshot". `entries` carries each entry's `Address`, so the answer goes
straight back into `screenshot`.

**The inversion that makes queries work: a report may never start work, but an
action may.** Reports are read constantly, by every sidebar row and every tab
glyph, so `PluginReport` stays a pure read of cached state. An action was asked
for by name — and in `fw` and MCP the process was born for that request and
holds nothing, so a query that only read the cache would answer "nothing" every
time. That is precisely what the two deleted actions did.

**No `--refresh` flag.** Every `fw` invocation and every MCP tool call opens a
fresh `Session`, so a query is always cold and the flag's set and unset
behaviour would be identical — a lie in a published schema, existing only for a
daemon that does not exist. `entries` simply always re-scans: 38ms against a
700ms process start.

**What the invoke abstraction survived.** The obvious question after finding two
fake actions is whether the dispatch was wrong too. It was not: swapping the
content changed nothing about the mechanism, and both replacements worked on
both surfaces immediately. `fw run dependencies list --package=app` arrives as
strings from a shell and MCP arrives as JSON from a model — neither can reach a
typed Dart method, so *something* must look up a name and hand it a bag of
arguments. The alternative is not typed methods, it is three hand-written
adapters. What is genuinely provisional is `Job`: `list` and `entries` compute
and return, and nothing streams. It is carried for the test runner, builds and
`pub upgrade`, which do stream.

**The method mistake, since it cost a day:** the actions were read, not run. Two
commands would have shown they did nothing.

#### `docs/capabilities.md`, generated

`app/lib/src/session/capabilities.dart` renders the whole surface — `fw`'s
commands, the MCP tools taken from `FlutterwareMcpServer.tools`, and every
plugin action with its parameters — and `tool/generate_capabilities.dart`
writes it. `test/tools/capabilities_test.dart` fails when the file no longer
matches the build, naming the command that fixes it, so the document cannot
drift away from the code. `mcp_server_test` asserts a connected client is served
exactly `FlutterwareMcpServer.tools`, so the generator cannot describe a tool
nobody serves.

**Schema, not data.** It resolves the cores against a synthetic one-package
project, so it carries the shape every project gets — never this repo's entry
ids. Those are what `entries` and `list` are for.

#### The catalog answers two more questions

`check` and `describe` landed, and both exist because a *scan* cannot answer
them. Parsing finds an entry; whether it **compiles** is a fact only the
compiler holds, and what **knobs** it offers is a fact only a running build
holds. Until now the panel was the only thing that could ask either.

- **`check [--package]`** needs no guest: the daemon compiles every wrapper
  into one program while it prepares and quarantines what fails, so the answer
  is already in the handshake. Against this repo it finds
  `does_not_compile.dart` and returns the compiler's diagnostics verbatim.
  Packages are checked one at a time — each may build a host binary, and two
  cold builds racing helps nobody.
- **`describe --entry [--knobs]`** answers from the scan in under a second;
  `--knobs` costs a compile and a frame, which is why it is opt-in.

**`screenshot` can turn the knobs before the frame is taken**, and knobs are
axes — the same entry seen differently — so they go on the address, prefixed:

```
?height=700&knob.count=7&knob.label=Turned&width=900
```

Prefixed because a demo may declare a knob called `width`, and an address where
a knob quietly overwrote the viewport would name a picture nobody took. The file
name derives from the address, so two settings are two artifacts rather than one
file written twice — the collision `Address` already caught once for sizes.

Values arrive as text from every direction and are coerced to the kind the
demo's `KnobDescriptor` declares; a name the entry does not declare is an error
listing the ones it does, because a knob silently ignored renders a picture that
looks right and is not.

Two things running it taught us:

- **A headless host draws nothing until a frame is asked for**, and a knob is
  only declared while the demo builds — so reading knobs without rendering
  first returns "no knobs" for a demo that plainly has three. The panel never
  meets this because it drives frames continuously.
- **`package:flutterware/ui_catalog.dart` reaches `package:flutter`.** Importing
  the umbrella for `KnobDescriptor` made `fw` unlinkable; the purity walker
  caught it and printed the chain. `knob.dart` is plain Dart by design, so the
  import is that, directly. The lesson generalises: import the library, not the
  umbrella.

#### A test that drives both surfaces, and the three disagreements it found

`test/session/surface_parity_test.dart` is enforcement #2 from decision 6, made
real. It **walks the manifest** rather than naming actions: for every declared
action it invokes through `fw` and through MCP over the *same* session and
compares. A new action joins the matrix the day it is declared.

Making it possible was most of the work: `fw`'s logic moved out of `bin/` into
`FwCli` with injected sinks and a session factory, and the MCP server takes the
same factory. **A parity rule that cannot be driven by a test is a claim, not a
rule** — and a `bin/` file nothing can import cannot be driven.

It found three real defects, one of them introduced by the fix for the first:

1. **`--loud=true` was the string `'true'`.** A shell has no types, so a boolean
   passed the explicit way arrived as text and every plugin asking
   `arguments['x'] == true` saw false — silently, on the CLI only, while the
   same call over MCP worked because JSON carries a real bool.
   `fw run dependencies list --transitive=true` listed 27 of 88 dependencies and
   said nothing.
2. **The fix then crashed on a bad value**, with a stack trace and exit 255,
   because it threw out of `invoke` before a job existed.
3. **Both surfaces dropped the offending value from error messages.**
   `ArgumentError` keeps it in `invalidValue`; both renderers formatted
   `message (name)` and discarded it, so "expected red or blue" never said what
   you passed.

The fixes are all at the single door, which is what the door was for:

**The declared `ActionParameterKind` is now applied in `Session.invoke`.** Once,
for every renderer, rather than by hand in every core. Parameters an action does
not declare pass through untouched — the framework parses up to the plugin and
no further. A value of the wrong kind is a **failed job**, the same line an
unknown action falls on: `fw: expected an integer (width): wide`, exit 64.

This is the answer to a question left open earlier — the published parameter
schema was a contract nothing enforced. It is enforced now, and the thing that
made it visible was a test comparing two renderings of it.

#### Typed results, and a schema read out of the code

Three steps, in order, because each is worth having if the next is abandoned.

**A `PluginResult` marker and a class per result.** `CatalogEntriesResult`,
`CatalogCheckResult`, `CatalogEntryDescription`, `DependencyListResult` and the
rows beneath them; `Artifact` implements it too, so it stops being a special
case. `toJson` is generated from the fields, so the wire form cannot drift from
the type. Renderers switch on the marker rather than asking
`value is Map || value is List` — a test that says "somebody built a map" and
goes false the moment a core returns something typed. (The map branch is kept:
an action that has not adopted a type yet should not have its output degrade to
`toString()`.)

**Nullability is the reason this beats deriving shapes from sample output.**
`knobs` is `List<CatalogKnob>?` because absent means "not looked at" and empty
means "declares none". No sample can say that.

**`PluginAction.returns` is a `Type`, not a name** — a type literal is what can
be *followed*. And `Session.invoke` **checks it**: an action that declares one
and returns something else fails like any other broken invocation, naming both
types. Exact match rather than `is`, because a subclass would serialise fields
the published shape does not mention. Verified by commenting the check out and
watching the test fail.

**`ShapeExtractor` reads the shape out of the classes**, and the document and
MCP publish it. A spike answered the design questions first, and corrected the
plan:

- **A bare class name in an expression position is a `TypeLiteral`, not a
  `SimpleIdentifier`.** The element hangs off `literal.type.element`. The first
  version silently found nothing.
- **No `build_runner`, no `source_gen`, no `build.yaml`.** A plain
  `AnalysisContextCollection` in the existing generator does it — 4.4s against a
  core that transitively imports Flutter. A builder was recommended and was not
  needed.
- **Only `@JsonSerializable` classes get a shape.** There the keys are generated
  from the fields, so reading fields describes what is sent. `Artifact` writes
  its own `toJson` and turns an `Address` into a string; the first version
  walked it anyway and published `address: Address`, the exact lie the rule
  exists to prevent. The document says why instead of guessing.
- **First sentence, not first line.** Dartdoc wraps at 80, so taking the first
  line published `reading a knob costs a`.
- **The analyzer cannot infer its own SDK under `flutter test`**, where
  `Platform.resolvedExecutable` is `flutter_tester`. It is found by walking up
  for a `dart-sdk` directory, which works under `dart run` too.

Kept honest by re-derivation: `action_shapes_test.dart` re-runs the extraction
and fails when the checked-in data no longer matches the classes, because
generated data nobody re-derives is a hand-maintained schema with extra steps.
The generator formats its own output, or `prepare_submit` rewrites the file
afterwards and the freshness test fails forever on a difference nobody made.

#### `fw` explains itself, from the declarations it already has

`fw help` was seven hand-written lines and `capabilities.dart` had the same
prose typed out again. Commands are data now — `fwCommands` and `fwExitCodes`
are the only place either is written, and both the terminal and the document
render them.

```
fw help run                        what run does, and how to ask it things
fw run ui_catalog                  the four actions that plugin has
fw run ui_catalog describe --help  its parameters, and what comes back
```

The last prints the same `ActionParameter`s an agent gets over MCP and the
result shape extracted from the returned class, so terminal, document and agent
are three renderings of one source. A parameter with `optionsFrom` prints the
command that lists its values — which only reads correctly because that pointer
was fixed to name `entries` rather than the report view it was truncating.

Three renderers were quietly duplicated and now are not: the shape tree is
`ResultShape.toText`, the usage line is `FwCli.usageLine`, and the "no plugin X,
declared: …" message is `Session.requireCore` — so a bad plugin name reads the
same whether it was about to run something or only to describe it.

`fw run <plugin>` with no action used to be a usage error. It is a question, and
it is answered. Help never invokes anything, which a test asserts by counting.

### Next

Item 0 of the previous list — queries for what the plugins already know — is
done: `check`, `describe`, `entries` and `list` all exist. A framework-level
`read <address>` is still the tidier long-term answer and still premature with
two plugins; add it when a third makes you write the same thing a third time.

1. **The CLI story proper** — how a user gets `fw` without `dart run`, and
   whether `fw` learns to fetch its own Flutter (it cannot today, which is why
   `fvm` is doing the job and the pre-commit hook still needs `--no-verify`).
   Its own session, per decision 10.
2. **The viewer capability** — `reveal`, `viewer.capture`, `viewer.state`, and
   `fw show <address>`. Nothing blocks it now that `Address` is real and
   carried by artifacts; it needs the GUI side, which is where it stops being
   cheap.
3. **Global search**, once there is a viewer to drive. See "Deferred" for the
   mechanics — opening the palette loads, typing filters, Enter escalates — and
   for why the aphorism that used to sit there should not be built on.

Smaller things the last session left on the floor, in the order I would take
them:

- **`Artifact` publishes no shape**, because its `toJson` is hand-written. It is
  the most-returned result of all. Teaching the extractor to read a
  `@JsonKey(toJson:)` converter's return type would fix it — worth doing when a
  *second* class needs a converter, not before.
- **A `PluginResult` is not required.** An action may still return a raw map,
  and the renderers still print one. That is deliberate kindness to a plugin
  that has not adopted a type, and it is also the hole through which an
  undocumented result shape can arrive. Whether to close it is a decision for
  when a third plugin exists.
- **The daemon-backed actions are unverified by the parity harness.** `check`,
  `screenshot` and `describe --knobs` need an SDK, a compile and a guest, so the
  matrix covers the cheap ones and a fake. `headless_check.dart` is where an
  integration pass would live.

Two standing habits rather than tasks:

- **Add each new pure entry point to `_pureEntryPoints` as it is written.**
  That list is the specification of what "pure" means here; an entry point
  absent from it is simply unguarded.
- **The blocked three** (`worktree_session`, `shell_controller`,
  `catalog_session`) follow the core/panel split rather than leading it. They
  reach Flutter transitively through `NativePlugin`, which returns a `Widget`
  by design, so there is nothing to fix in them directly.

Smaller, unowned:

- Run `fw` from a package subdirectory (`examples/example`) and the worktree
  reads as a path rather than a branch: `git worktree list` from there reports
  the *outer* repo's worktrees and none matches. Cosmetic in `fw status`, but
  `Address` uses the worktree name as identity, so it will matter.
- There is no `.mcp.json` in the repo, so wiring the MCP server to a client is
  manual. Whether to commit one is a project-policy call.
