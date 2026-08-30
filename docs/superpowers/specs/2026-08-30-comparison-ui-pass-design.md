# The comparison UI pass — what the screen says

Phase C of `2026-08-29-comparison-events-channel-design.md`. That note makes
every difference a delta carrying five facets; this one is about what the
studio does with them.

The split matters: **the model decides what can be known, the UI decides what
gets said.** Phase A and B ship a complete faceted artifact and change almost
nothing on screen. Everything here reads that artifact and computes nothing of
its own.

## What is already right

Worth stating before proposing anything, because most of this screen is good
and the reasons are written down in
`2026-08-11-worktree-comparison-design.md` §9.

- **Three tabs on the worktree's Changes panel**, not a space of their own.
  Files is free and the other two cost seconds, so the expensive halves get
  discovered behind the screen you already open to read a diff.
- **Nothing runs on tab focus.** One explicit Compare per half. Reversed once
  already, on measurement; not to be reopened.
- **Master and detail, not a wall of thumbnails.** A catalog is hundreds of
  entries and a grid spends its area on the ones that did not move.
- **Both halves rank worst-first** — `ComparedState` is declared in severity
  order, so ranking is a sort, and it is already applied in
  `ComparisonResult.of` and `ScenarioResults.of`.
- **The stage** — side by side, slider, onion, blink, pixels, with the diff's
  cluster boxes drawn on the head half and the pixels lens tinting regions
  rather than merely outlining them.
- **The empty state** names the base and says what the first run will cost.

None of that is what this note changes.

## 1. The screen has no verdict

`ComparisonIndex.findings` merges both halves and ranks them worst-first. `fw
compare` uses it. The exported page uses it. `comment.md` uses it. **The studio
does not** — you land on `files`, and each half's findings live behind its own
tab, so the question the whole feature exists to answer has no place on screen
that answers it.

A **verdict strip** above the tab row, always present once either half has run:

```
previews 4 · scenarios 2 · 1 new          pixels 5 · tree 3 · events 2 · +192 system
```

Left, the counts by half; right, the counts by channel with filtered channels
still announcing themselves (`2026-08-29` §6). Every number is a control: it
selects the tab and applies the filter that produced it. A half that has not
run says so rather than reading as zero.

Above the tabs rather than as a fourth tab, and rather than as a landing screen
of its own. The tabs are drill-downs into one delta; a fourth tab beside them
would say the verdict is a fourth view of the same rank, and a landing screen
would put a click between the user and the diff they came to read.

**It must be counted, not built.** `ComparisonIndex.ok`'s own docstring is the
warning: *"Counted rather than built... the exported page reads this from
inside a `build`, and `findings` allocates a row per finding and sorts them."*
The same trap has already been paid for once — a plugin's report join that went
quadratic and cost 324 ms a frame. The strip reads counts; it never sorts.

## 1a. Research — the studio already has most of this

Before drawing anything, what exists. The answer changes the shape of the whole
pass: **this is composition, not new components.**

| what | where | what it already decides |
|---|---|---|
| `FwFilterBar` | `ui/filter_bar.dart` | Two axes, and the reasoning for them. `pills` are one-of; `toggles` are *"filters that narrow whatever `pills` chose, rather than replacing it"*, kept visually apart because a pill means one-of and these do not. Below 520px the count stands down. |
| `CountBadge` | `ui/count_badge.dart` | `Events ⟨7⟩` reads as a label with a quantity; `Events 7` reads as two words. And `active: false` — *"Off recedes rather than disappears: the count is still the reason a reader would turn it back on."* |
| `StateChip` | `comparison/ui/state_chip.dart` | *"Colour is the fastest thing on the screen and the least precise"* — red means three things here, so every chip carries its word too. Optional `count`, for standing in for a group. |
| `_ChannelChip` | `scenarios/events_view.dart` | A channel name plus its `CountBadge`, toggled, accent-soft when on. The comparison's channel filter already exists; it is just pointed at one run instead of two. |
| the files tab's `_Tab` strip | `changes/changes_screen.dart` | `All 1 · Important 1 · Review 0` — a filter strip **on this very screen**, and a `live` flag for the one count that is about *you* rather than about the checkout. |

Two consequences.

**§2's "monochrome badges" was wrong, and the code says why.** There is already a
channel colour language — `network` accent, `analytics` green, `db` amber,
`system` `mut3` — chosen *"so a transition can be skimmed for its shape before
it is read: the two that usually matter stand out, chatter recedes."* Inventing
a second one would be the mistake; so would ignoring it.

