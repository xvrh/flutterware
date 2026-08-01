# Scanning from the package root: how to list files without walking into a trap

**Date:** 2026-08-01
**Status:** Investigation complete. Feeds the whole-package scan, which
[the rename spec](2026-08-01-previews-rename.md) left out of scope.
**Question:** if `roots` defaults to the package root instead of `demo/`, what
lists the files — without a hand-maintained deny-list, and without walking into
`node_modules`, `cdk/out`, or a Flutter SDK.
**Measured:** on this checkout, 2026-08-01, `3.47.0-0.1.pre`. Times are a single
warm run; the ratios are what matter, not the milliseconds.

## The measurement

Walking this repo's root, counting `.dart` files:

| approach | time | `.dart` found |
|---|---|---|
| `listSync(recursive: true)` — **what `_dartFiles` does today** | 904ms | **17,163** |
| the same with `followLinks: false` | 61ms | 1,603 |
| pruned walk: no links, skip dot-dirs + `build` + `node_modules` | **22ms** | 1,127 |
| `Ignore.listFiles` — the vendored lister, called directly | 176ms | **1,127** |
| `listFilesInDirectory` — our wrapper over that lister | 884ms | 1,127 |
| `AnalysisContextCollection.analyzedFiles()` | 1338ms (1151ms setup) | 1,128 |

Per package rather than repo root, which is the shape that will actually ship:
`listFilesInDirectory('app')` is 161ms for 538 `.dart`, and **0** of them under
`app/build/` — which is 4.7GB.

## Three findings, in order of how much they cost

### 1. `followLinks` defaults to **true**, and that is the catastrophic one

`Directory.listSync(recursive: true)` follows symlinks unless told not to.
`.fvm/flutter_sdk` is a symlink to the pinned SDK, so a scan from the repo root
walks the entire Flutter SDK: **17,163 `.dart` files against 1,127 real ones**,
15× the parse budget, before any deny-list is even discussed.

**It is a cost, not a correctness bug — today.** The SDK contains **0** real
`@Preview` annotations: its previewer fixtures hold their sample sources as
string literals, and the scan is AST-based, so a `@Preview` inside a string
never becomes an entry. That is luck rather than design. One annotated file
anywhere in the SDK, or in a symlinked sibling package, and the catalog would
silently gain entries nobody wrote.

`followLinks: false` is the single highest-value line in this whole document,
and it is needed whatever else is decided. It also disposes of the class of
trap this investigation started from: a symlinked `node_modules`.

### 2. Our wrapper costs 5× the lister it wraps

`listFilesInDirectory` ([`list_files.dart`](../../../app/lib/src/utils/list_files.dart)) and `Ignore.listFiles`
([`ignore.dart`](../../../lib/src/utils/ignore.dart)) return **the same 1,127 files** — 884ms against 176ms.

The wrapper builds a `_Directory` per directory and, for every path, walks the
parent chain calling `_ignores`, each level recomputing a relative path and
re-running the matcher. `Ignore.listFiles` carries the accumulated stack down
the walk instead. The vendored lister is already the better implementation; the
wrapper is the thing to stop using, not the thing to optimise.

That matters beyond this feature: the dependencies plugin uses the wrapper.

### 3. On this repo, the deny-list and gitignore agree exactly

Set difference between the 22ms pruned walk and the 176ms gitignore walk:
**zero, in both directions.** Skipping dot-directories, `build` and
`node_modules` reproduces what the project's own `.gitignore` files say, at an
eighth of the cost.

That is not an argument for the deny-list. It is an argument that the deny-list
is *not buying speed we need* — 176ms is affordable — while gitignore buys
correctness on projects whose ignores we cannot guess: a generated `lib/gen/`,
a vendored `third_party/`, a `packages/legacy/` nobody compiles. The agreement
here is a property of this repo, not of Flutter projects.

## The options

**A. Deny-list prune.** 22ms, no dependency. Rejected on the stated grounds:
the list is per-project and unknowable, and it silently over-collects the first
time somebody vendors a directory we have not heard of.

**B. `git ls-files`.** Exactly the project's own view, and fast. Rejected: a
preview file that has just been written is untracked, so it would be invisible
until `git add` — precisely the "where did my preview go" failure the empty
state exists to prevent. Also needs a git repo and a subprocess per rescan.

**C. The analyzer's context collection.** Correct — it excluded `.fvm`, `build`
and `.dart_tool` without being told — and it is what Flutter's own previewer
uses. Rejected on price: **1,151ms just to construct the collection**, for a
file list. It is the right tool when you are going to resolve; we are not.

**D. `Ignore.listFiles`, with a small hard floor. ← recommended.**
Gitignore-aware, 176ms, already vendored and already used. The floor is for
what `.gitignore` cannot be relied on to say:

- **`followLinks: false`**, always (finding 1).
- **`.git/` skipped unconditionally** — it is never in `.gitignore`, and it is
  large.
- Optionally `.dart_tool/` and `build/`, which every Flutter template ignores
  anyway — belt and braces for a package that has no `.gitignore` of its own.

That last point is a real gap rather than a nicety. `listFilesInDirectory`
reads `.gitignore` starting **at the walk root**; files above it are never
consulted. Walking `app/` here works only because Flutter's template ships
`app/.gitignore` with `/build/` and `.dart_tool/` in it. A workspace member
relying on the repo-root `.gitignore` — which is exactly how this repo's root
`.*` rule works — would be walked in full. Either read ignores from the project
root down to the package, or keep the hard floor.

Two more gaps worth knowing, neither fatal:

- Git's global `core.excludesFile` is not read. It is a machine preference, so
  a project that depends on it is already not portable.
- `.gitignore` is parsed per directory on every walk. It must be built once per
  scan and, critically, kept off `fingerprint()` — that runs on the reload loop
  and today only stats.

## What widening the scan does *not* cost

**Ids do not move.** [The rename spec](2026-08-01-previews-rename.md) claimed
they would, and sequenced the work around it; that was wrong.
`CatalogEntry.path` is `p.relative(file.path, from: projectRoot)`
([`discovery.dart:122`](../../../app/lib/src/previews/discovery.dart)) — relative to the *project*, never to the scan
root. Widening `roots` from `['demo']` to `['']` leaves
`demo/buttons.dart#buttons` spelled exactly as it is. Nothing stored has to
change, and the sequencing argument disappears with it.

## Still open, and not answered here

- **Which root.** Per declared package, not the repo root: the config already
  names packages, and scanning a workspace root from one package would attribute
  another package's previews to it.
- **`test/`.** Flutter's previewer scans it. Previews there pull `flutter_test`
  into the compile closure, which is the one place the wider scope has a real
  build cost. Include, exclude by default, or make it a config key.
- **The tree.** Hierarchy is path-derived, so entries under `lib/` gain a `lib/`
  level. Needs a rule — most likely stripping the package's source root the way
  `demo/` is stripped now.
- **What `directory:` becomes.** It stops being the place previews live and
  becomes an optional narrowing, for a project that wants to bound the scan.
