# The launch experience, and one live region under it

**Date:** 2026-07-29
**Status:** Measured, then built. Everything in "What was measured" is a number
from this worktree; everything in "What was built" landed in the same session.
**Extends:** `2026-07-28-cli-adoption-story.md` (the first-run budget it
narrates), `2026-07-27-gui-cli-mcp-architecture.md` (the session `fw` renders).
**Settles, partly:** master-plan decision 8 — "stop investing in
`app/lib/src/tui/`, evaluate termui". It is answered with a **trigger** rather
than a choice, and the trigger has not fired.

## What was measured

One machine (M-series, Flutter 3.47.0-0.1.pre), the `examples/example` project,
a cold `app/build`.

| | |
|---|---|
| `dart build cli` → AOT bundle, 11MB | **5.6s** |
| `dart compile kernel` → dill, 40MB | **2.0s** |
| `flutter build macos --release`, cold | **38.4s** (~11s CPU in the parent) |
| CLI **then** GUI, as it shipped | **44s** |
| CLI **and** GUI, started together | **34s** — CLI at 6s, GUI at 34s |
| `fw help` from the AOT bundle, warm | 0.01s |
| `fw help` from the kernel dill | **0.07s** |
| `fw help` via `dart run` from source | 4.0s — build hooks, every time |
| `dart run flutterware help`, warm, end to end | 0.65s |

Three findings, in the order they matter.

### The first build was serial for no reason

The GUI build does not consume the CLI binary. It consumes `app/`, resolved.
Started together, the CLI build cost **0.2s more** (5.6 → 5.8s) and the GUI
build was not slower. Ten seconds of a 44-second first impression were being
spent on an ordering nobody chose.

`flutter build macos` burns ~11s of CPU in the parent across 38s of wall time.
Most of the rest is Xcode subprocesses and I/O, which is why there is room for
a Dart compile beside it.

### AOT for the CLI buys 60ms and costs 3.6s a rebuild

`dart compile kernel` produces a snapshot that starts in **0.07s** against the
AOT bundle's **0.01s**, and produces it in **2.0s** against **5.6s**.

This is the launcher-AOT mistake of `2026-07-28-cli-adoption-story.md` one
level down: that document deleted an AOT artifact, a pin file and a
self-replacement protocol which together bought ~120ms. Here the same trade is
60ms for 3.6s per rebuild — and `_isFresh` rebuilds on **any** `.dart` change
under `app/lib`, `app/bin` or `lib/`, so a flutterware developer pays it on
every edit.

**Not acted on, deliberately.** Once the two builds overlap, the CLI build is no
longer on the critical path — it finishes at 6s inside a 34s launch, and
shaving it to 2s changes nothing a user can see. The number is recorded here
because it is the right answer to a *different* question (the dogfooding inner
loop), and because it should not have to be measured twice.

### The blocker the adoption story flags is already gone

That document names one: `bin/flutterware.dart` sets `singleCharMode` and
subscribes to keystrokes, so the launcher would swallow the `r` that a nested
`flutter run` needs. **It does not.** The file's own doc comment now says it
deliberately holds neither stdin nor the child's output. Nothing stands between
us and an interactive terminal while the GUI is up.

## The framework question, answered with a trigger

The resolution recorded in the previous session was: *do not answer decision 8
as part of CLI progress work; settle it later by building one real panel each
way.* That was done.

**The panel** — the first-run plan, below — was built twice: hand-rolled on
plain ANSI, and on `package:termui`. Both render identically. Hand-rolled is
~95 lines. termui is ~100 widget lines **plus** a change-stream model to drive
them, because `PromptRunner.run()` is an await point and so is the work being
narrated, so the panel has to close itself from inside the tree via
`PromptScope.done()`.

> **At this complexity the framework buys nothing.** It is not close.

### What termui is, since the evaluation should survive being wrong

