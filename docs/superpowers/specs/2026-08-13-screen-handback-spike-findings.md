# How a screen is handed back — spike findings

2026-08-13. Four spikes against the running flutterware GUI (`app/lib/main_dev.dart`,
macOS, hidden window, the Changes screen of a worktree with 14 changed files).
Everything below is measured on that screen through `ext.flutterware.act`, not
estimated. The spike code was thrown away; the design it argues for is
`2026-08-13-screen-handback-design.md`.

The question: `previews`, `scenarios` and `run` each hand a screen back a
different way, none of them can be asked a *second* question about a moment
already captured, and it is not obvious that pixels-by-default is the right
opening move for an agent.

## S1 — what an observation costs to produce

Guest-side, per piece:

| piece | ms | bytes |
|---|---|---|
| widget tree build (`getRootWidgetSummaryTree` + walk) | 71–134 | — |
| noise filter | 1.1 | — |
| encode, compact spelling | 13.4 | 78 KB (252 nodes) |
| encode, verbose spelling | 2.6 | 221 KB (439 nodes) |
| encode, unfiltered compact | — | 121 KB |
| semantics capture | 4.5–9.7 | 7.0 KB (44 nodes) |
| `visibleTexts` | 11.6 | 684 B (63 strings) |
| PNG @ maxSide 1200 | 234 | 189 KB → ~1440 image tokens |
| PNG @ maxSide 900 | 143 | 133 KB → ~810 |
| PNG @ maxSide 600 | 46 | 76 KB → ~360 |

End to end, `settleMs: 300`, three runs each:

| call | round trip | wire bytes |
|---|---|---|
| texts only | 26 / 31 / 61 ms | 776 B |
| + tree | 113 / 113 / 102 ms | 45 KB |
| + shot @1200 | 345 / 386 / 267 ms | 207 KB |
| tree + shot @1200 | 349 / 311 / 330 ms | 252 KB |
| + shot @600 | 105 / 84 / 110 ms | 83 KB |

**The screenshot is ~70% of the round trip, not the tree.** And the host does not
forward `tree` to the guest at all, so the guest builds and serialises the whole
tree on *every* observe and the host drops it unless asked — confirmed by an
observe that requested no tree and came back reporting `nodes: 255`.

**Holding a `SemanticsHandle` is free.** Six alternating taps, two runs each way:
medians 431 / 443 / 428 / 432 ms with semantics off, 434 / 435 / 437 / 433 ms
with it on. A frame-timing probe over 30 forced frames with the whole element
tree dirtied put build at 82 / 96 / 60 ms off and 81 / 71 ms on — the handle is
inside the noise of a full rebuild.

**Gate: passed.** Archiving the complete capture on every step costs nothing new
for the tree (already built), ~46 ms for a 600px PNG when the reply asked for
none, and nothing for semantics.

## S4 — the actionable projection

**The noise filter destroys exactly the actionability signal.** On this screen:
**32 interactive widgets before it, 3 after** — 29 `IconButton`s, `InkWell`s and
`GestureDetector`s dropped. That is the survivor-scoring working as designed and
against this use: a wrapper is dropped in favour of whichever node carries the
words or the properties, and an `InkWell` carries neither.

Semantics recovers it — 44 nodes, 7.0 KB, with `label`, `actions`, `flags`.
Merging widget identity with semantics actionability by rect:

| projection | items | bytes | tokens |
|---|---|---|---|
| v1 — path ids, source, every text | 95 | 18.0 KB | ~4500 |
| v2 — short handles, roll-up, int boxes, no source | **42** | **2.76 KB** | **~690** |

Same screen, for comparison: picture @1200 ~1440 tokens, texts ~170, tree ~19 500.

v2 reads as a screen:

```json
{"n": 19, "role": "field",  "w": "Filter paths", "box": [8, 154, 304, 23]}
{"n": 20, "role": "button", "w": "All\n15",      "box": [0, 185, 47, 30]}
{"n": 21, "role": "button", "w": "Important\n0", "box": [47, 185, 85, 30]}
{"n": 27, "role": "button", "w": "M\nlog_client.dart\n+19\n-7", "box": [12, 326, 308, 30]}
{"n": 8,  "role": "button", "box": [708, 6, 28, 28], "off": true}
```

Two things there are in neither the texts nor (reliably) the pixels: `role:
field`, and `off: true` on a disabled control.

What it does **not** carry, honestly:

- **6 of 42 items are unlabelled buttons** — targetable only by box. That is
  simultaneously an accessibility finding about this GUI.
- **No selected state.** The filter tabs are `InkWell`s, not `Tab`s, so Flutter
  publishes no `isSelected`; "which tab is active" still needs the colour.
