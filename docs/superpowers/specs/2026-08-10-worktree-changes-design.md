# The changes screen — design

**Date:** 2026-08-10
**Status:** Slices 1–6 built — **v1 complete** (§10); what is left is listed
after the build order. Decisions below are settled unless listed under "Open
questions". Measurements are from this machine on 2026-08-10 and 2026-08-11
against this repository's own worktrees, and are reproducible.
**Parent:** `2026-08-10-worktree-explorer-view-design.md` (the facts layer this
drills into), `2026-07-25-overhaul-master-plan.md`.
**Prototype:** an HTML mockup exists outside the repo (claude.ai conversation
`70cfae12`, artifact *Branch review ui v2*). Its two good ideas are kept and
named below; its central assumption is corrected in §1.

## What this is

One screen answering **"what changed here, and what should I look at first"**
for a single worktree. The explorer says *this checkout has 53 files, +2.1k
−890*; this is where you go to find out whether that matters.

The motivating case is not human code review. It is **watching an agent work**:
several worktrees, each with a Claude session in it, and the question every few
minutes is "what has it actually done, and did it touch anything I care about".
That case sets three requirements a conventional diff viewer does not have —
uncommitted work is the interesting work (§1), the screen must be live (§7), and
ranking is not a nicety but the feature (§5).

## 1. The central decision: the change is the delta, not the commits

The prototype's whole state hangs off a commit selector. That is the right
control for reviewing a pull request and the wrong model for this screen: **an
agent's most interesting work is not committed yet.** A view driven by commits
renders an empty page for the one worktree you opened the app to look at.

So the unit is **the worktree's total delta from its base** — merge-base to the
files on disk, including staged, unstaged and untracked. Committed-ness is an
*attribute of a file within that delta*, not the thing that selects it.

This is also cheaper, not more expensive. From inside the worktree:

```
git diff -M $(git merge-base <base> HEAD)      # committed + staged + unstaged
```

is one process for the whole answer — 27 ms and 473 KB on a 53-file branch. The
committed-only diff is a second, numstat-only call (tiny) used solely to label
which files carry uncommitted work; untracked files come from the `status` the
screen needs anyway.

Consequence worth stating because everything downstream depends on it: **there
is no "no changes" state for a dirty worktree with no commits.** A branch cut
five minutes ago with three edited files is a full, ranked screen.

## 2. Where it lives

### Address

```
fw:///worktrees/<name>/changes
```

`changes` occupies the plugin slot without being a plugin — exactly what
`Address.shellConfig` already does, including the reservation in
`lib/src/plugins/manifest.dart` that refuses a plugin claiming the id. Add
`Address.shellChanges = 'changes'` beside it and extend the same refusal.

**It is shell-owned, not a plugin,** for the reason §1 of the explorer design
gives: it must never *require* project code to run, because the worktree you most
want to look at is the one you have *not* opened. A plugin needs a resolved
config and a `WorktreeSession`; git needs neither.

The precise form of that rule, since §5 does read the project's config: **nothing
on this screen is unavailable because a worktree is closed.** An open worktree's
executed manifest is used when it is there, and its absence costs fidelity in one
place — which globs the scan could read — and never a blank screen.

> **One thing this breaks, and it is real work, not a footnote.**
> `ShellController.selected` resolves the address's worktree `among:
> openWorktrees`. Every shell-owned screen today therefore presupposes an open
> worktree. The changes screen is the first surface that must render for a
> **closed** one, so address resolution needs a third path: a screen that
> resolves against `_worktrees` rather than `_open`, and a tab that can exist
> without a session behind it. This is the single largest piece of shell surgery
> in the build order (§10, slice 2) and it should not be discovered late.
>
> > **Corrected 2026-08-10 by building it.** The surgery was smaller than this
> > predicted, and in one place the prediction was simply wrong.
> >
> > - **`selected` did not need changing.** It is *right* that it sees only open
> >   worktrees — every screen that needs a session depends on that. What was
> >   needed was a second resolver beside it, `addressedWorktree`, so the two
> >   questions ("which checkout is this window in" and "which checkout does this
> >   address name") stop being the same call.
> > - **The real change is in `go`, not in resolution.** `go`'s governing rule is
> >   *opening is the navigation* — an address naming a closed worktree opens it.
> >   That is correct for everything that needs a session and exactly wrong here,
> >   so `Address.shellSessionless` names the exemption and `go` consults it. The
> >   exemption is **per id, not per shell-owned screen**: `config` is about the
> >   session and still opens what it names. There is a test for that, because
> >   "shell-owned" is the generalisation someone will reach for.
> > - **No tab that can exist without a session.** That was the wrong shape. A
> >   tab means *open*, and the explorer spent a whole design keeping that pixel
> >   honest. The screen renders full-window with the pinned tab lit, because
> >   `fw:///worktrees/<name>/changes` for an unopened checkout **is a page in the
> >   worktrees space** — which is what a pinned tab means in a browser. One
> >   concept, `inWorktreesSpace`, drives all three of the rail, the lit tab and
> >   what Escape does, so they cannot disagree.

### Reached from the explorer

The primary path, and the one this section is long for: the explorer is where you
are when the question occurs to you, fourteen times a session.

#### The ladder, and the rung that was one too many

The explorer already has two rungs, and it is worth naming what each answers
before adding a third:

| rung | answers | where |
|---|---|---|
| the row's changes cell | **how big**, and is anything alarming | `_ChangesCell`, 220 px |
| the expanded detail | **where the work went**, by bucket, beside agent/branch/PR | `_ChangeTable` |
| — | **which files**, ranked | *new* |
| the changes screen | **what the diff says** | `fw:///worktrees/<n>/changes` |

The third rung is a popover, and the split between it and the detail is not
arbitrary — it follows from what the explorer is for. **The detail is a set**:
expanded rows stay expanded because comparing checkouts is the whole point.
Buckets survive that (`app 78% · lib 15%` reads down a column). **A file list does
not** — nobody compares two ranked file lists side by side, and four expanded rows
each carrying six paths turns the list into a page.

So: **buckets are comparable and live in the detail; files are singular and live
in a popover.** The detail does **not** grow to hold files — that is the rule that
keeps this from being four rungs where three would do.

#### The trigger, and the tap it costs

The complication is one line of the row's existing contract:

> **Tapping the row expands it; it does not open the worktree.**
> — `explorer_row.dart:54`

The whole row is one `GestureDetector` around `onToggleExpand`. So any new click
target is subtracted from the expand gesture, and the naive choice — "click the
changes cell" — subtracts the **220 px column whose expanded content is the
detail's widest element**. That is backwards.

**The trigger is the fingerprint bar itself**, roughly 100 px of the 220, with a
click cursor on hover:

- It is the one element on the row that already *means* changes, so clicking a
  chart to see what it is made of is a learned idiom rather than a new rule.
- It has a fixed position, so unlike a hover-revealed glyph it shifts no layout
  and can be aimed at before the pointer arrives.
- Your eye is already there — it is what you were reading when the question
  formed.

The cost, stated rather than hidden: **~100 px of ~1200 stops expanding the row.**
The remaining 92% still does, including all of the name cell, so the gesture is
not lost, just dented. A row with nothing to show — the main checkout, a branch in
sync — draws no bar and therefore has no trigger, which is correct.

`c` opens it from the keyboard on the cursor row. `⏎` still opens the worktree,
unchanged.