MIT, by jtmcdole. Created **2026-06-06** — seven weeks before this was written.
22 releases in that time, the latest four days old. 18 stars, 3 likes, 1414
downloads in 30 days, 150/160 pub points. Pure Dart, 26 transitive dependencies
(including `test_api` and `matcher` at *runtime*, which is a smell and not a
blocker).

It is a genuine superset of `app/lib/src/tui/`: overlapping windows, mouse
input, `Table`/`LazyTable`, `TextField`, tabs, forms, canvas and braille
sub-cell drawing, animation, a tracer — and inline rendering that preserves
scrollback, which is the mode this document needs.

Cost is not the objection. Measured against a no-dependency baseline,
`dart compile exe` grew **+0.5MB** and **+1.5s**, which is noise beside an 11MB
CLI that takes 5.6s.

**The objection is colour.** `Color` is 24-bit ARGB and the renderer emits
`38;2;r;g;b` unconditionally — no 16-colour path, no 256-colour path, no
`COLORTERM` probe, and no way to say *the terminal's own green*. You can render
unstyled, and that is all. For an application that owns its palette this is
correct. For a developer CLI that has to sit inside everyone's theme it is a
mismatch, and `app/lib/src/tui/cell.dart` already models the right thing:
**default / 16 ANSI / 24-bit**.

### The trigger

Neither framework is adopted, and `app/lib/src/tui/` stays frozen — 6247 lines,
34 files, ~30 test files, **zero production importers**.

> **The trigger is the first surface that needs layout *and* focus** — an
> interactive picker over actions or addresses, or a full-screen job dashboard.
> Nothing on the current path needs either.

When it fires, the recommendation is to **adopt termui and delete
`app/lib/src/tui/`** — maintaining a widget framework is not flutterware's
business — *conditional on* the colour gap closing. The package is MIT with a
responsive author, so a `ColorProfile` fallback is a plausible contribution
rather than a fork. If that does not happen, hand-rolled remains right, because
a CLI that overrides the user's palette is worse than a CLI without colour.

**Do not reopen this without a concrete panel to build.** That rule is inherited
from the previous session and it held.

## What was built

### `LiveRegion` — the primitive

`lib/src/live_region.dart`. Rows pinned at the bottom of the terminal, repainted
in place; everything else printed *above* them, into ordinary scrollback.

No alternate screen and no scroll region (`DECSTBM`). Both were considered and
both are wrong here: every line the user scrolls back to should be a real line
in their terminal's history, and a crash should leave a readable transcript
rather than half a restored screen. The mechanism is `ESC[nF` to return to the
top of the region, `ESC[2K` per row, and `ESC[0J` when the region shrinks.

Three users, which is the entire argument for it being one class:

| user | rows |
|---|---|
| the first build | the plan — one row per stage, elapsed against budget |
| `fw app`, while the GUI runs | what is running, and how to stop it |
| `fw run` *(not yet)* | a job's event stream |

**`Step` is not rebuilt on top of it**, though it is `LiveRegion` with one row.
Its escape sequence is pinned by tests, it is in use, and it works; replacing a
working renderer to make a diagram tidier is churn. The two overlap and that is
accepted.

### The plan panel replaces one-line-at-a-time

```
  flutterware · examples/example
  First run. Building the tools — once per flutterware version.

  ✓  unpack flutterware         1s
  ✓  build the CLI              6s
  ⠋  build the GUI       18s / 25s

  26s elapsed · about 10s left
```

The stages are listed **before** they run. That is the whole point, and it is a
different claim from the one `Step` makes: a per-step budget answers *is this
stuck*, and only a plan answers *how much is left*. At second 20 of the old
rendering there was no way to tell you were two thirds through.

Off a terminal it degrades to exactly what `Step` printed — one line per stage,
at the moment the stage starts — so a CI log is unchanged.

### The two builds overlap

The launcher starts the GUI build beside the CLI build when the command implies
the GUI. It does not learn how to build the GUI: **`DesktopGui`
(`lib/src/desktop_gui.dart`) is the one place that knows where the binary lives
and which command produces it**, and both the launcher and `GuiLauncher` call
it. Two copies of a platform-specific path is how a 38-second build silently
runs twice.

