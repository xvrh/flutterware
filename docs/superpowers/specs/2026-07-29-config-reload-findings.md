# Config reload, and what a swap must preserve

**Date:** 2026-07-29
**Status:** Design. Amends `2026-05-18-worktree-explorer-plugins-design.md`
§ config.dart lifecycle, whose decisions mostly stand and whose mechanisms
mostly do not.
**Follows:** `2026-07-27-compile-pipeline-performance-findings.md`,
`2026-07-28-cli-compilation-spike-findings.md`.

## The trigger

`tool/flutterware.dart` stops being a JSON emitter. It gains executable code —
callbacks the framework holds and invokes later — which turns the config from a
value that is read into a process that is alive. Realtime reload was deferred on
the grounds that it was not worth the complexity "for native plugins only". That
rationale expires with the reframe: an edit-and-see loop that requires a button
press is not a usable way to write a callback.

Master plan **decision 4 expires with it**. It forbids "a resident compiler, a
spawn-then-swap, and a long-lived per-worktree config process"; executable
config requires the second and third. Retire it in the plan explicitly rather
than accumulating exceptions — the 2026-07-28 spike already had to argue the
manifest kernel cache was not one.

## What the 2026-05-18 lifecycle got right

Unchanged, and worth restating because it was decided before most of the
supporting machinery existed:

- **Spawn-then-swap, no hot reload.** `reloadSources()` considered and rejected:
  it re-imposes reassemble/diff complexity and stale-state risk to save a
  fraction of a second. The July measurements make this more true, not less —
  see below.
- **The watch set is the compiler-reported import closure of the config**, not
  the config file. Once callback bodies grow they move into their own files; a
  watch on `tool/` alone would miss them. The closure comes free from each
  compile.
- Directory watching for atomic rename-saves, debounced ~150–250ms.
- `pubspec.yaml` / `.lock` route to a slower `pub get` + cold-restart path.
- **A compile error keeps the last-good config serving** and surfaces file+line.
- A manual affordance plus a `config.reload` RPC, for filesystems that do not
  deliver native watch events.

One gap in the closure rule, worth closing when it is built: the set is
refreshed only on *successful* recompiles, so a fix living in a file that
entered the closure in the broken version produces no event. Watch the config
file and its directory as a floor underneath the closure.

## Four stale mechanisms

| the note says | what is true now | source |
|---|---|---|
| compile via `package:frontend_server_client` | abandoned — its `Platform.resolvedExecutable` spawn relaunches the app recursively inside Flutter, and its hard-coded arg list made `--initialize-from-dill` unreachable. Replaced by our own `FrontendServer`, ~180 lines speaking the same line protocol | 2026-07-27 |
| `--initialize-from-dill` is the fast path | worth ~25ms. Keep it; it is not carrying the budget. The earlier 2396ms→341ms figure was environmental | 2026-07-27 |
| no resident compiler — 50–150MB per open worktree | there *is* a resident compiler daemon now, and it is **shared**: `DaemonAddress` hashes the config into a socket path under `~/.flutterware/run/`, and a second client's connect→ready is 19ms. The question is no longer resident-vs-not but whether the config compile joins the daemon already running for the catalog | 2026-07-27 |
| edits reflect within ~0.5–0.8s | conservative by roughly 5×. A kernel-cached config run is 70–80ms, and a `void main(){}` kernel is 70ms — i.e. the config's own work is unmeasurable against VM start. A thirty-line config recompiles incrementally in single digits. Spawn-then-swap should land near 100–150ms plus handshake | 2026-07-28 |

The last row closes the hot-reload question harder than the note did. The gap it
declined to chase as "~0.3s" is nearer 40ms.

## The invariant that makes a swap cheap

Between the 2026-05-18 design and the shipped code, closures were flattened into
values: `TeardownStep` (`lib/src/plugins/teardown.dart`) has `String? detail`
and `bool enabled` where the design had closures over source state. That was not
recorded as a decision but it is the load-bearing one.

> **The report is a snapshot, so no closure ever crosses the boundary. The only
> thing that crosses is `invoke`, and it crosses by plugin id + action name +
> JSON arguments.**