#### What the popover says

About 420 px wide, capped near 360 tall and scrollable past it:

```
┌────────────────────────────────────────────────────┐
│ 53 files  +2148 −890  ·  7 uncommitted             │
│ base master (inferred)                             │
├────────────────────────────────────────────────────┤
│ LOOK HERE FIRST                                    │
│ A  db/migrations/0042_stream_log.sql    +8   −0    │
│    matches **/migrations/**  · uncommitted         │
│ M  pubspec.yaml                         +1   −1    │
│    dependency manifest                             │
├────────────────────────────────────────────────────┤
│ BIGGEST                                            │
│ M  app/lib/src/motion/timeline.dart   +140  −22    │
│ M  app/lib/src/motion/lane.dart        +96  −14    │
│ D  app/lib/src/motion/legacy_box.dart   +0  −88    │
│ … 5 more                                           │
├────────────────────────────────────────────────────┤
│ 6 low-signal files hidden, +210 −278               │
├────────────────────────────────────────────────────┤
│ Open changes  ⌘⇧D              Reveal · Editor     │
└────────────────────────────────────────────────────┘
```

**No churn map here.** One column per file needs every file's counts, which is
the one thing too big to cache per worktree; and the popover's job is *which
files*, which is a list. The churn map is the full screen's opening move.

**Deletions are pinned into `BIGGEST` regardless of size** — `D` with `−88` is the
line most worth seeing and the one a sort by churn buries under three larger
edits.

#### Making it free

A popover that hitches on open gets disabled within a day. It renders from
`WorktreeFactsStore`, which means `CachedDiff` gains one field beside
`ChangeShape`, computed when the diff is and keyed by the same
`(base_sha, head_sha)`:

```dart
class ChangeHeadline {
  final List<RankedFile> pinned;    // cap 4
  final List<RankedFile> biggest;   // cap 6, deletions promoted
  final int noiseFiles, noiseAdded, noiseRemoved;
  final int totalFiles;
}

class RankedFile {
  final String path;
  final ChangeStatus status;
  final int added, removed;
  final String? reason;         // 'matches **/migrations/**'
  final bool uncommitted;
}
```

Ten-odd entries, under a kilobyte per worktree, ~14 KB across this repository —
`worktrees.json` can carry that. On a **cache miss** (a worktree whose diff
predates this field, or one never probed) the popover opens *immediately* with
the header it can draw from `ChangeShape` and fills the lists in behind a
`--numstat` — **27 ms**, measured, and never on the UI isolate. It never blocks,
and it never runs the project's config: closed worktrees rank by the cached
`ChangesConfig` (§5).

#### What this buys the row, for free

The same field lets the **row** carry the attention signal inline — a `migrations`
badge in the changes cell, no interaction at all. Across fourteen worktrees that
answers *did any agent touch a migration today* at a glance, from cache, and it
falls out of work the explorer is already doing.

It is not v1 — the cell is 220 px and already holds a bar, two counts and a dirty
badge, so where the badge goes is a layout question this document has not earned
the right to answer. But `ChangeHeadline` is shaped for it now rather than
retrofitted, and it is the most valuable thing in this section.

### Also reachable from

**A sidebar row under Overview** when the worktree is open, beside Config, and
`⌘⇧D` from anywhere.

## 3. Performance: git is not the cost

Measured, warm, this repository:

| range | files | git | patch bytes |
|---|---|---|---|
| `animation-timeline` vs master | 53 | 20 ms | 473 KB |
| `ui-catalog-design` vs master | 177 | 20 ms | 521 KB |
| 30 commits back (worst case tried) | 652 | **74 ms** | 3.6 MB |
| `git check-attr --stdin -a`, 177 paths | — | **9 ms** | one process |
| `git status --porcelain=v2` | — | 18 ms | — |

`--numstat`, `--name-status`, `-M` rename detection and `-U0` all sit inside the
same envelope. **`-U0` is not an optimisation** — 469 KB against 473 KB on the
53-file branch, because on a real diff the changed lines *are* the payload and
context is the small part. Anyone reaching for it to save bytes is measuring the
wrong thing.

So: **3.6 MB in 74 ms.** Every plausible git invocation is free. The cost is
entirely ours — decoding half a megabyte of unified diff into Dart strings, and
building Flutter widgets for ten thousand diff lines. A design that spends its
cleverness on git invocations is optimising the half that was already fast.

### The one-pass index

One `git diff`, streamed once into a byte buffer, **indexed rather than
parsed**:

```dart
class PatchIndex {
  final Uint8List bytes;             // the whole patch, retained
  final List<FileChange> files;
}

class FileChange {
  final String path;
  final String? oldPath;             // renames, from -M
  final ChangeStatus status;         // added modified deleted renamed binary
  final int added, removed;
  final List<HunkSpan> hunks;
  final int byteStart, byteEnd;      // slice of PatchIndex.bytes
}

class HunkSpan {
  final int oldStart, oldCount, newStart, newCount;   // from `@@`
  final int added, removed;                            // the ruler's weight
  final int byteStart, byteEnd;
}
```

The scan looks at the **first byte of each line only** — `d` for `diff --git`,
`@` for a hunk header, `+`/`-` to accumulate hunk weight, `B` for `Binary files`
— and allocates a string for nothing else. Content lines are skipped by
advancing a cursor. A file's text is materialized by slicing and UTF-8 decoding
`byteStart..byteEnd` **when that file is expanded**, and dropped when it
collapses.

What this buys, in one pass:

- the file list, statuses and rename pairs — so no separate `--name-status`
- per-file `+`/`−` — so no separate `--numstat`
- **every hunk ruler**, which is the feature you liked most, for free
- **exact expanded height before any content is decoded**, because a hunk's line
  count is in its own header. Scroll extents never jump, which is what makes a
  virtualized list over mixed file-header and diff-line rows tractable at all.

Everything on the screen above the fold — churn map, tree, counts, buckets,
pins, rulers — comes out of the index. Patch text is a lazy read against a
buffer we already hold.

### The overview is already paid for

`WorktreeFactsStore` persists `ChangeShape` keyed on `(base_sha, head_sha)`. The
screen's header and churn map therefore render **from cache, instantly**, before
any process starts — the explorer's "stale-then-fresh, never empty-then-full"
rule applied one level down. The index streams in behind it and refines the
picture; it never replaces an empty page with a full one.

### Never freezing the editor

The failure this screen must not have is the one where somebody's agent leaves an
un-gitignored `build/` behind and the window stops responding. Three rules, and
the first one is where the whole risk actually lives.

**1. `--untracked-files=normal`. Never `-uall`.**

The case to design against is specific, and it is not "somebody forgot to
gitignore their build output". It is this, which happens on a normal working day:

> Create a new package on a branch. Build it. `packages/newpkg/build/` fills up.
> Switch back to another branch on the same checkout. **The `.gitignore` that
> covered `build/` lives in that package, on that branch — so it went away with
> the branch switch.** 30,000 files are now untracked *and un-ignored*, and every
> tool that lists changes walks into them.

`.gitignore` is versioned; the build output is not. Switching branches routinely
un-ignores things. Reproduced and measured — 30,000 files under
`packages/newpkg/build/`, after switching to a branch without the package:

| | rows | git |
|---|---|---|
| `status --porcelain=v2` (normal) | **1** — `? packages/` | **7 ms** |
| `status --porcelain=v2 -uall` | **30,000** | 63 ms |

