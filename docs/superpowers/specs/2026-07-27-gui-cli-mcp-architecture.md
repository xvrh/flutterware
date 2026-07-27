# GUI / CLI / MCP — the shared architecture

**Date:** 2026-07-27
**Status:** Decisions 1–6 agreed in discussion. **1, 2, 4 and 6 are
implemented** — `Address`, `Artifact`, `ValueStream`, and the `Session` that
`fw` and the MCP server both render. **3** (the daemon contract) and **5**
(`reveal` vs `capture`) are pinned but unbuilt: there is no daemon holding a
run log yet, and no viewer to reveal into. See the "landed" sections at the
end for what exists.
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
fw://<worktree>/<plugin>/<plugin-specific path…>?<axes>
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

**Global search**, until the CLI exists. The design constraint to carry, since it
was nearly written down wrongly: the rule is **not** "search reads only cached
data" — that would be a bad search engine. It is

> **A keystroke may never start work. An intent may.**

Two phases: instant on every keystroke from warm indexes (the syntactic scan is
~1ms incremental over 778 files, so catalog entries and scenarios are free), then
real work on intent — Enter, or the query settling — with results **streaming and
merging** so a slow provider never blocks a fast one. The default flips per
surface: the GUI starts fast and escalates; `fw search` and MCP `search` default
to full, because an agent typing a query once has already expressed intent.

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
(`app/lib/src/utils/import_walker.dart`) is ported from rimbaud
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
now a panel that delegates to it. `Session` resolves a manifest into cores.
`app/bin/fw.dart` renders them, and is in `_pureEntryPoints`.

```
cd app && dart run bin/fw.dart status [--compute] [--json]
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
document was wrong about it. `rimbaud/bin/fw` calls itself frozen, but that was
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
| **Core** (pure) | the scan, entries, report, `rescan`, **and `screenshot`** |
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

**`computeAll()` moved onto `PluginCore`** with a do-nothing default, so
`--compute` stopped being `if (core is DependenciesCore)` in two renderers.
A capability belongs on the contract or nowhere.

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
fw://<worktree>/flutterware.ui_catalog/app/tool/catalog/demos/counter.dart%23counter?height=320&width=420
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

### Next

1. **The CLI story proper** — how a user gets `fw` without `dart run`, and
   whether `fw` learns to fetch its own Flutter (it cannot today, which is why
   `fvm` is doing the job and the pre-commit hook still needs `--no-verify`).
   Its own session, per decision 10.
2. **The viewer capability** — `reveal`, `viewer.capture`, `viewer.state`, and
   `fw show <address>`. Nothing blocks it now that `Address` is real and
   carried by artifacts; it needs the GUI side, which is where it stops being
   cheap.
3. **Global search**, once there is a viewer to drive. The rule to carry is in
   "Deferred": a keystroke may never start work, an intent may.

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