But it cannot go on a finding row unaltered, because that row already carries a
`StateChip`, and the two palettes collide on the two colours that matter: green
is `added` **and** `analytics`, amber is `changed` **and** `db`. So: **channel
colour belongs where events are the only subject** — the events pane, and the
folded shape line — and **a finding row keeps state colour and names its
channels in words.** `StateChip`'s own rule generalised: colour may be the fast
path, never the only carrier.

**The filter is not new work.** `FwFilterBar`'s two axes are exactly §3's
`include` pills and `exclude` rules, and the run cockpit already argued the case
for keeping them apart: folding `Errors` into the app/build/platform pills would
have made it mean *everyone's* errors, throwing away the split at the one moment
it earns its keep.

## 1b. Five options, rendered

Drawn as real widgets against the real design system —
`app/tool/catalog/demos/comparison_verdict.dart`, entries under *Comparison* —
because a mockup that does not use `FwSpacing` and `context.colors` cannot
answer whether this fits.

| | what it is | verdict |
|---|---|---|
| **A** | `StateChip`s alone: `7 changed · 2 added · 36 same · 156 skipped` | Familiar and free, and answers the wrong question. It counts *rows by state*, not what the branch did, and carries no channel at all — so the entire events channel is invisible on it. `36 same · 156 skipped` is coverage proof, which belongs in the artifact rather than in the headline. |
| **B** | channel chips with counts, toggled | Closest to what the model now produces, and rendering exposed two faults. `pixels 0 · tree 0 · texts 0` spends three-fifths of the strip saying nothing. And `system 11` sits beside `events 7` as a sibling when it is a *subchannel* — a hierarchy drawn as a list. |
| **C** | `FwFilterBar` — pills, toggles, search, count | Handsome, and it is the studio's own bar. But it is a **filter, not a verdict**: it says `9 of 201` and nothing about what changed. The search box earns nothing on a nine-item list. This is right for §3 and wrong for §1. |
| **D** | one sentence, folded | Says the right things, including the one line no other option can print: *nothing moved on pixels, tree or texts*. But it is static — §1 requires every number to be a control. |
| **E** | **D's sentence with B's controls** | Recommended. See below. |

### Why E

The counts lead, because they are the verdict. The channels that **fired** are
chips, because a reader wants to click them; the channels that **did not** are a
sentence, because three chips reading zero waste the strip and the sentence says
it better. `system` sits in the events group rather than beside it. The folded
shape (§4a) gets its own line with its count receding to the right, so a reader
sees *what this comparison is mostly made of* without it competing with the
verdict.

### Where it goes: full width, above both panes

The floating strip could not answer this, and the question is the first one a
reader of the proposal asks. The tab's layout is the files tab's, and it has
exactly one slot for something like this:

```
_Header            ← full width: title, branch, `0 files  +0  -0`, Watching
Divider
Expanded( Row( _IndexPane(width: 320), │ detail ) )
```

**The verdict takes the header slot** — full width, above the divider, above
both panes. Drawn both ways at 900px
(`tool/catalog/demos/comparison_verdict_in_place.dart`), and it is not close:

- **Full width** — one line of counts and chips, the quiet-channels sentence
  under it, the folded shape under that. Nothing wraps, nothing truncates.
- **Over the index only** — inside 320px the chips wrap to a second row, the
  shape line truncates to `autofill.uniqueIdenti…`, and the whole thing eats
  about 110px of the list's height. It is also wrong in kind: a verdict is
  about both halves and both panes, and putting it in the index column says it
  is a property of the list.

So the two things are in two places, and they are not the same thing:

| | where | what it is |
|---|---|---|
| the **verdict** (§1) | the full-width header slot | what this branch did — counts, channels that fired, the folded shape |
| the **filter** (§3) | ~~inside the 320px index~~ → **the verdict header**, see §3a | what is *not* being looked at |

That also settles the narrow-width worry: the verdict is only ever as narrow as
the window, where the filter really does live in a 320px column. The `Wrap`
stays anyway — a window can be narrow.

One residual, visible in the full-width shot: at 900px the folded shape's count
badge sits hard right, a long way from the text it counts. Either tuck it
straight after the text or drop the `Expanded`.

### What rendering it caught, that reasoning did not

