# The adoption story — how a project gets flutterware

**Date:** 2026-07-28
**Status:** Design. Settled in discussion; unbuilt.
**Evidence:** `2026-07-28-cli-compilation-spike-findings.md` — every number here
was measured, not estimated.
**Extends:** `2026-07-25-overhaul-master-plan.md` (decision 10 — distribution is
last), `2026-07-27-gui-cli-mcp-architecture.md` ("Next", item 1).

Supersedes the three-layer distribution model of
`2026-05-15-wrapper-tool-architecture.md` §Distribution. That model assumed a
frozen bash walker, a precompiled bootstrapper shipped from GitHub releases, and
an SDK the tool installs itself. **The user brings their own SDK**, which deletes
the bootstrapper layer entirely, and `dart install` turns the walker into a
published artifact rather than a shell script.

## The story

```sh
dart pub add flutterware
dart run flutterware                 # or: fvm dart run flutterware
```

That is the whole thing. The second command initializes the project and launches
the GUI. Nothing is installed globally, nothing is added to `PATH`, and nothing
in the repo needs editing.

Then, optionally, once:

```sh
dart install flutterware             # gives you `fw`, usable from any subdirectory
```

**Declining leaves you fully working.** `dart run flutterware` at the project
root keeps doing everything `fw` does — which is also exactly what CI uses, and
the reason `fw` is allowed to be simple: it is an accelerator, never the only
door.

## Vocabulary

Four artifacts, which the discussion kept conflating because only two had names.

**The walker and the launcher are separate files, deliberately.** An earlier
draft had one file play both roles, told apart by whether
`Isolate.resolvePackageUri` returned null — a real signal, and an implicit one.
Two files need no signal: `executables:` decides what `dart install` installs,
`dart run <package>` resolves `bin/<package>.dart`, and the two never meet.

| | what | where | how it is built |
|---|---|---|---|
| **The walker** | `bin/walker.dart`. Finds the project, execs `dart run flutterware`. Frozen, version-floating, no logic. | published package, installed as `fw` by `dart install` | AOT, ~5.8MB, ~10ms |
| **The launcher** | `bin/flutterware.dart` in `package:flutterware`. Checks the artifacts are current, builds them if not, execs the CLI. Never does real work. | published package | **only** JIT, by `dart run` — 0.13s, 967KB snapshot |
| **The CLI** | `app/bin/fw.dart` → `FwCli`. `status`, `run`, `app`, and everything a plugin declares. | `flutterware_app`, shipped inside the published package | `dart build cli` — 7.2s |
| **The GUI** | the Flutter desktop app | same | `flutter build macos --release` — 23.2s |

And two phases, which were also being conflated:

- **init** — write `.flutterware/`. Instant. Records the SDK, ensures the
  directory is ignored, optionally scaffolds `tool/flutterware.dart`.
- **first build** — compile the launcher, the CLI, then the GUI. ~32s.

They are separate because init cannot fail in an interesting way and first build
can, and because only one of them needs a progress indicator.

## Why the published package can carry all of this

Verified, and it is the fact the whole story rests on: **`package:flutterware`
ships `app/`** — 8.1MB in the pub cache, GUI and CLI sources included. So a
single `pub add` delivers everything the first build needs, and there is no
second package to publish.

Two more that make `dart install` viable:

- `dart install` exists on **stable Dart 3.12.1**, not only on beta.
- The root package's resolution has **no build hooks**, so the launcher
  AOT-compiles to a single 6.3MB binary with no dylibs — none of the
  `objective_c` trouble that blocks `dart compile exe` in `flutterware_app`.

Installing needs a Flutter SDK's `dart`, because `flutterware` depends on
`flutter` via `sdk: flutter`. Not a real limit for this audience, but it means
"whatever SDK" means "whatever *Flutter* SDK".

## The walker contract — frozen

The global `fw` is version-floating: `dart install` resolves whatever the
installing SDK allows, and it is not reinstalled per project. It is therefore
safe **only** because it carries no logic:

> Walk up from `$PWD` for `.flutterware/sdk`.
> Not found → print the redirect and exit non-zero.
> Found → `exec <sdk>/bin/dart run flutterware <argv>`.

That path is a permanent contract, the way the IDE-facing SDK path was in the
2026-05 design, and it is the **only** one. Everything else — the artifact
layout, the freshness check, what the launcher does after it starts — may move
freely, because none of it runs inside the frozen binary. `fw` execs
`dart run flutterware` and the project's own version decides everything from
there.

