# A new worktree pays for a compile every other worktree already did

2026-08-26. Opening previews or scenarios in a freshly created worktree cost
~6s here and ~15s on a real consumer project, every time, for a program whose
libraries are ~95% files that no checkout owns. This is where that time went and
what is left of it.

## Where a cold start's time goes

The daemon's own log, on this repo's 159-entry catalog in a worktree created
minutes earlier:

| phase | ms |
|---|---|
| scan | 191 |
| quarantine | 21 |
| asset bundle | 80 |
| host build (concurrent) | 1834 |
| **cold compile** | **6031** |

A consumer's numbers, from their daemon logs: scan 220–255, asset bundle
235–342, host build 1530–1663, **cold compile 14830–14984**. The compile is
~95% of the start in both, and every other lane already overlaps it.

## Three things were wrong, and none of them was the compile

### 1. `reject` on nothing rebuilds the program

`ResidentCompiler.compile` rejected every failed compile. On the *first* compile
of a process there is nothing accepted to roll back **to**, so the reject
recompiles the whole program's outlines to arrive back where it already was.
This catalog has one deliberately broken fixture: the failing compile cost
6112ms and the reject after it another **5496ms**, of an 11.6s start.

Fixed by rejecting only once something has been accepted. Nothing is given up:
a caller whose first compile failed goes on to change the program — the catalog
drops the entry it blamed — and until an `accept` the next compile is a whole
program either way. **11637ms → 5852ms.**

### 2. The warm kernel was keyed on the daemon's own revision

`DaemonAddress.key` hashes the whole config, `daemonRevision` included, and the
warm kernel and quarantine were filed under it. They are functions of the
sources, the engine and the package resolution, and none of those move when
flutterware's own code does — but keyed on the address they moved anyway, and
every move cost a cold start plus another ~95MB kernel left behind. Measured:
touching one file in the daemon's own closure took the next start from **841ms
to 10493ms**. For a consumer the same happens on every flutterware upgrade,
because the unpack rewrites every mtime.

Fixed with `DaemonAddress.kernelKey` — the same hash minus `daemonRevision` —
and a `learnedDir` under it. **10493ms → 887ms**, with the quarantine carried
over.

### 3. Nothing was shared between checkouts

The remaining 5.5s is a real compile of a real program, and there is no
mechanism to speed it up. There is one to *skip* most of it.

## The seed

A warm kernel is per worktree because it holds the project's own sources at
their absolute paths. Everything else in it — the framework, the SDK, every
resolved dependency — lives outside the worktree and is identical for every
checkout on the machine. So the first checkout to compile leaves a kernel of
**only that half** behind, and every checkout afterwards starts from it.

Building it does not cost a second compile. The root is a *per-request*
argument in the frontend server's line protocol, so a warm compiler can be asked
for a different program built out of the libraries it already holds:

```
reset; recompile <seed.dart>   →  74ms   (the shared half, 82MB)
reset; recompile <program>     →  225ms  (back where it was)
```

against 4687ms to compile the shared half from cold. `FrontendServer.asideAt` is
that excursion; `writeSeedKernel` is what it is for.

### Measured

This repo's catalog, in a worktree created for the measurement:

| | cold compile |
|---|---|
| no seed | **6031ms** |
| seeded | **1671ms** |

Scenarios, the harness compile isolated:

| | compile | harness ready |
|---|---|---|
| no seed | 3479 / 3225 ms | 4395 / 4162 ms |
| seeded | **693 / 705 ms** | **1114 / 1123 ms** |

Whole `fw run scenarios run` — CLI startup, asset bundle, tester spawn, the
scenarios themselves, the captures — moves **15.9–17.0s → 12.8–13.0s**. The
compile drops 78% and the wall drops 23%, because the compile was never the
whole of that number: unlike the catalog daemon, where it is ~95% of a start, a
scenario run does most of its work after the harness is up. Quote the compile
when comparing, not the wall.

Writing the seed costs ~800ms including the 82MB copy, once per resolution per
machine.

Two checkouts compiling the same seed produce a **byte-identical** file. That is
not decoration: the root a seed is compiled from is itself a library in the
kernel, so it lives beside the seed in the shared directory rather than in
whichever checkout happened to build it.

### What goes in, and what takes it out

Only libraries under the Flutter SDK or the pub cache — the trees where the way
to change something is to resolve a different version, which moves its path. A
path dependency is *not* immutable, so a sibling package somebody edits daily
stays out and keeps being compiled per checkout. The same list is what
`SourceInvalidator` skips, because "nobody edits it" and "everybody can share
it" are the same claim.

Every package that made it in is recorded by name and resolved directory, and
compared against the current resolution before the seed is handed over.
**Invalidation on the compiler's side is all-or-nothing**, which is what makes
the precision worth having. With one dependency moved to a new path:

| | seeded compile |
|---|---|
| unchanged resolution | **1600ms** |
| an **unused** package moved (370 files) | **1573ms** — no effect at all |
| a **used** package moved (347 files) | **6098ms** |
| a **used leaf** package moved (180 files, nothing imports it) | **6298ms** |
| no seed at all | 5600ms |

Not proportional, and not a dependent cascade — a leaf costs as much as a
widely-used package. Any package *in the seed* resolving elsewhere discards the
whole seed, and a discarded seed is 82MB loaded for nothing, which is why the
manifest is compared before the file is passed rather than after.