**Narrow width is the discriminator, and it broke the first draft.** E as first
written was a `Row`, and at 430px it threw **two** overflow exceptions. A `Wrap`
fixes it — which is the lesson the files tab's own strip records three hundred
lines away: *"`Wrap`, not `Row`, and the reason is the test binding... this strip
really does overflow 320px."* The same mistake, on the same screen, twice.

**C overflows around 358px** with five pills and a search box — narrower than
this pane gets when a detail is open beside it. Not a bug in `FwFilterBar`,
whose own `_roomy` rule stands the count down at 520; a constraint on how many
pills §3 may spend.

**Two facts joined by a `·` read as one list.** E's first draft ran the quiet-
channels sentence into the folded shape. On screen they read as a single
enumeration, though one is about coverage and the other about noise. Two lines.

## 2. A finding does not say which channel fired

A row in either master list carries its state chip and its label. Whether it is
there because of pixels, because of the tree, or because an event moved is
invisible until you select it and read `ChannelLines`.

Channel badges on the row, **named rather than coloured** — see §1a for why
this used to say "monochrome" and what corrected it. There is already a channel
palette, and it is right where events are the only subject; on a finding row it
collides with the `StateChip` on exactly the two colours that carry meaning.
Colour stays for state; the channel is a word.

The badge is also the filter's smallest handle: clicking `events` on a row is
the same act as excluding every other channel.

## 3. The filter, and how a rule gets authored

The request this is built for: *"show me every screen that changed on pixels or
events, but not the db events coming out of `lib/data/cache.dart`, and no logs
at all."*

`2026-08-29` §9 settles the record — a filter is a list of rules, each a
conjunction over `half`, `channel`, `subchannel`, `property`, `origin`, each
including or excluding. What is left is how a person builds one.

**Never by typing.** A query box would be a language to learn, and the middle
clause above is exactly the kind nobody gets right first time. Instead a rule is
authored **by pointing at an example**: right-click a delta row →
*exclude events like this from `lib/data/cache.dart`*, and a chip appears
reading `− db · lib/data/cache.dart`. The chip is editable by dropping one of
its constraints, which widens the rule, or by adding one from another row, which
narrows it. The vocabulary is the facets and nothing else, so a rule can never
be malformed.

This is the same move the drive layer makes with targets: you address what the
last reply showed you, rather than composing an expression against a schema you
have to hold in your head.

Three things the filter must not do:

1. **Never hide a count.** A filtered channel keeps its number in the strip
   (§1). The filter decides what is drawn, never what is known — the artifact
   is complete by construction and a reader who filters everything out still
   sees that there was something to filter.
2. **Never survive silently.** A filter still applied on a later comparison,
   with the chips off screen, is how a reader is quietly lied to. Chips live in
   the strip where the counts are, and the strip is always visible.
3. **Never reach the artifact.** `index.json` is written whole, filtered or
   not. A `tool/` script reading it gets the same answer regardless of what
   anybody had toggled.

## 3a. Excluding some events from one file — audited and drawn

The model carries five facets. Checking each against what the UI had actually
drawn found one with no home at all.

| facet | where a reader meets it | before this section |
|---|---|---|
| `half` | the tab strip — previews / scenarios | ✅ |
| `channel` | verdict chips (§1), row badges (§2) | ✅ |
| `subchannel` | verdict chips — `events`, `system` | ✅ |
| `property` | the delta line in `ChannelLines` | ✅ |
| `origin` | **nowhere** | ❌ — drawn now |

Drawn as `tool/catalog/demos/comparison_filter.dart`. Three questions prose had
left open, and none of them could be settled without drawing it.

**Where is a rule authored?** From a **delta row in the detail pane**,
right-click. That is the only place a reader is looking at an origin, and it is
the point-at-an-example gesture §3 asked for. The menu is a **ladder by width**,
because the fact somebody wants to stop seeing is at a different width every
time:

```
Stop showing
  this field, on this statement            1 delta
  any field, on this statement             3 deltas
  db events from cache.dart                3 deltas · 2 findings
  everything from cache.dart               3 deltas · 2 findings
  every db event                           9 deltas · 4 findings
  ─────────────────────────────
  Report this shape to flutterware…
```

Every rung says what it would remove, so nothing has to be tried to be
understood. `MenuItem.onHover` already exists *"for a host that previews the
row's effect somewhere else on screen while you point at it"* — so the list
behind can dim what the rule would take while the pointer is on the rung.

