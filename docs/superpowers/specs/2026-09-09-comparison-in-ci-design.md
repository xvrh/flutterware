# Comparison in CI — the fixed cost, several packages, one page

Three questions arrived together from a consumer running comparisons on a
monorepo, and they turn out to be one question asked three ways: **what does a
comparison cost when nobody has warmed anything, and what does it hand back
when the project is bigger than one package?**

The report that started it:

> running all 135 scenarios (135.6s) costs barely more than skipping all 135
> cold (110.6s). The replay is nearly free; the harness is the cost.

That sentence is exact, and this note explains it, prices the fixes, and takes
the two design decisions the fixes need — how several packages land in one
verdict, and what the exported page owes a reader who arrived from a pull
request.

## 1. Where the time goes

Measured 2026-09-09 on this repo — 217 preview entries, 19 scenarios — with
`fw compare`. Every number below is from the halves' own stopwatches, not from
the terminal's, because a piped stdout buffers and lies.

| run | previews half | scenarios half |
|---|---|---|
| **A** — `--base=HEAD`, cold checkout, **every row skips** | 217 entries, 0 rendered → **2.1s** | 19 scenarios, 0 run → **60.5s** |
| **B** — the same run again, dills warm on disk | 2.1s | **2.6s** |
| **C** — `--base=HEAD~5`, a real branch | 430 renders → **47.1s** (~110ms each) | 19 replayed on both sides → **8.9s** |

Run A is the consumer's sentence at one seventh the scale: **a half that
decides to do nothing costs sixty seconds**, while the other half decides the
same thing about ten times as many rows in two.

### 1a. The asymmetry: one half plans without a compiler and the other does not

- **Previews list from a scan.** `PreviewsSide.entries` runs `CatalogScanner`
  over the checkout's sources, and `ComparisonRunner.plan` decides from the
  import graph and a digest pass. Nothing is compiled and no guest is started,
  which is why an all-skip previews half is 2.1s for 217 entries — less than
  the ~2.3s a guest takes to become connectable at all.
- **Scenarios list from the live harness.** `ScenariosSide.scenarios` asks
  `ext.flutterware.scenarios.list`, so `ScenariosRunner.plan` must generate,
  compile and boot a harness **on both sides** before it can look at a single
  closure. The skip rule then runs, concludes there is nothing to replay, and
  the two harnesses are disposed unused.

`ScenariosSide.scenarios` says why it is live, and the reason is real:

> Live rather than scanned: only the running harness knows a scenario's tags
> and its folder profile.

True, and irrelevant to the plan. The plan needs **ids**, a closure per id, and
nothing else. Tags and profiles decide what a *replay* does, and no replay is
happening.

So the consumer's arithmetic reads: 110.6s ≈ base `pub get` + two cold harness
compiles; the extra 25s ≈ 135 replays at ~185ms each. The replay is nearly
free. The plan pays for a harness it then throws away.

### 1b. Five levers

**(a) ✅ Plan the scenario half from the scan; boot lazily.** `ScenarioScanner`
already exists and is already run on every start — it is what
`_ScenarioProgram.sources()` uses to generate the harness entrypoint. It yields
`file` and `name`, which *is* the `<file>#<name>` id. Give `ScenarioSource` a
cheap listing, plan from it, and start a harness only when `toRun` is
non-empty; where one does start, take the live listing and let it correct
`added`/`removed` before anything is replayed.

What this gives up, stated plainly: a scan cannot see `skip:` or a name that is
not a literal, so a scan-only plan can misjudge added/removed. It only ever
does so on a run where **nothing is being replayed**, and the following run
that does replay something re-asks the harness. That is the whole exposure, and
it buys: a pull request touching no scenario closure goes from 110s to
approximately zero.

**Built.** `ScenarioSource` gained `scan`, `ScenariosSide.scannedScenarios`
answers it, and `ScenariosRunner.plan` uses it as a **gate only** — the plan is
remade from the live listing the moment anything has to be replayed, so nothing
is ever *replayed* on the scan's word. `LiveScenarioSource`'s two runners went
lazy with it, because a runner is a claimed build directory before it is
anything else and a run that starts no harness should leave none. Two rules
keep the gate honest: a scan carrying a `scenario()` it could not name answers
null rather than a listing one short (`ScenarioScanResult.unnamed` is the new
signal), and two empty scans are treated as the absence of an answer rather
than an answer, so a package whose harness will not build still reports its
refusal instead of a clean, silent, empty half.

