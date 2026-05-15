# Command-Wrapper Tool — Architecture Exploration

**Date:** 2026-05-15 (revised same day)
**Status:** Exploration / direction-setting. **Not a committed spec.** Only phase 1
(the `passthrough` PTY command) exists in code.

This document captures an ongoing design discussion about the larger tool that
the `passthrough` PTY command is the first building block of. It records the
shape we agreed on, the decomposition into sub-projects, and the open questions,
so a future session can pick it up without re-deriving everything.

> **Revision note (2026-05-15):** an earlier version of this doc framed the
> whole product as a wrapper CLI you invoke explicitly. That framing missed two
> things: (1) the product is really *two* mechanisms that compose, and (2) the
> daemon bundled two responsibilities that split on the per-project /
> per-worktree line. Both are corrected below.
>
> **Revision note 2 (2026-05-15):** the distribution/install model is now worked
> out — a three-layer split (frozen walker → tiny bootstrapper → host-built big
> CLI) and a plain-text `flutter_version` marker. See "Distribution & install
> model" below; it replaces the earlier "fw foundation" section.

## The goal

A per-project tool that AI agents (and humans) use across many git worktrees of
the same project. Every interesting process — `flutter run`, a long-running
Dart server, a test run — funnels to one central, **per-project** place so its
progress and results are observable in a GUI: each open worktree shown as a tab.

Crucially, this must observe runs started **any way**: by an AI agent, by a
human in a terminal, or by an IDE (IntelliJ / VS Code). The tool cannot assume
everything launches through an explicit wrapper command.

## Two mechanisms (the key reframe)

The product is two distinct mechanisms that **compose**. Earlier framing treated
the launch-wrapper as the foundation; in fact it is the *bootstrap* for the
back-channel.

**Mechanism A — wrap the launch (the *outside* of a process).**
Intercept *how* a process starts: observe its argv/output, inject env vars and
`--dart-define`s. This is where launch-time policy lives.

**Mechanism B — the app connects back (the *inside* of a process).**
A library embedded in the running app/server (today: `Devbar`, `lib/devbar.dart`)
opens a channel to the GUI for rich features — DB introspection, screenshots,
hot-reload, HTTP-log streaming, SQL-query streaming.

**How they compose:** A intercepts the launch *and injects an env var* (the
channel address) into the child. B reads that env var and phones home. A is not
a secondary convenience — it is how B learns where to connect.

| Feature | Needs |
|---|---|
| Worktree list & tabs | neither — GUI shell |
| Discover running `flutter run` / servers | A (the wrap point) |
| Rich app features (Devbar, DB, screenshots, hot-reload) | A injects + B connects |
| Server features (HTTP logs, SQL queries, open pages) | A injects + B connects |
| Inject `--dart-define` (e.g. server host/port per worktree) | A |
| `config.dart` shortcuts (`fw env up` → `cd … && …`) | A |

## Wrapping the SDK, not a prefix

The naive form of Mechanism A is a `fw <command>` prefix the user types. That
cannot catch IDE-launched runs — an IDE invokes `flutter` directly.

The fix: **wrap the `flutter` and `dart` scripts that the IDE actually
invokes** — the ones inside the project's SDK location. Because `fw` owns the
SDK install and the path the IDE is pointed at, wrapping `flutter`/`dart` there
means **every** invocation — CLI, AI, or IDE — passes through the wrap point.
That is what makes "observe runs started any way" achievable. The exact
placement of the wrapped scripts (shared SDK cache vs. per-project mirror dir)
is a sub-project 0 decision; see that section.

The sibling `rimbaud` project (`bin/fw` + `tool/fw`) is a working prototype of
the SDK-management half and a useful reference, but its structure is *not* the
model — see the distribution model below.

## Distribution & install model

The hard constraint: the very first run on a fresh machine has **no `dart` and
no `flutter`**. Whatever runs first must be bash or a precompiled binary. Only
*after* an SDK exists can Dart code (`pub get`, `dart compile`, `flutter build`)
run. That constraint produces a **three-layer split** — the dividing line is
"does this need a full SDK to exist yet?"