Named actions are stable handles by construction, so a swap needs no identity
scheme: the GUI's pending references stay valid because they were never
pointers. Keeping callbacks reachable *only* through `Session.invoke`
(`app/lib/src/session/session.dart`) is what makes the config process
disposable, and it is already how the code is shaped.

## Correctness first, and an exact no-op

The bias is **correctness, not preservation**. An edit that changes what a
plugin does reconstructs it, and losing a guest engine or stopping a daemon is
the expected price of having changed the thing that started them. What must
never happen is the reverse: typing a comment, or editing a part of the config
that has nothing to do with a plugin, must not cost that plugin anything.

So the entire design is the **equivalence relation on declarations**. Too coarse
and a plugin keeps running behaviour the file no longer describes — incorrect.
Too fine and every keystroke-save tears down a device — the annoyance the
feature exists to remove. Nothing else in the swap is difficult.

The config process itself is unaffected by any of this: it is replaced on every
source change, because it holds nothing worth keeping. The question is only what
the **GUI's plugin graph** does in response, and `UiCatalogPlugin` is why it
matters — it holds a `CatalogSession` with a guest engine and a texture behind
it. The 2026-05-18 note is silent here; "spawn-then-swap so panels never go
dark" is about *declarative* panels served from the config process, and native
plugins are compiled into the GUI.

### One comparison: run it, and diff the projections

We re-run the config on every change anyway — that is how a new projection is
obtained, and the process is replaced regardless because it holds nothing worth
keeping. So the comparison is just **old projection against new projection**,
per plugin declaration.

| what differs | what happens |
|---|---|
| nothing | **nothing.** No change to the plugin graph, no notify, no teardown |
| a plugin's declaration | that plugin is disposed and reconstructed |
| the `packages` list | the workspace is rebuilt, and every core with it |

Order comes from the new projection. There is no `reconfigure` and no in-place
update: an affected plugin is disposed and rebuilt, which is the only behaviour
that needs no cooperation from the plugin to be correct.

A comment or a formatting change produces an identical projection and therefore
costs nothing — not because anything detected the comment, but because running
the config is the detection. Nothing needs to parse source.

### Why one comparison is complete

The worry that motivates a second comparison is that two configs with identical
projections can have different callback bodies. It does not survive contact with
the process lifecycle:

- **The config process is always replaced.** A retained core that invokes a
  callback routes to the *current* process, which is running the new code. Live
  queries are fresh by construction.
- **Anything that shapes the graph is a value by the time it is projected.** A
  callback whose result decides what a plugin *is* — how many packages it has,
  what its actions are — is evaluated by the config process before it emits, so
  its result is in the projection and the comparison sees it. Callbacks that
  survive *into* the projection are handlers: invoked in response to something,
  never at construction.

That second point is the rule to hold, and it is not new — `TeardownStep`
(`lib/src/plugins/teardown.dart`) already flattens closures to `String? detail`
and `bool enabled` at report time. The same principle, one level up: **the
projection carries values, not promises.**

What is left uncovered is a core that caches the result of a live query and
never re-asks. That is an ordinary plugin bug — the same one it would have
caching any mutable external data — and not something the reload machinery
should parse source files to defend against.

One consequence worth stating because the comparison depends on it: a handler in
the projection must be spelled as a **stable path**, `{"$fn":
"flutterware.ui_catalog/onBuild"}`, never a per-run counter. With a counter,
every run produces a different projection, nothing ever compares equal, and the
no-op case is unreachable. Stable naming was earlier argued for on
swap-survival grounds; this is the stronger reason.

### What this deletes

Four things from the preservation-first sketch, all of them the fragile parts:

- `reconfigure` and its opt-in tier — the one mechanism that would have pushed
  reload correctness into every plugin.
- The semantic hash of the import closure, and with it any need to parse the
  config's sources. Re-running is the comparison.
- The discipline rule "anything a plugin caches from the config must appear in
  the projection", replaced by the sharper "the projection carries values, not
  promises" — a constraint on what the config process emits, which it can
  enforce, rather than on what every plugin remembers, which it cannot.
- Late binding as a *correctness* requirement. Routing handles through a stable
  per-worktree endpoint is still worth doing so an in-flight `invoke` survives a
  swap, but nothing depends on it any more.

### Preconditions

