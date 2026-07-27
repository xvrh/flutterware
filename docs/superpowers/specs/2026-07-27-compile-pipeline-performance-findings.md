# Compile pipeline performance — findings

2026-07-27. Question asked: *is the architecture the best it can be at squeezing
every second between the GUI, the agent and everything else?*

Answer: the marginal loop was already right. What was wrong was **fixed** cost,
and almost none of it was the user's code.

## Where the time was

| phase | start | now |
|---|---|---|
| `dart run` recompiling the daemon itself | 3166ms | 121ms |
| daemon prepare (scan, bundle, compiler, cold compile, host) | 2742ms | ~600ms |
| **first client, connect → ready** | **5908ms** | **2313ms** |
| **second client, connect → ready** | 5908ms | **19ms** |
| entry switch | 6–16ms compile + 66–130ms reload | unchanged |

The 3166ms was found only by instrumenting phases and noticing the daemon's
internal sum did not add up to the observed time. The gap *was* the answer: the
tool was recompiling itself — analyzer, image, vm_service — on every start.

## `Platform.resolvedExecutable` was never a real constraint

`package:frontend_server_client` spawns the compiler as
`Platform.resolvedExecutable <snapshot>` with no way to override it. That cost
twice over:

- inside a Flutter app `resolvedExecutable` is the app binary, so compiling
  in-process relaunched the app — recursively, observed, not theorised;
- it derives the SDK from the same path and hard-codes the argument list, so
  `--initialize-from-dill` was unreachable.

Neither is a platform limit. **`flutter_tools` does not use the package**: it
spawns `dartaotruntime frontend_server_aot.dart.snapshot` itself
(`packages/flutter_tools/lib/src/compile.dart`, `_compile`). Both artifacts are
in every Flutter checkout at `bin/cache/dart-sdk/bin/`.

So `FrontendServer` (`app/lib/src/embedder/frontend_server.dart`) is ~180 lines
speaking the same line protocol, taking its executable as a required parameter.
The old `_refuseToRunInsideAFlutterApp` guard is gone with the package that
needed it: the fork bomb is now unrepresentable rather than detected.

**Lesson worth keeping:** a wrapper package's limitation had shaped an
architecture. It was worth 30 minutes to read the 450 lines it was hiding.

## Correction: `--initialize-from-dill` is worth ~25ms, not 2s

Commit `e222cc5` claims "cold compile 2396ms -> 341ms" and credits the flag.
That is wrong. Measured by alternating with and without a warm kernel:

```
with warm kernel:     307ms, 318ms
without warm kernel:  322ms, 353ms
```

The old and new argument lists are equivalent (`--sdk-root`, `--platform`,
`--target=flutter`, `--output-dill`, `--packages`, `--incremental`; the package
additionally passed an inert `--filesystem-scheme`), and both resolved to the
same `dartaotruntime` + AOT snapshot spawn. So the 2396ms figure was
environmental, not caused by the client library.

The warm start is still kept — 25ms is 25ms, and it costs one file copy — but it
is not the reason the pipeline got fast. The reason is that a compile against
`platform_strong.dill` only compiles the app's own libraries; the framework
arrives precompiled. ~320ms is the real cost of a cold catalog compile here.

**Lesson worth keeping:** a 7x improvement that survives several runs can still
be environmental. Alternate the variable; do not trust before/after across a
session.

## Sharing the daemon

The plan's thesis is that the GUI and the CLI are two *drivers* of one pipeline.
They were two drivers of two copies: `CatalogSession`, `CatalogScreenshot` and
the headless check each started a daemon and each paid the full cold path.

`DaemonAddress` hashes the whole `DaemonConfig` into a socket path under
`~/.flutterware/run/`. Consumers derive the same address from the same config
and find each other without being told about each other. Deliberately the
*whole* config: adding a field without thinking about sharing should split the
daemon, not hand a client someone else's compiler.

- clients connect before considering a spawn;
- a file lock makes a startup race produce one daemon rather than two;
- the daemon binds *before* it prepares, so an early client waits instead of
  failing, and a second daemon losing the bind is a correct outcome, not an
  error;
- it exits ten minutes after its last client leaves.

### What sharing a compiler forces

Three pieces of shared mutable state had to become per-session. Two were
obvious; the third was not, and no test would have caught it.

1. **The asset bundle.** A guest reads `kernel_blob.bin` by name at launch. Each
   session gets a directory of symlinks to the shared bundle, including that
   file; asking for a kernel of its own replaces the symlink. The compiler now
   writes outside the bundle entirely, so the prepared kernel is immutable and a
   just-attached client can launch a guest with no compile at all.

2. **The delta path.** The compiler writes every incremental dill to the same
   file. A reply naming it would be overwritten by the next client's compile
   before this client's guest had reloaded. Each reply now names a per-request
   copy.

3. **Lazy wrapper registration — the subtle one.** The entrypoint generator
   added an entry's wrapper file on first visit. Deltas are relative to the
   *compiler's* baseline, not to any guest: whoever selected an entry first was
   the only client whose delta carried its wrapper. A second client selecting
   the same entry later would be handed a delta with the wrapper **absent** —
   unchanged since the baseline — and its guest, which never had that library,
   would reload nothing.

   `registerAll` imports every entry up front, so a select only ever changes
   `main.dart` and every delta is valid for every guest. This removes the
   divergence rather than tracking it.

   Cost, stated plainly: ~20ms of cold compile for five entries, scaling with
   catalog size; and a demo that does not compile would break the catalog's cold
   start rather than only its own entry. That second cost is paid off below.

## Quarantine: a broken demo costs you that demo, not the catalog