Sequencing, because not everything can overlap:

1. **unpack** — serial. It creates the tree the other two read.
2. **resolve** — serial, and only for a fresh copy. `flutter build` would run
   `pub get` itself, and two of them racing on `.dart_tool` is not worth 5
   seconds.
3. **build the CLI ∥ build the GUI**.

Overlapping only happens when there is a GUI build to overlap with: a path
dependency runs the GUI under `flutter run` and builds nothing, so flutterware's
own developers see the old shape unless they pass `--release`. That is the right
way round — the saving belongs to the adoption path.

**A failed prewarm is not reported by the launcher.** It passes
`FW_GUI_BUILD_FAILED` forward and `GuiLauncher` reports it from the log that is
already on disk, without rebuilding. Failure reporting stays in the one place
that knows about `--json`, and a broken build is not run twice at 38 seconds
each.

### The terminal stops being dead while the GUI runs

`fw app` in release mode now keeps a region at the bottom and puts the GUI's
output above it:

```
  flutter: opened the catalog
  flutter: 12 entries

  ●  GUI running  ·  examples/example  ·  up 41s
  q or ctrl-c to quit
```

This required giving up `inheritStdio` for that one case, which reverses a
decision worth restating rather than quietly overturning. `inheritStdio`
replaced `RemoteLogServer`/`RemoteLogClient` because a websocket to carry logs
between two adjacent processes was absurd. A **pipe** between those same two
processes is not that: no server, no port, no protocol, and the CLI is already
the parent.

The split is strict, and it is the same `editableSources` fork that already
decides how the GUI runs:

| | stdio | why |
|---|---|---|
| `flutter run` (path dependency) | **inherited** | it owns an interactive console — `r`, `R`, `q`. Two processes cannot both hold stdin, and the one that swallowed the `r` would make reload silently do nothing. |
| the built binary (everyone else) | **piped** | it has no console. Nothing is lost, and the terminal gains a place for events to arrive. |

Also strict: the region only appears when `outputIsInteractive` and not under
`-v`. Off a terminal, `fw app` behaves exactly as it did.

Three things the first real run taught, all of them consequences of owning a
stream and a terminal that were previously somebody else's:

- **Quitting is not failing.** `process.kill()` leaves the GUI on SIGTERM,
  which Dart reports as `-15` and a shell sees as **241**. So `fw app` exited
  non-zero every time a user pressed `q`, and `fw app && …` never ran the
  second half. `_Quit.requested` is the whole fix, and it exists because a GUI
  that crashed and a GUI that was asked to stop are otherwise the same dead
  process.
- **Cancel the stdin subscription after restoring the terminal, never before.**
  Cancelling closes the descriptor, so `stdin.lineMode = …` afterwards throws
  `StdinException: Bad file descriptor` — which surfaced as an unhandled
  exception immediately after `q`. Restoring is also wrapped: failing to give
  the echo back is bad, and crashing on top of it is worse.
- **The engine's `[IMPORTANT:…]` startup line is dropped**, and only that
  level. `ERROR` and `FATAL` wear the identical `[<LEVEL>:<file>(<line>)]`
  shape, which is why `isEngineChatter` is a named, tested predicate rather
  than a prefix match: a filter that swallowed a real engine error would make
  the GUI undebuggable from the only surface showing its output.

### The log tree, deleted

`_PrintLogClient.printBox` rendered a multi-line box as `'[$message - $title]'`,
so the GUI's welcome banner arrived as one bracketed blob with its title
stranded at the end. It had been doing that under `inheritStdio` too; putting a
tidy panel above it is what made anyone look. Pulling on it found the rest.