Measured 2026-09-09, the same two runs as the table above:

| | before | after |
|---|---|---|
| every scenario skipped | 60 491ms | **295ms** |
| every scenario replayed | 8 911ms | 7 710ms |

The 295ms starts no process at all, so unlike run B's 2.6s it is the same
number on a cold machine — which is the only column CI has.

**(b) ✅ The CI cache list is short by two directories.**
`docs/compare-in-ci.md` caches `~/.flutterware/shots` and stops. Run A → run C
is the measurement that matters: a *brand new* base sha's harness came up
inside an 8.9s scenario half in run C, against 60.5s in run A, because run A
had left a seed kernel behind. Add:

- `~/.flutterware/kernels` — `SeedStore`, the immutable half of the program
  (SDK + pub cache), keyed on engine revision and compiler flavour. Its own
  doc records 5.5s cold against 1.5s seeded on this repo, and ~15s cold on a
  consumer's.
- `~/.flutterware/bases/<sha>` — the base checkout, which holds the base side's
  built dill under `build/flutterware/comparison`. In CI the base is the merge
  base with the default branch, which is the same sha for every pull request
  open against it.

**Built 2026-09-10, and the second bullet is wrong.** `kernels` is cached, with
`restore-keys` so a lockfile change reuses the previous run's rather than
starting empty. `bases` is **not**, and must not be: a base checkout is a real
`git worktree` registered inside the repository's own `.git`, which a fresh CI
checkout does not have — a restored one is a directory git does not believe in.
The doc says so now, because it is exactly the optimisation somebody reads this
section and tries.

**(c) ✅ Scenario frames are not content-addressed** (built 2026-09-11 — see
§4). `ScenariosRunner` takes a
`ShotCache` and uses it for `cache.memo` — the closure memo — and nothing else.
It never reads or writes a frame. So the base side of every scenario is
replayed on every comparison, even though it is a pure function of (base sha,
closure, SDK) and `ShotKey` already exists to say so. The previews half has had
this since the beginning; it is what makes "five agents branched off one master
sha share one set of pictures" true of one half only. With (a) and (c)
together, the base side of a warm CI run disappears: no harness, no replay.

**(d) ✅ `pubspec.lock` invalidates everything, by design, and the design can be
narrowed.** `pixelInputsOf` folds the package lockfile and the workspace
lockfile into a `PixelInputs` shared by every row, so one changed byte in a
lockfile re-renders and re-replays the entire project. Run C, unedited from the
terminal:

```
217 entries, 430 rendered, 0 skipped in 47060ms
  because pubspec.lock differs — 168 entries
```

The bias behind it is correct and should not be reversed —

> A path wrongly included costs one render; a path wrongly left out reports a
> regression as clean, and nothing downstream can detect it.

— but it is currently all-or-nothing, and in CI that means every dependency
bump and every merge that touches a lock re-renders the world. The narrowing
that keeps the bias: for each entry, collect the **out-of-root package names**
its import closure imports (`ImportGraph` sees the directives even where it
deliberately does not resolve them), close that set transitively over
`.dart_tool/package_graph.json`, and hash only those packages' lock entries. A
bump to a package nothing in the entry reaches then costs nothing, and a bump
to one it does reach costs exactly what it costs today.

**Built 2026-09-10.** `LockInputs` hashes each package's lock entry on its own,
`ImportGraph.packagesOf` answers which packages an entry's closure names, and
`ReachableLock` closes that over `.dart_tool/package_graph.json`. Measured on
the same comparison the terminal above came from:

| | rendered | skipped |
|---|---|---|
| before | 478 | 0 |
| after | **188** | **145** |

59.1s → 29.1s, and `because pubspec.lock differs` is gone from the reasons
entirely. Where the lock *is* the reason it now says which dependency moved:
`pubspec.lock#flutter_svg differs`.