`CompileBlame` reads the compiler's own diagnostics — `<path>:<line>:<col>:
Error:` — and maps each reported file back to the entries declared in it. Blame
is per *file*: a file that does not compile takes every entry in it, because
none of them can be reached.

The daemon then compiles in rounds. On failure it quarantines what it can blame,
drops those imports, and tries the rest. Errors nobody declares an entry in — a
shared helper, the app itself — cannot be fixed by dropping anything, so they
stay fatal and say so rather than quietly serving a shrunken catalog.

A quarantined entry is re-admitted when its **source file changes**, so fixing a
demo is enough: no restart, no rescan. If it still fails it is quarantined again
with the new timestamp, which is what keeps that from looping.

Quarantine moves the catalog under clients that are idle, so the daemon
broadcasts `CatalogChanged` to every session and `DaemonReady` carries the same
at connect. A panel must not keep offering an entry the daemon can no longer
build, nor keep hiding one that now works.

One bug worth naming, because the symptom pointed elsewhere: `drop` removed the
entry from the import list but never rewrote `main.dart`. The compiler kept
reading a file that still imported what had just been dropped, so round two had
nothing new to blame and the whole thing presented as *"nothing could be
blamed"* — as if the attribution were broken. The generator now owns its active
entry so `drop` can rewrite the entrypoint itself.

`full` now uses the compiler's `reset` rather than restarting it, so one client
launching a guest no longer discards another's warm state. Verified: `reset`
yields a 45MB whole program and the guest renders the selected entry.

## What is verified, and how

`app/tool/catalog/headless_check.dart`, which asserts on what the guest
*painted* — not on a reload reporting success. That distinction is not
pedantic: the wrong-entry screenshot bug passed every test it had.

New checks cover both halves of the sharing claim — that a second client costs
nothing (`reused`, <500ms), and that it is nonetheless isolated (different
asset dirs, different kernel paths, byte-different kernels).

## Guest devices: on demand, not pooled

Asked directly: with a panel open and rendering, can an agent get its own guest
quickly, and are guests reused?

**Reused: no. Created on demand, one per client, killed when the client leaves.**
`CatalogScreenshot.captureAll` keeps one warm across a *batch*, so screenshotting
20 entries pays for one guest; two separate invocations pay twice.

Measured, with a daemon already running:

```
attach to the daemon        3–19ms
guest process → socket        10ms
        → vm service         110ms
        → first painted frame 374ms
```

So an agent screenshotting while a panel is open costs roughly
`19 + 374 + ~90 (select + reload)` ≈ **480ms**, and none of it is compilation.
Verified that the panel is undisturbed: the first client keeps rendering its
entry while the second compiles and launches its own guest.

The guest must stay client-owned for the GUI, because the texture bridge shares
an IOSurface with the process holding the socket. A *headless* guest has no such
constraint — `kMsgCapture` writes a frame to a file — so the daemon could keep
one warm and serve captures at the marginal 161ms, with no launch at all.
`kMsgResize` already exists, so one warm guest could serve different sizes.

Not built. The 374ms is engine startup, it is paid only once per invocation, and
the batch case — the one that dominates — already avoids it. Worth doing if
single screenshots turn out to be the common agent pattern.

## A long-lived daemon needs a version, not just an address

The daemon outlives the session that started it, and clients attach to whatever
is listening. Nothing restarted one when its *own code* changed — so editing the
daemon and re-running kept yesterday's behaviour, silently.

That is not a developer-only annoyance. The daemon decides what goes into a
hot-reload delta. A daemon predating `registerAll` registers wrappers lazily,
and hands a guest a delta missing a library the guest never had; the VM then
says

```
lookup Failed: wrapInApp in @method in file: .../shell.dart
```

naming a symbol from the *wrapper's* imports, which is a long way from the
cause. `DaemonConfig.daemonRevision` is derived from the daemon's own sources,
so a newer client derives a different `DaemonAddress` and starts its own; the
stale one idles out.

It has to live **in the config**, not beside it: the daemon computes its own
address from the config file it is handed. Passing the revision only to the
client's `DaemonAddress` put the two on different sockets, and the daemon exited
with *"address already served"* — a failure that reads like a race and is not
one.

**The general shape:** any process that outlives its caller and is found by a
derived address must fold its own build into that address. Otherwise the address
identifies *what it serves* but not *how*, and "reuse the running one" quietly
becomes "reuse the old one".

## Unix socket paths are shorter than you think

`sun_path` is 104 bytes on macOS, 108 on Linux (`man 7 unix`). The CLI installs
the GUI at `~/.flutterware/<sha1>/app/`, which is 70 characters before anything
is appended, so a socket under that copy's `build/` overflows:

```
.../app/build/embedder/guest-session-5.sock    107 bytes
```

Both the daemon and the guest sockets now live in one `flutterwareRunDir()` —
`~/.flutterware/run/`, 47 bytes with a name — and `checkSocketPath` fails with
the offending path and the limit. The OS error names the limit but nothing that
produced the path, which is why this took a report from outside to find.

Worth recording that the cap was *already known* here — it is why the daemon
socket was put in a short directory in the first place — and the guest socket
was lengthened under the deep path anyway. Knowing a constraint and encoding it
are different things; `checkSocketPath` is the encoding.

## Still open

- **`_ensureCompiled` walks `lib/src/catalog` and `lib/src/embedder` on every
  start** to date-check the daemon snapshot. Milliseconds, but O(files).
- **The cmake no-op costs ~110ms** and could be skipped when the host binary is
  newer than `native/`.
- **The idle timeout is fixed at 10 minutes** and not configurable.
- **A failing compile is slow** — 2.4s against 0.3s for a successful one — so a
  cold start with a broken demo pays it twice, once to fail and once to retry.
- **A warm headless guest in the daemon** would take a single agent screenshot
  from ~480ms to ~161ms. See above for why it is not built yet.