**`lib/src/logs/` was 2809 lines and almost none of it was reachable.** A copy
of `flutter_tools`' `Logger` (1469), an ANSI `Terminal` model (411), its
`platform`/`io`/`async_guard` support (571), and a websocket `RemoteLogServer`
(176) — the transport that carried the GUI's log lines back to the terminal
that ran `dart run flutterware`.

| | |
|---|---|
| `RemoteLogServer.start` call sites | **0** |
| anything setting `REMOTE_LOGGER_URL` / `FW_REMOTE_LOGGER_URL` | **0** |
| importers of `logger`/`terminal`/`io`/`platform`/`async_guard`/`remote_log_server` outside `logs/` | **0** |
| call sites on the whole `LogClient` surface | **3** |

Those three were `printBox` (the banner) and two
`Logger.root.onRecord.listen(…)`. So the "no server reachable" fallback had
silently become the only implementation there is, and an interface with
`printBox`, `startProgress`, `printStatus` and `printTrace` — terminal verbs —
was being implemented by a process with no terminal.

`2026-07-28-cli-adoption-story.md` deleted the transport when the process chain
moved to inherited stdio. This deletes the shape it left behind:
**2809 lines out, [`lib/src/log_client.dart`](../../../lib/src/log_client.dart)
in, 41 lines with one method.** With it goes the dead `loggerUri` thread —
`PackageRef` → `Project` → `daemon.dart` → the generated test entry point →
`runTests(loggerUri:)` — which nothing ever set, so the branch was dead the
whole way down.

### The banner moved to the process that can answer it

`main.dart` had to **hard-code** the plugin list — "Pub dependencies manager, UI
catalog" — because a `runApp` has no session to ask. `fw` does, so `fw app`
prints it, read from the same `session.reports` that `fw status` renders:

```
  Tools declared in tool/flutterware.dart:
    · Dependencies
    · UI catalog

  `fw status` for what each one says · `fw actions` for what they do.
```

Injected into `GuiLauncher` as `describeProject` rather than computed there,
and run **after** the GUI is spawned. Opening a session costs ~0.5s; nothing a
user is waiting for is behind it, and the region it prints above already exists.
It is also the first thing to use `printAbove` for what the region is actually
for — something arriving while the GUI runs.

Failures are swallowed on purpose: a project whose config file throws should
still get a window and a working `q`, and hear why from `fw status`.

**`q` is the only key.** Not because keys are hard, but because the case for
more is weak: `2026-07-28-cli-adoption-story.md` already argues that a second
`fw` invocation beats a prompt — it works from another terminal, from a
subdirectory, and from an agent, none of which a keystroke does. So the
terminal's value while the GUI is up is **ambient state and streams**, which is
display. A REPL was considered and rejected on that argument.

## What this deliberately does not do

- **No session channel to the running GUI.** The events the region is shaped to
  carry — `reveal` attribution, job progress, run results — need decision 3 and
  5 of `2026-07-27-gui-cli-mcp-architecture.md`, which are pinned and unbuilt.
  The region carries the GUI's stdout until then, and its shape does not change
  when they arrive.
- **No `--machine`.** What forces it is unchanged: programmatic reload,
  structured build errors, and owning the terminal's rendering during
  `flutter run`. Still to be scoped together, or not at all.
- **No kernel-snapshot CLI.** See above — measured, recorded, off the critical
  path.

## Open questions

1. **Does the plan's budget need to learn?** The GUI build measured 38.4s here
   and 23.2s in the spike that produced the adoption story's table. A budget
   that is wrong by 60% teaches the user to ignore it. The honest fix is to
   record the last successful duration per stage and quote that; the honest
   objection is that it is per-machine state for a cosmetic gain.
2. **`fw run` has no live region yet**, and it is the user the primitive was
   really designed for. It needs `Session.invoke` to expose the event stream it
   already promises rather than only `job.done`.
3. **Windows.** `ESC[nF` and `ESC[0J` are fine on Windows Terminal and on any
   VT-enabled console, which is what `stdout.supportsAnsiEscapes` reports. Not
   verified on a real Windows machine.