- **The workspace survives when `manifest.packages` is unchanged.** `Workspace`
  interns `PackageRef` "so callers can compare identity"
  (`app/lib/src/shell/workspace.dart`), and every `PluginHost` holds the
  workspace — so a new workspace forces every core to be rebuilt and defeats the
  table above. This is a precondition, not an optimisation. It is also provably
  safe: `packages` is pure data in the projection.
- **A failed compile changes nothing.** Load first, swap second. Today
  `reloadConfig` releases the session and *then* loads
  (`app/lib/src/shell/shell_controller.dart`), so a broken config leaves a dead
  worktree — survivable for a button you pressed, fatal for a watcher firing on
  a half-written file.

The address needs no special handling: it is a value, and `selectedPluginId`
already falls back to home when the plugin it names is gone.

### In-flight work: drain, do not kill

The wrapper-tool doc says recompile = kill+replace; the explorer doc kills the
old process once the new one warms. Both drop running work silently.

This is the one preservation rule that survives the correctness bias, because it
is not about state. Losing a device to an edit is a consequence the user can
see; a job that was asked for and never ran is not. The old process serves its
running jobs to completion while the new one takes everything new, and is killed
on a deadline with whatever was cancelled reported by name. Two processes
overlap briefly, which the crash-isolation model already assumes.

### Panel state, when the declarative tier lands

Panel state — scroll, expansion, form input — lives GUI-side keyed by path, not
in the config process's object graph. The config process is stateless between
swaps.

This is the same rule as **`configure()` must be pure and idempotent**, which is
worth writing into the `Flutterware.configure` doc *before* callbacks ship. It
is true today by construction (the config prints and exits), so nobody has been
tempted; the moment callbacks exist, someone puts a directory scan at configure
time and every swap double-applies it. Callbacks are the escape hatch for work;
the configure body is not.

Together they are what makes the correctness bias affordable: if the reloadable
unit holds nothing worth preserving, then throwing it away on every change costs
nothing, and the only judgement left is the equivalence relation above.

## The CLI never swaps

`fw` is one-shot — spawn, invoke, exit. It shares the channel protocol and none
of the watcher, the diff, or the swap.

One cost note: today the manifest load is 70–80ms that produces a value. An
action whose behaviour lives in a config callback needs a live process for the
duration of the command. Same VM start, but it moves the CLI from reading a
value to holding a process, and per the output policy
(`2026-07-29-cli-launch-experience.md`) that is where the config load earns a
`Step` line rather than staying silent.

## Surfacing it

The panel is process status, not compile status: up / swapping / crashed, when
it last swapped, which handles are registered, and a log of callback invocations
with durations and errors. That is the thing to have open while writing a
callback.

A chip in the shell chrome expanding to a drawer, and the same content rendered
as text by `fw`. Show the swapping state only past a ~150ms budget — a swap
should land near it, and a chip that flickers on every save reads as broken.
Same "budget before you show progress" rule the CLI already applies.

`reloadConfig()` and its button already exist
(`app/lib/src/shell/shell_view.dart`), so the manual affordance the 2026-05-18
note asks for is built; `config.reload` has an obvious home in `Session.invoke`.

## Order of work

1. **Load before swap**, in `reloadConfig`. Small, and it makes every step below
   safe to fire automatically.
2. **The projection comparison** and both preconditions. A JSON equality check
   and a diff — this is the whole rule, before callbacks and after.
3. **The two rules**, in the `Flutterware.configure` doc, before the callback
   tier ships: `configure()` is pure, and the projection carries values rather
   than promises. Retrofitting either is the expensive version.
4. **Process supervision** — per-invocation timeouts, per-callback error
   attribution, death detection with visible respawn, drain-on-swap.
5. **The watcher**, last and smallest, over the import closure.

Steps 1 and 2 are worth doing against the manual reload alone, before any
callback exists.

## Still open

- Whether the config compile joins the shared catalog daemon or spawns its own
  `FrontendServer`. The 19ms second-client figure argues for joining; version
  skew across worktrees argues against.
- The drain deadline, and whether a job that outlives it is retried against the
  new process or simply reported.
- Where the line falls between "shapes the graph, so evaluate and project the
  value" and "is a handler, so project a `$fn` path". Most cases are obvious;
  a callback that is cheap and pure could go either way, and projecting its
  value means the plugin reconstructs whenever the value moves, which may be
  what you want or may be a rebuild per tick.
