# The changes screen, v2: a commit range, and colour in the diff

Both features here were named and deferred by
`2026-08-10-worktree-changes-design.md` — the commit selector in §1 and its
"Rejected" list, syntax highlighting in §6 and again in the build order, where
it is called *polish, not a gap*. Neither was rejected on merit. This picks
them up, and the interesting half of each is the thing the original doc only
gestured at: **what a non-contiguous selection actually is**, and **what a hunk
is not**.

Nothing here changes what v1 decided. The unit is still the worktree's total
delta from merge-base to disk; a range is a lens over it, the way *just
changed* is, and it starts open on the whole thing.

---

## A. The commit range

### What was asked for

> A popover with the list of commits + uncommitted and a way to check/uncheck
> them to see only a part of the changes.

…and then, on reading the honesty problem below:

> would that help if it was not a checkbox but a radio, something we just pick a
> range or a single commit?

It would, and it is what this section now specifies. The short reason is in the
next two headings: **a single commit is already a range of one**, so a control
that can only pick one row or one run is a control every state of which is a
real `git diff`. See *the spelling* below for what that changes.

### The honesty problem, stated exactly

git can hand you a diff between **two trees**. Every selection that is a
contiguous run of commits is two trees:

| selection | the diff | honest |
| --- | --- | --- |
| everything (v1) | `git diff <merge-base>` | ✅ |
| the working tree only | `git diff HEAD` | ✅ |
| one commit, `c3` | `git diff c2 c3` | ✅ |
| `c3…worktree` | `git diff c2` | ✅ |
| `c2…c4` | `git diff c1 c4` | ✅ |
| `c1` and `c3`, not `c2` | — nothing git can produce | ❌ |

The last row is the whole reason §1 deferred this. A set with a gap in it has
no tree pair, so "the diff of c1 and c3" has to be **composed**: either the two
per-commit patches concatenated — in which case a file touched by both appears
twice — or a synthesised patch against a tree that never existed, whose hunk
headers name line numbers in a file nobody is looking at and which may not
apply. The original doc's phrase for it is right: *its composed-patch honesty
problem is real work that the delta model does not need.*

Read the table again and the shape of the control falls out of it: **every
honest row is a range, and a single commit is a range of one.** There is
nothing a set can express that a range cannot, except the row marked ❌.

### The decision: one range, picked like a file list

The ordered list is `[merge-base, c1, …, cn, working tree]`, newest first in the
popover, with `Everything` — the v1 delta, and the default — pinned at the top.

**Click a row and you get exactly that row.** Radio semantics: one commit, or
the working tree, or everything. **Shift-click a second row and you get the run
between them.** That is the idiom every file explorer has trained into people,
and it is the whole interaction.

**A checkbox was the wrong spelling.** It is set semantics over a thing that is
not a set: it advertises the one selection git cannot produce, and then the
control has to take it back — by filling in the gap you just skipped, by
greying rows out, or by a warning that a composed patch may not apply. All
three are the control apologising for its own affordance. A radio never lies
about what it can do, and the honesty problem does not get handled, it stops
existing.

This is one argument to the existing call. `ChangesProbe` already computes
`range` in `_rangeFor` and already carries `mergeBase` and `head` on the
`ChangeSet`; the whole feature is that `range` becomes `<from>` or `<from> <to>`
instead of always the merge base.

**The working tree is the last row, not a separate mode.** `uncommitted` alone
is `git diff HEAD` — the single most useful selection on this screen, and the
one an agent-watcher reaches for hourly. Treating it as row *n+1* of the same
list is what makes it a plain click, and what makes *since c3* — the question
you have when you have been away — a shift-click from `c3` down to it.

**What a radio cannot do, and what the answer to that is.** *Everything except
that lockfile-regen commit* is the one selection a checkbox was attractive for,
and it is the ❌ row: unbuildable whichever control asks for it. It is also not
really a question about commits — what is wanted is to stop looking at
`pubspec.lock`, which is the filter box and `attention:` rules, and both already
exist. Do not re-open the set model for it.

### What a range breaks, and has to be handled

These are not incidental; each is a place the screen currently states something
that stops being true.

- **Untracked files are not in any commit.** With the working tree out of the
  range they must leave the index entirely, not sit there unexplained. The
  *All* tab's untracked section and `attentionForUntracked` both key off this.
- **The `uncommitted` badge is a comparison against `HEAD`**, which is
  meaningless inside a range that ends at `c4`. It comes off the rows, and the
  summary's `n uncommitted` with it.