**Where does the chip then live? The verdict, not the index — the placement
table above is corrected.** `All · Important · Review` in the index is a *list
scope*: which rows to list. A rule is a statement about the whole comparison,
it has to sit beside the counts it changes or §3's rule 2 is broken, and it
does not fit in 320px beside a search box and three tabs. It reads
`− db · cache.dart ⟨3⟩ ×` — struck through, muted, its count still legible,
one click to undo.

**What happens to a finding whose only delta a rule removed?** It is
**demoted, not deleted** — greyed under `7 hidden by your rules`, with
`7 findings hidden by 2 rules · show` in the verdict. This is not a new
invention: the comparison design already decided this exact shape for
`skipped` rows, on the grounds that *a row that is missing tells a reader
nothing*. A row a **rule** removed is the same claim, made about the reader
instead of about the tool, so it degrades the same way. It is also the only
answer compatible with §3's rules 1 and 2 — the measured case would otherwise
make all seven findings vanish at one click with nothing on screen saying so.

### What is v1, and what is not

The measured case does not need any of the authoring machinery, and that is
the whole staging argument. `system` was 11 of 11 here and 192 of 293 on a
consumer's suite: **a single-facet exclusion**, which is a chip you click on
the verdict and nothing more.

| | what | cost |
|---|---|---|
| **v1** | verdict (§1), row badges (§2), folding (§4a), new-since-last (§4) — all read-only | low; no rules anywhere |
| **v1.5** | the verdict's channel chips become toggles — one facet, no authoring UI | low; covers the measured 90% |
| **v2** | conjunction rules, the authoring ladder, `origin`, the hidden group | the rest of §3 and §3a |

The seam that makes the staging safe is the same one as before: v1.5's toggle
and v2's rule are the *same record* — a rule with one constraint — so the
chip drawn in v1.5 is the chip v2 adds constraints to. Nothing is rebuilt.

### The exclusion log is a signal, not just a setting

When somebody excludes the *same shape* over and over — the 266
`autofill.uniqueIdentifier` deltas in the report that prompted all of this —
that is a candidate for the shared normalisation list (`2026-08-29` §11.4),
which is ours to own rather than theirs to declare. The filter is therefore the
cheapest discovery channel we have for entries that should never have needed
filtering. No analysis: watch what people exclude.

## 4. New since the last comparison

*"Four entries report changed on every comparison, permanently, are enough to
teach a reviewer to skim past the list."* That is the failure mode a comparison
tool dies of, and it does not need review state to fix.

The previous `index.json` is already on disk per worktree. Diffing this
findings set against it costs nothing and turns the verdict into
`6 findings · 1 new`. A permanently-noisy entry stops shouting without being
hidden, and the one that appeared because of this branch is the one the eye
lands on.

`new` is a property of the row, so it is a facet-shaped thing the filter can
use like any other — *show me only what is new* is a rule, not a mode.

## 4a. ✅ Measured, and built — fold the repetition before filtering the channels

Run against this repository on 2026-08-30, head against `origin/master` and
again against `4da90289`. Both answered identically, which is itself the
finding.

| | |
|---|---|
| preview rows | 185 — 150 skipped, 33 same, 2 added, **0 changed** |
| scenario rows | 16 — 9 same, 7 changed |
| steps compared | 74 |
| steps with a finding | 11 |
| steps where `pixels` fired | **0** |
| steps where `tree` fired | **0** |
| steps where `texts` fired | **0** |
| steps where `events` fired | **11** |
| event deltas | 11 |
| **distinct delta shapes** | **1** |

Three things follow, and only one of them is about a lens.

**Every finding was invisible to a screenshot.** Eleven findings, none of them
on pixels, tree or texts. A pixel-only comparison of these 74 steps reports
*nothing changed*. That is the events channel's whole argument, measured on our
own repository rather than asserted.

**`system` by default is settled.** All 11 deltas were `system`, on
`flutter/textinput TextInput.setClient`. With the consumer's 192-of-293 that is
two independent datasets saying the same thing, and §3's default is not a guess
any more.

**The problem is repetition, not variety.** Eleven deltas; **one** distinct
shape — the same subchannel, the same subject, the same property, eleven times
with a different hash. A channel filter shows or hides all eleven together and
helps nobody. What a reader needs is one line:

```
system · TextInput.setClient · autofill.uniqueIdentifier      11 steps
```

So **the verdict folds identical deltas** — same `subchannel`, `subject` and
`property` — into one row carrying a count, and expands on demand. That is
where the reading gain is, and it is a prerequisite for §3 rather than a
refinement of it: authoring a rule *by pointing* (§3) is far better aimed at a
folded row that already names the shape than at one of eleven identical lines.