And the near-variant, where the package *does* exist on the other branch but its
`.gitignore` does not: **1 row**, `? packages/newpkg/build/`, 8 ms.

**git does not descend.** It reports the topmost wholly-untracked directory and
stops, so `normal` costs nothing even when the directory is enormous — the guard
is asking git the right question, not a cap we invent and tune. `-uall` is 30,000
rows through our model, our ranking and our widget layer, which is the freeze.

**Nothing else may descend either.** Two rules follow, and they are where the
freeze would sneak back in:

- **Do not count.** Rendering "30,000 files" requires the walk we just avoided.
  The row says `packages/newpkg/build/ — untracked directory, not scanned`. A
  number is not worth a stall.
- **Expanding it is a click, and the click is bounded**: 200 entries, depth 4,
  250 ms, whichever comes first, and it says where it stopped. Past that it
  refuses and offers the editor — see open question 3.

The patch side is immune by construction: `git diff` never looks at untracked
files. Only `status` can reach them, which is why this is the only place the rule
has to hold.

**2. Every bound is checked before the expensive step, and is visible.**

| bound | value | behaviour past it |
|---|---|---|
| whole patch | 64 MB | refuse, name the number, fall back to the file list from `--numstat` |
| one file's patch | 512 KB | indexed, not expandable — "large change, open in editor" |
| untracked directory | not walked | one row; expansion capped at 200 / depth 4 / 250 ms |
| untracked file read | 256 KB | listed and sized, contents not read |
| binary | — | counted as a file, no lines, no hunks |

3.6 MB was the worst case reachable in this repository, so 64 MB is not a tuned
number — it is chosen to be obviously above anything real, so that hitting it
means something is *wrong* rather than something is big. **Silent truncation is
forbidden**: a screen that quietly drops files is worse than one that refuses,
because you cannot tell which it did.

**3. The probe and the scan run in `Isolate.run`; the UI isolate only ever
receives a finished index.** Even the good case is ~74 ms of git plus a scan over
megabytes — several dropped frames on the raster thread for no reason. Spawning
costs a millisecond or two, the `Uint8List` comes back as a memcpy, and the live
watcher (§7) re-runs this on every debounce fire, which is precisely when jank
would be most visible. Nothing unbounded is ever triggered by a *refresh* — only
by a click.

## 4. Data model

```
ChangeSet                 one worktree's delta, base → disk
  ├ base, head, mergeBase shas + the base branch name
  ├ PatchIndex            §3
  ├ uncommitted: Set<String>   paths whose delta is not all committed
  ├ untracked: List<UntrackedFile>
  └ ranking: Ranking      §5
```

Plain data in the existing `lib/src/plugins/` vocabulary (`Status`, `Tone`),
like `WorktreeFacts`, so `fw changes --json` and MCP need no second model. Pure
Dart: `fw` must not link `package:flutter`, and
`app/test/utils/entry_point_purity_test.dart` enforces it.

`PatchIndex` holds a `Uint8List`, which is fine in the CLI and in MCP; the JSON
renderer simply never asks for a slice unless a path was named.

## 5. Ranking — "the most important one"

This is the feature, not a garnish. Three tiers, cheapest first.

### Free from the file list, no patch content

- **Deletions and renames.** Highest signal per byte on the screen, and `-M`
  gives both in the index already.
- **Attention globs** — pinned into a *Look here first* section, each row
  showing the rule that pinned it, so precedence is inspectable rather than
  magic.
- **Noise** — collapsed into one drawer row, `N low-signal files, +x −y`.
- **Recency** — file mtime. On an agent's worktree this is *what it touched
  last*, and it is a `stat`.

### From the index, still no decoding

- **Hunk shape** — three hunks clustered at the top reads differently from
  changes scattered through 400 lines. Already computed; just needs to be a
  sort key as well as a picture.
- **Whitespace-only and import-only** files. Decidable from the `+`/`-` line
  spans without keeping the strings, and they are the bulk of what "noise"
  should catch that no glob can express.

> **Built 2026-08-11, minus two.** Deletions and renames, attention globs, the
> noise drawer and both derived rules shipped. Two did not, and both were
> dropped on purpose rather than forgotten:
>
> - **Recency (file mtime)** — cheap, and a bad *sort* key. It reorders the
>   list while you are reading it, which is the opposite of what a screen you
>   watch an agent through needs, and the explorer's activity column already
>   answers "what moved last" for the whole checkout. Worth revisiting as a
>   displayed hint on a row; not as a rank.
> - **Hunk shape as a sort key** — the churn map and the per-row ruler already
>   draw the shape, and a second, invisible use of the same number would be a
>   reordering nobody could account for. The data is there whenever a use for
>   it is.

### Not in v1

- **Test pairing** ("source changed, no test changed"). Cheap to compute and
  cut anyway: it is the one rule here that is *wrong* often enough to train
  people to ignore badges — a refactor with no behaviour change, a test that
  already covers the line, a glob map nobody maintains. A ranking earns trust by
  being right, and this one starts by spending it.
- **Blast radius** ("`openSocket` deleted · 4 untouched call sites") — the most
  valuable idea in the prototype and the one it was right to be honest about. It
  needs a symbol index. For Dart the analyzer makes it genuinely tractable
  later, which is more than the language-agnostic version can claim, but it is a
  project rather than a section. Same for the symbol outline.

### Config: `tool/flutterware.dart`, executed once and cached

**There is no second config file, and no second way of reading the one there
is.** The Dart config is the point — static analysis, autocomplete, and a type
error instead of a typo that silently matches nothing. It is *executed*, like
every other config in flutterware.

```dart
void main() => Flutterware.configure((fw) {
  fw.changes(const ChangesConfig(
    attention: ['**/migrations/**', 'openapi.yaml', '**/*.sql'],
    noise: ['**/*.g.dart', '**/__snapshots__/**'],
    base: 'develop',                     // only when inference fails, §"The base"
  ));
  fw.use(Previews());
});
```

> **Corrected 2026-08-11 by building it.** The draft above spelled this as
> named arguments to `Flutterware.configure(changes:, plugins:)`, which is not
> the API — the config is a *builder callback* and plugins arrive through
> `fw.use`. So ranking rules arrive through `fw.changes`, one door beside the
> other, and calling it twice throws rather than merging: two calls are a
> config with two answers, and either resolution loses one without a word.

The only real question is what a **closed** worktree ranks by, since executing
its config is exactly what "closed" means we are not doing. The answer is the
one the facts layer already is: **cache the value, keyed by the config file.**

```
ChangesConfig  →  ~/.flutterware/<sha1(main checkout)>/worktrees.json
validityKey    =  mtime + size of tool/flutterware.dart
```

That is `Fact<T>`'s existing `validityKey` machinery, in the store that already
holds the branch diffs and `lastOpenedAt`. Three states, and each is a `FactState`
that already exists:

| situation | state | ranks by |
|---|---|---|
| open, or `fw` ran here | `fresh` | the executed config |
| closed, config file unchanged since we cached | `fresh` | the cached config |
| closed, config file has moved since | `stale` | the cached config, **said so in the header** |
| never opened, or no config file | `unknown` | built-in defaults only |

Full fidelity — it is the real executed value, not an approximation of one — and
the degradation is a worktree you have never opened falling back to defaults,
which is both rare and honest.