The reach is over-approximated at every step, because the bias is unchanged:
both branches of a conditional import, unused imports, and — the part an
import graph cannot see at all — packages named only in a **string**, which is
how a dependency's *pictures* are reached. `Image.asset(…, package: 'icons')`
and `'packages/icons/logo.png'` are both collected, and deliberately only
those two shapes: `path`, `collection`, `clock`, `http` and `image` are all
packages *and* ordinary words, and matching a bare literal anywhere would put
half a catalog back inside every bump. Anything the split cannot answer — an
unparseable lock, a checkout with no package graph — falls back to hashing the
lockfiles whole, which is the old behaviour exactly.

**One input was included and then measured out.** The lock's `sdks:` constraint
belongs to no package, so "when in doubt, include" said every entry should
carry it — and on a base whose Dart floor had moved, that one line put 145 of
244 entries straight back into the render pass. It also cannot decide a pixel:
a constraint is not a resolution, and both sides of a comparison render with
the *same* SDK, the one the invocation named, which `ShotKey` already carries.
What a raised floor really changes is the package's own language version, and
that is declared in `pubspec.yaml` — which is a pixel input and stays one.

`ShotKey.revision` moves to **v9**: a v8 key hashed the whole lockfile into
every entry and a v9 key hashes a slice of it, so the two disagree for any
project with more than one dependency. The pictures did not change; what a key
*means* did.

**(e) The halves are serialised.** `runComparison` awaits the previews half in
full, then starts the scenarios half. They share a base checkout and nothing
else. Overlap them — with the caveat in §2c about how many processes may be in
flight at once.

### 1c. A disk note, found while measuring

On this machine: `~/.flutterware/bases` **12 GB** across 45 checkouts, several
of them 553 MB. `BaseCheckout.dispose` carries its own confession —

> Nothing calls this on a schedule yet. It exists because the class is built on
> the claim that a base is disposable, and a claim with no way to dispose
> cannot be checked.

`shots` (2.7 GB) and `kernels` (2.0 GB) both sweep. `bases` should too: it is
the largest of the three by four times, and a base whose sha nothing has
compared against in a fortnight is a base nobody wants.

**Built 2026-09-10.** `BaseCheckout.sweep` drops a base whose marker has not
been touched in a fortnight, and `ensure` calls it — swept on use rather than
on a schedule, for the reason `claimBuildDirectory` gives about its own
siblings: a schedule needs a caller wired up and remembered, and this one
cannot be forgotten. Reuse *touches* the marker, so the age is a last-used and
not a created — without that, a base off master, written once and reused for
weeks, is the first thing an age sweep takes.

Age alone, no size budget, which is the one difference from the other two: a
base is half a gigabyte, so pricing it means walking half a gigabyte to decide
whether to keep it. It also crosses repositories — the directory is shared, so
a sweep from one project takes another's expired bases, leaving a stale entry
in that repository's `.git/worktrees` that its own next `ensure` already
recovers from (`worktree add` fails, it prunes, it retries).

## 2. ✅ Several packages in one verdict

### 2a. What is true today

A comparison compares **one previews package against one scenarios package**,
and the second of those is not even selectable:

- `runComparison` takes `options.package ?? core.packages.firstOrNull` for the
  previews half.
- `_compareScenarios` takes no package at all — `core.packages.firstOrNull`,
  full stop. `--package` narrows one half and is silently ignored by the other.

So a project with previews in two packages and scenarios in two others, asked
to compare the second previews package, compares it against the *first*
scenarios package. Running the command once per package does not rescue it
either: every run writes `comparisonDirFor(...)/index.json`, so each overwrites
the last, and `--report` produces one comment and one page per package.

### 2b. The shape

The dimension is cheap to add because almost nothing below the orchestration
knows what a package is. The base checkout is per-repository. The shot cache is
keyed on a closure fingerprint whose paths are already package-qualified. The
diff kernel takes two frames. The viewer takes ids.

1. **`CompareOptions.package` becomes `packages`**, empty meaning *every
   package each half declares*. `_compareScenarios` reads it.