**The global `fw` is deliberately allowed to go stale** — it is installed once
and never refreshed unless `init` runs again. That is only safe because the two
frozen contracts are the sum of what it knows.

**`fw` and `dart run flutterware` are therefore the same command**, not two
implementations kept in agreement. `fw` finds the SDK and then types the other
one for you:

```
fw status                 →  <sdk>/bin/dart run flutterware status
dart run flutterware …    →  itself
```

Everything below that line is one code path, JIT-compiled from the project's
currently resolved sources on every invocation.

**Why this is affordable — measured in a realistic consumer project** (a Flutter
app with `flutterware` as a dev dependency, 39 packages):

| | |
|---|---|
| `dart run` of the launcher's real import closure | **0.13s** |
| the launcher's pub snapshot | **967KB** |
| an AOT launcher, for comparison | ~0.01s |
| **what dropping AOT costs** | **~120ms** |
| `fw status` end to end (launcher + AOT CLI) | **~0.23s** |

The launcher links no Flutter and no analyzer — `dart:convert`, `dart:io`,
`dart:isolate`, `crypto`, `path`, and flutterware's own logging. So its snapshot
is 967KB against the CLI's 31MB, and it loads accordingly. An earlier draft of
this document measured `dart run flutterware_app:fw` — the *CLI* — and concluded
`dart run` cost 1.6s. That was the wrong program: the CLI is not what `fw` runs.

**Correction, found while building it: `dart run <package>` must be invoked
from a package root.** An earlier draft said it walks up by itself, verified
from a nested subdirectory — but that verification used a package with no build
hooks. In this repo, from `app/lib` or `examples/example/lib`, it resolves, runs
the build hooks, and *then* fails with `Could not find a file named
"pubspec.yaml" in <cwd>`.

So the walker does two things rather than one: it finds the project root, and it
execs from there. Nothing is lost by moving — the session walks up to the repo
root regardless of where it started, so the root is where the work was always
going to happen.

### What `dart run` costs, and the measurement that was wrong

An earlier draft rejected `dart run` on every invocation at 1.6s and built an
AOT launcher, a pin file and a self-replacement protocol to avoid it. **That
number was for the wrong program.** `dart run flutterware_app:fw` runs the CLI,
whose snapshot is 31MB because it links the analyzer. `fw` runs the *launcher*,
whose snapshot is 967KB. In a realistic consumer project the launcher costs
**0.13s**, and all of that machinery bought ~120ms.

The rest of this section is kept because it explains a real anomaly in *this
repository*, which is now a bug rather than a design constraint.

pub caches an app-JIT snapshot at
`.dart_tool/pub/bin/<pkg>/<script>-<sdk>.snapshot`. Decomposed by running the
*same trivial script* in four contexts:

| resolution | closure | warm |
|---|---|---|
| 1 package | trivial | 0.12s |
| 120 packages | trivial | **0.13s** |
| the flutterware workspace | trivial | **0.65s** |
| the flutterware workspace | `fw` | 1.35s |

Of the 1.35s, **~0.7s is loading the snapshot** — 31MB for `fw` against 1KB for
the trivial script — and **~0.58s is pub's wrapper before the program starts.**
That second number is localized precisely and **not explained**: the same 1KB
snapshot runs in 0.07s directly and 0.65s through `dart run`, while in every
synthetic repository the same wrapper costs ~0.05s.

Eliminated, each by measurement:

| suspect | test | result |
|---|---|---|
| analytics | disabled, and `--suppress-analytics` | no change |
| path dependencies | 120 path deps, trivial script | 0.13s |
| hosted dependency count | 70 packages + Flutter | 0.13s |
| `sdk: flutter` deps | minimal Flutter package | 0.12s |
| pub workspaces | 3-member workspace | 0.12s |
| files in mutable packages | 1500 `.dart` files in a member | 0.12s |
| stale pubspec mtimes | fresh `pub get` | no change |

An earlier draft of this section claimed the cost was "fixed to a pub workspace
with `sdk: flutter` dependencies". **That was wrong** — a trivial workspace with
Flutter dependencies costs 0.12s. The honest statement is that the overhead is
twelve times larger in this repository than in any synthetic reproduction of it,
and nobody knows why yet.

