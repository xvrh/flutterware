# Comparison — what a worktree did to the pictures

**Date:** 2026-08-11
**Status:** design, brainstormed with the owner. **Steps 1–5 of §12 are built**
(2026-08-11), previews and scenarios both; §12 records which commit did what.
Rebased onto master's transition-events work, which shipped `verb`/`target` on
the step capture while this branch was adding the same thing — §7a records what
survived. The space, the static viewer and the MCP surface are not built. Every
decision below was taken in that conversation and **all of them are settled** —
§13 lists them, and §14 is the short list of constants deliberately left for
measurement. Every number is cited to the findings doc that measured it; nothing
here was measured for this design.
**Leans on:** `2026-08-10-worktree-changes-design.md` (the base definition, the
"delta is the unit" rule, the isolate discipline — **not merged into this
worktree yet**, this doc rebases onto it), `2026-08-10-address-spaces-brief.md`
(the space grammar this consumes), `2026-07-30-scenarios-design.md` (the
artifact triple, FakeAsync determinism), `2026-07-27-compile-pipeline-performance-findings.md`
(every compile/reload number below).
**Prior art in-tree:** `HeadlessCatalog.auditAll` already keeps one guest warm
and reloads per entry — it collects errors where this needs pixels, and that is
most of the difference. `lib/src/scenarios/harness.dart:593` already writes the
per-step artifact triple this diffs.

## The one word

**Comparison.** Not *diff* — the files tab owns that word and the confusion
would be permanent. Not *golden* / *baseline* — nothing here is blessed,
approved, or committed; both sides are computed from git on demand.

| surface | name |
|---|---|
| space | `fw:///comparisons` |
| CLI | `fw compare …` |
| artifact index | `index.json` |
| the two sides | **base** and **head** |
| what a row can be | same · changed · added · removed |

## What this is

Run every preview and every scenario in two places — the worktree as it sits on
disk, and its base — and say what changed. It answers the question the files tab
structurally cannot: *the diff says 200 lines moved; did the app change?*

Two consumers, and the design serves both from one artifact:

- **A human** wants to look. Pixels, a wipe slider, a merged flow tree.
- **An agent** wants to read. A 38%-changed heatmap tells it nothing;
  `Padding.all 12→20` is actionable. The tree channel is also what makes the
  pixel channel *explainable* to the human — "38% changed, because the card got
  24px taller".

## 1. The base, and why the checkout is disposable

**The base is whatever the changes screen says it is** — merge-base with the
default branch, head is the worktree as it sits on disk including staged,
unstaged and untracked. One definition, two tabs; the comparison never computes
its own. Arbitrary refs (`agent-a..agent-b`) fall out of the grammar in §7 and
are deferred, not designed against.

Materialising the base is the only genuinely new expensive thing in the feature,
and the decision that makes it cheap is:

> **The base checkout is a build fixture, not state.** A shared
> `git worktree add --detach` per `(repo, sha)` under `~/.flutterware/bases/<sha>`,
> one `pub get`, render, and it may be garbage-collected at any time. What
> survives is the **shots**, and they are content-addressed.

Consequences worth stating, because each one is a feature nobody has to build:

- Five agents branched off the same master sha share one base checkout **and one
  set of base shots**.
- The explorer already knows every worktree's merge-base. Warming the base in the
  background is a scheduling decision, not new machinery — and in the steady
  state a comparison renders **only the head side**.
- A finished comparison's index is a few KB of JSON pointing into the shared shot
  cache. It survives its worktree for free. **Do not build teardown for
  something that costs nothing to keep.**

## 2. The shot cache

One entry, keyed on everything that can change its pixels:

```
key = sha1(entry closure ‖ asset manifest ‖ pubspec.lock ‖ axes ‖ knobs
           ‖ sdk version ‖ capture settings)
~/.flutterware/shots/<key>.raw      the frame
~/.flutterware/shots/<key>.tree.json
```