| Layer | Job | Form | Distributed how |
|---|---|---|---|
| **Walker** | walk up from `$PWD`, find the project, dispatch | frozen bash (~30 lines) | once, global (on `PATH`) |
| **Bootstrapper** | install the pinned Flutter SDK — *nothing else* | tiny precompiled binary (`dart compile exe`) | GitHub releases, machine-global, version-*floating* |
| **Big CLI** | daemon, DB, wrapping, GUI — all real logic | built **lazily on the host** | from the pinned `flutterware` pub package |

**Why three.** A single distributed binary cannot carry the big CLI: the GUI is
a Flutter desktop app (`flutter build`, never `dart compile exe`) and the
daemon/DB layers may need native deps. So the big CLI is **built on the host**
once the SDK exists — the model `bin/flutterware.dart` already uses today
(`pub get` + `dart compile exe` + `flutter build` into a per-version cache,
reused on later runs). It is never shipped as a binary; its versioning is
ordinary pub resolution. Only the *bootstrapper* must be a clean precompiled
binary, and installing an SDK has trivial dependencies (HTTP/`git`, archive
extraction) — safe for `dart compile exe` indefinitely.

**The walker** is the only thing installed globally and the only thing "frozen".
It is safe to freeze precisely because it carries **no logic** — pure dispatch,
no external contract beyond "a `flutter_version` file exists up the tree". It is
a single global file, so if it ever does need to change the big CLI can simply
overwrite it (the escape hatch fvm never had). A `curl … | sh` installer (always
fetched fresh, never frozen) seeds the walker + the first bootstrapper.

### The marker — `flutter_version`

The walker keys on a **plain-text `flutter_version` file** at the repo root
(just the version string). Not `.fvmrc` (an fvm convention — would collide), not
the `flutterware` pubspec dependency (would force the frozen walker to
understand pub, and `pubspec.lock` does not exist on a fresh checkout).

This makes opt-in **two-level**, deliberately:

- `flutter_version` present → `fw` manages the Flutter SDK. Useful on its own —
  `fw` is a viable fvm replacement even for projects that never touch the GUI.
- `flutter_version` **+** a `flutterware` pubspec dependency → `fw` *also*
  delivers the big CLI, daemon, wrapping, and GUI. The pubspec dependency pins
  the big-CLI version and delivers the Mechanism-B runtime libs (`devbar`).

An optional committed config file (tentatively `tool/flutterware.dart`) carries
user policy; see `config.dart` below.

### Bootstrapper pinning — there is none (by design)

The bootstrapper **cannot** be pinned per-project, and does not need to be.

*Cannot:* it runs at cold-start, before any `dart` exists. The only pin readable
that early is the plain-text `flutter_version`. The `flutterware` version lives
in `pubspec.lock`, which does not exist until `pub get` runs — which needs the
SDK the bootstrapper has not installed yet. So the bootstrapper executes before
the project's flutterware version is even knowable.

*Does not need to:* the bootstrapper is a **fungible installer**, not part of
the build. Its only job is "fetch the exact Flutter SDK named in
`flutter_version`" — `git clone` of a tag, which works regardless of bootstrapper
age. Whichever bootstrapper does the fetch, the result is the same SDK. CI
reproducibility comes entirely from the two real pins: `flutter_version` and the
`flutterware` pub dependency.

So there are exactly **two per-project pins** (`flutter_version`, the
`flutterware` pub dep). The bootstrapper is machine-global and version-floating
(seeded by the installer, updated deliberately, not silently per-run).

**The one frozen contract: the IDE-facing SDK path.** What *could* bite CI is
not the bootstrapper's install *mechanism* (which may evolve freely — same
output) but its output *layout*. Within that layout, only the SDK path the IDE
is pointed at is a hard external contract — committed IDE configs (`.idea/`)
depend on it. That single path must be chosen once and treated as permanent,
like a public API. The *internal* cache structure may still evolve: the pinned
big CLI runs after the bootstrapper and can detect and migrate an older
internal layout. CI is further insulated because it caches the Flutter SDK
directory anyway, so the bootstrapper is not re-fetched or re-run per build.

**Optional escape hatch.** A project that wants hard determinism against
bootstrapper drift may commit an optional plain-text `flutterware_version` file
at the repo root; the walker reads it at cold-start (it already reads
`flutter_version`) and fetches that exact bootstrapper version. Deliberately
*optional* — making it mandatory would recreate fvm's real pain (a third version
knob to manage and skew), which the 99% case should not pay.

