# Bounding `~/.flutterware`

Measured 2026-08-23 on one machine.

**Tier 1 is implemented** — `trimWorkingCopy` in `lib/src/working_copy.dart`,
called from the launcher under the build lock, and only after a build that
worked. Measured on a real install: 1479 MB → 107 MB in 154 ms, and 45–63 µs on
a warm run with nothing to delete. Verified end to end against a throwaway
consumer: a failed GUI build kept its 1129 MB tree, and the retry that fixed it
built, launched, and came out at 109 MB.

One thing that only showed up in that test: a GUI build failing in the Dart
kernel step had **already staged a partial `.app`**, so "the product exists" is
not by itself proof the build finished. The trim needs both that and the
caller's knowledge that nothing failed in this pass.

Everything else here is still design.

## What is there

```
19826 MB   62.2%  installs (x21)          the launcher's working copies
 5531 MB   17.4%  comparisons             per-worktree comparison artifacts
 3998 MB   12.5%  sdks                    orphaned by #145
 1604 MB    5.0%  bases                   40 base checkouts, 23 live git worktrees
  341 MB    1.1%  shots                   swept, 17% of its own cap
  232 MB    0.7%  analysis-cache          written only by a spike tool
  186 MB    0.6%  engine                  2 revisions, both live
  137 MB    0.4%  run                     journals + per-worktree handles
    7 MB    0.0%  transformed, cache, native, shaders, locks
31862 MB
```

Plus **4287 directories holding nothing but `worktrees.json`** — 1.1 MB of JSON
across roughly 34 MB of blocks. Cheap in bytes, and the reason `ls ~/.flutterware`
is unusable.

## Three findings that change the shape of the problem

### 1. The 21 installs are 21 *commits*, not 21 projects

`workingCopyPath` hashes the flutterware package root, and its doc comment says
this makes it "one copy per flutterware version per machine, shared across every
project". That is true for a **hosted** dependency, whose path carries the
version. It is false for a **git** dependency, whose path carries the commit —
`~/.pub-cache/git/flutterware-<40 hex>/` — which is how anyone tracking an
unreleased flutterware actually depends on it.

Hashing each cached git checkout's path (with its trailing separator, which is
what `Isolate.resolvePackageUri` hands back) maps **19 of the 21 installs** onto
a flutterware commit:

| commit date | installs created |
|---|---|
| 2026-08-17 | 5 |
| 2026-08-18 | 1 |
| 2026-08-19 | 1 |
| 2026-08-20 | 5 |
| 2026-08-21 | 4 |
| 2026-08-22 | 2 |
| 2026-08-23 | 1 |

19 installs in 7 days. The launcher's own subtitle — *"Building the tools — once
per flutterware version"* — describes a machine that bumps a version tag. On a
machine that follows the git head it reads **~2.7 installs a day, ~4 GB a day**.

The 2 unmapped installs (2026-07-27 and 2026-07-28, 2015 MB and 23 MB) are the
ones whose pub-cache source pub has since removed. That is a *liveness* signal
and not a heuristic: with the source gone, nothing on this machine can ever
resolve to that key again.

### 2. 77% of the installs is incremental-build state nothing will read again

An install is not 1.5 GB of flutterware. Broken down, per fully-built install:

| | MB | what it is |
|---|---|---|
| `app/build/macos` minus the `.app` | ~1105 | Xcode intermediates. `FlutterMacOS.framework.dSYM` alone is **501 MB** — engine debug symbols, in a release build, that nothing here symbolicates. Plus `ModuleCache.noindex` 325 MB, `Intermediates.noindex` 174 MB. |
| `app/build/catalog/<revision>/` | 204–552 | the previews compiler daemon's warm kernel: `warm.dill` 172 MB, `out` 172 MB, `assets` 172 MB. A real cache. |
| `app/.dart_tool/flutter_build` + `.dart_tool/hooks_runner` | ~265 | Flutter's build-system state. |
| **`Flutterware.app`** | **65** | **the product** |
| `app/build/cli` | 17 | the `fw` binary |
| sources + `package_config` | ~38 | |

The freshness test for the GUI is `DesktopGui.binary.existsSync()` — literally
"is there a Mach-O at
`build/macos/Build/Products/Release/Flutterware.app/Contents/MacOS/Flutterware`".
The CLI's is `_isFresh`, an mtime comparison against `build/cli`. **Neither reads
anything else under `build/`.**