- **The watch stops meaning anything.** A range that excludes the working tree
  cannot be moved by a file write, so `_Watching` must say *pinned to a range*
  rather than *Watching* — a screen that claims to be live while showing frozen
  commits is exactly the "stale screen you trust" that widget's doc warns about.
  A range that *includes* the working tree stays live and unchanged.
- **The comparison strip's `against <base>` becomes false for this tab only.**
  Previews and scenarios always compare against the base; they have no range.
  The files tab therefore has to state its own range when it is not the default
  — which it can, on the summary line the header now is.
- **Ranking counts, the tab labels and the *just changed* lens** all read the
  narrowed set, which is correct and needs no work — they read the `ChangeSet`.
- **A diff that ends at a commit describes files as they *were*.** Its line
  numbers are in an intermediate tree, not on disk. Nothing on this screen jumps
  to the file on disk today, so nothing breaks — but "open this line in the
  editor", if it is ever wanted, is only correct for a range that ends at the
  working tree, and has to say so rather than open the wrong line.

### Where the control lives

The **base statement is the trigger**. `base master (inferred)` in the summary
line already answers "what am I looking at against what"; a range is the same
sentence with more in it, so the chip becomes tappable and opens the popover
above it. No new affordance in a header that has just been cut down to one
line, and the thing you click is the thing that changes.

`ui/popover.dart` exists and is what the explorer uses.

### The address

`fw:///worktrees/<n>/changes/files/<path>?from=<sha>&to=<sha>` — plain
parameters above the segments, the grammar the scenarios panel already uses for
`?device=`. A range you cannot paste is a range you have to re-pick every time
somebody asks you what you are looking at.

### Cost

| piece | shape |
| --- | --- |
| `ChangesProbe.commits()` | one `git log --format=… -z <merge-base>..HEAD`, ms |
| range on the probe | `_rangeFor` takes it; one argument changes |
| the consequences above | the real work — each is a conditional and a test |
| the popover | a list, click and shift-click. Smaller than the checkbox version by exactly the apology it no longer has to make |
| address round-trip | parameters, and a test like `scenarios_address` has |

Roughly a day, most of it in the consequences rather than the control.

### ✅ Built 2026-08-12

`change_range.dart` (the arithmetic, pure), `range_picker.dart` (the control),
plus `range:` on `ChangesProbe.probe`, `commits`/`range` on `ChangeSet`,
`setRange` on the controller, and `?from=`/`?to=` through
`ShellController.selectChangesFile` / `selectChangesRange` /
`selectChangesTab`. 46 new tests; workspace green at 2415.

Verified against real checkouts rather than only in tests: one commit of
`review-ai-codebase-b0026c` renders **16 files +35 −373**, which is exactly what
`git diff --numstat e1a5322d 01f0edb5` says, and the pasted
`?from=…&to=…` address opens straight into it.

Five things the build corrected, none of which reading the design would have
found:

- **The anchor has to outlive the popover.** Picking a row closes the list, so
  the only way to perform a shift-click is *click, reopen, shift-click* — and
  clearing the anchor on close made the second one a plain click. Caught by the
  test, not by the code. Nothing is hidden by keeping it: the anchor is always
  inside the current range, and the range's rows are the lit ones.
- **`Everything` must not light every commit row.** Every commit *is* inside the
  whole delta, so marking them all made the top row indistinguishable from a run
  spanning the branch, and a list where every row is lit has stopped saying
  anything. Picking the oldest commit and shift-clicking the working tree comes
  out as `everything` on its own — both ends resolve to null — so the top row
  lighting up again is the arithmetic agreeing, not a special case.
- **The chip *is* the base statement, not a control beside it.** The header had
  just been cut to one line; the base already answered *against what*, which is
  the same question a range answers with more in it. Under the comparison strip
  the unnarrowed label drops to `Everything`, because the strip says the base —
  except for `no base`, which is said either way, being the reason the counts
  beside it are smaller than they look rather than a duplicate of anything.
- **A commit moves the picker without moving a byte of the patch**, so
  `sameAnswerAs` had to grow a commit-sha comparison. Committing the whole
  delta changes nothing on the left and everything in the list; without this the
  popover stayed a commit behind for as long as the screen was open — which is
  precisely the case `gitMoved` exists for.