### Cold-start trace

1. **One-time per machine:** `curl … | sh` puts the walker on `PATH` and seeds
   the latest bootstrapper into `~/.flutterware/`.
2. `fw …` in a project → walker walks up, finds `flutter_version`, dispatches.
3. **Bootstrapper** runs (native binary, needs nothing): installs the Flutter
   SDK named in `flutter_version`.
4. `dart`/`flutter` now exist → `pub get` resolves the `flutterware` package at
   the pinned version into the pub cache.
5. **Big CLI** is built lazily on the host into a per-version cache (reused on
   later runs), then runs the requested command / daemon / GUI.

### Evolution resistance

CI reproducibility rests on the **two per-project pins** (`flutter_version`,
the `flutterware` pub dep) — not on the bootstrapper, which is a fungible
installer (see "Bootstrapper pinning" above). The big CLI is host-built at its
pinned pub version, so an old project keeps building its old, known-good CLI and
is never forced to upgrade.

The bootstrapper stays backward compatible for *installing* old Flutter versions
because that is just `git clone` of an old tag — durable for any tag. Its
install *mechanism* may evolve freely (a floating "latest" is fine). Its output
*layout* may also evolve, with one exception frozen forever: the IDE-facing SDK
path. The walker's contract (`find flutter_version` → dispatch) is the other
forever-stable surface, and it is regenerable.

Two honest limits, neither solvable by architecture:
- If we ever *must* move the IDE-facing SDK path, that is a breaking change — a
  deliberate, rare major-version migration, not something a pin file makes
  painless (it would only trade the migration for permanent multi-layout
  support).
- If Flutter *upstream* removes old download artifacts, nothing saves you — but
  cloning a git tag from `github.com/flutter/flutter` is about as durable as
  anything gets.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  flutterware daemon  (one per PROJECT)                         │
│                                                                 │
│  ┌────────────────────────────────────────────┐               │
│  │ per-WORKTREE config-process pool            │  each worktree │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐    │  has its own   │
│  │  │ wt-A cfg │ │ wt-B cfg │ │ wt-C cfg │    │  config.dart;  │
│  │  │ process  │ │ process  │ │ process  │    │  compiled +    │
│  │  └──────────┘ └──────────┘ └──────────┘    │  run per wt,   │
│  │     ▲ JSON-RPC: policy.query per worktree  │  crash-isolated│
│  └─────┼──────────────────────────────────────┘               │
│  ┌─────┴────────────┐   ┌────────────────────────────┐        │
│  │ RPC server       │ ← │ wrapper invocations query  │        │
│  │ (unix socket)    │   │ "spawning X in wt-B —       │        │
│  └──────────────────┘   │  policy?"                   │        │
│                          └────────────────────────────┘        │
│  ┌──────────────────┐                                          │
│  │ DB writer        │ → <project>/.flutterware/flutterware.db   │
│  └──────────────────┘   (single DB — the funnel)                │
└──────────────────────────────────────────────────────────────┘
        ▲                  ▲                    │
        │ query            │ inner-app channel  │ sqlite_async.watch()