Verified on a fresh build in a scratch copy: deleting everything under
`build/macos` except `Flutterware.app` took it from **1188 MB to 66 MB (−94.4%)**,
and the trimmed bundle still starts — it boots Impeller and reaches
`main.dart:32`, failing only on the missing env vars `main.dart` documents as
required. `otool` confirms why: the frameworks are embedded in
`Contents/Frameworks` and every rpath is `@executable_path`-relative, so nothing
outside the bundle is referenced.

Applied across all 21 installs on disk:

```
19826 MB   installs today
-12183 MB   build/macos trimmed to the .app        no rebuild
 -3059 MB   .dart_tool build state                 no rebuild
 -3032 MB   build/catalog                          costs a warm-kernel recompile
 = 1552 MB
```

**15242 MB — 77% — comes off with no rebuild at all**; 92% if `build/catalog`
goes too, and that one is a real cache whose loss costs a recompile. The whole
install problem is that flutterware keeps a build tree it will never build in
again.

### 3. Rebuilding an install from nothing costs 57 seconds

Measured end to end, cold, from a pub-cache git checkout, on the pinned SDK:

| stage | measured | the launcher's declared budget |
|---|---|---|
| unpack (3282 files, 59 MB) | **1.34 s** | 3 s |
| resolve (`flutter pub get`) | **3.40 s** | 5 s |
| build the GUI (`flutter build macos --release`) | **51.87 s** | 30 s |
| build the CLI | not measured — the launcher overlaps it with the GUI build, at a measured cost of 0.2 s | 10 s |

**56.6 s in total.** So even the *maximal* eviction — delete the whole directory — is a one-minute
penalty paid once, on the next launch, with a narrated progress plan already
built to explain it. This is not a several-minute penalty and should not be
priced like one.

## Answers

### Q1 — what is safe to evict, and on what signal

Three different signals, and the distinction matters more than the thresholds:

**Provably dead — no threshold needed.**
- `~/.flutterware/sdks/` (**3998 MB**). Where the deleted `fw` version-manager
  downloaded SDKs. Removed by *"The SDK is whichever one you started us with,
  and both `fw` binaries are gone" (#145)*. Nothing in the tree reads it today;
  the only surviving mentions are an example path in a doc comment and a test
  fixture string. Delete on sight, once.
- `~/.flutterware/analysis-cache/` (**232 MB**). Written by
  `app/tool/catalog/resolve_spike.dart` and by nothing else. Delete on sight.
- `comparisons/scenarios/` and `comparisons/example/` (**171 MB**). The layout
  from before `comparisonDirFor` started keying on the worktree path; the
  current writer cannot produce these names. Delete on sight.
- An install whose pub-cache source is gone (**2038 MB today**). Pub deleted the
  package root, so the key is unreachable forever.

**Liveness — cheap and exact, so prefer it to age.**
- `bases/`: a base checkout is a registered git worktree. 40 directories on
  disk, 23 registered — `bases/2279b066…` (**553 MB**, the largest) is
  registered by nobody. **Eviction here must go through
  `git worktree remove --force` + `git worktree prune`, never `rm -rf`**, or it
  leaves a stale registration in the owning repo's `.git/worktrees`.
- `run/`: `sweepRunDir` already probes sockets and pids. Two file classes fall
  through every one of its rules and accumulate forever: **`stack-*.json` (41)**
  and **`live-*.json` (37)**. The doc says `live-*.json` is "exactly one per
  project, so it is bounded" — it is one per *worktree*, and worktrees are
  disposable. Both are per-worktree and both should age out when the worktree
  path they name no longer exists.

**Age then size cap — for genuine caches with no liveness signal.**
- `comparisons/<name>-<sha1[:12]>/`. The key is a hash of the worktree path, so
  a sweeper cannot ask "does this worktree still exist" without knowing every
  repo on the machine. One dead worktree holds **5048 MB** — a comparison over a
  consumer's 66-scenario suite, `base` and `head` sides both kept whole. Use
  `ShotCache.sweep`'s rule exactly: 14 days, then a size cap, entries dropped
  whole, plus `sweepScenarioRuns`'s `protect` set for a comparison being read
  right now.
