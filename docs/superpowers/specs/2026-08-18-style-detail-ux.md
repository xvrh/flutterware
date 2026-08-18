# The style block reads badly — what it should be instead

**Date:** 2026-08-18
**Question:** the `set here` badge and the same property appearing twice are
not clear. What is the better shape, and does a popover help?
**Answer:** the badge is not the problem, the *duplication* is — and the badge
is a symptom of the same missing fact. Both go away once the pane knows the
**inherited base**, which is one O(1) lookup away and registers no dependency.
Fix the pane with subtraction and grouping; put the full merge in a popover,
because that is the one thing that genuinely does not fit.

Follows `2026-08-18-node-detail-enrichment.md`, which built the resolved style.

---

## What is actually wrong, measured

Three text nodes, `flutter test`, current filter applied:

| the text | widget rows | style rows | **said twice** | rows shown | distinct facts |
|---|---|---|---|---|---|
| `Text('…')`, nothing set | 1 | 7 | **0** | 8 | 8 |
| the way this app writes them¹ | 7 | 7 | **4** | 14 | **10** |
| `Text('…', style: TextStyle(fontSize: 30))` | 2 | 7 | **1** | 9 | 8 |

¹ `style: TextStyle(fontSize: 13, fontWeight: w400, color: …, letterSpacing: 0)`
plus `overflow` and `maxLines` — i.e. every label in the studio's own UI.

**The duplication scales with how much the author wrote, so it is worst on the
codebase the pane is used on most.** On a studio label, four of fourteen rows
are the same fact twice — `color`, `size`, `weight`, `letterSpacing` — and each
carries a `set here` badge, so the badge column is four repetitions of the same
word down a 170px-wide pane.

Four separate problems, worth naming apart because they have different fixes:

- **P1 — the echo.** `color 13.0` in `style`, `color 13.0` in `widget`.
- **P2 — the badge says nothing when it fires on everything.** Measured: with
  `style: Theme.of(context).textTheme.titleLarge`, `Text.debugFillProperties`
  reports the *whole* style — size, family, weight, height, letterSpacing, all
  of it — so **every row gets `set here`** and the mark stops distinguishing.
  It is at its least useful exactly where a reader most wants to know what
  came from the theme.
- **P3 — `from` is unreadable where it lives.** 88 characters of nested
  parentheses in a 170px column.
- **P4 — the `widget` block is two things.** `maxLines`, `overflow`, `data` are
  the widget's configuration; `color`, `size` are style echoes.

## The fact the pane is missing

`set here` is answering *"did the author write this key"*. The question a
reader actually has is **"is this value the theme's or this widget's"**, and
those are different questions — a widget can set a key to the value it would
have inherited anyway.

The missing input is the **inherited base**, and it is cheap:

```dart
element.getInheritedWidgetOfExactType<DefaultTextStyle>()?.style
```

Measured: it works from inside the walk, it is documented O(1), and — the part
that matters for an inspector — it **registers no dependency**, so reading the
app does not dirty the element. (`dependOnInheritedWidgetOfExactType` would.)

Two caveats found while probing, both load-bearing for the design:

1. **The default style is not always the base.** `Text.build` merges it only
   when the authored style is null or `inherit: true`. Material's ramp styles
   are `inherit: false`, so `style: theme.textTheme.titleLarge` *replaces*
   rather than merges — measured, the resolved `debugLabel` names `titleLarge`
   and never mentions the ambient `bodyMedium`. A pane that showed the
   `DefaultTextStyle` as "inherited from" there would be lying. The flag is
   readable; the current filter drops `inherit` and would need to keep it as a
   flag rather than a row.
2. **Resolved and authored genuinely diverge.** With the OS bold-text
   accessibility setting on, an authored `weight 300` renders as **700**.
   Measured. So "just delete the duplicate row" is wrong: the echo is
   redundant *when the values agree*, and it is the single most valuable row in
   the pane when they do not.

## Options

### A — Subtract the echo, keep the disagreement (fixes P1, P4) ✅ built

Drop a key from the `widget` block when the style block already shows the same
value. Keep it when it differs, and say so:

```
size      12.0
weight    300 → renders 700        bold text is on
```

Studio label: 14 rows → 10. Nothing lost, because the two rows were the same
string. The divergence case gets *louder* rather than quieter, which is the
right trade — it is rare and it is the answer to "why does this look wrong".

### B — Group instead of badge (fixes P2, P3) ✅ built

Order the style rows by where the value came from, with one rule instead of N
badges, and give the provenance the divider rather than a row:

```
style
  size           13
  weight         400
  color          #15181D
  letterSpacing  0
  ─ inherited · bodyMedium ─────────
  family         .AppleSystemUIFont
  height         1.4x                                    why ⓘ
```

Four badges become one divider. `from`'s 88 characters become the slot name —
`bodyMedium` — which is the only part anybody was reading.

Honest failure mode: with `style: theme.textTheme.titleLarge` everything sits
above the divider and the divider vanishes. That is not the design breaking,
it is the design reporting that the widget really did set everything — which
is what P2 currently obscures.

Also worth taking here: **order the rows the way a person says a style out
loud** — size, weight, colour, then the rest. The framework's declaration
order puts `family` second and `size` third.

### C — Collapse to one line, everything behind a popover ❌ rejected

```
style   13 / 400 · #15181D · .AppleSystemUIFont          ⓘ
```

Densest, and wrong. `HoverCard`'s own doc has the lesson already: *"one target
with two interactions, and the cheap one wins every time."* Putting the common
case (what size is this) behind an interaction to save six rows trades the
frequent question for the rare one. **Not recommended.**

### D — The three-way merge, in a popover (the original ask, fully answered) ✅ built