┌───────┴────────┐ ┌───────┴────────┐  ┌────────▼────────────┐
│ wrapped        │ │ inner app /    │  │ GUI                 │
│ flutter/dart   │ │ server connects│  │ (attaches any time, │
│ (any worktree, │ │ back via env   │  │  one tab/worktree)  │
│  any launcher) │ │ var (Mech. B)  │  │                     │
└────────────────┘ └────────────────┘  └─────────────────────┘
```

### Per-project vs per-worktree — the split

The word "daemon" earlier bundled two responsibilities that belong on different
sides of the per-project / per-worktree line:

- **Per-project:** the DB, the funnel, the RPC server, the GUI-facing hub. This
  *must* be per-project — a single DB with a `worktree` column is the entire
  reason the GUI can show all worktrees with one `watch()` + `WHERE`. N
  per-worktree databases would force the GUI to discover and merge them.
- **Per-worktree:** `config.dart` compilation + execution. Each worktree is a
  separate checkout with its own `flutterware/config.dart`; they diverge. One
  config process cannot serve them all.

**Resolution:** the daemon stays **per-project** and manages a **pool of
per-worktree config processes** — one compiled `config.dart` per active
worktree. A `policy.query` from a worktree's wrapper routes to *that worktree's*
config process. The doc's original diagram already drew the config process as a
separate, crash-isolated, recompile-replaced process; the only change is
quantity (one per worktree instead of one).

Daemon identity is per-project, not per-user (different projects may use
different flutterware versions). The deeper complication — different *worktrees*
of the same project pinning different flutterware versions — is deliberately
deferred; per-worktree config processes partly absorb it, but the daemon binary
itself stays single-version.

### Components

**Wrapper (the wrapped `flutter`/`dart`)** — thin, per-invocation. Flow:
1. Resolve project root and **worktree identity** (a worktree's `.git` is a file
   pointing at the common dir).
2. Find or auto-spawn the project daemon.
3. RPC `policy.query`: "about to run `<cmd> <args>` in worktree `<wt>` — policy?"
4. Apply returned rewrites (argv, env, GUI metadata, channel routing).
5. Spawn the child under `passthrough` (PTY), stream observations to the DB
   through the daemon.
6. If the daemon is down or policy fails → fall back to plain passthrough.

**Per-project daemon** — long-lived, one per project. Owns: the per-worktree
config-process pool (compile-on-invalidation, crash isolation, recompile =
kill+replace), the Unix-socket JSON-RPC server, the DB writer.

**Per-worktree config process** — runs that worktree's compiled `config.dart`,
crash-isolated, serves `policy.query` for invocations in that worktree.

**Config file** (optional, tentatively `tool/flutterware.dart`) — user-written
policy code. Proposed API:

```dart
import 'package:flutterware/config.dart';