2. **A row gains a `package` field.** An added key, so
   `comparisonReportVersion` does not move and an older reader ignores it —
   which is the property that made added keys cheap in the first place.
3. **An id is qualified only when a run spans more than one package.** Ids
   appear in deep links, in the comment's table and in consumers' scripts over
   `index.json`; qualifying unconditionally would rename every id in every
   single-package project to buy nothing. And because a row now carries
   `package` as a field, no script ever has to parse an id to recover it.
4. **`packages: [...]` on each half**, so the page can facet and the comment
   can group without walking every row.
5. **The halves merge**: items concatenated, `rendered`/`ran`/`skipped` summed,
   `because` maps merged. One `index.json`, one `comment.md`, one page —
   which is the whole of what was asked for.

### 2c. The two decisions this forces

**A package that will not compile is a row, not the end of the run.** Today
`SideDidNotCompile` becomes `ComparisonRefused` and `fw compare` exits 64 with
the compiler's output. With four packages, one skewed base kills the report for
the three that were fine. This is the argument §11a of
`2026-08-11-worktree-comparison-design.md` already settled one level down —

> one decision in the source is one row, however many things hang off it

— applied one level up: one package that will not build is one row. The
verdict gap (`verdictGapOf`) is the right place for it to be visible, so
`fw compare` still exits non-zero and still says which package and why.

**Packages run concurrently, under a pool.** This is where the CI wall clock
is: four packages × two halves × two sides is sixteen `frontend_server` +
`flutter_tester` pairs, and a `Future.wait` over them will take a runner down.
A bounded pool sized from the host, defaulting low.

**Reversed in the building (2026-09-09): serial, and the pool deferred.** §1b
(a) landed first and took the premise away. A package a branch did not touch
now costs milliseconds rather than a harness build, so on an ordinary pull
request there is nothing left to overlap — the one package that changed is the
only one doing work. The case the pool would still help is a lockfile touch,
where every package is expensive at once, and that case belongs to §1b (d):
narrowing the lockfile input is what stops it being expensive in the first
place, and a pool would only make paying it faster. Building the pool now
would be sixteen concurrent processes on a runner sized for one build, bought
for a case the next lever removes.

**Built.** `CompareOptions.packages` replaces `package`, `--package=` is
repeatable, and both halves read it — the scenario half read nothing at all
before. `ComparedItem`/`ScenarioComparison` gained `package` and `inPackage`,
`comparedIdIn` is the published id rule, and `ComparisonResult.merged` /
`ScenarioResults.merged` are the arithmetic. The GUI's environment loops the
same way, deliberately: the panel and `fw compare` write the same
`index.json`, so an id that means one thing in one and another in the other is
a deep link that lands nowhere.

Two things came out of the building that the section above did not anticipate:

* **The comment printed a no-verdict half as a pass.** A half whose harness
  would not build leaves no rows, no rows means no findings, and `comment.md`
  answered *"Nothing changed"* — the one thing a pull-request gate must never
  say. It has always been able to; a per-package refusal, which leaves rows
  from the packages that worked *and* a note from the one that did not, is
  what made it likely enough to find. The comment now leads with the
  `verdictGapOf` sentence, above the viewer link.
* **A multi-line note broke the findings table.** A newline inside a markdown
  cell ends the row, so a failing entry's compiler diagnostics broke the table
  from there down — and that is exactly the row whose note is a compiler's.
  The cell is one line with an ellipsis now; the page has the whole message.

## 3. The exported page

Read from a real export served over HTTP (run C: 236 rows, 11 findings, 63 MB).
Worst first.

1. ✅ **There is no combined findings view.** `comment.md` merges both halves with
   `rankComparedFindings` — worst first, both halves, one table. The page does
   not: it opens on previews, and scenarios is a tab you have to think to
   click. A reader arriving from a pull-request comment wants exactly what the
   comment just showed them, and the ranking function is already published.
2. ✅ **The header is the whole comparison's, over one half's tab.** The scenarios
   tab's rail reads *Changes 0 · All 19* under a header reading *2 failed · 2
   added · 7 changed*. Either the counts follow the tab or they say which half
   they are counting.