- `app/build/catalog/<revision>/` inside an install. Keyed by SDK identity plus
  newest-source mtime; a new key means a new directory and the old one is never
  removed. Bounded at one revision per install in practice, because an install's
  sources are immutable — the one exception on disk is the oldest install, which
  carries two revisions plus the pre-keying flat layout.

**Leave alone.** `shots/` (341 MB, swept, at 17% of its 2 GB cap — working as
designed). `engine/` (186 MB, two revisions, both currently in use).
`run/journal` (137 MB, already covered by `sweepRunDir`'s handle rule).

### Q2 — when is an install dead, and what does eviction cost

Reframed by finding 2: **mostly, don't evict — trim.** The policy in three tiers,
cheapest first:

**Tier 1 — trim every install, at any age, immediately after its build succeeds.**
Delete everything under `app/build/<os>` except the product bundle, plus
`app/.dart_tool/flutter_build` and `.dart_tool/hooks_runner`. **−13778 MB across
the 19 live installs — 77% of what they occupy — for zero rebuild**, because the
freshness tests read only the product. This
belongs in the launcher, right after the build stage it already narrates: the
tree is immutable, so the incremental state it just wrote can never be used
again by construction.

The one thing to get right: this rule is about `~/.flutterware/<key>/`, **not
about a checkout's own `app/build/`**, where incremental state is the whole
point. `editable` (the path-dependency flag the launcher already computes) is
the discriminator that keeps them apart.

**Tier 2 — evict `build/catalog` on age.** −2595 MB across the live installs, at
the price of one warm-kernel recompile the next time that install's previews are
used. 14 days unread, same rule as `shots/`.

**Tier 3 — evict the whole install.** Only two signals justify it:
- its pub-cache source is gone (provably unreachable), or
- nothing has run from it in N days *and* a newer install exists.

After tier 1 a built install is ~105 MB plus its `build/catalog` (204–552 MB),
and after tier 2 as well, ~105 MB — against ~1500 MB today. So at the measured
2.7 installs/day, tier 3 is worth ~280 MB/day rather than ~4 GB/day, and the
57-second recovery is easy to justify against that. Suggest 30 days, and the
useful atime proxy is
`app/build/cli/bundle/bin/fw` — the launcher spawns it on every run.

An honest caveat about tier 3: an install being unused for 30 days does not
prove the *consumer* is gone — a project pinned to an old flutterware ref uses
exactly one install and might not be opened for a month. That is why the penalty
matters, and 57 seconds is a penalty a monthly user can absorb.

### Q3 — `FactsStore`

The premise needs one correction before the fix: **the injection points exist.**
`flutterwareDir()` honours `flutterwareDirOverride`, and
`WorktreeFactsStore.open` takes `at: File?`. The failure is that the tests that
write don't reach for either — two test files set the override
(`lints_core_test.dart`, `review_agent_test.dart`), three call `open()` with no
`at:`, and eight can reach a `save()` indirectly through `ShellController`.

Measured: one run of `test/shell/config_watch_wiring_test.dart` creates
**exactly 6 stub directories, one per `test()`** — its `setUp` makes a fresh
`Directory.systemTemp.createTempSync('fw_watch_wiring')` per test, and each new
temp path is a new sha. The whole `test/shell/` + `test/worktrees/` suite — 392
tests — creates the same 6, so this one file is the entire source. 4230 of the
4287 stubs name a `/var/folders/…/T/fw_watch_wiring*` path; 4230 ÷ 6 ≈ **705
runs over 13 days**, about 54 a day.

So: **the fix is one `setUp` line**, not an API change. Point
`flutterwareDirOverride` at a directory inside the test's own temp root and null
it in `tearDown`, exactly as the two files that already do it. Doing it in the
shared shell-test helper covers the eight indirect writers at once.

Worth adding a guard, because this will recur: an `app/test/` setup hook that
snapshots `ls ~/.flutterware` before and after the suite and fails on a delta.
The measurement above is that check, run by hand.

**The other 45 stubs are not test pollution — they are the feature working.**
Each names a real worktree, one file per worktree, and worktrees are created and
deleted constantly here. That is a genuine, slow leak (45 in 13 days, ~3/day)
and it ages out on the same liveness rule as `run/stack-*.json`: the file names
its own worktree paths, so a store whose every `opened` path is gone is dead.

**The 4287 existing stubs: yes, worth one cleanup**, but for legibility rather
than bytes — 34 MB is nothing, and a directory with 4300 entries makes every
other question about this tree harder to ask. A one-off script that deletes
`<key>/` where the directory contains only `worktrees.json` (+ `.lock`) and
every path inside it is gone. Not a shipped sweeper.

### Q4 — who runs it, how loud

Follow the precedent, which is already consistent: `sweepRunDirOnce` is called
fire-and-forget from `launch.dart`, once per process; `ShotCache.sweep` runs
inside `Isolate.run` from `comparison_controller`. Both are silent, both swallow
every failure, both run on the path that owns the thing being swept.

**Silent by default, at four owners:**

| what | who runs it | when |
|---|---|---|
| tier-1 trim of an install | the launcher | immediately after its own build stage, before it spawns the CLI |
| `comparisons/` age + cap | `comparison_controller`, beside the existing `ShotCache.sweep` | after a comparison finishes |
| `bases/` unregistered | `BaseCheckout` | when it materialises one |
| `stack-*` / `live-*` / stub dirs | `sweepRunDir` and a sibling | once per process, as now |

Two places to be louder than that:

- **The tier-1 trim is worth one line.** The launcher already narrates
  `LaunchPlan` stages; a build that reclaims a gigabyte can say so where it
  already says it is building. Nothing else needs a voice.
- **One visible surface, because 31 GB earns one.** `fw` has five top-level
  commands (`status`, `actions`, `run`, `init`, `app`). A sixth — `fw disk` —
  that prints the table at the top of this document and takes `--prune` to run
  every sweeper at once, with the tier-3 rules relaxed on request. Read-only by
  default. That is what makes the silent half auditable, and it is what a user
  who has just noticed 31 GB actually wants to type.

Explicitly *not* proposing: a background daemon, a scheduled job, or a GUI
storage panel. The sweepers already have natural owners on paths that run
anyway, and adding a surface to watch a number that a launcher-side trim takes
from 31.9 GB to 18.1 GB on its own would be the expensive way round.

## What this adds up to

Each row is disjoint — the two dead installs are evicted whole, so their build
trees are not also counted in the tier rows.

| | MB |
|---|---|
| today | 31862 |
| provably-dead directories (`sdks` 3998, `analysis-cache` 232, legacy `comparisons` 171, orphan base 553) | −4954 |
| the 2 installs whose pub-cache source is gone | −2038 |
| tier-1 trim, 19 live installs | −13778 |
| `comparisons/` age rule (one dead worktree) | −5048 |
| tier-2 `build/catalog`, 19 live installs | −2595 |
| | **= 3449** |

The 3449 MB left is: 1415 MB of install sources and product bundles, 1051 MB of
live base checkouts, 341 MB of swept `shots/`, 312 MB of recent comparisons,
186 MB of engine, 137 MB of `run/`.

Steady state after that is roughly: one ~105 MB install per flutterware commit
resolved, a bounded `shots/`, an `engine/` revision per SDK, and comparison
artifacts for the last fortnight — a tree that grows about **280 MB a day** on a
machine following the git head, against **~4 GB a day** today.

## What of this reaches a normal user

Everything above was measured on the machine flutterware is developed on, which
is the worst possible sample. Separating the two:

**Does not reach them at all.**
- `sdks/` (3998 MB). The `fw` version-manager that wrote it was added *and*
  removed inside the same `## Unreleased` section — 328bae61 introduced it,
  #145 deleted it, and 0.5.2 shipped before either. No published version has
  ever written this directory.
- The 4230 `fw_watch_wiring` stub directories. `app/test/` does not ship.
- `analysis-cache/` (232 MB). Written only by `app/tool/catalog/resolve_spike.dart`,
  which nothing invokes.
- 19 installs in 7 days. That is the git-dependency law from finding 1. A user
  on a **hosted** dependency gets `~/.pub-cache/hosted/pub.dev/flutterware-<version>/`,
  whose path carries the version — so one install per *published* version,
  shared across every project of theirs on that version, exactly as
  `workingCopyPath`'s doc comment claims. 13 versions have been published in the
  package's life.

**Reaches them, and matters more to them than to us.**

1. **The baseline install is 12× larger than it needs to be.** This is not an
   accumulation problem for a normal user — it is a *first-install* problem. One
   flutterware version, one project, one `dart run flutterware`, and
   `~/.flutterware` is ~1.5 GB of which ~1.4 GB is build state that nothing will
   read again. Tier 1 is the same fix and it is the whole fix for them:
   **~1500 MB → ~105 MB, no rebuild.** Everything else in this document is
   second-order by comparison.

2. **One install per published version, never reclaimed.** At four upgrades a
   year that is ~6 GB/year today and ~0.4 GB/year after tier 1 — the same law as
   this machine, two orders of magnitude slower. Tier 3 (evict when the
   pub-cache source is gone, or 30 days unused with a newer install present)
   still applies; it is just no longer urgent.

3. **`engine/` grows one 93 MB entry per engine revision and nothing prunes it.**
   `ensureEmbedderFramework` keys on `cache.engineRevision` and returns early
   when the stamp matches; `removeLegacyEngineDir` reclaims the *old per-package*
   layout but no code ages out a superseded revision. Two revisions here, both
   live. A user following Flutter stable accumulates roughly one per release —
   ~1 GB/year, of which one entry is ever read. Rule: keep the current revision
   and the previous one, drop the rest.

4. **On Windows the tree is split in two, and one half moves with the shell.**
   Four call sites derive the root, with three different Windows answers:

   | site | Windows resolves to | holds |
   |---|---|---|
   | `working_copy.dart` `userHomePath()` | `%APPDATA%` | the install, `locks/` |
   | `pub_dev_api.dart` `defaultCacheDirectory()` | `%APPDATA%` | `cache/pub.dev` |
   | `run_dir.dart` `flutterwareDir()` | `%HOME%` if set, else `%USERPROFILE%` | `run/`, `shots/`, `comparisons/`, `bases/`, `engine/`, the facts stores |
   | `protocol.dart` `existingRunDir()` | `%HOME%` if set, else `%USERPROFILE%`, else null | the inspector gate |

   So on a default cmd/PowerShell Windows the install lands in
   `C:\Users\x\AppData\Roaming\.flutterware\` while everything else lands in
   `C:\Users\x\.flutterware\` — two trees, and a user who deletes the one they
   found keeps the other. Worse, `HOME` is set by Git Bash/MSYS and not by
   PowerShell, so the *run directory moves depending on which shell started the
   process* — and the run directory is where the daemon socket lives, so a
   daemon started from one shell is invisible to a client started from the
   other. Separately, `%APPDATA%` is the **roaming** profile: domain-joined
   Windows syncs it to a server and quotas it, which is the last place a 1.5 GB
   build tree belongs. `compiler_daemon.dart` already reaches for
   `LOCALAPPDATA`, which is the right answer for all of them.

   Read from the code, not observed — there is no Windows machine here and no
   test covers the Windows root. It should be reproduced before it is fixed.

5. **There is no uninstall.** No `fw` command removes `~/.flutterware`, nothing
   documents where it is, and a user who tries flutterware and drops it keeps
   1.5 GB with no obvious way to find it. The `fw disk` command proposed above
   covers the reclaim; a line in the README covers the discovery.

6. **CI pays the 57 seconds every job.** A runner has no warm install, so every
   job unpacks, resolves and builds. Caching `~/.flutterware` is the fix and at
   1.5 GB it exceeds what most CI cache budgets will carry; at ~105 MB after
   tier 1 it is an ordinary cache entry. Tier 1 is what makes "cache
   `~/.flutterware`" advice worth giving.

**Order for a normal user**, which is not the order for this machine: tier 1
first (it is ~93% of their problem), then the Windows root, then `engine/`
pruning, then `fw disk`. The `comparisons/` and `bases/` sweeps that dominate
here only matter to someone using comparison heavily.

## One number that is not ours

`~/fvm` is **110 GB** across 35 cached SDKs, and `~/.pub-cache` is **13 GB**
(4.6 GB of it 32 flutterware git checkouts, one per commit — the same law as the
installs, one layer down). Both are outside this tree and neither is flutterware's
to sweep. Noted only so that "31 GB" is not mistaken for the whole bill.