void main() => Flutterware.configure((fw) {
  // declarative match pattern + imperative handler
  fw.command('flutter run', timeout: Duration(seconds: 3), (ctx) async {
    final flags = await fetchRemoteFlags();       // async allowed
    ctx.args.inject(['--dart-define=APP_ENV=dev', ...flags]);
    ctx.gui.tabLabel = 'flutter · ${ctx.worktree.name}';
    ctx.channels.enable(['http.logs', 'ui.buttons']);
  });

  // config-defined shortcut: `fw env up` from anywhere in the repo
  fw.shortcut('env up', (ctx) => ctx.run('dart tool/local_env up',
      cwd: 'packages/server'));

  // async reactions to runtime events (off the spawn critical path)
  fw.on<ChannelMessage>('http.logs', (msg) {
    if (msg.statusCode >= 500) fw.notify('5xx from ${msg.path}');
  });
});
```

- The match pattern is **declarative data** (so the daemon/GUI can list
  recognized commands without running code).
- The handler is **imperative** and `FutureOr<void>` — sync for the fast path,
  `await` allowed when needed.
- Synchronous spawn-time config (`ctx.args`, `ctx.env`, `ctx.gui`) is on the
  wrapper's critical path; `fw.on` event reactions are not.

**Communication channel** — per-invocation Unix socket. The wrapper owns the
socket; its address is injected into the child via an environment variable so
the inner app (Mechanism B) can connect back. Wire format: JSON frames with an
envelope `{session, channel, payload}`. `channel` is a sub-protocol name
(`pty.stdout`, `http.logs`, `ui.buttons`, …); new features = new channel name,
no protocol version bump.

**SQLite as the bus** — the daemon writes everything (PTY output, channel
messages, session metadata) to `<project>/.flutterware/flutterware.db`. The GUI
reads via `sqlite_async`'s `watch()` and subscribes selectively with SQL `WHERE`
clauses. No separate daemon↔GUI protocol. Cross-process change detection is
~100–200 ms (polling `pragma data_version`) — acceptable because the user's own
terminal already shows real-time output; the GUI is a secondary observer.

Active-session discovery and orphan cleanup (wrapper killed `-9`) use a
heartbeat column the wrapper bumps periodically, plus a staleness sweep.

## Decomposition into sub-projects

The product is too large for one spec. Four sub-projects, each its own
spec → plan → implementation cycle, ordered by dependency:

| # | Sub-project | Delivers | Depends on |
|---|---|---|---|
| 0 | **The SDK wrap point** | Every `flutter`/`dart` invocation intercepted (CLI/AI/IDE); can observe output + inject env; worktree identity resolved | — |
| 1 | Central place + GUI shell | Per-project daemon + single DB, worktree tabs, lists running sessions | 0 |
| 2 | The back-channel | `Devbar` reads injected env, connects back; one rich feature end-to-end | 0, 1 |
| 3 | `config.dart` | Per-worktree config-process pool; `--dart-define` injection; shortcuts | 1 |

## Decisions locked

- **Two mechanisms** — A (wrap the launch) bootstraps B (app connects back).
- **Wrap point is the SDK's `flutter`/`dart` scripts**, not a typed prefix — so
  IDE-launched runs are caught.
- **Three-layer distribution** — frozen bash *walker* (global) → tiny
  precompiled *bootstrapper* (install-SDK only, from releases) → *big CLI*
  (daemon/DB/wrapping/GUI) built lazily on the host from the pinned pub package.
- **Marker is a plain-text `flutter_version` file** at the repo root — not
  `.fvmrc`, not the pubspec dependency.
- **Two-level opt-in** — `flutter_version` → SDK management; + `flutterware`
  pub dependency → big CLI / daemon / GUI.
- **Two per-project pins only** — `flutter_version` and the `flutterware` pub
  dep. The bootstrapper is **machine-global and version-floating**, not pinned
  (it runs before any pin but `flutter_version` is readable); it is a fungible
  installer, so it does not affect reproducibility.
- **One frozen contract: the IDE-facing SDK path.** Install mechanism and
  internal cache layout may evolve; the path the IDE points at may not.
- **Optional `flutterware_version` escape hatch** — a project may pin the
  bootstrapper version; deliberately optional, not the default.
- **Big CLI is never distributed as a binary** — host-built; ordinary pub
  versioning. Old projects keep building their pinned CLI and are never forced
  to upgrade.
- **Per-project daemon + DB** (the funnel); **per-worktree config processes**.
- **Unix socket** for the per-invocation channel.
- **GUI is lazy** — the CLI/wrapper does everything; the GUI catches up later.
- **JSON** wire format, named sub-protocol channels.
- **Multiple simultaneous invocations** across worktrees funnel to one
  per-project DB.
- **Compile-on-invalidation** for the config file (not Dart hot reload).
- **Config handler is `FutureOr<void>`** — async allowed.
- **Per-command tunable timeout** with a conservative global default.

## Guiding principle — always degrades to plain passthrough

Every layer can fail and the user's command still runs:

- **Policy-query timeout** — wrapper waits ≤ the command's budget for
  `policy.result`; on timeout, spawn unmodified and log it.
- **Atomic policy application** — if the handler times out mid-`await`, discard
  the *entire* decision. Never apply a partial `ctx`.
- **Compile failure** — daemon keeps the last-good compiled config per worktree;
  surfaces the error in the GUI; if there is no good version, commands fall
  through.
- **Config crash** — daemon restarts the process; repeated crashes trip a
  circuit-breaker → that worktree's config disabled, plain passthrough.
- **Daemon unreachable** — wrapper auto-spawns it; if that fails → plain
  passthrough.

## Open questions

- **Noise classification (sub-project 0's central question):** wrapping `dart`
  catches the IDE's analysis server, `dart pub get`, and internal tooling — far
  more than interesting runs. How does the wrap cheaply tell a session worth
  observing from the dozens of noise invocations, without breaking the IDE?
- How the GUI process starts (manual `fw gui`, auto-spawn, or standalone app
  with a project picker). Leaning toward manual.
- Whether a purely-declarative `fw.rules([...])` subset is worth adding for
  GUI-editable rules.
- DB schema for sessions, PTY chunks, and channel messages.
- Daemon auto-start mechanics (double-fork / `setsid`) and the well-known socket
  path convention.
- Worktrees pinning different flutterware versions (deferred).

## Next step

Brainstorm and spec **sub-project 0 — the SDK wrap point**. It is the
foundation everything else depends on, and it is the riskiest assumption (a hack
against Flutter's SDK layout and IDE behavior). It sits on the distribution
model above: the walker + bootstrapper get the SDK in place; sub-project 0 adds
the wrapped `flutter`/`dart` and proves an IDE-launched `flutter run` is
intercepted and classified without breaking the IDE.