- **`--first-parent` is load-bearing, not tidiness.** The left edge of a run is
  *the row below its oldest commit*, which is only well defined for a linear
  list. It is also what a person means by "the commits on this branch".

Two smaller decisions worth keeping:

- **Narrowing drops the file selection.** A file in the whole delta is often not
  in one commit of it, and the right pane's *this file is no longer part of the
  delta* is a confusing thing to read about a file you were just looking at and
  have not touched.
- **`setRange` drops the previous answer**, unlike a refresh. Stale-then-fresh
  is right for the same range read twice and wrong here, where the old counts
  under a new label would be the screen actively lying for the ~100 ms the probe
  takes.

### What is deliberately **not** in this

**An arbitrary set of commits.** The radio is not a stepping stone to it — it
is the decision not to have it. A set wants a different body: not "this file's
diff" but "this file, once per selected commit that touched it", which is a
history rather than a diff and a different screen. If that screen is ever
wanted it starts at `buildFileRows`, and the popover is the last thing it
would change.

---

## B. Syntax highlighting in the diff

### What already exists

`dartSpans` in `app/lib/src/scenarios/help_page.dart` — the vendored
`highlight` tokeniser with **the app's palette rather than a highlight theme**,
which is the right call and the doc comment says why: the shipped themes are
picked for a light or a dark editor and this app is both. That function is the
feature, minus a cache and a language table. It moves to `app/lib/src/ui/`,
and the help page keeps calling it.

### The two things that make a diff different from a code block

**1. A hunk is a fragment.** `highlight.parse` starts in the default state, so a
hunk that begins inside a block comment or a triple-quoted string colours the
rest of itself wrong. Parsing the hunk **as one string** rather than line by
line fixes every multi-line construct that opens and closes inside it, which is
almost all of them; a construct that opens above the hunk cannot be fixed
without the whole file, which the diff does not carry. Accept it. The vendored
parser does have a `continuation` parameter on its private `_parse` and a
`Result.top` to feed it — if boundary errors turn out to be visible in use,
exposing that on the public `parse` is a three-line change to a file we already
edit in place.

**2. A hunk is two files interleaved.** This is the one that will be missed.
The `-` and `+` lines are alternative versions of the same region; feeding them
to one tokeniser means a removed line that opens a quote and an added line that
does not close it leave the tokeniser in a state neither version of the file is
ever in. So: **two parses per hunk**, over two reconstructions —

- old side: context + removed lines, in order
- new side: context + added lines, in order

— and each display line takes its spans from its own side. Context lines are in
both; take them from the new side.

### Where it plugs in

`HunkLineCache.linesFor(hunk)` already decodes bytes into `List<DiffLine>`
lazily per hunk and is thrown away with the patch. The span cache is the same
shape, keyed by the same hunk, and shares its lifetime — one class, not two.
`DiffLineView` takes `List<InlineSpan>?` and falls back to `line.text`.

### Language selection

By extension, from a **fixed table of about a dozen** — dart, yaml, json, js,
ts, kotlin, swift, java, python, bash, sql, xml/html, css. Not
`languages/all.dart`: that is 190 languages compiled into the app for a screen
that will meet four of them. An unknown extension is not an error, it is plain
monospace, which is what the screen does today.

### The frame budget

§6 calls this "the one thing on this screen expensive enough to show up in a
frame budget", and that claim has never been measured. It has to be, first,
because the answer decides the shape:

- **under ~1 ms for a typical hunk** → compute synchronously on first build,
  cache, done.
- **not** → compute in a microtask and rebuild the hunk when it lands, and cap
  it: a hunk past *N* lines stays plain. A diff that stutters while you scroll
  is worse than a diff that is grey.

Measure before writing the widget, with a hunk from a real 1109-line file — the
`database_panel_view.dart` in the sqlite worktree is a good one.

### Tests

- a `+` line of Dart yields a keyword-coloured span
- the old/new split: a hunk whose **removed** line opens a string that the
  **added** line does not, and the added line's colours are unaffected
- an unknown extension yields one plain span and no throw
- the cache: two reads of one hunk parse once

### Cost

Half a day, and it is genuinely polish: the measurement, the two-sided parse
and the language table are the whole of it.

### ✅ Built 2026-08-12

`app/lib/src/ui/syntax.dart` (the tokeniser, the language table, the palette
mapping) and `app/lib/src/changes/hunk_syntax.dart` (the two-sided per-hunk
cache), wired through `DiffLineView`. `dartSpans` left `help_page.dart` and
became `codeSpans` on the shared module. 18 new tests; workspace green at 2432.