This is what "what is this style with all the overrides/applies computed"
actually looks like, and it is the one thing that genuinely does not fit in a
170px column:

```
 ┌ bodyMedium · englishLike 2021 · blackRedwoodCity.apply ─────────┐
 │                    inherited      this widget      renders as   │
 │  size              14             13               13           │
 │  weight            400            400  ·same       400          │
 │  color             #1D1B20        #15181D          #15181D      │
 │  letterSpacing     0.3            0                0            │
 │  family            Roboto         —                Roboto       │
 │  height            1.4x           —                1.4x         │
 └──────────────────────────────────────────────────────────────────┘
```

Three columns the pane already has two of, plus the base from the lookup above.
It answers, in one glance: what the theme offered, what this widget changed,
and what won.

And it makes a **new** distinction the badge cannot: `weight 400` over an
inherited `400` is an override that changes nothing — a redundant line in the
source. In a design system that is a lint, not a curiosity.

Anchored on the `why ⓘ` at the end of the inherited divider, so there is one
target with one interaction, per the `HoverCard` rule. `Popover`
(`app/lib/src/ui/popover.dart`) is the primitive — click, not hover: this is a
read the user goes looking for, and `HoverCard`'s enter/exit delays exist for
things you brush past.

## Status: A, B and D are built. C is rejected.

The pane now groups instead of badging and subtracts the echo. On the studio
label measured above it went from **14 rows and 4 badges to 10 rows and one
divider**:

```
style
  size           12.0
  weight         700
  color          #3A3D43
  letterSpacing  0.3
      inherited ──────────────
  family         .AppleSystemUIFont
  height         1.4x
  from           bodyMedium
widget
  data           "Instant — the case this exists for"
```

Two notes from the build:

- **`overflow` and `maxLines` survive the subtraction, and nearly did not.**
  `TextStyle` has an `overflow` too, so it looked like a collision. It is not:
  `TextStyle.debugFillProperties` adds `overflow` to its local list *after*
  that list has already been flushed to the builder, so the field never reaches
  a resolved style at all. The widget's own `overflow` is therefore the only
  one, and the subtraction cannot eat it. Worth knowing rather than
  rediscovering — it is a quirk of the framework, not a property of our rule.
- **The origin is derived by shape, not by vocabulary.** `_originOf` takes the
  first parenthesised group with nothing nested in it — the base of the merge
  chain — and the last name-shaped word in it. No list of Material slot names,
  so an app that labels its own styles reads the same way.

### What D turned out to need, and what it found

Built on `InspectNode.inheritedStyle` (the ambient `DefaultTextStyle`, via
`getInheritedWidgetOfExactType` — O(1), no dependency registered) plus
`styleReplacesInherited`. Anchored on the `from` row, click not hover, opening
upward.

```
((englishLike bodyMedium 2021).merge((blackRedwoodCity bodyMedium).apply)).merge(unknown)
 field           inherited            this widget      renders as
 size            14.0                 12.0             12.0
 weight          400                  700              700
 color           #1A1B21              #3A3D43          #3A3D43
 family          .AppleSystemUIFont   —                .AppleSystemUIFont
 letterSpacing   0.3                  0.3   same       0.3
 height          1.4x                 —                1.4x
```

**The first real node it was pointed at had a redundant override in it.** The
studio's own caption style sets `letterSpacing: 0.3`, which is exactly what
`bodyMedium` was already giving it — the `same` marker, on the studio's own
type ramp, on the first look. That is the column earning its place: neither
of the other two maps can see it.

Three things the build turned up:

- **The 12-property cap was silently eating widget config.** A `Text` handed a
  whole theme slot reports fifteen info-level properties, eleven of them style
  fields — `overflow` and `maxLines` fell off the end, and they are exactly the
  rows the `widget` block exists to show. The cap now counts configuration and
  exempts fields the resolved style already carries.
- **The descriptions wanted memoising, and that is why D is free.** 112
  paragraphs on a test screen resolve to *three* distinct styles.
  `debugFillProperties` plus a `toDescription` per field was being paid per
  text. Keyed on the style (value equality), the resolved pass went 288µs →
  135µs and the new ambient pass costs 84µs — so the two together cost less
  than the resolved one did alone.
- **A font family has no space to break at**, so a narrow card did not
  ellipsize `.AppleSystemUIFont`, it spilled it into the next column. Width
  first, ellipsis as the backstop. Seen in the pane, not predicted.

## Recommendation

**A + B in the pane, D behind one popover. Skip C.**

- A and B are pane-only — they need no new capture, they remove every row and
  badge complained about, and together the studio label goes from 14 rows and
  4 badges to 10 rows and one divider.
- D needs the inherited base on the node (one field, one O(1) lookup per
  paragraph, no dependency registered) plus keeping `inherit` as a flag. That
  is the same shape and roughly the same cost as the resolved style itself.
- B's divider is what anchors D, so they want doing together; A is independent
  and could land first.

## What is still open

- **Does the inherited base belong on every node, or only on request?** The
  resolved style rides the walk because it is 2%. A second style map per
  paragraph is roughly a second 2% and about 60 bytes a node on the wire.
  Probably fine, but it should be measured before it is kept — the same rule
  the properties, the semantics capture and the resolved style were each held
  to.
- **Does `styleLine` in `find`/`at` want the origin?** `13/400 #15181D` says
  nothing about whether it is the theme's. One extra word (`13/400 #15181D
  bodyMedium`) may be worth ~4 tokens; unmeasured.
- **The scenario artifacts and comparison caches** hold trees written before
  any of this. B degrades cleanly (no divider, no popover); D needs the
  popover to say "not captured" rather than "inherited nothing".
