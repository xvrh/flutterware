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

**(b) The CI cache list is short by two directories.**
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

**(c) Scenario frames are not content-addressed.** `ScenariosRunner` takes a
`ShotCache` and uses it for `cache.memo` — the closure memo — and nothing else.
It never reads or writes a frame. So the base side of every scenario is
replayed on every comparison, even though it is a pure function of (base sha,
closure, SDK) and `ShotKey` already exists to say so. The previews half has had
this since the beginning; it is what makes "five agents branched off one master
sha share one set of pictures" true of one half only. With (a) and (c)
together, the base side of a warm CI run disappears: no harness, no replay.

**(d) `pubspec.lock` invalidates everything, by design, and the design can be
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

1. **There is no combined findings view.** `comment.md` merges both halves with
   `rankComparedFindings` — worst first, both halves, one table. The page does
   not: it opens on previews, and scenarios is a tab you have to think to
   click. A reader arriving from a pull-request comment wants exactly what the
   comment just showed them, and the ranking function is already published.
2. **The header is the whole comparison's, over one half's tab.** The scenarios
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
   the page.
5. **63 MB per report, and ~95% of it is rows nobody will open.** The
   breakdown: 36 MB CanvasKit, 18 MB preview shots, 4 MB scenario frames. Only
   11 of 236 rows are findings. `--export=changed` was deferred in the August
   round when the page was mostly read locally; CI hosting is now its main
   career, and the "Not re-rendered" empty state already exists to cover the
   rows whose frames were left out. The CanvasKit third is a hosting question,
   not an export one — identical bytes across every pull request, which git
   deduplicates on the artifact branch and a clone still materialises.
6. **An added entry has no picture at all.** `ComparisonRunner.plan` settles
   `added` and `removed` without rendering either side, so the row reaches the
   page with no `shots` key and the stage says *"Neither side rendered"*. For
   `removed` that is arguable; for `added` it is backwards — a preview this
   branch introduced is the one a reviewer most wants to look at, and the head
   side is sitting right there in the checkout. Found while verifying the
   multi-package export, and pre-existing.
7. **The page carries no provenance.** No head sha, no wall clock, no way back
   to the pull request. The receipt line was already on the open list from
   PR #302; a page reached from a comment is the case that needs it.
8. ✅ **A multi-line note breaks the comment's table.** A compile failure's
   `Δ` cell was written with the compiler's newlines intact, and a newline
   inside a markdown table cell ends the row — so the table rendered broken
   from that row down. Fixed alongside §2: one line and an ellipsis in the
   cell, the whole message on the page.

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
3. **`--export=changed` + the combined findings view** (§3.1, §3.5). Together
   they are what a comment link opens onto. §3.6 — rendering the head side of
   an added entry — belongs in the same bite.
4. **The lockfile narrowing** (§1b d). Its own piece — it touches the skip rule,
   which is the part of this feature least forgiving of a mistake.
5. The cache-list documentation (§1b b), the base sweep (§1c) and the comment
   table fix (§3.7) are independent of all of the above and of each other.

Deliberately not scheduled: caching scenario frames by `ShotKey` (§1b c). It is
right, but with (1) landed the base harness mostly does not start at all, and
the remaining win should be measured before it is built.