- Flat list. Reading order comes from tree order; there is no grouping.

## S2 — ten real questions, three surfaces

Questions fixed before the answers were looked at. Surfaces: **A** = today
(`observe` → texts + shot @1200, drill down with `tree: true`); **B** = A plus
`find` / `at` / `styles`; **C** = the projection as the default reply, no
picture, plus the same three queries.

| # | question | A | B | C |
|---|---|---|---|---|
| 1 | what opens `log_client.dart`'s diff | 0 (assumed tappable) | 0 | 0 (*says* it is a button) |
| 2 | is Important selected, what is its count | pixels, judgement | find 215 | find 215 |
| 3 | where to type to filter paths | pixels, judgement | find 200 | 0 |
| 4 | is anything disabled | **unanswerable** | **unanswerable** | 0 |
| 5 | the refresh button's hit box | tree | at 501 | 0 |
| 6 | is "Watching" centred on that button | tree | at 501 + find 131 | 0 (+501 for the cause) |
| 7 | folder vs file row height | tree | at 448 + at 469 | 0 |
| 8 | the inactive tab's two greys | tree | styles 185 | styles 185 |
| 9 | the type ramp | tree | (same call) | (same call) |
| 10 | why the two label indents differ | tree | (reuses #7) | at 448 + at 469 |

| | opening | drill-down | total | round trips | answered |
|---|---|---|---|---|---|
| A today | 1 610 | 19 500 | **21 110** | 2 | 9/10 |
| B + find/at/styles | 1 610 | 2 650 | **4 260** | 9 | 9/10 |
| C projection default | 690 | 1 818 | **2 508** | 6 | **10/10** |

Neither A nor B can answer #4: "disabled" is not in the widget tree, it is in
semantics.

Three results worth pulling out:

- **`find` is worth ~150×.** `find "Watching"` → 131 tokens, and it lands the
  whole answer: `Text("Watching")` at `changes_screen.dart:528`, box
  `[679.9, 56, 50.1, 15]`, `color #C4C7CD, size 10.5, weight 600`.
- **`at` must be filtered.** The raw chain under a point is 35 nodes / 1258
  tokens, 20 of them the same root wrapper run that is on every chain on every
  screen. Over the filtered tree, innermost-8: **10 nodes / 501 tokens**, and it
  carries `Row @ changes_screen.dart:402 crossAxisAlignment: start` — the answer.
  *previews' `at` has this same problem today.*
- **Aggregate queries are a category nobody had.** "What is the type ramp" is not
  a list of nodes, it is a table. `find "Text("` answered it in 2451 tokens and
  was still truncated at 30 of 63 hits. A `styles` aggregate answered it in
  **185 tokens**, complete and ranked:

  ```
  12.5/400/#6B7280: 14 · app
  10.5/600/#C4C7CD:  9 · Watching
  22.0/700/#15181D:  1 · Changes
  12.5/400/#0553B1:  1 · All
  10.5/600/#0553B1:  1 · 15
  ```

  Nineteen rows, and it answers #8 and #9 outright.

The one thing this table does not score: **"does it look right"**, which only
pixels answer. It is not in the ten because it is not a question with a
derivable answer — which is exactly why the picture has to stay one call away
rather than gone.

## S3 — what a stale capture does

Four attempts to make a node id from an old read lie:

1. navigate to a different screen → **clean refusal**
2. navigate to the same-shaped screen of another worktree → **clean refusal**
3. collapse the folder containing the node → **clean refusal**
4. expand a folder above a sibling → **id resolved, same widget, box moved from
   y=436 to y=481**

So the path id is largely self-protecting against naming the *wrong widget*:
three of four structural edits invalidated it outright. The failure mode is
subtler than expected and worse for being quiet — **a re-query against a live
app returns current geometry, not the geometry of the capture the id came
from.** An agent that reads a box, acts, then drills into the same id is
comparing two afters.

Conclusion: reading a capture must read the **snapshot on disk**, not re-walk
the live tree, and the reply must say how old the capture is and whether the app
has moved since.

## S5 — the projection on Android and iOS

Brewline (`examples/example/lib/shop_devbar.dart`, the menu screen) on
`emulator-5554` (Android 15) and the iPhone 16 Pro simulator, against the macOS
baseline.

**The tree is the framework's, not the platform's.** Android and iOS returned
byte-for-byte the same shape — 107 nodes full, 71 filtered, 19 semantics nodes,
27 projection items — differing only in geometry. Nothing about the projection
is platform-specific by construction.

**Two platform differences that are real:**

- **iOS already has semantics on** (`wasAlreadyOn: true`); Android does not. The
  handle is needed on Android and free on iOS.
- **Speed.** tree build 14.9 ms (iOS sim) vs 69 ms (Android emu); semantics
  capture 1.4 vs 38.8 ms; PNG @900 14 vs 104 ms. The Android emulator is ~5×
  slower and still comfortably inside budget.

**The failure that mattered: label-driven roll-up produced 0 of 6 labelled
buttons.** Every product card is an `InkWell`, and `InkWell` publishes a
semantics node with `onTap` but does **not** merge its children's labels. So the
projection said "there are five buttons at these boxes" and, separately, "here
is some text" — leaving the agent to infer containment from geometry. The macOS
run only looked fine because that GUI's rows happen to merge.

Fixed by rolling up **by geometry** — a text inside an interactive's box belongs
to it, innermost wins — with the semantics label preferred where an app provides
one. Containment is a property of the layout, which every app has whether or not
it thought about accessibility.

| Brewline menu | items | unlabelled | tokens |
|---|---|---|---|
| roll-up by semantics label | 27 | 6 of 6 controls | 415 |
| roll-up by geometry | **7** | **1** | **179** |

```json
{"n": 1, "role": "button", "w": "☕ · Cappuccino · Espresso, steamed milk, silky foam. · 4.20 €", "box": [20, 100, 371, 84]}
{"n": 5, "role": "button", "w": "🧊 · Cold brew · Steeped cold for sixteen hours. · 3.90 €",     "box": [20, 484, 371, 84]}
{"n": 6, "role": "text",   "w": "The menu",                                                       "box": [16, 39, 99, 26]}
{"n": 7, "role": "button", "box": [351, 28, 48, 48]}
```

179 tokens for that whole screen. Same screen: PNG @900 ~490 tokens, tree ~5100.

The complex screen pays a little for the change — macOS goes 42 items / 690
tokens to 47 / 810 — because geometry keeps a few texts separate that a merged
semantics label had swallowed. Worth it: one app was slightly denser, the other
was wrong.

## S7 (partly) — the tooltip nobody was reading

An unlabelled `IconButton` usually is not: it carries a `tooltip`, which is in
the widget's own diagnostics and which the projection ignored. Adding it as the
last fallback recovered **2 of 8** anonymous controls on the macOS screen
(`"Read this checkout again"`).

The remaining 6 have no label, no tooltip and no text — no accessible name at
all. That is a finding about the flutterware GUI rather than a limit of the
projection, and it argues for the projection *reporting* anonymous controls
rather than only tolerating them.

## S8 — the light default needs regions, and they cost ~19%

The flat projection lists controls; it does not describe a layout. The question
was whether that gap is worth tokens.

**A region is a branch point, and it falls out of the tree for free.** Prune the
widget tree to the projection's items, collapse every single-child chain, and
what is left is the screen's shape: a node survives exactly when two or more of
its subtrees hold something. No heuristics, no naming — the label is the
widget's type and the `file:line` that built it.

Three spellings measured on both screens:

| | macOS, 47 items | Brewline, 7 items |
|---|---|---|
| A — flat list | 899 tok | 193 tok |
| B — flat + a `regions` summary | 1213 (+35%) | — |
| C — nested, every branch point | 1144 (+27%) | 245 (+27%) |
| **C — nested, thinned** | **1070 (+19%)** | **228 (+18%)** |

B loses to C on both size and legibility: the summary repeats item numbers that
nesting expresses by position. C is the answer.

Thinning is `minItems: 3` — a region holding one or two things is a grouping
nobody needed, so its children splice into its parent. **With one exemption,
found by breaking it:** at `minItems: 3` the file list's own
`ListView @ changes_screen.dart:735` vanished, because only two rows were
visible. That is the single most useful region on the screen — it is the answer
to "what scrolls", which is a question every agent has and which `scrollTo`
needs. Scrollables are never thinned. With the exemption, 14 regions survive on
the macOS screen and all three `ListView`s are among them.

What 1070 tokens buys, in outline:

```
Column @ shell_view.dart:185 [0, 0, 800, 600]
  Row @ shell_view.dart:266 [78, 0, 722, 40]          ← top bar, 9 controls
  Row @ shell_view.dart:199 [0, 40, 800, 536]
    ListView @ shell_view.dart:1267 [0, 40, 231, 536] ← the nav rail, 13 items
    Column @ comparison_tabs.dart:247 [232, 40, 568, 536]
      Row @ comparison_tabs.dart:333 …                ← the tab band
      Column @ changes_screen.dart:305 …
        Column @ changes_screen.dart:399 …            ← the header block
        Row @ changes_screen.dart:323 …               ← master / detail
          Column @ changes_screen.dart:638 …
            ListView @ changes_screen.dart:735 …      ← the file list, scrolls
```

Which pane is which, how wide each is, what scrolls, and which file builds it.
On Brewline the same rule turns seven flat rows into "five cards in a
`ListView @ shop_screens.dart:46`" for 35 tokens — the menu scrolls, which the
flat list never said.

**Verdict: build it, nested, thinned at 3, scrollables exempt.** ~19% is the
price of the default being a description instead of a list.

## S6 — selected state: Flutter publishes it, the join was wrong

A throwaway screen with every Material idiom for "this one is current" —
`NavigationRail`, `TabBar`, `ListTile(selected:)`, `CheckboxListTile`,
`SwitchListTile`, `RadioListTile`, `FilterChip`, `SegmentedButton`,
`NavigationBar`, plus a hand-rolled `InkWell` pair styled only by colour, which
is what flutterware's own tabs are.

**First answer, by rect matching: 4 of 15 controls report nothing, `Tab` among
them. That answer was wrong.** The raw semantics tree has
`Tab B → flags: [isSelected, hasSelectedState]` sitting right there. The `Tab`
*widget's* box is `[241, 0, 38, 46]` — just its label — while the semantics node
it contributes to is `[80, 0, 360, 48]`, **9.5× the area**. Matching semantics to
widgets by rectangle fails in both directions and by a wide margin: a
`Checkbox`'s flags are on a node *smaller* than the `CheckboxListTile` that owns
them, a `Tab`'s on one much *larger* than the `Tab`.

**The right join is the render tree, and it is exact.** For each widget take
`element.renderObject`, walk up render parents until one has a
`debugSemantics`, and read the flags off it. Measured: **60 controls, 60
matched, 0 missed.**

| idiom | reports selection |
|---|---|
| `NavigationRail` destination | ✓ |
| `TabBar` / `Tab` | ✓ |
| `ListTile(selected:)` | ✓ |
| `CheckboxListTile` | ✓ `isChecked` |
| `SwitchListTile` | ✓ `isToggled` |
| `RadioListTile` | ✓ `isChecked` + `isSelected` |
| `FilterChip` | ✓ |
| `NavigationBar` destination | ✓ |
| **`SegmentedButton`** | **✗ — no flags at all** |
| **hand-rolled `InkWell`** | **✗ — nothing declares it** |

Eight of ten. `SegmentedButton` renders its segments as plain `TextButton`s and
publishes no selection — arguably a Flutter bug, and not something to work
around here.

**The tri-state falls out mechanically**, which is what makes it safe to emit:

- `isSelected` / `isChecked` / `isToggled` present → **on**
- only `hasSelectedState` / `hasCheckedState` / `hasToggledState` → **off**
- neither → **unknown**, and the projection says nothing

`hasSelectedState` is the discriminator. Without it there is no way to tell "not
selected" from "not selectable", and the difference is the whole value.

**Two further findings the join produced for free:**

- **It gets labels exactly**, including Flutter's own positional hint —
  `"Tab A\nTab 1 of 2"`. Better than the geometry roll-up S5 arrived at, so the
  word order gains a step in front: render-object semantics label, *then*
  geometry roll-up for apps that labelled nothing.
- **The semantics node is a better identity than the rect.** The join returned
  60 rows for 15 controls, because `ListTile > InkWell > GestureDetector` all
  resolve to the same node. Deduplicating on node identity is exact where
  deduplicating on rectangle is a guess.

**Verdict: emit `sel: true|false`, omit when unknown, never infer from colour.**
For the two idioms that publish nothing, the default stays silent and `styles`
already answers it — it showed `All`/`15` sharing `#0553B1` against `Important`
at `#9AA1AC`. That split is the right one: the default never guesses, the
aggregate shows the difference, the agent draws the conclusion.

## Two findings that were not spikes

**The journal archives the answer, not the screen.** Measured in
`~/.flutterware/run/journal/app-d07a74ed3a5f-70360/`: 17 steps, 17 texts files,
16 trees (only because a session was testing with `tree: true` — a normal
session writes none) and **5 PNGs**. The trees that are there are the *scoped*
ones, 4.8 KB and 3.8 KB where the call asked for a depth cut.
`run_core.dart:2890` argues this deliberately, and the principle is right
applied to the wrong file: the testimony is `journal.jsonl`, the artifact beside
it should be the archive.

**Targeting by words is ambiguous where targeting by item is not.** Live: `tap
"Changes"` was refused — *2 widgets match* — on a screen whose projection
contains exactly one `Changes` button, as item 12.
