# The UI catalog's first five minutes

**Date:** 2026-07-31
**Status:** **Implemented**, same day — see [What landed](#what-landed). Two
forks settled before drafting: **no fallback sweep** (a first-time project has
no `@Demo` anywhere, so there is nothing to find), and a **hard rename** of
`entrypoint:` to `directory:`.
**Cause:** reported from a real project — demos in `examples/`, not `demo/` —
where the tool took 30s to produce an error that named neither the directory it
searched nor the way to change it.
**Evidence:** measured on this checkout, 2026-07-31. Numbers in
[The thirty seconds](#the-thirty-seconds) are from `CompilerDaemonClient.connect`
driven against `examples/example` with a catalog root that holds nothing, and
from daemon logs in `~/.flutterware/run/`.

## The thirty seconds

The reported symptom was "the daemon took 30s to start and ended with an error".
The assumption behind every earlier reading of this — including the comment that
sits on the code — was that the wait is the cold build, and that a project with
no demos simply pays it before being told. That is wrong. **Nothing is built.
The thirty seconds is a poll loop waiting for a socket that was deleted four
milliseconds in.**

| | measured |
|---|---|
| daemon kernel snapshot, when stale | 1485ms |
| scan of an empty root | **1ms** |
| polling a socket that no longer exists | **30000ms** |
| **total, catalog root with nothing in it** | **31629ms** |
| total, `examples/example` with 6 entries, engine framework cached | 4046ms |
| total, genuinely cold success (from a daemon log: framework 4346ms + cold compile 8453ms + host 822ms + the rest) | ~14200ms |

So the failing case is **eight times slower than the succeeding one**, and the
slowness is pure waiting. The sequence:

1. `_main` binds the socket ([`compiler_daemon.dart:67`](../../../app/tool/catalog/compiler_daemon.dart)) — the file appears.
2. `serve()` calls `_prepare()`, which scans in 1ms, finds nothing, and throws
   ([`:431`](../../../app/tool/catalog/compiler_daemon.dart)).
3. The catch at [`:334`](../../../app/tool/catalog/compiler_daemon.dart) sends `DaemonFailed` to every session in `_sessions`
   — **which is empty**, because the client is still polling and has not
   connected yet. The message goes nowhere.
4. `_shutdown()` deletes the socket file; `exit(1)`.
5. The client's poll loop ([`compiler_daemon_client.dart:447`](../../../app/lib/src/catalog/compiler_daemon_client.dart)) never sees a
   socket again and runs to its 30-second deadline.
6. It reports `the compiler daemon never started listening` — true, and useless.

The comment above that loop states the invariant it relies on: *"The daemon
binds before it prepares, so this waits only for the bind."* That holds only
when preparing **succeeds**. On failure the daemon is gone before the first
poll, and the faster it fails the more certainly it is missed. **The quickest
failure in the system produces the slowest feedback**, which is why this reads
as a hang rather than as a refusal.

The real message — `no catalog entries found under demo` — is not lost: the
client appends `_tailLog` to the `StateError`. It arrives half a minute late,
under a wrong headline and a Dart stack trace, rendered as red 12px
`SelectableText` in the middle of the panel
([`catalog_view.dart:377`](../../../app/lib/src/catalog/catalog_view.dart)).

**None of this needed a daemon.** The GUI holds its own scan of the same
directory, in ~38ms, in-process, before the panel mounts. It knew there were no
entries and started a compiler anyway.

## What a first-time user is not told

Five silences, and each one is a place the answer already exists in the code.

**Where it looks.** `_defaultRoot = 'demo'` is a private constant
([`ui_catalog_core.dart:46`](../../../app/lib/src/plugins/native/ui_catalog_core.dart)). The string `demo/` appears in no README section, no
dartdoc on `@Demo`, no scaffolded config, and no generated capability doc. The
convention is real and undocumented.

**How to change it.** `UiCatalogPackage(pkg, {entrypoint})` — a name that reads
as "the `.dart` file with `main()`", for a value that is a directory to scan.
Its dartdoc says *"the plugin's convention applies when null"* without naming
the convention ([`first_party.dart:84`](../../../lib/src/plugins/first_party.dart)). `ScenariosPackage` calls the identical
idea `directory:`.

**That a typo is a typo.** `rootFor` returns the configured string unvalidated
([`ui_catalog_core.dart:229`](../../../app/lib/src/plugins/native/ui_catalog_core.dart)); `_dartFiles` silently skips a missing directory
([`discovery.dart:99`](../../../app/lib/src/catalog/discovery.dart)). `directory: 'exmaples'` behaves exactly like a correct
directory that is empty.

**Where it looked, on success.** `CatalogPackageEntries` carries `path`,
`entries` and `diagnostics` — no directory. `fw run ui_catalog entries` on a
project with none prints an empty list and nothing else.

**What to write.** No authoring hint, no empty state, no scaffolding action.

There is also one piece of advice the API does not keep: `@Demo`'s dartdoc tells
a project to register a custom annotation *"in `previewAnnotations`"*. That
field exists on the scanner ([`discovery.dart:46`](../../../app/lib/src/catalog/discovery.dart)) and on the wire
([`protocol.dart:462`](../../../app/lib/src/catalog/protocol.dart)), and is not exposed on `UiCatalogPackage` at all. The
daemon's refusal message points at it too.

## The shape of the fix

**Scenarios already solved all of this**, four commits ago, and the UI catalog —
older, and the first plugin anyone opens — has none of it.
`ScenarioListPackage` carries `directory:` and an `authoring:` hint populated
exactly when the list is empty ([`scenarios_core.dart:1189`](../../../app/lib/src/plugins/native/scenarios_core.dart)); the panel shows "No
scenarios in `<dir>`", the hint, and a **New scenario** button
([`scenarios_plugin.dart:308`](../../../app/lib/src/plugins/native/scenarios_plugin.dart)); `fw run scenarios new` writes the first file. Most
of what follows is porting that pattern rather than inventing one.

The reframing that decides the rest: **a catalog with no entries is not an
error.** It is what every project looks like before its first demo is written,
and it is the state the tool should be best at. The current design treats it as
a fatal condition discovered by a compiler — which is both the wrong verdict and
the wrong component to ask.

### Why no fallback sweep

The rejected alternative was to sweep the package for stray `@Demo`/`@Preview`
annotations when the configured root is empty, and name what it found. It reads
well against the reported case, where twelve demos genuinely sat in `examples/`.
It is wrong for the case that matters more: **a project opening the tool for the
first time has no annotations anywhere.** The sweep would spend its effort on
the rare migration and answer "found nothing, in more places" for the common
first run — while making the message longer at exactly the moment it should be
shortest. A project that already has demos in an unconventional folder is a
person who can read one sentence naming the directory and the override.

## The work

**P0 — the empty catalog never reaches the daemon.**
`UiCatalogCore` answers, from the scan alone, whether a package has a root that
exists and entries in it. The panel gates `sessionFor` on that answer instead of
starting a session unconditionally ([`ui_catalog_plugin.dart:73`](../../../app/lib/src/plugins/native/ui_catalog_plugin.dart), [`:352`](../../../app/lib/src/plugins/native/ui_catalog_plugin.dart)). No
daemon, no wait, no error — an empty state, at scan speed. The two `entries.first`
sites ([`catalog_session.dart:909`](../../../app/lib/src/catalog/catalog_session.dart), [`:1365`](../../../app/lib/src/catalog/catalog_session.dart)) are guarded so the crash is
unreachable rather than merely unreached.

**P0b — a daemon that dies is noticed when it dies.**
Independent of the catalog, and the more valuable half: the poll loop must
detect the daemon's exit rather than run to a deadline. Spawning non-detached
long enough to observe an early exit, or watching for the socket to appear *and
then vanish*, both turn 30s into milliseconds. Every fast daemon failure — not
just this one — currently costs half a minute and reports the wrong cause. The
`DaemonFailed` message that already exists should be what surfaces, and the
"never started listening" headline should be reserved for a daemon that really
never bound.

**P1 — `directory:`, hard rename.**
`UiCatalogPackage(pkg, {directory})`, matching `ScenariosPackage`. `entrypoint:`
is removed, not deprecated; the only in-tree use is this repo's own config
([`tool/flutterware.dart:26`](../../../tool/flutterware.dart)), updated in the same change. The dartdoc names
`demo/` out loud. `previewAnnotations` is either exposed on `UiCatalogPackage`
— it is already plumbed end to end — or the advice is cut from `@Demo`'s
dartdoc; an API that documents a knob it does not have is worse than one that
documents neither.

**P2 — say where you looked, always.**
`CatalogPackageEntries` gains `directory`, and `authoring` when the list is
empty — the shape `ScenarioListPackage` already has. One
`catalogAuthoringHint(directory)`, in one file, mirroring
[`authoring.dart`](../../../app/lib/src/scenarios/authoring.dart), reused by the CLI result, MCP, the GUI empty state and the
daemon's refusal, so the four cannot drift. Status becomes `no entries in demo/`
rather than `no entries`. A configured directory that does not exist is
distinguished from one that is empty, in the status and in the hint.

**P3 — a first demo, from a button.**
`fw run ui_catalog new --name='Buttons'` writes `<directory>/buttons.dart`,
creating the directory, mirroring `scenarios new`. The GUI empty state carries a
**New demo** button above the hint and the resolved directory. `fw init`'s
scaffolded config names `demo/` and the override in its comment.

**P4 — the sentence, where people look.**
One sentence in the README's UI catalog section and on `@Demo`'s dartdoc, saying
where demos live and how to move them. `docs/capabilities.md` is generated, so
it follows from the action descriptions.

## What landed

All of P0–P4, plus `previewAnnotations` exposed rather than cut — it was
already plumbed from the scanner to the wire, so keeping the dartdoc's promise
cost a config key and a thread through `DaemonConfig.forPackage`.

**The measurement, re-taken on the same setup:**

| | before | after |
|---|---|---|
| catalog root with nothing in it, cold daemon snapshot | 31629ms | 1608ms |
| the same, warm snapshot | 31629ms | **249ms** |

The remaining 249ms is process spawn and handshake. The GUI does not pay even
that: the panel gates its session on its own scan, so an empty catalog never
reaches a daemon at all.

Guarded by two integration tests in `app/integration_test/compiler_daemon_test.dart`
— one asserting the *cause* is reported and the wait is under 15s, one asserting
the recorded failure is read exactly once so a retry after a fix is not answered
by the previous run's reason.

Verified end to end against the reported case — config declaring
`directory: 'examples'`, demos in `examples/` — through `fw run ui_catalog
entries`, `new`, and `inspect` (`ok: true, errors: []`, so the scaffold renders
as written).

Two wordings changed during implementation, both because the first draft failed
the case that prompted this:

- The empty-directory message no longer suggests `directory: 'demo'` to
  somebody who has already declared `directory: 'examples'`. A declared
  directory that does not exist now says so, and says that it is the only place
  scanned. Suggesting the default back to a person who overrode it reads as the
  tool not having noticed what they set, which was the original complaint.
- The daemon's refusal names the directories **absolutely**, and marks the ones
  that do not exist.

## The successful start, which turned out to be the other half

Left out of the first draft as "spent on work that is genuinely needed". Half of
that was wrong. Measured per phase off the timings the daemon already reports:

**A single demo that does not compile cost ~3.9s on every start, forever.** The
quarantine was not persisted, so each start rediscovered it the expensive way —
compile everything, fail, attribute, drop, recompile, then a third
whole-program rebuild to repair the delta. Three compiles to relearn what the
last run knew. On this repo's own catalog: 4514ms of compile against 620ms
without the broken fixture.

**`_prepare` was strictly sequential, and three of its four chains are
independent.** Only the C host needs the embedder framework; the compiler needs
neither. Run in sequence the start cost their sum — on a first run, a ~93MB
framework download and a cold compile each waiting on the other.

**The framework was cached per project, not per machine.** `engineDir` was
`<appPackageRoot>/.engine`, and a hosted install unpacks `app/` per project
under `~/.flutterware/<sha1(packageRoot)>/`. Every project downloaded and kept
its own 93MB copy of an artifact that depends on nothing but the engine
revision.

### What was done

- **The quarantine is persisted** beside `warm.dill`, honoured only for entries
  whose source mtime is unchanged since it failed, and discarded wholesale
  whenever the warm kernel is — the engine, the package resolution or
  `trackWidgetCreation` moving means the last compile said nothing about this
  one. A quarantine covering every entry is dropped rather than applied.
- **The whole-program rebuild is conditioned on `_blamedWhilePreparing`**
  rather than on the quarantine being non-empty. It repairs a delta written on
  top of a failed compile; a start that already knows what is broken never
  writes one, and testing the quarantine would have paid the rebuild forever
  precisely to undo a failure that no longer happens.
- **Three lanes under `Future.wait`** — framework→host, asset bundle, compiler —
  with the one real ordering kept: the kernel is published into the bundle.
  `wait` rather than three bare awaits, so a lane failing while another runs is
  observed rather than becoming an unhandled async error.
- **`ensureEmbedderFramework` owns its location** and returns it, downloading
  into a staging directory and renaming into place so two projects starting at
  once cannot link against a half-unzipped framework. The orphaned per-project
  copy is reclaimed on proof it is ours.

### Measured, on this repo's own catalog (26 entries, one broken)

| | before | after |
|---|---|---|
| restart, everything cached | 5525ms | **1181ms** |
| nothing cached | 9983ms | 11136ms → dominated by an unavoidable cold compile, with the download and host build now overlapped rather than added |
| broken demo touched (must retry) | 5525ms | 5724ms — unchanged by design |
| broken demo repaired | — | 1111ms, entry readmitted |

The safety property is the one that matters and is tested three ways in
`app/integration_test/compiler_daemon_test.dart`: a recorded quarantine is
honoured only while the source is untouched, a touched-but-still-broken demo is
retried and re-quarantined, and a repaired one comes back.

## Still not in scope

The cold compile itself — 620ms for a small catalog, ~8s for one whose demos
import the whole app. It scales with the transitive import graph of the demos,
not with how many there are, and `--initialize-from-dill` is already wired up.
Reducing it means compiling less, which is a different conversation.