**Where it lands:** flutterware's own developers pay ~0.7s per `fw` instead of
~0.23s, and users pay nothing, because a consumer project measures 0.12s. That
makes it a dogfooding annoyance and a bug worth chasing on its own merits — not
an input to this design. The way to find it is to bisect *this* repository's
174-package resolution downward; building up from 1 to 70 packages never
triggered it.

## Staleness — pub owns the launcher, the launcher owns the artifacts

This is the part the 0.13s measurement simplifies most, so it is worth stating
what was deleted and why.

**`dart run` recompiles the launcher from the currently resolved sources, and
pub invalidates its own snapshot when the resolution changes.** So the launcher
is *never* stale — structurally, not by protocol. Everything an earlier draft
built to fake that property is gone:

| deleted | it existed to |
|---|---|
| the AOT launcher in `.flutterware/bin/` | save ~120ms |
| the pin file, and comparing it | let a stale launcher detect that it was stale |
| self-replacement, write-then-rename | let a stale launcher fix itself |
| the handoff to `dart run` on mismatch | let the *new* version perform the upgrade |
| "missing or unreadable pin means stale" | make the above fail safe |
| worrying about the pin format | keep old launchers able to compare |

**pub does that bookkeeping for us, correctly, in 130ms.** Our version would
have been a worse reimplementation of it.

What remains is one genuine question — are the **CLI and GUI artifacts**
current? — asked by code that is always fresh. That is the whole difference:
the checker can change however it likes, forever, because there is never an old
one running.

**Key: the `flutterware` entry in `.dart_tool/package_config.json`** — its
`rootUri`, plus the file's top-level `flutterVersion`. Not the 1280-file source
walk `_sourceStamp` does today, which costs ~95–138ms on every invocation
against a target of ~100ms for the whole command.

`package_config.json` rather than `pubspec.lock`, for four reasons:

- **`rootUri` locates as well as identifies.** For a hosted dependency it is
  `file:///…/.pub-cache/hosted/pub.dev/flutterware-0.5.1` — the version *and*
  the sources the launcher must build `app/` from. The lock file gives
  `version: "0.5.1"` and leaves the launcher to reconstruct the cache path,
  which is the guessing this design exists to remove.
- **The lock is intent; the package config is the resolution.** They disagree
  whenever a lock file changed without `pub get` running, and keying on intent
  would trigger a rebuild against sources that are not there yet.
- **It carries the SDK.** The top level has `flutterRoot` and `flutterVersion`,
  which answers the SDK-skew question in the same read. Precedent that this
  belongs in the key: pub names its own snapshot
  `fw.dart-3.13.0-282.1.beta.snapshot`.
- **One file per resolution**, at the workspace root — where the launcher is
  already walking to find `.flutterware/`.

Two things not to do. **Do not hash the whole file**: `packages` changes on any
unrelated dependency bump, and rebuilding the GUI because someone upgraded
`collection` is exactly the over-invalidation the source stamp is being replaced
for. And note that **for a path dependency `rootUri` is `../` and never moves**,
which is why the source stamp survives for that case and only that case.

The source stamp stays, but only for the case it was written for: a **path
dependency**, where the sources move without the lock file noticing. Which is
us. So:

| the project's flutterware is | staleness key | cost |
|---|---|---|
| a hosted version | the `pubspec.lock` entry | ~1ms |
| a path dependency | the source stamp | ~100ms |

### Why the global `fw` can be indefinitely stale

`dart install` resolves whatever the installing SDK allows, and nothing
reinstalls it. It is therefore years-out-of-date in the limit — and that is
fine, because after this simplification it knows exactly two things: the name
`.flutterware/sdk`, and the string `dart run flutterware`. Neither can rot,
because the second is the door CI already depends on.

Everything version-sensitive lives on the far side of that exec, in code that
was JIT-compiled from the project's own resolved sources moments earlier.

**This is the argument for keeping `fw` this thin even when it is tempting not
to.** Any logic added to the global binary is logic that ages independently of
every project it is pointed at.

## What `init` does

1. **Record the SDK.** `Platform.resolvedExecutable` — the exact `dart` that
   launched it, fvm or otherwise. Recorded as a symlink at `.flutterware/sdk`,
   pointing at `.fvm/flutter_sdk` when that exists so fvm stays the single
   source of truth rather than a second one to drift from. This is the whole
   reason discovery heuristics are unnecessary: **whatever runs init is already
   running under the right SDK.**
