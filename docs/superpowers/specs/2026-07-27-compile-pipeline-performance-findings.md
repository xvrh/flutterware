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
   catalog size; and a demo that does not compile now breaks the catalog's cold
   start rather than only its own entry. The second is a real regression in
   robustness and is worth revisiting with a per-entry compile probe.

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

## Still open

- **`_ensureCompiled` walks `lib/src/catalog` and `lib/src/embedder` on every
  start** to date-check the daemon snapshot. Milliseconds, but O(files).
- **The cmake no-op costs ~110ms** and could be skipped when the host binary is
  newer than `native/`.
- **A demo that fails to compile now blocks the cold start.** Consider probing
  entries individually and dropping the broken ones into `diagnostics`.
- **The idle timeout is fixed at 10 minutes** and not configurable.