The cache is not a base cache. It serves the **head** side by the same key, so
re-running a comparison after an unrelated edit re-renders nothing, and it is
shared across every worktree on the machine.

Scenario granularity is coarser and deliberately so: one run produces a whole
tree of steps, so the key covers the scenario's closure and any app change
invalidates all of its steps. The owner's ruling is **replay all** — per-branch
replay is representable (`advance` bumps the deepest unvisited split) but buys
too little to justify the second code path.

Eviction is LRU by total size. Not designed here beyond that.

## 3. The skip rule — the whole performance story

The frontend_server knows each entry's transitive dependency set. If nothing in
an entry's closure differs between base and head, the entry **cannot** have
changed: skip both renders and report `same` without rendering anything.

This is what turns 213 entries into 14, and it has a second-order effect that
matters more than the wall clock: **the verdict list is complete before any
rendering starts.** Hashing is the whole computation, so within ~100ms the screen
knows all 213 rows' status and exactly which ones need pictures. It draws its
full shape immediately and the thumbnails fill in. No spinner, no blank page.

The trap is the inputs you forget. Assets, `FontManifest.json`, `pubspec.lock`,
l10n `.arb`, the SDK pin are all in the key. **Over-invalidate on doubt** — a
false "changed" costs one render, a false "same" is a lie the tool cannot detect.

## 3a. Correction — the compiler cannot answer the closure

§3 says "the frontend_server knows each entry's transitive dependency set".
**It does not, and cannot be made to.** Its program is the *generated
entrypoint*, which imports a wrapper for every entry visited so far
(`EntrypointGenerator._entrypoint`), so the source set it reports is the union
of all of them; `FrontendServerResult.newSources` is a delta against whatever
was already loaded, not a closure. Only a fresh daemon per entry gives a
per-entry answer, and that is a cold compile each — the cost the skip rule
exists to avoid.