3. **A scenario detail wastes its pane.** A two-step scenario draws as a ~60px
   column in the top-left corner of a 620×400 area, with its note (*"the
   refusal is on the step"*) wrapped at the flow's width rather than the pane's.
   Longer flows overflow to the right with no scroll affordance. Fit and centre
   the flow; give the note the pane.
4. **The index rail has no thumbnails.** Eleven rows of grey text, in a tool
   whose subject is pictures. Every frame the rail would need is already beside
   the page. *Partly answered:* the findings view has them, and the rails
   inside the two halves still do not.
5. ✅ **63 MB per report, and ~95% of it is rows nobody will open.** The
   breakdown: 36 MB CanvasKit, 18 MB preview shots, 4 MB scenario frames. Only
   11 of 236 rows are findings. `--export=changed` was deferred in the August
   round when the page was mostly read locally; CI hosting is now its main
   career, and the "Not re-rendered" empty state already exists to cover the
   rows whose frames were left out. The CanvasKit third is a hosting question,
   not an export one — identical bytes across every pull request, which git
   deduplicates on the artifact branch and a clone still materialises.

   **Built 2026-09-10, and two of those three sentences were wrong.**

   The CanvasKit third was not a hosting question at all: the page **never
   loads it**. The viewer is built without `--no-web-resources-cdn`, so the
   browser fetches the engine from `www.gstatic.com` — checked in the network
   log of a served page — while `flutter build web` emits a local copy
   regardless and `copyTo` faithfully copied all 37.9MB of it into every
   export. It is now copied only for an offline build, which is the only kind
   that reads it. Nothing was traded for that; it was dead weight.

   And "Not re-rendered" does not cover a trimmed row. That sentence says
   nothing in the row's inputs changed so it was never rendered, which is
   **false** of a `same` row: both sides rendered and matched. A page that
   said it would be contradicting its own verdict. So the index records
   `exported: findings`, `ComparisonIndex.framesWithheldFor` asks the
   question, and the row gets its own sentence — *"Identical, and not
   exported"*.

   The flag is `--frames=changed`, not `--export=changed`: `--export` already
   takes a directory, so `--export=changed` would have been read as one. The
   default is `all`, deliberately — a page without the unchanged frames cannot
   show what a branch did *not* touch, and somebody browsing for that is a
   real reader. The CI recipe names the other one.

   A scenario is kept or dropped **whole**. Its steps are one graph in a
   pan-and-zoom canvas, and dropping the unchanged steps out of a flow that is
   a finding would leave the reader panning across holes.

   Measured on the same export, both changes together: **65MB → 6.5MB**
   (2.8MB of it `main.dart.js`, 1.6MB fonts, 1.5MB the findings' frames).
6. ✅ **An added entry has no picture at all.** `ComparisonRunner.plan` settles
   `added` and `removed` without rendering either side, so the row reaches the
   page with no `shots` key and the stage says *"Neither side rendered"*. For
   `removed` that is arguable; for `added` it is backwards — a preview this
   branch introduced is the one a reviewer most wants to look at, and the head
   side is sitting right there in the checkout. Found while verifying the
   multi-package export, and pre-existing.
7. ✅ **The page carries no provenance.** No head sha, no wall clock, no way back
   to the pull request. The receipt line was already on the open list from
   PR #302; a page reached from a comment is the case that needs it.
8. ✅ **A multi-line note breaks the comment's table.** A compile failure's
   `Δ` cell was written with the compiler's newlines intact, and a newline
   inside a markdown table cell ends the row — so the table rendered broken
   from that row down. Fixed alongside §2: one line and an ellipsis in the
   cell, the whole message on the page.

**Built (2026-09-10).** The page opens on a **findings** tab — `index.findings`,
which is `rankComparedFindings`, which is the comment's own table — with base
and head thumbnails per row and the compiler's first line where there is one.
A row is a door: tapping hands it to the half that owns it, because the
five-mode stage and the merged flow already live there and a third copy of
either is the drift this codebase keeps paying for. The chips over the strip
count the selected tab, and a receipt above it says
`91a5daa against origin/master · 263 compared · across 2 packages · in 18.5s ·
1m ago` — for which the artifact had to start recording the head commit and
the wall clock, since the only `head` in the file was a worktree **path** on
somebody else's machine.

Two limits are deliberate and worth knowing before the next pass. Frames are
decoded at **twice their drawn width** rather than whole — twenty rows of two
900×700 frames is a hundred megabytes of images drawn at eighty-four pixels —
which is a new `width` on `ShotStore`; and only the first
`FindingsTab.framedRows` rows get frames at all, the mosaic's cap, for the
same reason and in the same place in the argument.

The **added entry** fix is in the runner rather than the page:
`ComparisonPlan` gained `onlyOnHead`/`onlyOnBase`, and the run draws the side
that has the entry. Its verdict is still settled without a picture — the row
is out before anything renders — so what changed is only that the row now has
something to show. Its two keys are computed the same way as everything
else's, and the key for the side that does not have the file is one nothing
ever writes bytes under: fabricating an absence, because a row's `shots` is a
pair and a pair cannot say *head only*.

**Not done, and why.** The scenario half's added flows still show nothing: a
picture for one means *replaying* it, which means booting the head harness —
the thing §1b (a) just stopped doing on a branch that needs no replay, and the
gate would have to learn that an added scenario is a reason to boot. It is the
same fix and a different cost, so it is its own bite.

One more, unresolved: on a cold page load the first selection once showed
*"Neither side rendered"* for an entry whose two PNGs had just been fetched
`200 OK`; re-selecting drew them. `decodeEncodedShot` swallows every decode
failure into a `null`, so the page cannot tell "no frame" from "this frame
would not decode". Worth separating those two answers regardless of what the
underlying cause turns out to be.

## 4. Build order

1. ✅ **Lazy scenario harness** (§1b a). Largest measured win, smallest change,
   and it needed nothing else to land first. 60 491ms → 295ms on an all-skip
   run; the replay path unchanged.
2. ✅ **Several packages** (§2), including the per-package refusal. The pool
   was reversed rather than built — see §2c.
3. ✅ **The combined findings view** (§3.1), with §3.2, §3.6 and §3.7 — what a
   comment link opens onto. `--export=changed` (§3.5) did **not** land with it:
   trimming the export is about what the page weighs, and the rest of this was
   about what it says. It is the next one, with §3.3 (the scenario flow's
   pane) and the rails' own thumbnails.
4. ✅ **The lockfile narrowing** (§1b d). Its own piece — it touches the skip
   rule, which is the part of this feature least forgiving of a mistake.
   478 rendered → 188, on a comparison whose lockfile really had moved.
5. ✅ The cache-list documentation (§1b b), the base sweep (§1c) and the comment
   table fix (§3.7) — independent of all of the above and of each other.

Deliberately not scheduled: caching scenario frames by `ShotKey` (§1b c). It is
right, but with (1) landed the base harness mostly does not start at all, and
the remaining win should be measured before it is built.

**Measured by a consumer, and built 2026-09-11.** On a second push with
identical inputs, the previews half came from the store (0 rendered, 8.5s
against 119s) and all 135 scenarios replayed on both sides — 262s, the whole
cost of a run with findings. The build differs from (c) as written in three
ways worth knowing:

- **The unit is a side's replay, not a frame.** `ReplayStore` files one
  scenario's step list under a key per side, taken over *that* side's closure
  (the base graph for the base, as previews already did), and each step's
  frame and tree as ordinary shots beneath it. A list whose frames were swept
  reads as absent and the side replays.
- **The scan gate answers a fully filed plan too.** When every scenario the
  change needs is filed on both sides, no harness starts — the second-push
  case costs a plan. When anything must replay, both harnesses are still
  listed live, as (a) requires; only the missing sides replay.
- **Two replays are never filed:** one the harness abandoned, and one whose
  requests reached a live network (read off the `answered` the funnel puts on
  each request's event; the app's own network logging carries none and says
  nothing either way — counting it as live kept two of this repository's
  scenarios replaying on every run). Everything else a replay reads is
  in the key — the project's clock and network setting included, and the
  committed network recording, which the skip rule could not see either.