**The measurement came first, and it decided the shape.** On the vendored
tokeniser, against the real `database_panel_view.dart`:

| lines | chars | parse |
| --- | --- | --- |
| 20 | 867 | 0.29 ms |
| 60 | 1,820 | 0.58 ms |
| 200 | 5,740 | 1.60 ms |
| 600 | 17,651 | 4.80 ms |
| 1,110 | 34,257 | 9.25 ms |

Near enough linear at ~0.28 ms per 1000 characters. So §6's claim — *the one
thing on this screen expensive enough to show up in a frame budget* — is right
only at the tail: an ordinary hunk is tens of lines and costs a fraction of a
frame even parsed twice, and it is the **whole added file**, which arrives as
one hunk of a thousand lines, that would cost most of a frame. Synchronous on
first build, cached. No microtask, no rebuild-when-it-lands: that shape was only
needed if the common case was slow, and it is not.

#### The cap, and why there is not one

The first build capped a hunk at 500 lines and drew anything longer plain, with
a `not coloured · 1109-line hunk` note in the header — because
`ChangesLimits`'s own doc says every bound here is visible when it bites. Both
are gone. The question that removed them was **"why not colour only what is on
screen?"**, and answering it properly gives something better than either:

- **The viewport cannot be the unit.** Tokeniser state depends on where the
  fragment starts, so with a viewport-sized parse the same line changes colour
  as you scroll — start the window above a `/*` and line 300 is a comment, start
  it below and line 300 is code. Colour that flickers under scrolling is worse
  than grey.
- **Fixed boundaries can be.** Each side is parsed forward in
  [`highlightChunkLines`] blocks by *line index*, on demand, and the tokeniser's
  own state is threaded from one block into the next — so a block's colours are
  a property of the file, not of how you arrived at it, and a construct
  straddling a boundary survives it. That last part needed a two-line change to
  the vendored `highlight`: `_parse` has always taken a `continuation` and
  `Result` has always returned a `top`; only the public `parse` hid them.
  **A re-vendor will drop it.**
- **So chunking is a scheduling decision and nothing else**, and there is no
  size at which the screen stops colouring. Measured on the same 1,109-line
  file: **3.0 ms for the first screenful**, then ~2.6 ms once per 200 lines
  scrolled. Against 9.25 ms in one go, or nothing at all under the cap. Total
  work across the whole file is ~70% higher — 15.9 ms against 9.25 — which is
  the right trade for a UI, where what matters is the size of the worst single
  hitch.

The test that keeps it honest opens a `'''` two lines before a boundary and
reads a line five past it. Verified to fail when the threading is removed.

Three more things the build settled that the design did not:

- **Tokens are cached, not spans.** A `TextSpan` carries a `Color` from the
  palette, so a cache of spans is a cache that is wrong the moment the window
  changes theme. What is cached is `Token(text, className)` — plain data, and
  testable without pumping anything.
- **The old side is only built when there is one.** A hunk of pure additions —
  what an agent writing new code produces — has no removed lines, so context and
  added both come off the new side and the second side never exists. Half the
  cost of the two-sided design, back, in the common case.
- **The token cache is keyed by the open file, not by the patch.** The line
  cache is per patch because lines are per patch; the *language* is per file,
  and one cache outliving a selection would hand a hunk of Dart to a `.yaml`.
  One file is open at a time, so one cache is the right number.

Also true, and worth knowing before someone matches on diff text: a coloured
line is a `Text.rich`, and `find.text` and the semantics tree both still see
the plain string — the drive tools' `texts` are unchanged.

---

## Two things found while polishing, worth recording

- **The base is resolved twice, and the two can disagree.**
  `BaseRef.defaultBranch` (comparison) keeps `origin/master`;
  `GitProbe.defaultBranch` (changes screen, explorer) strips the prefix and
  uses the **local** `master`. On this machine they are the same commit, so the
  only visible symptom was two spellings in one header — but a worktree whose
  local trunk is behind its remote gets two different deltas on one screen.
  `BaseRef`'s own doc comment says these must not disagree. One of them should
  go.
- **A tab reached by address never ran its half.** `ComparisonTabs` opened the
  selected half only from the click path, so arriving at `changes/scenarios`
  from a link, the back button or a drive `navigate` lit the tab and left it on
  *Nothing to compare yet.* for ever. Fixed 2026-08-12 in `_onShell`.
