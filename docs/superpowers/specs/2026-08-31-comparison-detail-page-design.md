# The comparison detail page — leading with what changed

`2026-08-30-comparison-ui-pass-design.md` designed a summary strip, shipped it,
and never once opened the page underneath it. This note is the correction, and
it starts with why that happened, because the same mistake is cheap to repeat.

## What the last pass got wrong

Four things, and only the last is about taste.

1. **It researched components, not the screen's job.** The inventory of
   `FwFilterBar`, `CountBadge`, `StateChip` and the channel chip was good work
   and answered *what can I build this from*. Nobody asked *what is this screen
   for now that the model knows more than pixels*.
2. **It evaluated five variants in isolation**, then put the winner in context
   only after being asked where it went — and only in the list layout. The
   pushed step page was never drawn at all.
3. **It measured the wrong thing.** Overflow at 430px got measured. The
   fraction of the screen carrying the finding did not.
4. **It optimised a header while the body of the screen was showing the wrong
   thing.** Three passes were spent on one summary line.

## The root cause: a layout from the pixels-only era

`2026-08-11-worktree-comparison-design.md` §5 closes with:

> **Visual stays first.** The other channels are available, not promoted.

That was right when it was written — `events` was a row in a table with a tick
beside it. The detail page encodes it structurally: a five-mode stage of two
frames takes the top, and everything else is a footnote under it.

Measured on this branch's own scenario half: **11 of 11 findings are invisible
to a screenshot.** Pixels fired on zero of them, tree on zero, texts on zero.
On the step page for one of those findings:

| | height | carries |
|---|---|---|
| the verdict header (which belongs to the list, not this page) | ~75px | nothing about this step |
| the mode switcher | ~30px | five ways to look at two identical frames |
| the stage | ~400px | two identical pictures |
| `ON THE WAY HERE` and its one line | ~40px | **the entire finding** |

Roughly **7% of the page carries the finding, and 60% carries two pictures the
strip above has just finished saying are identical.**

So §5's decision is reopened, with evidence, and narrowed rather than reversed:
**visual stays first when the visuals changed.** The page should lead with the
channel that has something to say.

## Three defects with one shape

1. **The verdict header stays visible on the pushed step page.** A scope bug:
   the verdict is about the half, the pushed page is about one step, and it
   was mounted above the whole tab body rather than above the list.
2. **The stage is the hero even when the two frames are identical**, and
   nothing on the page says they are — so a reader stares at two pictures
   hunting for a difference the tool already knows is not there.
3. **The flow canvas wastes most of its width.** Cause measured, not guessed:
   `_nodeWidth` is a constant 132px sized for a desktop-shaped frame, and a
   portrait phone capture fitted to `_thumbHeight` is about **88px** wide. That
   leaves ~44px dead inside each node, and `cellSize` adds 40 and `cellPadding`
   another 40 on top — so two 88px pictures sit about **128px apart**. The gap
   is wider than the subject.

What they share: the layout assumes the picture is the subject. Where it is
not, the page has no other plan.

## The method, this time

The last pass's failure was procedural, so the fix is procedural.

1. **Enumerate the states before drawing anything.** The detail page is not one
   screen, it is one per shape of finding. They were never listed, which is how
   *events-only* — the commonest state on the branch in front of us — reached
   production having never been designed.
2. **Draw each state with real data**, in the layout it ships in, at the width
   it ships at. Not a floating widget.
3. **Measure area against information** for each. The table above took two
   minutes and is the single most damning fact in this note.
4. **Include the nested pages.** A pushed page is a screen.

### The states

| # | what changed | today | designed? |
|---|---|---|---|
| 1 | pixels (± everything else) | stage is the hero | ✅ correct |
| 2 | tree only — a key, a constraint, a size with no repaint | stage of identical frames | ❌ |
| 3 | texts only | stage of identical frames | ❌ |
| 4 | events only | stage of identical frames | ❌ **the measured case** |
| 5 | nothing — a `same` row opened deliberately | stage of identical frames | partly |
| 6 | broke / failed — one side did not render | ? | to check |
| 7 | added / removed — exists on one side | ? | to check |

### ✅ Drawn — `tool/catalog/demos/comparison_states.dart`

All seven against the real `StepPage` (extracted from `scenarios_tab.dart` so
it could be an entry) over real decoded frames, at 900px. What they show:

| # | state | verdict |
|---|---|---|
| 1 | pixels moved | **right.** The stage is the subject and the boxes point at it. Nothing to change. |
| 2 | tree only | **worst of the seven.** See below. |
| 3 | texts only | two identical frames over `- Save / + Pay`. The finding is two words at the bottom of a 700px page. |
| 4 | events only | 415px of identical pictures; the finding is a **`POST /session  detail  200 → 500`** in grey, in the same weight as the autofill noise above it. A 500 is a regression, and it is drawn as a footnote to a picture that did not change. |
| 5 | nothing changed | 700px of two identical frames and no words at all. Honest, but it is the whole page for *there is nothing here*. |
| 6 | broke on head | **better than expected.** `base only`, one frame, the note in red, mode pills correctly disabled. The pills should not be *drawn* when there is one frame, but nothing here is wrong. |
| 7 | only on head | same shape as 6 and equally sound. |

So the damage is concentrated in **2, 3, 4 and 5** — every state where the
pixels are identical. 1, 6 and 7 are fine and should be left alone.

### Two bugs the drawing found, neither of them layout

**A key change reads as two identical rows.** State 2 renders

```
TREE
+ Column › Text("This code is not valid.")
- Column › Text("This code is not valid.")
```

which is, verbatim, the consumer report that started this whole thread. The
cause was diagnosed on day one and never fixed: `TreeDiff._label` spells a
widget's key back **only when the node has no description**, and a `Text`
always has one — while its own docstring three lines above says the key is
spelled back full stop. One line, still outstanding.

**A key change on the root node produces no delta at all.** Measured
separately: `TreeDiff.of` over two `Text`s differing only in a key gives
**0 deltas** at the root and 2 on a child. `_walk` compares `description`,
`layout` and children, and never `widgetKey` — the key only ever influences
`_signature`, which is about *aligning children*. A single-node entry whose
key changed therefore reports `same`. Narrow, but wrong.

## The shape being proposed

**The page has a hero and a rest.** The hero is whatever changed; everything
else collapses to one line that can be opened.

- **Pixels changed** → the stage is the hero, exactly as today. Nothing about
  state 1 needs to move.
- **Pixels identical** → the stage collapses to a single line saying so, and
  the channel that fired takes the space with its deltas drawn large.

**The collapsed stage still shows one frame, small.** Not zero: *what does this
step look like* is a fair question even when the answer is *the same as
before*, and a reader who has just arrived from a list needs to know where they
are. One frame answers that; two answer nothing that the word `identical` does
not.

Three smaller things fall out and should ride along:

- **The verdict moves down**, onto the list view rather than the tab, so a
  pushed page does not inherit it.
- **`ChannelLines` trims a property the way the verdict does.** It still draws
  `data.arguments[1].autofill.uniqueIdentifier` where the strip above it says
  `autofill.uniqueIdentifier`. One rule, one place.
- **The flow node sizes to its frame's aspect** instead of to a constant, and
  the cell padding is measured against the result rather than added blind.

## What this note does not decide

Where the deltas go once they are the hero. `ChannelLines` was written as a
footnote — a flat list of one-line strings under a header — and a footnote
promoted to a headline is usually the wrong widget rather than the right widget
in the wrong place. That is step 2's question, and it wants the states drawn
before it is answered.