> **Corrected 2026-08-10, and the correction is why this section is short.** The
> first draft proposed a *syntactic scan* of `tool/flutterware.dart` with
> `package:analyzer` for the closed case — the `scanDefines` / `scanEntrypoints`
> posture, *parsed never resolved*. That was solving the right problem with the
> wrong tool, and it carried a caveat that should have been the tell: those
> scanners lean on a language rule (`String.fromEnvironment` **requires** a
> constant expression, so the literal is always there to find), and nothing
> imposes an equivalent rule on a list of globs. So the scan would have been a
> lossy read of a value we had already computed exactly, at least once, and
> thrown away. Cache the answer instead of re-deriving a worse one. Nothing here
> requires anything to be `const`.

Worth knowing for the cost of the *open* path, because it is better than it
looks: `ManifestLoader` memoises the config's kernel on disk, so a warm run is
**70–80 ms** against 510–590 ms for a cold `dart run` — the bare VM floor. It is
not free, but it is not a reason to avoid executing a config we are executing
anyway when the worktree is open.

**`.gitattributes` still comes first** for noise. `linguist-generated=true` and
`-diff` already mean "this is generated", GitHub already honours them, and many
repositories already have them. One batched `git check-attr --stdin -a` over 177
paths measured **9 ms**. Competing with a standard that already works would be
indefensible, and it costs the user nothing to have configured.

**Good defaults, zero config.** A built-in list ships and is what most repos will
ever use — `**/migrations/**`, `openapi.yaml`, `pubspec.yaml`,
`.github/workflows/**` as attention; lockfiles, `*.g.dart`, `*.freezed.dart`,
`build/`, `**/__snapshots__/**` as noise. Config *adds* to it, and subtracts by
naming a path in the other section.

**Every rule is a hint, never a hide.** The drawer is one click from open, and
the header's file count always reports the true total. A ranking that can lose a
file is a ranking nobody can trust.

### The base, and refusing to guess

`GitProbe.defaultBranch` already tries `origin/HEAD`, then `main`, then `master`,
and returns null when none exist. **That null is a state, not an error to
paper over.** With no base there is no delta, and a screen that guessed one would
show a diff against something the user never chose — silently wrong in the most
expensive direction.

So: infer, and when inference fails, say so and name the fix — a `base:` on
`ChangesConfig`, which the same two-ways read above makes available to open and
closed worktrees alike. The header always shows which base is in use and where it
came from (`inferred` / `configured`), because the one thing worse than no base is
the wrong one presented as fact.