It is also the honest reason §7.1 stays open. There were no *real combinations*
to measure — the sample has one shape — so naming four presets from it would be
picking them from an armchair and calling them measured.

### What was built

`foldChannelDeltas` groups on channel, subchannel, subject and property — and
pointedly **not** on the values, since a hash that differs on every occurrence
is the whole case it exists for. It keeps **input order**, not count order:
`ComparedItem.deltas` already builds in channel order, and ranking by count
would put the noisiest shape at the top of every report.

A folded row carries two numbers, because they answer different questions.
`count` is occurrences; `items` is how many compared things wore it. Four text
fields on one screen is one screen's problem; one text field on four screens is
the suite's.

Wired in three places:

- **`ComparisonCompareResult.shapes`** — the whole comparison folded, in channel
  order. On the measurement above it is the entire verdict in one row:
  `count: 11, items: 7`, one row where the findings list has seven.
- **`ComparisonFinding.deltas`** — folded within the finding. The step with four
  text fields went from four identical rows to one carrying `× 4`.
- **`ChannelLines`** — the same fold on screen, with `× N` after the values so
  the eye reaches *what moved* before *how often*.

`count` and `items` are omitted at one, the way `deltasDropped` is omitted at
zero, so an unrepeated delta costs nothing extra on the wire.

## 5. Then, and only then: the self-check

Re-render the **findings** only, head against head. An entry that differs from
itself is nondeterministic; it earns a `changes every run` badge and drops out
of the ranking into its own bucket.

Scoped to findings rather than to the suite, this costs a handful of renders
rather than a second full pass — four previews and two scenarios on the branch
that prompted this, not 267. It is what lets a reviewer trust the list instead
of auditing it, and with §4 it fully answers the "permanently changed" problem:
one says *this is not new*, the other says *this is not real*.

Last because it shares the re-render machinery with phase A's work and is worth
nothing until the ranking it demotes out of exists.

## 6. Ranked, with what each one costs

| | value | cost | depends on |
|---|---|---|---|
| §1 verdict strip | high — the question finally has an answer on screen | low — the ranking exists, only the drawing is new | B |
| §4 new since last | high — kills the skim | low — previous `index.json` is on disk | B |
| §2 channel badges | medium — makes a list scannable | low | B |
| §4a folding | high — measured: 11 lines that are one fact | low — group by three facets | B |
| §3 filter | high for a large suite, low for a small one | medium — chips, rules, the authoring gesture | A's facets, B, §4a |
| §5 self-check | high — it is what trust is made of | medium — a scoped re-render pass | §1 |

§4a moved up on measurement: it is cheaper than the filter, it is what makes
the filter aimable, and on the only real sample we have it turns eleven lines
into one. §1 and §4 remain the two that change how the feature *feels* for the
least work:
a screen that opens saying `6 findings · 1 new` is a different product from
three tabs you have to go looking through.

## 7. Left open

1. **The lens presets — measured once, still open.** `ObserveLens` got its four
   by measuring real combinations. B shipped and the measurement ran (§4a): it
   found **one** delta shape repeated eleven times, which names no combinations
   at all. What would unblock it is a comparison whose findings span channels —
   a branch that moves pixels *and* the tree *and* an event — which this
   repository will produce once the normaliser change in `A2` is behind the
   base rather than in front of it. Until then the filter (§3) is the GUI's
   affordance and there is no preset to pin. Whatever they turn out to be, they
   and the filter must resolve to the same rules.
2. **Whether the findings deserve a grid.** A ranked grid of before/after pairs
   would answer "what did my branch do" in one glance, and the mosaic already
   built for `comment.md` proves the rendering. It does not contradict the
   rejected thumbnail wall — that rejection was about spending the whole area
   on entries that did not move, and findings are few by construction. But it
   is a second view of the same data, and §1 plus §2 may leave it with nothing
   to add. Decide after using them.
3. **Whether a finding can point at the files that explain it.** `decide`
   already computes each entry's closure and folds it into `because` as a
   reason→count map, throwing the per-entry mapping away
   (`app/lib/src/comparison/runner.dart:338`). Retained, a changed preview
   could name the changed files it imports and link into the files tab — which
   nothing else can do, because nothing else holds both the render and the
   import graph. It is the most differentiating idea in this note and the
   least specified; it needs its own measurement of what retaining costs across
   the isolate boundary before it is worth planning.