`ImportGraph` follows imports instead, and that is the better shape rather than
a concession: **no daemon, no guest, no compile**, so the skip decision runs
before anything is started, which is what §3's second-order claim actually
requires. Measured on this repo: first entry 171ms across 118 files
(its own, its shell's, and `package:flutterware`'s — a path dependency inside
the checkout, so a change to the framework package correctly invalidates the
example's previews); ~1ms per entry after that, since closures overlap and each
file is parsed once.

It over-approximates deliberately: both branches of a conditional import,
`part`s, exports, unused imports. A file wrongly included costs one render; a
file wrongly left out reports a regression as clean, and nothing downstream can
detect that.

## 4. The diff kernel

Pure Dart, `package:image` is already a dependency, and it runs in `Isolate.run`
— the same discipline the changes scanner is held to.

**Raw in, raw out.** Previews' guest is already spawned with `--capture-raw`, and
`ScenarioRunArgs.captureRaw` exists for the same reason: PNG encoding is ~80% of
a 1× capture's cost. So the pipeline captures raw, diffs raw against raw, and
encodes PNG **only for what is displayed**.

**Threshold, no re-render.** The owner's ruling: both sides run on the same
machine against the same binaries, so a self-diff calibration pass is not worth
its cost. A pixel counts as changed when its maximum channel delta exceeds a
small epsilon; an entry is `changed` above a small fraction of changed pixels or
any cluster above a minimum size. The exact constants are to be tuned on real
branches, not decided here.

**Clusters are computed on the same pass** — connected components over the
changed mask, emitted as rects. One computation, three consumers: the agent's
coordinates, the UI's jump-to-next-change, and the crop for a zoomed thumbnail.

### Alignment, because a naive pixel diff is mostly noise

A card that grows 24px taller makes an unaligned diff report most of the screen.
Two answers, both wanted:

- **Tree-anchored**: match nodes by identity, diff their rects and properties,
  and let the pixel diff *illustrate* a delta already named.
- **Scanline LCS** on the two images: an inserted band reads as an inserted band,
  and everything below it stays `same`.

## 5. Channels

A step or entry is not "a picture plus extras". It is a set of **named channels,
each with its own differ and its own normalise/ignore rules**:

| channel | source | rules it needs |
|---|---|---|
| `pixels` | the raw frame | epsilon + minimum cluster |
| `tree` | `.tree.json` | node identity; property allow-list |
| `semantics` | `.semantics.json` | traversal order is significant |
| `texts` | `capture.texts` | none |
| `events` | ✅ `08db2c68` — network, analytics, logs, platform channels, captured between steps | channel + title, digits masked |

`events` is the reason to build the seam now rather than later. Tokens,
timestamps and request ids will make every event diff 100% noise without field
masks, and retrofitting a mask concept into a kernel that assumes "pixels have a
threshold and everything else is exact" means reopening it. It is also the
highest-value non-visual channel in the system: a duplicated request, a new
analytics call, an N+1 that appeared because a fetch moved into a builder — none
of it changes a pixel. FakeAsync makes the ordering deterministic, so alignment
is `(method, url-template, ordinal)`.

**Visual stays first.** The other channels are available, not promoted.

## 6. Previews

**Default axes, default knobs.** A specific value may be requested for a run; the
cross-product is not offered. Two devices × three languages is six times the cost
and six times the rows, and nobody asked the question that way.

### The clock is a gap, not a setting

`ScenarioRunArgs.clockOrigin` exists and its doc comment already names this
feature as its purpose. **Previews have no equivalent** — verified by grep. The
ruling is that previews should *always* pin dates, so this is a change to the
preview guest: render the entry body under `withClock(Clock.fixed(…))`, with the
same honest caveat the scenarios doc states — it reaches `package:clock` only,
and a raw `DateTime.now()` cannot be intercepted by anything, in any test.

Worth doing regardless of comparison: it makes every preview screenshot
reproducible.

### Identity and renames

Entries are keyed by id, and **a moved file reads as removed + added. That is
accepted.** The changes screen's `--name-status -M -z` pairing could fix it, and
deliberately will not: a rename produces two rows that are individually correct
and sit next to each other, which is a small cost against a second identity
scheme running underneath the first one.

## 7. Scenarios

### 7a. Auto steps get a derived label

Today an unnamed capture is `step 3` — an index-derived label that breaks the
moment anything is inserted. `_resolve(target, 'tap')` already knows the verb and
`finderForTarget` already knows the target kind, so a derived label costs
nothing to produce.

**Emit it structured, not as a baked string:**

```jsonc
"action": { "verb": "tap", "target": "pay", "kind": "key" }
```

Three reasons it must not be the string `tap(#pay)`:

1. The aligner can then distinguish *same verb, different target* from
   *different verb*.
2. It can rank stability by kind — `key > type > icon > tooltip/label > text`.
3. **A text target's label changes across the language axis.** `tap("Pay")` and
   `tap("Payer")` are the same step; a flat string cannot know that, and a
   structured one lets the aligner downweight `kind: text` and match on position
   instead.

`auto` stays as it is and `name` is not overwritten — which steps the author
named is real information. `action` sits beside them.

**Master shipped `verb` and `target` while this was being written** (`#87`,
rebased 2026-08-11), so the plan's `action: {verb, target, kind}` became
master's two flat fields plus one addition — `targetKind`, the trust rank,
which is what the aligner reads before deciding how far a label can be trusted.
Master's own test caught the rest: the richer per-`Target` descriptions this
proposed broke the rule that the error a verb throws and the step it records
use *one* spelling. A target reads back as what the author wrote, everywhere.

**Write `position` down.** `_capture` already computes
`'${_state.plan.path}#${_ordinal}'` — the split choice path plus the ordinal
since the last split — uses it for replay dedup, and throws it away. Putting it
in the step record is nearly free and gives the aligner a branch-scoped anchor,
so an insertion shifts positions within one branch segment instead of globally.

Built 2026-08-11, and building it corrected one thing: a choice in that path is
a branch's **index** in its `split`, not its label — `'0.1#3'`, not
`'guest.express#3'`. So renaming a branch leaves every position beneath it
untouched, and *reordering the map* moves them all. That is the right way round
for §7b, and it is why the two keys divide the work the way they do: branches
match by label, and positions only ever match *within* an already-matched
branch.

This change is **independent of comparison and should ship ahead of it**: the
flow view, `fw run scenarios list`, the MCP surface and the auto-write generator
all currently say `step 3`.

### 7b. Split makes it a tree

`split(Map<String, Future<void> Function()>)` replays the whole body per branch
and dedups the shared prefix by position, so what lands on disk is a tree: every
step carries `parent`, and a branch's first step wears the `branch` label. Splits
nest.

**Two trees side by side stop being readable at the first added branch** — the
entire right side shifts. The primary view is therefore **one merged tree, drawn
once, each node carrying an A/B state**; side-by-side is a per-node drill-down.

Alignment:

1. **Match branches by label.** Split map keys are authored strings — the most
   stable identifier in the system.
2. **LCS within each branch's linear run**, over the label sequence
   (authored name → action → position → content hash). It must be an LCS and not
   a map lookup, so that `tap(#next)` three times aligns correctly and a fourth
   inserted in the middle is one insertion, not three renames.
3. **A second pass pairs leftovers by content hash** within the same branch
   segment, reported as its own delta kind — *step retargeted*. This is what
   stops a `#pay` → `#pay_now` key rename reading as removed + added over an
   identical picture.

Delta kinds that exist only because of splits, and which must each report as
**one** delta rather than N steps:

| kind | reads as |
|---|---|
| branch added | "new branch: apple pay, 4 steps" |
| branch removed | one collapsed row, expandable |
| split introduced | the fork itself is the delta |
| split collapsed | likewise |

A removed branch's steps exist only on the base side. **Render them lazily on
expand** — rendering them eagerly costs a full base run the skip rule would
otherwise avoid.

When a scenario is mostly auto steps with `kind: text` targets, say so in the
header — *"6 unnamed steps, alignment is a guess"* — rather than producing a
confident-looking wrong diff.

### 7b-bis. What building the aligner corrected

Two things reasoning had wrong (`08db2c68`):

- **A linear scenario is a chain of single-child nodes, not a list of
  siblings.** Aligning sibling lists compares one step against one at each
  level and recognises no insertion at all. The run has to be flattened —
  every step until one forks — before the LCS can see it.
- **A retarget claim needs a verb on both sides.** Two steps that merely lack
  one share nothing but a gap; pairing them on that turns a renamed `Shot`
  into a claim about what the app did.

### 7c. Axes — always the default

A scenario's folder profile offers devices and languages, and a comparison takes
**the first of each**, exactly as a bare run does. Never "whatever the last
manual run used": a comparison that inherits transient UI state is not
reproducible from its address, and two people looking at the same `<id>` would
see different pictures.

### 7d. Ranking

`pass → fail` outranks every pixel delta and sorts to the top. A scenario that
now fails is the single most valuable output of the feature.

## 8. The artifact

```
~/.flutterware/comparisons/<id>/
  index.json          the whole verdict; a few KB
  <rev>/              per-revision deltas — diff PNGs, cluster rects
```

As built (`ComparisonArtifact`):

```jsonc
{
  "base": "0c05335f…", "head": "/Users/…/worktree", "ms": 4575,
  "counts": { "added": 1, "changed": 4, "skipped": 6 },   // both halves
  "previews":  { "rendered": 0, "ms": 178, "counts": {…}, "items": [ … ] },
  "scenarios": { "ran": 4, "skipped": 0, "ms": 4397, "counts": {…},
                 "note": "…",                             // only if it refused
                 "items": [ … ] }
}
```

A previews item, and a scenario's step, are the same row:

```jsonc
{ "id": "demo/card.dart#card", "state": "changed", "label": "tap \"Accept\"",
  "channels": {
    "pixels": { "changed": 0.0038, "sizeChanged": false, "width": 390,
                "height": 844, "clusters": [{"x":12,"y":40,"w":180,"h":64}] },
    "tree":   { "deltas": [ … ] },
    "texts":  { "added": ["We use cookies"], "removed": [] },
    "events": { "added": ["network GET /order/#"], "removed": [] }
  } }
```

A scenario adds `branches` and holds its rows under `steps` instead of
`channels`.

**Two named halves, never one flat list.** `items` at the top of a file holding
both means previews to whoever wrote it and everything to whoever reads it. The
counts *are* merged, because "did this branch break anything" is a question
about the branch: one preview that broke and one scenario that broke is two
broken things, and which half they came from is the second question.

**Everything is precomputed in Dart** — diff images, cluster rects, tree deltas,
alignment. The GUI panel, the MCP tools and (later) a static HTML page are all
dumb viewers over the same `index.json`. Three hosts, one artifact, which is the
pattern the inspect kit already proved. The HTML page only gets expensive if it
is made to do the comparing.

### 8a. What folding the scenario half in corrected

Both found by reading the file the CLI had been printing all along (`f7f8…`):

- **A scenario that gained a step was reported as `added`.** The verdict took
  the worst state among its steps, and `added` outranks `changed` — so a flow
  that has existed for months read as new, and sorted above one that genuinely
  came out different. A step's own word does not carry up: at scenario level,
  `added`/`removed` mean the scenario exists on one side only.
- **A rename above a `split` reported every branch under it twice.** The LCS
  drops the renamed step's pair, orphaning each branch on *both* sides — once
  as gone, once as new, over a flow whose shape did not change at all. Orphans
  are now matched by label before being reported, which also aligns their
  bodies; what has no counterpart is the case that handling was written for.

Rows that were never run — skipped, or present on one side — are **in** the
list. A missing row tells a reader nothing; "skipped" tells them the tool looked
and found no reason to run it. Same reason a harness that would not build
records a `note`: an empty list is also what a project with no scenarios leaves
behind, and a reader who cannot tell those apart reads silence as a clean bill.

### Revisions

Latest is enough, **except while a re-run is in flight**: the previous revision
stays browsable, and the running one is browsable as it fills. So the index
carries `latest` and `running` pointers, and a row shows the new result the
moment it lands, the old one marked stale until then.

The revision is **not in the address**. It is two states of one comparison, and
an address naming a revision would be pasted into agent output and go stale
within a minute. A segmented *previous · running* control in the header is where
something that transient belongs.

## 9. Where it lives — corrected (2026-08-11)

**Not its own space. Three tabs on the worktree's changes panel**, alongside the
file diff. **Merged with that panel on 2026-08-11**, when #88 landed it — which
had independently chosen the same `changes` slot, the same reservation shape,
and the same `fw capture` fix (`shownScreenId`). What differs is that its screen
reads git and so renders for a worktree **nobody has opened**, which these two
halves cannot: they need the previews and scenarios cores, and those need a
resolved config. So the files tab stands alone there and the other two say to
open the checkout.

```
[ files ][ previews · 14 of 213 ][ scenarios · 5 ]
```

This reverses §13.8, and the reversal is worth writing down because the original
was argued from the wrong thing. "A comparison spans two plugins and needs a
session on both sides" is a fact about the *runner* — and `fw compare` already
disproves it, running with no session on the base at all, materialising a
checkout and driving its own. What a comparison spans is not what a screen
belongs to. The case that matters is *this work against its base*, which is a
fact about one worktree.

**Files, previews and scenarios are three renderings of one delta** — same base,
same scope, same question. The argument for putting them together is not
tidiness: **files is free and instant while the other two cost seconds.** Behind
tabs on the panel you already open to read a diff, the expensive halves get
discovered. In their own space they have to be remembered, and a feature that
has to be remembered is used twice.

The address falls out of the existing grammar for free, since a plugin owns
everything after its own segment:

```
fw:///worktrees/<name>/<changes>/previews/demo/card.dart#card
fw:///worktrees/<name>/<changes>/scenarios/test/shop.dart#Checkout/signed in/3
```

The base is **the project's**, not a second answer: `fw.changes(base:)` is read
before anything is inferred, because a comparison against `master` on a screen
whose other tab says `develop` is exactly what §1's one-definition rule forbids.
The inference *fallback* still differs in detail between the two — both take the
default branch, by slightly different routes — and that is the remaining gap.

`fw:///comparisons/…` is **not** spent. It is where the deferred `agent-a..agent-b`
case goes — the one that genuinely has no worktree to live in — so the space
slot stays reserved for the case that needs it.

**A tab exists only if its plugin is declared.** A previews tab that always says
"no previews here" should not be there; the explorer already drops a column
every worktree leaves empty.

### The screens

**Entering a tab runs that tab**, which narrows §13.11 rather than reversing it.
No Run button — the skip rule usually makes a comparison seconds, and a tool
that asks permission to do the only thing it does is a tool nobody opens. But
*per tab*: opening the panel must not spawn two compilers and a `flutter_tester`
for a half you did not want. Files runs nothing. The tab carries its own
estimate, so the cost arrives before the work does, and a run already in flight
is joined rather than restarted.

**The header** names both sides, the scope and the elapsed time, and carries the
counts (broke · changed · added · removed · skipped). Lists are sorted by
**severity**, not by name — head-broke, then scenario failed, then branch
removed, then percent changed. The top row should be the thing most likely to be
a mistake.

**Getting there from the live panels.** Previews and scenarios each offer
*compare against base* on the entry you are looking at, and a comparison row
offers *open live* back. A **jump, not a toggle**: the previews panel is live —
a running guest with knobs and axes you can turn — and a comparison is two
frozen shots. `ShellController.goToWorktree` is the same move already argued for
("the same place, in another checkout").

**A preview.** The two frames in one stage with five modes — *side by side ·
slider · onion · blink · pixels*. Under it, the tree channel as prose:
`Padding.all 12→20`, `FilledButton.background #1A1A18→#378ADD`, and the height
delta called out because it explains the pixel percentage.

**A scenario.** The merged tree of §7b: a shared trunk, branch lanes, each node a
thumbnail with a state ring, added and removed branches collapsed to a single
labelled row.

## 10. Budget

Measured elsewhere, cited here; the totals are arithmetic on those and are
**estimates, not measurements**:

| | measured | source |
|---|---|---|
| daemon, first client connect → ready | 2313ms | compile-pipeline findings |
| daemon, second client | 19ms | ditto |
| entry switch | 6–16ms compile + 66–130ms reload | ditto |
| scenario warm 3-step run | 123ms | S4 findings |
| PNG capture | a few ms each | S4 findings |
| `fw run scenarios run` process | ~2.5s | scenarios agent-surface memo |

So a preview costs ~80–150ms warm per side. 200 previews ≈ 20s per side cold;
both sides in parallel ≈ one side's wall clock; **and with the skip rule a
typical branch is a handful of entries, so seconds.** Watch mode is then close to
free — the head guest is already warm, so a save re-renders only the affected
entries.

## 11. Failure, tolerantly

| situation | reported as |
|---|---|
| head renders, base does not | "already broken on base" — head-only, not an error |
| base renders, head does not | the loudest row in the report; this is a regression you introduced |
| neither renders | one muted line |
| scenario passes on one side only | outranks every pixel delta |

### 11a. The base is rendered with the head's tooling

Found by running it (`f554fced`). The generated entrypoint, the scanner and the
daemon all come from the checkout the command was typed in; only the *sources*
come from the base. So a generator that emits a call into `package:flutterware`
meets whatever version the base checkout resolves — and comparing this repo
against master fails to compile the base entirely, because `withPreviewClock`
does not exist there.

It is not self-hosting-specific: any project whose base commit pins an older
flutterware can meet the same skew. It is also **a result rather than a
crash** — a side that cannot start reports every entry as "this side could not
render it" and lands on the severity ladder. Rendering each side with its own
tooling would mean running two versions of the tool, which is a much larger
call than this feature; the honest position for now is that a base too old to
build with today's generator reports as broken, loudly, per entry.

**SDK mismatch hard-fails**, for now. If base and head pin different Flutter
versions, every pixel differs for reasons that are not yours. Detect it by
comparing `.fvmrc` and the resolved `flutter --version` between the two
checkouts *before* rendering anything, and refuse with both versions named. This
is a real gap and it is accepted deliberately: it gets revisited when `fw`
handles SDK management.

## 12. Build order

1. ✅ **Derived step labels** (§7a) — `c7bb9d9c`. Independent, improves four
   existing surfaces, and the aligner is worthless without it.
2. ✅ **Preview clock pin** (§6) — `9e29155d`, smoke-tested through a real
   guest — and the **SDK-mismatch detector** (§11) — `bbc2ac6f`.
3. ✅ **Shot cache + skip rule** (§2, §3) — `55207ba6`; **base checkout**
   (§1) — `b396d464`; **the closure** — `1445faf8`, and it corrects §3: the
   compiler cannot answer it. See §3a.
4. ✅ **The diff kernel** (§4, §5) — `9b8379fd`. Pixels, tree, texts, the
   severity ladder. Not yet run in an isolate: it has no caller to be off the
   UI thread of.
5. ✅ **`fw compare` + `index.json`** (§8) — previews in `f554fced`
   (prerequisites in `1445faf8`), scenarios in `08db2c68`, **both halves in one
   artifact** after that. Measured on this repo against `origin/master`: 6
   entries, 0 rendered, 6 skipped, 142ms; change one label and it renders that
   entry alone on both sides. Scenarios run per-scenario on a warm runner,
   skipped by the same closure rule. MCP is not wired. Corrections these forced
   are in their commit messages; the structural ones are in §8a and §11a.
6. **The space** (§9) — overview, preview modes, merged split tree, two live
   revisions.
7. **The static viewer** — in v1, and dumb: it reads `index.json` and renders,
   with no diffing logic of its own. "Improve later" means richer modes, never
   moving computation into the page.
8. Later: `events` channel, arbitrary A/B.

## 13. Decided — do not relitigate

1. Head is the worktree as it sits on disk, uncommitted and untracked included.
2. The base checkout is disposable; the shots are what persist, content-addressed.
3. Threshold, no confirmation re-render — same machine, same binaries.
4. Default axes and default knobs; no cross-product.
5. Previews pin the clock, always.
6. Replay a whole scenario; no per-branch replay.
7. Merged tree is the primary scenario view; side-by-side is a drill-down.
8. ~~Its own space, not a plugin.~~ **Reversed 2026-08-11** — three tabs on the
   worktree's changes panel. `fw:///comparisons` is kept for the deferred
   two-worktree case. See §9.
9. Latest revision is enough, plus the running one while it runs.
10. SDK mismatch hard-fails until `fw` owns the SDK.
11. Entering a **tab** runs that half; there is no Run button. Narrowed
    2026-08-11 from "entering the space" — see §9.
12. Scenario axes are the profile's first of each — never the last manual run's.
13. A renamed preview entry reads as removed + added. No rename pairing.
14. The static viewer ships in v1 and stays a dumb reader of `index.json`.

## 14. Left unset on purpose

The pixel epsilon and minimum cluster size (§4) and the shot cache's eviction
policy (§2). All three are constants that want a real branch and a full disk to
tune against, and picking them from an armchair would only make them look
decided. Measure, then write the numbers here.