Correctness is never at stake either way: with the seed stale, the moved
package's new code landed in the output kernel (marker present, twice) and no
path from the old version survived. A stale seed costs time, never an answer.

Recording what the seed *contains* rather than what the project resolves is
therefore the whole of the affordance. Most of a lockfile's churn is in packages
nothing imports, and keying on those would throw the seed away for every one of
them.

### Two lanes, one seed

The catalog daemon and the `flutter_tester` harness compile under the same flags
against the same resolution, so they reach the same file and whichever runs
first pays for both. The seed directory is keyed on the engine revision and the
compiler flags — as the flag list itself, not a boolean, so two lanes share a
seed exactly when they would produce the same kernel.

A seed that is a strict *superset* is still used, and it does cost something.
Measured on `fw run scenarios run` end to end, where the two seeds are unusually
far apart — this repo's catalog resolves 57 packages and the sample project 32:

| the scenarios harness compiles from | ms |
|---|---|
| nothing | 3479 / 3225 |
| the catalog's seed (57 packages, 82MB) | **1509 / 1490** |
| its own seed (32 packages, 54MB) | **693 / 705** |

So of the ~2.6s there is to save, the shared seed delivers ~1.85s and gives
~0.75s back — 70% of the best case, for one file on disk instead of two. The
program it emits also carries 1.3MB of libraries nothing reads (61.0MB against
59.7MB cold).

Undershooting is worse than overshooting — a seed holding a fraction of what the
program needs saves a fraction of the compile — so `find` prefers the *largest*
matching seed rather than the closest. And this measurement is close to the
worst case for sharing: the catalog is this whole GUI and the scenario target is
a sample project. In a real consumer both lanes compile the same app and the two
seeds nearly coincide.

## Concurrency

Every checkout on the machine writes to one directory, and a fleet of worktrees
starting at once is the normal case rather than the exotic one. Three rules
cover it, and the third is the one that took a fix:

- **Every write is a rename.** The kernel, the manifest and the root are each
  staged beside themselves under a pid-suffixed name and renamed into place, so
  a reader sees a whole file or none. Staged names end in `.tmp`, which is
  neither `.dill` nor `.json`, so a listing never picks one up mid-flight.
- **The kernel lands before its manifest.** A manifest is a promise that the
  file beside it is loadable; written first, a reader could be handed a path
  that is not there yet.
- **The root is written atomically too, and only when it would change
  anything.** This is the one that is easy to get wrong. Naming the root by its
  manifest hash is what makes two checkouts produce the same kernel — and it
  also aims them at one path. A plain `writeAsStringSync` truncates the file
  another checkout's compiler is that moment reading, and a half-read root does
  not fail: it is a *smaller seed that looks like a whole one*.

Measured — three worktrees created for the test, seed directory empty, all three
started simultaneously so all three race to build it:

```
c1 connect=10125ms coldCompile=6626ms entries=159 quarantined=1
c2 connect=10033ms coldCompile=6764ms
c3 connect=10062ms coldCompile=6563ms
wall for all three: 18.9s
```

Afterwards: one kernel, one manifest, one root, zero staging files — and the
kernel is **byte-identical** (`b45060ea…`) to the one a single process building
alone produces. The same three, started together against a seed that already
exists: 3968/4119/4270ms, 12.7s wall.

Nobody locks, and nobody should. Two checkouts racing to build the same seed do
the work twice and write the same bytes; a lock would serialize a cold start
behind another checkout's cold start to save ~800ms of duplicated work. What is
*not* tolerated is a torn file, and renames give that without one.

The one window left is narrow and self-healing: a sweep can unlink a kernel
between the moment `find` returns it and the moment the compiler opens it. On
POSIX an already-open file survives the unlink; on Windows the delete fails and
is swallowed. Either way the worst outcome is a compile that starts cold, which
is what it would have done without a seed at all.

## What was measured and rejected

- **Rewriting the paths inside a kernel.** A donor worktree's kernel byte-patched
  to a new worktree's paths compiles in 764ms — but only with equal-length paths
  and a canonical symlink. A real rewrite through `package:kernel` costs ~1.5s,
  gives 1372–1590ms, leaves a gap in `compiler.sources`, and pins a vendored copy
  of an SDK-revision package. The seed is faster and has none of that.
- **A seed built from the whole resolution** rather than from what the program
  reached. Measured: 9250ms to build, 8808 errors (`dart:mirrors` on the Flutter
  target), 146.3MB, and when used it emitted a 107.7MB program with 12.7MB of
  dead libraries and 2409 phantom sources. Whatever is in the seed is emitted
  into the output; over-approximating is not free.

## What is left

- The excursion is paid once per resolution per machine, but it is paid on a
  start that was already cold. Nothing pays it twice.
- `build/catalog/<address>/` still holds `out/` (~187MB) and `assets/` (~91MB)
  per daemon revision, and nothing sweeps them. Measured on one machine: 6.5GB.
  The kernels moved out from under the address; the rest did not.
- A methodological note worth keeping: **`frontend_server` implicitly initializes
  from its `--output-dill` when `--initialize-from-dill` is absent.** Every
  measurement of a "cold" compile has to delete the output dill first. A set of
  earlier conclusions in this investigation were wrong because it did not.
