# Scanning from the package root: how to list files without walking into a trap

**Date:** 2026-08-01
**Status:** **Implemented.** Option D built, default root widened to the
package. What shipped and what it measures is at the bottom, under
[What was built](#what-was-built).
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

*Done. `listFilesInDirectory` is now an adapter over `Ignore.listFiles` rather
than a second walk beside it, and the same 1,127 files come back in 44ms.*

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

## What was built

`listFilesInDirectory` ([`list_files.dart`](../../../lib/src/utils/list_files.dart))
is now a thin adapter over `Ignore.listFiles` rather than a second walk beside
it, and `CatalogScanner._dartFiles` uses it.

**Ancestor ignores were already in the vendored lister.** `Ignore.listFiles`
walks from its root down to `beneath` before the search starts, pushing each
directory's ignores onto the stack
([`ignore.dart:254`](../../../lib/src/utils/ignore.dart)) — the machinery for
"a sub-package inherits the repository's `.gitignore`" was there and nothing
called it, because `listFilesInDirectory` never used `Ignore.listFiles` at all.
So the fix was to delete the parallel implementation, not to write a feature.
The old walk also could not express a negation: `ignored |= parent._ignores(…)`
means a child's `!keep.dart` can never take back what a parent ignored, which is
the opposite of git's last-match-wins.

The root is the enclosing git repository (`gitRootOf`, matching a `.git` of
either shape — directory in a clone, file in a worktree or submodule), so the
gap this document flagged is closed rather than papered over: a workspace member
with no `.gitignore` of its own is now filtered by the repository's.
`.git/info/exclude` is read too. The floor kept from option D is `.git/` and
`.dart_tool/` only — `build/` came off it, because unanchored it would also kill
`lib/build/`, and every Flutter template ignores its own.

| | before | after |
|---|---|---|
| repo root, wall clock | 904ms (`listSync`) / 884ms (old wrapper) | **44ms** |
| repo root, `.dart` found | 17,163 | 1,126 |
| `app/`, list + stat every `.dart` | — | 16ms |

**It agrees with git exactly.** `git ls-files --cached --others
--exclude-standard` and this lister return byte-identical sets at the repo root,
`app/`, `app/lib/`, `lib/` and `examples/example` — zero difference in either
direction. Covered by [`test/utils/list_files_test.dart`](../../../test/utils/list_files_test.dart).

16ms is what settles the *listing* half of the `fingerprint()` worry above. The
other half — that a rescan now fires on every save anywhere in the package — was
real, and is dealt with under
[The rescan](#the-rescan-which-the-widening-broke-and-this-fixes).

**One rule inheritance needed that git does not have:** asking for a directory
by name outranks a rule above it that covers the whole directory. Reading
ignores from the repository down means a home directory that is itself a git
repository with `.pub-cache/` in its `.gitignore` would empty every walk of a
cached package — the dependencies plugin would report each one as zero lines and
zero bytes. When the inherited walk comes back empty, the walk is redone from
the requested directory.

## The rescan, which the widening broke and this fixes

Widening the scan quietly moved a cost onto the hot path, and it took measuring
to see it. `_rescanIfNeeded` runs on the panel's 3s poll *and* at the head of
every `select` — which is every hot reload. Its gate is `fingerprint()`, and the
fingerprint now moves when **any** `.dart` file in the package is touched.
`lib/main.dart` is a file you edit constantly and one that cannot change the
entry set; before, it was not even looked at.

**Where a listing's time actually goes** — measured, and not where either of the
obvious guesses said:

| | repo root, 1,127 `.dart` |
|---|---|
| `listSync` on every directory | 5ms |
| `statSync` on all of them | 1ms |
| the whole gitignore-aware walk | 43ms |
| the same walk with **no ignore rules at all**, over a *larger* tree | 41ms |

So it is neither syscalls nor the ignore matcher: it is per-entity path
manipulation inside the walk — `p.relative`, `p.split`, `p.posix.joinAll` for
every file found. A cache of compiled `Ignore` objects keyed by mtime was
written against the "it must be the regexes" theory and measured at **no
difference**; it was deleted rather than kept as plausible-looking insurance.

Two changes came out of it:

- **`fingerprint()` stopped naming every file**, hashing instead — 151KB of
  string allocated, sorted and discarded every three seconds. It was deleted
  outright a pass later; see the review section below.
- **`CatalogScanner` is incremental.** It holds each file's contribution keyed by
  mtime and re-reads only what moved. Grouping is per file by definition and
  moved inside that cache; duplicate-id and `MultiPreview` checks are cross-file
  and stayed outside it, recomputed on every assembly.

| rescan | before | incremental | gate removed |
|---|---|---|---|
| `examples/example` | 9ms | 8ms | 8ms |
| `app/` | 57ms | 17ms | **17ms** |
| repo root | 134ms | 47ms | **45ms** |

(The middle column is what the scan itself costs; the last is what the daemon
actually pays per changed reload, which was twice that until the gate went.)

What is left is the listing, which is now the floor. Beating it means a
filesystem watcher rather than a poll — worth it if a project makes 47ms felt,
and not before: Dart's recursive `Directory.watch` is unsupported on Linux, so it
is a per-platform answer rather than a swap.

### The review pass, and the four things it caught

Run over the landed change looking for what the measurements had hidden rather
than shown.

**1. The gate had become the cost it was guarding against.** `fingerprint()`
listed and statted the whole package to decide whether a scan was worth it — a
good trade while a scan meant reading and parsing everything, and not one once a
scan re-reads only what moved. Measured, they were the same work: 45ms against
47ms at the repo root. So every reload that *had* something to do paid for the
walk twice — 90ms where 45ms was the floor. `fingerprint()` is gone; `scan()`
answers with [`ScanResult.changed`](../../../app/lib/src/previews/discovery.dart)
and returns the previous entries untouched when nothing moved.

**2. The scan crossed package boundaries.** A plugin's `example/`, a workspace's
`packages/*` — the widened walk read them as part of the package above. Verified
before fixing: a `@Preview` in a nested package was discovered, and the wrapper
imported it *by relative path*, which is both the two-libraries bug again and an
import resolved against a package config that need not contain what that file
imports. A package boundary is where the scan stops now, re-read each scan so a
package created mid-session takes its previews with it.

**3. Inheriting ignores is wrong for a package you are not working in.** The
empty-result guard catches an ancestor rule that blacks a directory out
entirely. It cannot catch a *partial* one: `$HOME` kept as a dotfiles repository
ignoring `bin/` would silently drop `bin/` from every package under
`~/.pub-cache` — including, in the hosted install, the `bin/fw.dart` the copy
exists to carry. The launcher's three walks and the dependencies plugin's three
now pass `ignoreRoot: <the package itself>`; a dependency's own `.gitignore`
still applies, and nothing above it does.

**4. A rescan on the reload path must not throw.** A file listed by the walk and
deleted a moment later — a checkout, a build landing — would take a
`FileSystemException` straight out of `select`. It is treated as gone instead,
and picked up again if it comes back.

Checked and found sound: mtime resolution is microseconds here, not the second
that would make same-tick edits invisible; `Ignore.listFiles` prunes to `beneath`
rather than filtering a full-repo walk, so an ancestor ignore root costs a few
`ignoreForDir` calls and nothing else; the daemon's generated wrappers live in
the *GUI's* `build/`, outside any scanned project, so they cannot feed a rescan
loop; and overlapping `roots` now dedupe through the per-file map instead of
yielding an entry twice.

### One thing the investigation missed

**A preview under `lib/` cannot be imported by a relative path.** The generated
wrapper imported the demo file relatively, always — correct while previews lived
in `demo/`, which has no `package:` URI. A file under `lib/` reached both ways is
*two libraries* to the compiler, with separate copies of every class in it.
`CatalogWrapperWriter.uriFor` now spells `package:<name>/…` for anything under
the package's `lib/`, for the demo itself and for its carried relative imports.

### The questions that were open, and how they were answered

- **Which root.** Per declared package. `rootFor(path)` is per package config,
  as it already was.
- **Nested packages.** Excluded — a package boundary is where "the package"
  ends. `test/` is included and `example/` is not, which sounds inconsistent
  until you note that one is this package's own directory and the other is a
  different package that happens to live inside it.
- **`test/`.** Included — the scan is the package. A preview there pulling
  `flutter_test` into the compile closure is a cost somebody opted into by
  writing one, not a reason to make the default surprising.
- **The tree.** Nothing needed doing: `buildCatalogTree` already drops the
  directories every entry shares
  ([`catalog_tree.dart:146`](../../../app/lib/src/previews/catalog_tree.dart)),
  so a package whose previews all sit under `lib/` collapses that level by
  itself, and a package with some in `demo/` and some in `lib/` gets both — which
  is what it should show.
- **What `directory:` becomes.** An optional narrowing, and the only reason to
  write it. It also moves where `new` writes, so the place files are written and
  the place they are looked for stay the same; with no `directory:`, `new` still
  writes to `demo/` (`defaultAuthoringDirectory`), which is a convention about
  new files rather than a constraint on where previews may live.

## The other listings in the tree

Audited after the fact, since the same trap is not previews-specific.

**Fixed here, both raw recursive walks over user-controlled directories:**

- `ScenarioScanner.scan` ([`scenarios/discovery.dart`](../../../app/lib/src/scenarios/discovery.dart))
- `_unreachableFiles` ([`assets_core.dart`](../../../app/lib/src/plugins/native/assets_core.dart)) —
  gitignore-awareness is not just hygiene here: it *is* the finding. A generated,
  ignored file under an asset directory was being reported as "on disk, and not
  in the bundle", which is a false positive by construction.

**Fixed for free**, having always gone through `listFilesInDirectory`: the
dependencies plugin's line counts, and the launcher's three walks in
`bin/flutterware.dart` — the working-copy copy, the freshness check and the
source stamp. Those were walking `.git/` on any project whose `.gitignore` does
not mention it, which is every project.

**Left alone, deliberately:**

- `findPackages` ([`repo_layout.dart`](../../../app/lib/src/shell/repo_layout.dart))
  is the deny-list approach this document rejected, but it runs *before* any
  package is known and is bounded by `maxDepth`. Worth revisiting; not a trap.
- `codeMetricsOf` ([`code_metrics.dart`](../../../app/lib/src/overview/model/code_metrics.dart))
  globs `lib/**`, `test/**`, `tool/**`, `bin/**` with `followLinks: false`. It
  carries a TODO asking for exactly this treatment; bounded to source
  directories, so the cost is counting the odd generated file.
- `_guessedSources` ([`compiler_daemon_client.dart`](../../../app/lib/src/previews/compiler_daemon_client.dart))
  walks flutterware's own `app/`, not a user's project.