## 6. The view

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ animation-timeline · claude/animation-…-bca225 vs master   53 files  +2.1k −890 │
│ ▁▂█▃▁▁▂▅▂▁ ▁▂▁  churn                          ●7 uncommitted   ↻ 4s ago        │
├──────────────┬─────────────────────────────────────────────────────────────────┤
│ ⌕ filter     │ LOOK HERE FIRST      ChangesConfig.attention · base master (inferred)│
│              │ ┌─────────────────────────────────────────────────────────────┐ │
│ ts 7  dart 31│ │ A  db/migrations/0042_stream_log.sql       ▊▁▁▁▁   +8  −0    │ │
│ yaml 2  md 4 │ │    PIN **/migrations/**  · uncommitted                       │ │
│              │ └─────────────────────────────────────────────────────────────┘ │
│ ▸ app        │ EVERYTHING ELSE                                                 │
│   ▾ lib/src  │ ┌─────────────────────────────────────────────────────────────┐ │
│     motion/  │ │ M  app/lib/src/motion/timeline.dart       ▁▊▊▁▂  +140 −22   │ │
│     ...      │ │    3 hunks · uncommitted · 2m ago                            │ │
│              │ └─────────────────────────────────────────────────────────────┘ │
│              │ ⌄ 6 low-signal files, +210 −278                                  │
└──────────────┴─────────────────────────────────────────────────────────────────┘
```

Kept from the prototype, because both earn their pixels:

- **The churn map.** One column per file, additions up, deletions down, shared
  scale. It answers "is this branch a rewrite of one module or scattered edits"
  before you read a line. Filtering **dims** rather than removes, so the
  whole-branch context survives the filter.
- **The hunk ruler**, per row: where in the file the change sits and how
  add/delete-heavy each hunk is, from `HunkSpan` directly.

Changed from the prototype:

- **Colour follows the app's tone palette**, not the prototype's teal/amber. The
  prototype chose those to be colour-blind-safe and to not look like GitHub;
  both are good reasons, and both are already settled questions inside
  `app/lib/src/ui/design`, which every other panel obeys. A screen with its own
  palette is a screen that looks bolted on.
- **Uncommitted is a badge, not a mode** (§1).
- **No commit selector in v1** (§10).

**Syntax highlighting** uses the vendored `lib/src/third_party/highlight` +
`flutter_highlight`, computed **per visible hunk, lazily**, never per file and
never eagerly. It is the one thing on this screen expensive enough to show up in
a frame budget, and the only thing that gets a cache keyed by hunk.

**Keyboard**: `j`/`k` move · `o` expand · `⏎` open in editor · `/` filter ·
`Esc` clear.

## 7. Live, because that is the point

The explorer deliberately does not watch working trees: fourteen recursive
watches is the cost that design exists to avoid, and dirty state there refreshes
on visibility.

**This screen is the scoped exception, and the exception is the feature.** One
worktree, one recursive watch, only while the screen is visible. An agent
editing files is exactly the case, and a changes screen that needs a refresh
button to notice is a screen you stop trusting.

Reuse `watchers.dart`'s coalescing: 300 ms debounce **with a 2 s floor**,
because an agent writing continuously never offers a quiet moment and a debounce
alone would either never fire or fire on every write. On each fire, re-run the
worktree diff (27 ms) and re-index; the committed half is cache-keyed on
`(base_sha, head_sha)` and is skipped until a commit lands.

**Preserved across a refresh:** expansion state, scroll position, and filter. The
`(path, hunk)` identity survives a re-index, so a file that did not change does
not move. Anything less makes the live update a punishment for having scrolled.

**No polling timer**, per the explorer's rule. The watch is the signal;
visibility gates it; the button forces it.

## 8. Renderers

Same model, three surfaces:

```
fw changes [<worktree>]
53 files  +2148 −890  ·  7 uncommitted  ·  base master

  LOOK HERE FIRST
  A  db/migrations/0042_stream_log.sql          +8   −0   pin **/migrations/**
  …
  6 low-signal files, +210 −278 (--all to list)

fw changes --json
fw changes <worktree> --file app/lib/src/motion/timeline.dart   # the patch
```

The `--file` form is what makes this useful to an agent: *what did I change in
this file, against base, without reading the file twice.* That is the MCP
surface too, and it is the one thing here that no `git` alias already gives an
agent in a usable shape — because it arrives ranked, with the noise named.

> **Corrected 2026-08-10 by building it, and caught by the round-trip test.**
> `--file` cannot be one `git diff … -- <path>`. **git detects renames over the
> *filtered* set**, so asking for `lib/new.dart` alone hides `lib/old.dart` and
> the answer is a brand new file whose every line was added — the single most
> misleading thing this command could say about a refactor, and exactly the case
> `--file` exists for. Verified: naming both paths restores the rename. So a
> cheap `diff --name-status -M -z` runs first to find the other end. The
> round-trip assertion — every file's byte slice equals what git says that file's
> patch is — is what surfaced it, which is the argument for having written that
> test first.

## 9. Code layout and testing

```
app/lib/src/changes/
  patch_index.dart      the byte scanner and its model            pure Dart
  change_set.dart       ChangeSet, statuses, untracked            pure Dart
  ranking.dart          globs, .gitattributes, noise              pure Dart
  changes_config.dart   defaults + the syntactic scan of the      pure Dart
                        config, when the manifest is unavailable
  changes_probe.dart    the git calls, injectable runner          pure Dart
  changes_controller.dart  isolate, watch, debounce, cache        Flutter
  changes_screen.dart   the view                                  Flutter
  churn_map.dart        the diverging bar chart                   Flutter
  hunk_ruler.dart       the per-row track                         Flutter
  diff_view.dart        virtualized rows + lazy highlight         Flutter
```

Testing, in the order the parts are likely to break:

- **`patch_index.dart` gets recorded fixtures and the nasty ones by
  construction**: renames in both `--numstat` spellings (`a => b` and
  `app/{lib => src}/x.dart`), binary files, a file with no trailing newline, CRLF,
  a hunk header with omitted counts (`@@ -1 +1 @@`), a patch that ends
  mid-hunk. This is the file where a wrong byte offset silently renders the
  wrong code, which is the worst failure this screen can have.
- **Ranking gets a table test**: path in, tier and reason out. The *reason*
  is asserted, not just the tier — the UI promises to show which rule fired.
- **A round-trip property**: for every file in a fixture patch, the decoded
  slice equals `git diff -- <path>` for that file. This is the assertion that
  makes the whole lazy-slice architecture safe.
- **`changes_config.dart` gets a validity-key test**: touching
  `tool/flutterware.dart` moves the key and marks the cached config `stale`;
  reading it twice without touching it does not re-execute anything. A fake clock
  and a fake filesystem, as the facts scheduler already has.
- **The untracked trap gets a real repository, built in the test**: a package
  whose `.gitignore` exists only on the other branch, a directory of files under
  it, and an assertion that the probe produces **one** row and never stats the
  contents. This is the regression that matters most, because it is invisible on
  every developer's machine until it isn't.
- **Widget tests over a fabricated `ChangeSet`** for the states a happy path
  never produces: 0 files, only-untracked, an untracked directory, no base,
  a 512 KB file, binary, a patch that blew the budget.
- **Providers take injectable process runners**, as `GitProbe` and
  `WorktreeDiscovery` already do.

## 10. Build order

1. **`patch_index.dart` + `changes_probe.dart` + `fw changes`.** No GUI. Proves
   the scanner against every worktree in this repo, and the untracked and
   no-base states against a repo built to have them. Lands a useful command.
   Depends on nothing.

   > **✅ 2026-08-10.** `app/lib/src/changes/` — `patch_index.dart`,
   > `change_set.dart`, `changes_probe.dart`, `changes_text.dart` — plus
   > `fw changes [<worktree>] [--file=<path>] [--json]`. 45 tests across a
   > parser suite that needs no git, a sequencing suite with an injected runner,
   > and a real-git suite that builds its repositories, the branch-switch trap
   > included.
   >
   > **Validated against every checkout on this machine**: a throwaway harness
   > cross-checked the scanner's per-file counts against `git diff --numstat`
   > across all 21 worktrees — **over 1,000 files, renames, deletions and
   > binaries included, and every count agreed.** The probe ran in **62–195 ms**
   > per worktree, the largest being 228 files at +36,168 −849 in 80 ms. That is
   > the §3 claim measured rather than predicted: git is not the cost.
   >
   > The harness itself is not kept — it needs real worktrees with real diffs,
   > which CI does not have, and the claims it checks are the ones
   > `changes_git_test.dart` makes against repositories it builds.
2. **Address resolution for closed worktrees** (§2) — the shell surgery. Small
   in lines, wide in blast radius; worth its own review.

   > **✅ 2026-08-10.** `Address.shellChanges` + `shellOwned` + `shellSessionless`,
   > reserved on both doors (`FlutterwareConfig.use` and `PluginManifest.fromJson`);
   > `ShellController.addressedWorktree`, `isChangesScreen`, `isUnopenedScreen`,
   > `inWorktreesSpace`, `selectChanges`; the `go` exemption; `_Panel`, the rail
   > rule, the lit pinned tab, `⌘⇧D` and Escape. Plus `ChangesController` —
   > `Isolate.run`, stale-then-fresh — and a first `ChangesScreen` that is the
   > shape rather than the finished view.
   >
   > 21 new tests: the controller's exemption (including that `config` still
   > opens what it names), the id reservation on both doors, the screen's states
   > a happy path never produces, and the chrome — no tab, no rail, pinned tab
   > lit, Escape back, and the same address inside an open checkout keeping its
   > rail. Whole workspace green: 2017 app tests, 348 root tests, analyze clean,
   > formatter no diff.
   >
   > Not verified by running the GUI: the chrome is covered by widget tests, and
   > nobody has looked at this screen in a window yet.
3. **The screen**, git only, in an isolate: churn map, tree, filter, rows, hunk
   rulers, lazy expansion with virtualization. The shape; everything after is a
   cell.

   > **✅ 2026-08-10.** `churn_map.dart`, `hunk_ruler.dart`, `change_rows.dart`,
   > `diff_lines.dart`, `diff_view.dart`, `changes_tree.dart`, and a rewritten
   > `changes_screen.dart`. 43 new tests; workspace green at 2044 + 348.
   >
   > **Photographed on a real 177-file branch**, light and dark, via
   > `fw capture` — which is how three of the four findings below were found at
   > all.
   >
   > - **Deleted files had blank rulers.** git writes `@@ -1,322 +0,0 @@` for a
   >   whole-file deletion, so a ruler measured on the *new* side computed a
   >   length of zero and painted nothing. Five `D` rows, all empty tracks, on
   >   the first screenshot. The ruler now takes whichever side the hunk has. No
   >   fixture would have caught this — a fixture is never a whole-file deletion
   >   by accident.
   > - **`fw capture` could never photograph a shell screen**, `config`
   >   included, long before this existed: it compared the landing against
   >   `selectedPluginId`, which is null for shell-owned ids by design. Fixed
   >   with `ShellController.shownScreenId` — a pre-existing gap the second
   >   screen made visible.
   > - **The `@@` header is a prediction, and the content is the truth.** Row
   >   extents come from `displayLines`, which is arithmetic on the header. A
   >   header that overstates its hunk therefore indexed past the end of the
   >   decoded lines and threw **while scrolling**. `HunkLineView` draws the
   >   shortfall as a meta line rather than swallowing it.
   > - **The file is addressable**: `fw:///worktrees/<n>/changes/<path…>`
   >   expands and scrolls to one file, and expanding writes the address back.
   >   Not in this slice's plan — it was added because photographing an expanded
   >   diff needed it, and it turns out to be the rule every other panel already
   >   follows (segments after the plugin id belong to the panel). It also makes
   >   a file's diff something you can paste to somebody.
   >
   > **Syntax highlighting is deliberately not here.** §6 calls for the vendored
   > `highlight`, and the structure has to be settled before a per-hunk
   > highlight cache is worth writing. Monospace with tinted rows and `+`/`-`
   > markers reads well enough that this is polish, not a gap.
4. **Ranking** — `.gitattributes`, built-in defaults, `ChangesConfig` read both
   ways, pins, noise drawer.

   > **✅ 2026-08-11.** `ranking.dart`, `path_glob.dart`, `diff_shape.dart`,
   > `changes_config_cache.dart`, plus `ChangesConfig` in the published package
   > and `fw.changes(...)` on the config. Sections, reasons and the drawer in
   > both renderers. 79 new tests; workspace green at 2125 + 353.
   >
   > **Verified against every checkout on this machine and photographed on
   > three.** Four of the six findings below came from running it, not from a
   > test.
   >
   > - **`package:glob` is not `.gitignore`, and the difference is silent.**
   >   Measured: `**/*.g.dart` does *not* match `a.g.dart`, `**/migrations/**`
   >   does not match `migrations/1.sql`, and `*.sql` does not match
   >   `db/a.sql`. Every one of those is a rule a user writes, believes, and
   >   never sees fire — the exact failure the Dart config exists to prevent.
   >   `path_glob.dart` implements the two `.gitignore` anchoring rules
   >   everybody already has in their fingers, plus the trailing-slash one.
   > - **An `export` is not an import.** The derived imports-only rule demoted
   >   `lib/plugins.dart` gaining one `export` line — which *is* the package's
   >   public surface. Caught by reading the first real run's output. `export`
   >   is no longer a directive for this purpose; `import` and `part` are.
   > - **`*.generated.dart` is a real convention.** Not build_runner's, but
   >   this repository's own `action_shapes.generated.dart` led a 228-file list
   >   until it was in the defaults. Found by running the ranking over all 21
   >   worktrees rather than by reasoning about suffixes.
   > - **Two `WorktreeFactsStore` instances over one file lose writes.** The
   >   store reads the whole file at `open` and writes the whole file at
   >   `save`, so the shell's write of the executed `ChangesConfig` was
   >   reverted by the explorer's next sweep — whose instance had been opened
   >   before it. Nothing was ever wrong in memory, so the screen looked right
   >   until the next launch. Found by running the app twice.
   >   `WorktreeFactsController.store` is now the repository's one instance,
   >   and a test pins the clobber so nobody re-adds a second opener.
   > - **An attention rule has to work before `git add`.** Photographed with a
   >   real `attention: ['docs/superpowers/specs/**']`: the design doc sitting
   >   in *Untracked* was not pinned, because untracked entries are not
   >   `FileChange`s. But an agent that just wrote a new migration and has not
   >   staged it is the motivating case, so a pin that only works after `git
   >   add` misses the moment it exists for. `attentionForUntracked` is a
   >   second door — **files only, never a directory**, since matching into one
   >   would be the walk `--untracked-files=normal` exists to avoid.
   > - **A lone `Changes` heading labels nothing.** On a 25-file branch with
   >   noise but nothing pinned, the heading sat at the top with the drawer it
   >   distinguished from thirty rows below the fold. Headings now appear only
   >   when something is pinned; the drawer names itself.
   >
   > **The four rows of the §5 table are one code path**, which was not the
   > plan and is better than it. *One writer, one reader*: `_apply` — the only
   > place the GUI executes a config — writes what it got, stamped with the
   > file it read; the screen, `fw changes`, open and closed worktrees all read
   > that. "Open ranks by the executed config" is then true by construction
   > rather than by a second mechanism. Confirmed end to end: a `ChangesConfig`
   > added to this repo's own `tool/flutterware.dart` was invisible to
   > `fw changes` until the GUI ran it, then visible to a separate process that
   > opened no session.
   >
   > **The cache stays out of the checkout**, tempting as `.dart_tool/` is —
   > the kernel cache is already there. A worktree's `.gitignore` is
   > *versioned*, so a cache written inside the checkout becomes an untracked
   > row on the screen it feeds, which is the §3 trap exactly.
   >
   > Not photographed: the stale-config banner. It is the same `_Note` widget
   > as the no-base and refusal notices, which are in the screenshots, and it
   > has a widget test — but nobody has seen that particular sentence in a
   > window.
5. **The explorer popover** — `CachedDiff` gains `ChangeHeadline`; the
   fingerprint bar gains the trigger, `c` gains the binding, and the popover
   gains the *Open changes* link. The row's pin badge is deliberately **not**
   here; see open question 4.

   > **✅ 2026-08-11.** `changes_summary.dart`, the trigger and `c` in
   > `explorer_row.dart` / `explorer_screen.dart`, and a **Changes** row in the
   > sidebar under Overview. 22 new tests; workspace green at 2147 + 353.
   >
   > **`ChangeHeadline` was not built, and should not be.** Two things killed
   > it. `CachedDiff` is keyed by `(base_sha, head_sha)` and is therefore
   > **committed-only**, so a worktree whose agent has not committed yet would
   > open an empty popover above a changes screen full of work — §1's mistake
   > wearing a different hat. And the measurement went the other way from the
   > assumption: on the largest checkout here (228 files, +36k) the **whole
   > patch costs 20 ms** while the five metadata calls a lighter probe would
   > need cost **70 ms**. Process spawn dominates, not diffing — §3 again —
   > so there was no cheaper probe to build. The card holds a
   > `ChangesController` and renders the same `ChangeSet` the screen does,
   > which also means the two cannot disagree about what is pinned.
   >
   > Driven in a real window with the app running, which is where four of the
   > five findings came from:
   >
   > - **The popover must not take the focus.** The explorer's filter field
   >   holds it the whole time you are on that screen — that is what makes
   >   typing filter and arrows walk. `autofocus: true` stopped Down dead, and
   >   sweeping several checkouts with `c ↓ c ↓` is the case the screen exists
   >   for. The screen's Escape closes the card instead, before it touches the
   >   filter.
   > - **The directory ellipsised at random-looking widths** — `app/lib/src/
   >   motion/` fitted whole on one row while the shorter `docs/sup…` was cut
   >   on the next — because a `Spacer` and the directory's `Flexible` both had
   >   flex 1 and split the free space between them. Fixing it by flex ratio
   >   then starved the *name* instead. The layout that works is the name
   >   unflexed, taking the width it needs, with the directory as the only
   >   flexible child. Seen wrong in both directions before it was right.
   > - **Name first, directory after it, dimmed.** Even with the truncation
   >   fixed, drawing the directory first left the names on a ragged left edge
   >   — and the name is the column you scan. This is what an editor's
   >   breadcrumb does, for the same reason.
   > - **Nothing bounds a popover's height**, so the card grew until it ran off
   >   the window. Capping it at 380 then pushed the noise tally out of the
   >   scrolling body — and that line is true of the whole delta, like the
   >   header. The tallies are now a fixed band above the footer.
   > - **One card at a time**, unlike the detail: expanded rows stay expanded
   >   because comparing checkouts is the point, but nobody reads two ranked
   >   file lists side by side. The framework dismisses on an outside tap, but
   >   the `c` path has no tap, so the screen closes the last one itself.
   >
   > **The trigger cost, paid as designed:** ~100 px of ~1200 stop expanding
   > the row. Verified by test in both directions — the bar opens the card and
   > does not expand, the rest of the row expands and does not open.
   >
   > `ChangeHeadline` not existing also removes the free ride open question 4
   > was counting on for the row's pin badge. Still not v1; it now needs its
   > own cheap source rather than falling out of this.
6. **Live** — the scoped watcher, state preservation across re-index.

   > **✅ 2026-08-11.** `WorkingTreeWatcher` beside `WorktreeWatcher`,
   > `ShellController.gitMoved`, `ChangesController.watch`,
   > `ChangeSet.sameAnswerAs`, and `ChangeRow.anchorKey` with the screen's
   > anchor. 47 new tests; workspace green at 2183 + 353.
   >
   > **Watched a real window while editing, committing and inserting files
   > into it**, which is where every finding below came from.
   >
   > - **A working-tree watch cannot see `git add` or `git commit`**, because a
   >   linked worktree's index and HEAD live in `<main>/.git/worktrees/<name>/`
   >   — nowhere near the checkout. Committing moves *not one byte* of the
   >   delta and clears every `uncommitted` mark on screen, so this is a real
   >   update, not a nicety. `WorktreeWatcher` already watches exactly that,
   >   repository-wide, for the explorer; the screen listens to both rather
   >   than putting a second watch on the same directory. §7's "one worktree,
   >   one recursive watch" turns out to be the whole of what this slice had to
   >   add.
   > - **`touch` fires nothing, and that is correct.** Measured: an mtime that
   >   moves without a byte changing produces no event on macOS — and moves no
   >   diff either. Also measured: `watch()` returns in **5 ms** on a 2.3 GB
   >   checkout with events arriving immediately, so "the checkout is huge" is
   >   not a reason to hesitate. And 3,000 files written under `build/` is
   >   **9,002 events**, which is why the 2 s floor is the bound rather than a
   >   filter we would have to invent.
   > - **Most re-probes produce the same answer**, because most of what fires
   >   the watch is gitignored build output. `ChangeSet.sameAnswerAs` keeps the
   >   previous object, so the decoded text of every expanded hunk survives and
   >   the screen does not rebuild. The patch bytes are compared in full —
   >   **188 µs for 473 KB**, a ninth of a frame, at most once every two
   >   seconds, which is cheaper than putting a digest nobody else wants into
   >   the model. What bytes cannot see is compared beside them: a commit, a
   >   ranking rule edited outside the checkout, a base that moved.
   > - **A refresh that arrives mid-probe used to be dropped.** It joined the
   >   running read and returned its answer — but the save that triggered it
   >   landed *after* that read touched the disk, so on a checkout an agent had
   >   just gone quiet in, the last edit went missing until somebody pressed
   >   the button. Fine for a button pressed twice; wrong for a watcher.
   > - **Keying the rows does not hold the scroll**, which was worth finding
   >   out by trying it. `findChildIndexCallback` preserves *element* identity;
   >   `RenderSliverList` still lays out from the offset it was given, so a row
   >   inserted above still slid the diff down by its height — photographed at
   >   63 px, small enough to look like a glitch and large enough to lose the
   >   line you were on. The position is now remembered as **a row and an
   >   offset into it**, and restored after the new rows are laid out. Its
   >   bound is stated rather than hidden: only rows the sliver laid out can be
   >   measured, which is a screenful of insertions and then some.
   > - **The liveness has to be visible.** A screen that updates by itself and
   >   never says so is indistinguishable from one that has stopped — and a
   >   watch *can* fail. `Watching` / `Not watching`, with the last read's
   >   clock time in the tooltip. Deliberately **not** an age that counts up:
   >   it needs a ticker rebuilding the header every second for a number that
   >   climbs to "40m ago" on a quiet worktree and reads as broken.
   >
   > A first attempt at that indicator said `Reading…` during a probe, six
   > pixels from the summary's own `Reading…`, meaning something else. A probe
   > is 60–195 ms; the word was a flicker nobody could read.
   >
   > **Not filtered, and deliberately:** nothing here asks git which paths are
   > ignored. A `flutter build` therefore costs one re-probe every two seconds
   > for as long as it runs, all of them returning the same answer and none of
   > them reaching the screen. Naming `build/` and `.dart_tool/` would be a
   > guess about the project, and §3's trap is precisely a `build/` that
   > *stopped* being ignored — whose appearance is a real row. `.git` is the
   > one exception, and it is not a guess: git's own directory is never part of
   > a delta, and on the main checkout it sits inside the tree being watched.

Deliberately after v1, in likely order: **since-last-read** with content-keyed
reviewed state (the prototype is right that this is the biggest
quality-of-life win in repeat review, and it needs the scanner to be settled
first); **the commit selector**, including its honest warning that a
non-contiguous selection is a composed patch that may not apply; **move
detection**; **blast radius**.

## Decisions reached

- The unit is the worktree's **total delta from merge-base to disk**, not a
  selection of commits. Uncommitted work is an attribute of a file, not a mode.
- **Shell-owned screen** at `fw:///worktrees/<name>/changes`, `changes` reserved
  the way `config` already is. It must work on a **closed** worktree — which
  turned out to need a second resolver beside `selected` and an exemption in
  `go`, **not** a tab without a session. An unopened checkout's changes screen is
  a page in the worktrees space, with the pinned tab lit and no rail.
- **One `git diff`, streamed, indexed not parsed.** First-byte-only scan, lazy
  per-file slice, hunk headers give exact expanded heights.
- Git is never the bottleneck; **decoding and widget building are**. All
  performance work goes there.
- The header renders from `WorktreeFactsStore`'s existing cache before any
  process starts.
- Ranking is three tiers: free-from-paths, free-from-the-index, and deferred.
  **Test pairing, blast radius and symbol outline are all out of v1** — pairing
  because it is wrong often enough to teach people to ignore badges, the other
  two because they need a symbol index.
- Config stays **`tool/flutterware.dart` and nothing else**, **executed** like
  every other config. A closed worktree ranks by the **cached** `ChangesConfig`,
  keyed on the config file's mtime and size in the store that already holds the
  branch diffs — full fidelity, not an approximation. Never opened → built-in
  defaults. `.gitattributes` is read first for noise.
- **The base is inferred, never guessed.** `origin/HEAD` → `main` → `master`,
  and when that fails the screen says so and names the fix rather than diffing
  against something nobody chose. The header always shows the base and its
  provenance.
- Every ranking rule is a **hint, never a hide**; the true file count is always
  in the header. **Silent truncation is forbidden anywhere on this screen.**
- **`--untracked-files=normal`, never `-uall`** — git reports the topmost
  untracked directory and does not descend. Measured against the branch-switch
  trap that un-ignores a built package: **1 row and 7 ms, against 30,000 rows.**
  Nothing else may descend either: the row is not counted, and expanding it is a
  bounded click.
- **The probe and scan run off the UI isolate.** The window must not be able to
  hitch on a worktree's contents.
- Colour follows the app's existing tone palette, not the prototype's.
- The churn map and the hunk ruler are kept, unchanged in intent. The ruler
  measures on whichever side of a hunk exists, because a deleted file has no
  post-image at all.
- **The popover runs the same probe as the screen**, rather than a cached
  headline. Measured: the whole patch is cheaper than the metadata calls a
  lighter probe would need, and a cache keyed by sha pair could only ever show
  committed work — which is the one thing this screen is not about.
- **The card does not take the focus.** The explorer's filter field keeps it,
  so `c ↓ c ↓` sweeps several checkouts. Escape closes the card first, then the
  filter.
- **One card at a time**, unlike the expanded detail. Buckets are comparable;
  a ranked file list is not.
- **Ranking has one writer and one reader.** Whatever executes
  `tool/flutterware.dart` records the `ChangesConfig` it produced, stamped with
  the file's mtime and size; everything that ranks reads that. The four cases
  in §5's table are one code path, and "open ranks by the executed config" is
  true because opening is what wrote it.
- **Matching follows `.gitignore`, not `package:glob`.** A pattern with no `/`
  matches the name at any depth, a leading `**/` also matches at the root, and
  a trailing `/` means the directory. Measured: without these, three of the
  four spellings a user would naturally write match nothing and say nothing.
- **Precedence is project → `.gitattributes` → built-in → derived.** Specificity
  order, with the rules read off the change itself deliberately last: demoting
  a file the user explicitly pinned is the one direction a hint must never
  take.
- **Every verdict names the rule that produced it**, in the words it was
  written in. A badge nobody can trace back to a line of config is magic, and
  magic is what people learn to ignore.
- **An attention rule applies to untracked files too**, because an agent that
  just wrote a new migration has not staged it — but **never to an untracked
  directory**, since matching into one is the walk `--untracked-files=normal`
  exists to avoid.
- **`export` is not an import.** The imports-only rule covers `import` and
  `part`; a barrel file gaining an export is the package's public surface.
- **One `WorktreeFactsStore` per repository.** It reads and writes the whole
  file, so two instances are two copies and the last save wins.
- **A file is addressable** — `…/changes/<path…>` expands and scrolls to it, and
  expanding writes the address back. Segments after the plugin id belong to the
  panel, as they do everywhere else.
- Rows come from a **flat list built from hunk metadata**, so scroll extents are
  right before any text is decoded; `displayLines` is a prediction the view must
  tolerate being wrong about, rather than trust.
- The explorer reaches it through a **popover triggered by the fingerprint bar**,
  running the same probe the screen does, with *Open changes* as the footer link.
  (Designed as a cached `ChangeHeadline` beside `ChangeShape`; **not built** —
  that cache is committed-only, and the whole patch measured cheaper than the
  metadata a lighter probe would need. See slice 5.) **Buckets are comparable and
  stay in the expanded detail; files are singular and live in the popover** —
  which is why the detail does not grow to hold them.
- The popover costs the row **~100 px of its expand gesture**, and that is
  accepted rather than worked around.
- **This screen watches its worktree**, as a scoped exception to the explorer's
  no-working-tree-watch rule, only while visible — and it listens to the
  explorer's repository-wide git watch beside it, because **staging and
  committing are invisible from a working tree**: a linked worktree's index and
  HEAD are under the main checkout.
- **A re-probe that found the same answer keeps the previous `ChangeSet`
  object.** Most of what fires a working-tree watch is gitignored build output,
  so this is the common case; keeping the object keeps every expanded hunk's
  decoded text and costs the screen no rebuild at all.
- **Scroll position is remembered as a row and an offset into it**, not as
  pixels, and restored after a re-index. Keying the rows was tried first and
  does not do this — it preserves elements, not the viewport.
- **A watch that is not established is said out loud.** The screen otherwise
  looks live and has stopped being true, which is worse than a screen that
  never claimed to be.
- **Nothing filters the watch by what git ignores.** A build costs one re-probe
  every two seconds and no screen update; naming `build/` would be a guess
  about the project, and a `build/` that stopped being ignored is a real row.

## Rejected

- **A plugin (`flutterware.changes`)** — would get sidebar, CLI, MCP and search
  free from `PluginCore`, but needs an open worktree and a config subprocess, so
  the explorer could never link to it for the thirteen worktrees you have not
  opened. That link is the primary path.
- **`-U0` to shrink the payload** — 469 KB against 473 KB. It buys nothing and
  costs the context that makes an expanded hunk readable.
- **Parsing the whole patch into lines up front** — 3.6 MB of Dart strings for a
  screen whose first paint needs none of them.
- **A commit selector in v1** — the right control for a pull request, the wrong
  model for an agent's uncommitted work (§1), and its composed-patch honesty
  problem is real work that the delta model does not need.
- **`--color-moved` for move detection** — git really can do it, but only into
  ANSI output. That is a parsing spike, not a feature, and it goes in a spike
  brief rather than a v1 section.
- **Blast radius in v1** — needs a symbol index; tractable for Dart via the
  analyzer, and a project of its own.
- **A YAML config file** — it would buy exactly one property, closed-worktree
  ranking, at the cost of the static analysis and autocomplete that are the
  reason `tool/flutterware.dart` is Dart. Caching the executed value buys the
  same property and keeps them.
- **A syntactic scan of the config** — proposed and withdrawn the same day; see
  the correction in §5. A lossy re-derivation of a value we had already computed
  exactly and thrown away.
- **Test pairing** — see the decision above. Cheap, and cut for being wrong too
  often.
- **`--untracked-files=all`** — 501 rows where git's default gives 2, and the
  freeze this screen must not have.
- **Guessing a base** when `origin/HEAD`, `main` and `master` are all absent — a
  diff against something the user never chose is silently wrong in the most
  expensive direction.
- **The prototype's teal/amber palette** — good reasons, already-answered
  questions in this app's design tokens.
- **A polling timer** — the watch is the signal, visibility gates it.

## Open questions

1. **What a `stale` cached config should actually do.** The config file has moved
   since we cached it, and the worktree is closed. Ranking by the old value and
   labelling it is one answer; another is to execute it anyway — it is 70–80 ms
   warm, and "closed" is a statement about sessions and tabs, not a vow never to
   run a subprocess. Leaning: cache-and-label, because the explorer's whole
   premise is that a list of worktrees costs no subprocesses, and one exception
   invites the next.
2. **A stacked branch's base.** Inference gives `master`, but the interesting
   base is the parent branch and nothing in the repository records which that
   is. `base:` on `ChangesConfig` is per-repo, not per-worktree, so it does not
   solve this. Leaning: base pickable in the header, remembered per worktree in
   the facts store, which needs no config at all.
3. **The untracked-directory expansion.** One row is right; what the click does
   past 200 entries is not settled — page, or refuse and say "open it in your
   editor". Leaning: refuse, because paging a directory nobody should be reading
   is building the wrong feature well. A related temptation to resist: offering
   *"add to .gitignore"* on the row. It is the correct fix for the trap that
   produced it, and it is a write to the user's repository from a screen whose
   entire contract is that it only reads.
4. **Where the pin badge goes in the 220 px changes cell.** The cell already
   holds a bar, two counts and a dirty badge; a `migrations` chip needs room the
   column does not obviously have. Options are a glyph instead of a word, a
   second line, or promoting it into the gutter dot's tone. Needs to be built and
   looked at, the way the detail's three layouts were.
5. **Whether the popover trigger should instead be a hover-revealed glyph in
   `_Actions`.** It would steal no tap at all and follows that cluster's existing
   hover-reveal pattern — but 76 px already holds `Open` plus a chevron, and it is
   the least discoverable spot on the row. Rejected for now on discoverability;
   revisit if the dented expand gesture annoys anyone in practice.
6. **Second `AgentProbe` attribution.** The facts layer already reads Claude's
   session JSONL. "These files changed since the agent's last message" is
   reachable from data we hold and would be the most direct answer to *what is
   it doing right now* — but it needs a per-turn timestamp the current tail
   reader does not extract. Unowned, and deliberately not promised in v1.