2. **Ensure `.flutterware/` is ignored.** It holds an absolute SDK path and
   build artifacts, so committing it breaks every teammate. init checks
   `.gitignore` and adds the entry if missing — announcing that it did, since
   it is a write to a tracked file.
3. **Optionally scaffold `tool/flutterware.dart`.** Not required: a project with
   one package and the default plugins has nothing to say in it, so the session
   falls back to a manifest declaring the current package. It is offered because
   an empty-but-present config is how people discover that configuration exists
   at all.
4. **Offer the global `fw`** — and offer the `PATH` line separately. Two
   consents, because they are two intrusions. `dart install` puts executables in
   `~/Library/Application Support/Dart/install/bin`, which is not on `PATH`, so
   the second ask is unavoidable rather than a courtesy.

Re-running `init` is the **self-update**: it reinstalls the global `fw` at the
version this project pins. Safe precisely because the walker contract above is
frozen.

## Auto-init, and what the user sees

`dart run flutterware` in an uninitialized project **initializes and continues**
rather than refusing with an instruction. It has everything it needs, and
demanding a separate command to gather information it already holds is
ceremony.

But it must narrate, because the measured first-run budget is not small:

| stage | measured |
|---|---|
| dart's own compile of the launcher | 1.6–3.2s |
| init | instant |
| build the launcher (AOT) | ~1.5s |
| build the CLI | 7.2s |
| build the GUI | 23.2s |
| **total** | **~33s**, with a warm pub cache |

Each stage named as it starts, with its expected duration. **A stage that says
"building the GUI (~25s, first run only)" is worth more than any spinner** — the
question a user has at second 20 is whether it is stuck, and only a stated
budget answers it.

Explicit `fw init` remains, for CI, for scripting, and for the self-update.

## The dev loop, and how the GUI is launched

The GUI launch **forks by mode**, which is a second consequence of running in
place for a path dependency:

| | how the GUI runs | reload |
|---|---|---|
| user / release | `flutter build macos --release` once, then spawn the binary | n/a |
| dev (path dependency) | **`flutter run -d macos`** | yes |

**Hot reload and restart need no wiring, if we build nothing.** `flutter run`
already owns an interactive console — `r`, `R`, `q`, the DevTools URL. Spawned
with `ProcessStartMode.inheritStdio`, the child owns the terminal and every key
works at full fidelity with zero code.

**The rule for this phase: choose the mode, build nothing on it.** The switch is
one argument, so replacing it later costs one line. What would be wasted is
anything layered on top — a keystroke forwarder, a log parser, progress scraped
from human-formatted output. None of that.

**Log forwarding is deleted, not written.** `RemoteLogServer` /
`RemoteLogClient` exist only because the three-process chain used piped stdio.
inheritStdio end to end puts the GUI's output in the terminal directly, in
release mode too.

**The blocker, which is easy to miss:** `bin/flutterware.dart` sets
`singleCharMode = true` and subscribes to keystrokes for its `q` handler. Two
processes cannot both own stdin — the launcher would swallow the `r` and reload
would silently do nothing. The launcher must **hand stdin over**, not share it.

**This does not retire `main_dev.dart`** or its four siblings. Those are IDE run
configurations and they give breakpoints; `flutter run` from a terminal does
not, short of `flutter attach`. It is a second loop, not a replacement.

**One unknown to settle while building it:** the GUI reads its context from
`Platform.environment`. Under `flutter run` the app is a child process so the
environment should inherit, but if it does not, `--dart-define` is the fallback
and it changes the shape of the wiring.

### A reload button in the GUI, via the VM service

`flutter_tools` **registers `reloadSources` and `hotRestart` as VM service
methods** (`vmservice.dart`, aliased `Flutter Tools`), and its own doc comment
says why: clients use the external service instead of the VM's internal one,
so that a client connected to an app "started in hot mode" can invoke Flutter
hot reload.

So **both hot reload and hot restart are callable by any VM service client** —
including the GUI itself, next to or inside the Devbar. The condition is that
`flutter run` must be alive: it registers the methods, and it owns the
`frontend_server` that produces the delta kernel. Without it the VM has no way
to obtain new code, so neither works in a release build.

The consequence worth planning around: **that button bypasses `flutter run`'s
stdio entirely**, which means human-triggered reload does not require
`--machine`. It removes the most obvious reason to hurry there.

### What actually forces `--machine`

Not interactive input. The motivating example — "paste the URI you want the GUI
to open" — is `fw show <address>`, which is `viewer.reveal` from decision 5 of
`2026-07-27-gui-cli-mcp-architecture.md` and already item 2 of its Next. A
separate `fw` invocation reaching the running GUI over the session is strictly
better than a prompt: it works from another terminal, from a subdirectory, and
from an agent, none of which a prompt does.

What forces it is:

- **Programmatic reload** — "apply my edit, tell me when the frame is ready",
  which the master plan names as the agent-facing requirement and which a
  keypress cannot express. The Devbar button does not cover this; it is a human
  trigger.
- **Structured build errors**, rather than scraping human-formatted output.
- **Owning the terminal's rendering** — and this is why it is its own step
  rather than a mode swap. Owning stdout means needing a renderer, which is
  master-plan decision 8 and the termui question. Scope the two together or
  neither.

Rejected for this purpose: the existing PTY tee (`runUnderPty`,
`app/lib/src/wrap/transport.dart`). It exists to be *transparent* to arbitrary
commands. We are not transparent, we are a UI, and deciding "is this keystroke
mine or Flutter's" from a raw stream is exactly what `--machine` avoids.

## Failure messages

The one that will be read most often. `.flutterware/` holds an absolute SDK
path, so it is gitignored, so it is **absent after every clone for every
teammate, forever**. That is not an edge case, and the walker cannot fix it
without acquiring the logic that makes it unsafe to freeze.

So the message is the fix, and it has to teach the actual rule:

```
fw: no project set up for fw in this directory or any parent.

The first run has to go through your own Flutter SDK, so flutterware can
record which one to use. From the project root:

    dart pub add flutterware      (skip if pubspec.yaml already has it)
    dart run flutterware          (or: fvm dart run flutterware)

After that, `fw` works here and in every subdirectory.
```

It says *why* rather than only *what*, because the thing a user needs to
understand is that `fw` cannot know their SDK until something running under it
writes it down.

## Open questions

1. **Where do build artifacts live** — `.flutterware/bin/` per project, or
   `~/.flutterware/<version>/` shared? The spike found the existing cache key
   already hashes the *flutterware package root*, so for hosted consumers it is
   per-version and shared across their projects. Shared pays 32s once per
   machine per version instead of once per project; `.flutterware/` then holds
   the SDK symlink and a pointer. Leaning shared, undecided.
2. **`fw` with no arguments** — GUI, or help? `dart run flutterware` launches
   the GUI today. It is the first thing everyone types. *Partially resolved:*
   outside a set-up project, `fw help` prints walker-owned static help and
   bare `fw` prints the setup message; inside one, both forward as before.
3. **Uninstall.** `.flutterware/`, the global binary, the `PATH` line. One
   command should undo all three, and its absence is the kind of thing that
   makes people hesitate at step one.
4. **The transitional version trap.** `dart install flutterware` resolves the
   newest version the installing SDK allows — today, a stable-channel dart gets
   0.5.1, whose `bin/flutterware.dart` is the old bootstrapper and crashes when
   run globally (`Null check operator used on a null value`, because
   `Isolate.resolvePackageUri` returns null with no package config). It
   self-heals once walker behavior ships, but until then the global install is
   actively broken and should probably not be advertised.
5. **SDK skew.** The GUI is built with one SDK and the project may later use
   another. Recording which SDK built the artifacts makes that detectable rather
   than mysterious.

6. **The unexplained 0.58s** in this repository. Not a design input any more —
   users measure 0.12s — but flutterware's own developers pay it on every `fw`.

## The one thing worth restating

`fw` does not run a copy of the launcher. It runs **`dart run flutterware`** —
literally the command a user would type — having found the SDK to type it with.
There is one program, reached one way, JIT-compiled from the project's resolved
sources every time.

That is what makes staleness structurally impossible rather than protocol-
managed, and it is worth ~120ms. An earlier draft spent an AOT artifact, a pin
file, a comparison, a self-replacement protocol and a handoff to save that
120ms, and every one of those was a worse reimplementation of what pub already
does correctly.

**The lesson to keep:** the 1.6s that justified all of it was measured on the
CLI, which `fw` never runs. A design was built on a benchmark of the wrong
program.
