# Handing a screen back: one capture, one query grammar

> **Built 2026-08-13**: M1 (the complete capture and its address), M2/M3 on all
> three surfaces (`screen` as the default reply, `find`, `at`, `styles`), M4
> (`item: N`, plus the `{"at": …}` target it rests on), the `lens`, and
> `scenarios read` — the call that reads a past capture. What is left is
> narrower than a milestone: previews still cannot be asked about a *past*
> render, because it keeps no archive to ask. What each build changed is
> recorded in the *What … corrected* sections at the end.

2026-08-13. Gated on `2026-08-13-screen-handback-spike-findings.md` — every
number quoted below is measured there, on the flutterware GUI's own Changes
screen.

## The thesis, in one paragraph

An observation should produce **one complete capture on disk** and hand back **a
screen an agent can act on** — a short list of the things that carry words or
respond to touch, with their boxes and their state. Pixels and structure both
move behind a **query on that capture**, reachable in one call, never gone.
Today all three surfaces do the opposite: they decide up front what to send,
send the expensive thing (a picture) by default, send the useful thing (the
tree) only if asked, and archive whichever subset the call happened to want.

## What changes, and why the measurement says so

| | today | proposed | why |
|---|---|---|---|
| default reply | picture + texts, ~1610 tok | actionable screen, ~690 tok | answers 10/10 of the spike's questions vs 5/10, at 43% of the tokens |
| picture | on by default, 234 ms, ~1440 tok | on request; always archived | 70% of the round trip; irreplaceable for "does it look right" and useless for everything else |
| tree | opt-in, whole-screen, ~19 500 tok | opt-in via `find`/`at`/`styles`/`node` | `find` is 131 tok for the same answer; `styles` is 185 tok for the whole type system |
| archive | whatever the call asked for | complete, always | the tree is already built every step; a 600px PNG is 46 ms |
| drill-down target | the live app | the snapshot | a live re-query returns *current* geometry under an *old* id (S3 #4) |

## M1 — the capture is complete, and it has a name

The unit is a **capture**: one settled moment, four legs, on disk. **Built.**

```
~/.flutterware/run/journal/<runKey>/<stamp>.{png,tree.json,semantics.json,texts.json}
~/.flutterware/run/journal/<runKey>/<stamp>.capture.json     ← the manifest
```

- The guest sends the **unfiltered** tree; the host filters for the reply and
  archives the unfiltered one. Filtering already lives host-side in
  `InspectTree.filtered`, so this is a move, not a new implementation. Wire cost
  121 KB vs 78 KB over a local socket — not the model's context.
- The PNG is archived **whatever the reply asks for** — but not at full
  resolution, which the measurement did not support. A picture is the one leg
  that is not already paid for: 234 ms at 1200, 46 ms at 600. So a step that
  returns a picture takes it at the reply's cap (900), and a step that declines
  one takes it at **600 for the archive alone**. One capture per step either
  way, and the manifest records which resolution it holds.

  The default loop got *faster*, not slower: its picture cost went from 234 ms
  (1200, returned) to 46 ms (600, archived), while gaining a complete archive.
- Semantics rides along (7 KB, free).
- Every reply carries `capture: fw:///worktrees/<wt>/flutterware.run/<runKey>/<stamp>`
  — the project's existing identifier, which artifacts already carry and the GUI
  can already open.

**On the testimony argument** (`run_core.dart:2890`: "a journal claiming
otherwise would be a record of something that did not happen"). The principle
stands; it is being enforced on the wrong file. The journal entry records what
the step *reported* — verb, target, scoping, what came back. The artifacts
beside it are the archive. One file cannot be both, and today the archive loses:
17 steps produced 5 PNGs.

Scenarios already writes this shape and has done for two milestones. Run and
previews adopt it.

## M2 — the screen is the default reply

`observe` and every `act` reply return `screen`. `texts` stays beside it for
now — it is ~170 tokens, and the refusal messages are written from it.

```json
{"n": 19, "role": "field",  "w": "Filter paths", "box": [8, 154, 304, 23]}
{"n": 20, "role": "button", "w": "All\n15",      "box": [0, 185, 47, 30]}
{"n": 8,  "role": "button", "box": [708, 6, 28, 28], "off": true}
```

Built by merging the **full** widget tree (identity, type, source) with the
**semantics** tree (label, actions, flags) — the full tree, because the noise
filter drops 29 of 32 interactive widgets and the survivors are not the ones you
tap.

**The merge is a render-tree walk, not a rectangle comparison** (S6). Take
`element.renderObject`, walk up render parents to the first with a
`debugSemantics`, read it there: 60 controls, 60 matched, 0 missed. Rect
matching was tried first and is wrong in both directions — a `Checkbox`'s flags
sit on a node smaller than the `CheckboxListTile` that owns them, a `Tab`'s on
one **9.5× larger** than the `Tab` widget. It reported "Flutter does not publish
tab selection", which is false. The semantics node is also the right identity
for deduplication: `ListTile > InkWell > GestureDetector` are one control and
three rectangles.

**Selection is a tri-state and it is emitted, never inferred.**
`isSelected`/`isChecked`/`isToggled` → `sel: true`; only `has…State` → `sel:
false`; neither → say nothing. `hasSelectedState` is the discriminator, and
without it "not selected" and "not selectable" are indistinguishable. Eight of
the ten Material idioms publish it; `SegmentedButton` and hand-rolled `InkWell`
tabs do not, and for those the default stays quiet and `styles` shows the
colour difference for the agent to read.

**Words are found in this order, and the order is load-bearing** (S5, S6): the
semantics label reached through the render-object join — which gets Flutter's
own positional hints too, `"Tab A\nTab 1 of 2"`; the widget's own text; the
texts geometrically **inside** the control, innermost owner wins; the `tooltip`.
Anything label-first is wrong — on
Brewline it left all six buttons anonymous, because `InkWell` publishes `onTap`
without merging its children's labels. Containment is a property of the layout,
which every app has; a good semantics label is a property of an app that thought
about accessibility, which not every app is.

A control that comes out of all four with no words is **reported as anonymous**
rather than quietly listed — 6 of 47 on the flutterware GUI's own screen, which
is an accessibility bug the projection is well placed to surface.

- The run guest holds a `SemanticsHandle` from launch. **Built.** Measured free;
  report `semantics: unavailable` where a platform refuses rather than silently
  degrading the projection to widget types alone.
- `screenshot` defaults to **false** on the drive path, and default `maxSide`
  drops 1200 → 900 when a picture *is* asked for. **Built, with M1** — the trade
  only works because the picture is archived either way. The picture attaches
  itself without being asked for when the step was refused or the app threw,
  because looking is the useful thing to do then.
- `layer: native` keeps its picture-by-default, and the difference is the point
  of that layer: there is no `screen` projection of a platform accessibility
  tree, and what brings anyone there is something Flutter cannot see. The
  picture is the answer, not a second opinion on it.

**The risk, named.** An agent that never asks for the picture will miss what
only pixels show. Three mitigations, in order of how much they are worth: the
reply says the capture holds one; a framework error, an overflow, or a failed
target attaches it automatically; and `role` + `box` + `off` already cover the
cases where an agent used to squint at a screenshot to guess at state.

### The screen is nested, not a list (S8)

A flat run of 47 rows lists controls; it does not describe a layout. So the
items are **nested under the layout's branch points**, which fall out of the
tree for free: prune the widget tree to the items, collapse every single-child
chain, and a node survives exactly when two or more of its subtrees hold
something. The label is the widget's type and the `file:line` that built it —
no naming heuristics, and it doubles as the jump target.

```
Column @ shell_view.dart:185 [0, 0, 800, 600]
  Row @ shell_view.dart:266 [78, 0, 722, 40]           ← top bar
  Row @ shell_view.dart:199 [0, 40, 800, 536]
    ListView @ shell_view.dart:1267 [0, 40, 231, 536]  ← nav rail, 13 items
    Column @ comparison_tabs.dart:247 …
      Row @ changes_screen.dart:323 …                  ← master / detail
        ListView @ changes_screen.dart:735 …           ← the file list, scrolls
```

Measured cost **+19%** over the flat list (899 → 1070 tokens on that screen,
193 → 228 on Brewline). Which pane is which, how wide, what scrolls, and which
file builds it — for a fifth.

Two rules, both found by breaking them:

- **Thin at three.** A region holding one or two things is a grouping nobody
  needed; splice its children into its parent. Unthinned costs +27% for regions
  that say nothing.
- **Never thin a scrollable.** At `minItems: 3` the file list's own `ListView`
  vanished because only two rows were visible — the single most useful region on
  the screen, and the answer to "what scrolls", which `scrollTo` needs.

## M3 — one query grammar, three surfaces

One action, `read`, taking a capture (or `live: true`) and:

| | what it does | measured |
|---|---|---|
| `find` | nodes whose type or on-screen words match | 131–215 tok |
| `at` | the chain under a point, **filtered**, innermost-8, `outerElided` | 501 tok (1258 unfiltered) |
| `styles` | distinct size/weight/colour, ranked, with a sample | 185 tok |
| `node` + `depth` + `noise` | a subtree | 3.8–13.9 KB |
| `pixels` | `full` / `node` (cropped) / `none`, `maxSide`, `annotate` | 360–1440 tok |

Previews already has `find`, `at`, `node`, `depth`, `annotate` and crop-to-node;
run has none of them; scenarios has no reader at all. So this is mostly
*porting*, not inventing:

- `_matching` moves from `previews_core.dart:1878` into `node.dart` beside
  `filtered()`.
- `at` gains the noise filter and the innermost cap — a fix previews needs too.
- `styles` is new, and is the highest value-per-line item in the whole plan.
- `ext.flutterware.hitTest` is already registered in the shared guest kit; the
  drive path just never exposed it.

**Scenarios first.** It has the complete archive already and no way to read it:
an agent debugging a red scenario gets one inlined frame and a pile of paths.
That is the cheapest large win here.

### What "unified" means here, and where it stops

The three surfaces have genuinely different subjects: run has a live app,
previews has an entry it can re-render on demand, scenarios has a finished run
of N steps. They cannot share a *selector* — "which app / which entry / which
step" is three different questions.

What they share is everything after it. **Each surface's job is to produce a
capture address; from there the grammar is identical** — same verbs, same
parameter names, same reply shape, same lens vocabulary, one implementation over
`InspectTree`. A `find` against a scenario step and a `find` against a live app
differ in which file was opened, and in nothing an agent has to learn twice.

That is the whole of the unification, and it is worth stating because the
temptation is to unify the selector too and end up with a parameter that means
something different on each surface.

### The reply teaches the drill-down

The same rule the refusals already follow. A default reply carries its capture
address **and one line naming what can be asked of it** — `find`, `at`,
`styles`, `node`, `pixels` — because a schema an agent read once at connection
time is not where it will look on step forty. This is roughly ~20 tokens and it
is the difference between a drill-down that exists and one that gets used.

## M4 — act by handle. **Built.**

`tap {item: 20}` — the numbered thing from the last reply's screen, instead of
a target.

Two things it fixes, and the second turned out to be the bigger one:

- **Ambiguity.** `tap "Changes"` was refused live — *2 widgets match* — on a
  screen whose projection contains exactly one `Changes` button. A number
  cannot be ambiguous.
- **Controls with no words.** Six or seven of the forty-odd items on a real
  screen carry no label, no text and no tooltip. Before this there was **no
  target that could name one**: not text, not key, not tooltip, not label.
  Verified live by tapping an unlabelled icon button in the flutterware GUI's
  own top bar.

**It becomes a point, not a special case.** The host resolves the item against
the run's last capture and rewrites the target as `{"at": {"x": …, "y": …}}` —
a new form on the drive layer, closing an asymmetry the docs already described
(`layer: native` has had `{"at": …}` all along). `Target.at` resolves through
`finderForTarget` like every other target, so a covered, offscreen or vanished
item is refused by the existing ladder rather than tapped blind. The point runs
the framework's own hit test, not a rectangle comparison, so transforms, clips
and `IgnorePointer` are all respected.

**Resolved from disk, not from memory.** Every surface opens a fresh session
per call, so "the screen you last saw" cannot live in a field. It is read from
the journal, and the screen is recomputed from the archived tree rather than
stored beside it — `Screen.of` is deterministic, and one fewer file is one
fewer thing that can disagree with the tree next to it. It also means an item
number taken from an MCP reply works from `fw`.

**Staleness is answered by renumbering, not by a counter.** The plan called for
`capturedStepsAgo` and a refusal when the app had moved. In the building it
turned out the honest thing is simpler: numbers are per observation, the
lookup always uses the *latest* capture, and a screen that changed has already
renumbered. `no item 9 on the screen this run last reported — it had 2. Observe
again; the numbers are per observation and a screen that changed renumbers.`
A stale number is either out of range (refused with the count) or lands on
whatever now occupies that position — and the reply and the journal both say
`item 9 "…"` with the words it hit, so the next observation shows it. The
counter would have been a second source of truth for something the numbering
already carries.

## M5 — the MCP surface (and yes, it is partly a documentation problem)

- `flutterware_act`'s description is ~1900 characters and the drill-down is
  buried in the middle of it. Restructure: the description says what one reply
  contains and names the follow-ups; the detail moves to the per-parameter docs
  where a model reads it when it needs it.
- **Do not build the drill-down on MCP resources.** A resource is read whole by
  URI and has no query verb, so every combination of (node, depth, find, crop)
  would need its own URI; and whether the *agent* can read a resource at all
  varies by client, where tools do not. Optionally emit a `resource_link` for
  the archived PNG — that one is a fetch, not a query.
- Keep returning the archive **path**. A filesystem-capable client skips the
  round trip for ~60 tokens, which is also the reason the on-disk capture has to
  be complete and self-describing.

## Order, and what each milestone is worth on its own

1. **M3 `styles` + `find` on run** — days, no format change, 150× on targeted
   questions. Do this first even if nothing else ships.
2. **M1 complete capture** — the enabling change; nothing else is possible
   without it, and it costs one guest→host wire change.
3. **M2 screen-by-default** — the visible one, and the one to argue about.
4. **M3 the rest, scenarios first.**
5. **M4 act by handle.**
6. **M5 docs.**

## Telling the agent what the defaults are, and letting it change them

Two halves, and only one of them is a feature.

**Saying so is free, and mostly missing today.** Every reply states the lens it
was produced under and what the alternatives cost. Ten tokens, and it removes
the class of failure where an agent does not know a picture was available.

**Changing it ahead of time is a `lens`** — a named preset, not eight booleans.
**Built**, on run; measured live on the Changes screen:

| lens | contains | measured |
|---|---|---|
| `act` (default) | screen, logs, errors | ~1700 tok, 600×450 archived |
| `look` | + the picture @900 | + ~810 image tokens |
| `design` | + every text style | ~2230 tok |
| `raw` | + the whole tree | **~20 980 tok** |

`{lens: design}` on any call for that call, or `run lens {lens: design}` to pin
it for the run (`none` clears it).
**Part of the shared grammar, not a run feature** — the same four words mean the
same four things on a preview and on a scenario step, which is most of what
makes the three surfaces feel like one tool. Scenarios' existing `steps:
failing|all|none` is the same idea under another name and folds into this
vocabulary rather than sitting beside it.

Pinned state lives where the subject lives: the run dir for a run, the session
for a preview, the run's output directory for a scenario. Never in the MCP
server — a preference held in one client's connection is invisible to `fw` and
to the GUI, and this project has no privileged renderer.

The cost is hidden state: a second agent, or the human, gets a reply shaped by
something they did not set. Two rules make that survivable, and both are the
house style already — **every reply names the lens in force**, and setting one
returns what it changed from. A preset that cannot be seen in the reply that it
shaped should not exist.

Named presets rather than knobs because the knobs are the thing an agent will
not read: eight booleans in a tool schema is eight decisions per call, and the
measured answer is that there are about four sensible combinations.

## Nothing is open

Every unknown this design was gated on has been measured.

- **S5** — the projection is platform-independent; Android and iOS returned
  identical trees, and the roll-up rule changed because of what Brewline showed.
- **S6** — Flutter publishes selection for 8 of 10 Material idioms. The rect
  join was the bug; the render-object join is exact, 60 of 60.
- **S7** — the tooltip closes a quarter of the anonymous controls; the rest have
  no accessible name and should be reported as such.
- **S8** — nest under the layout's branch points, thinned at three, scrollables
  exempt. +19%.

Three of the four changed the design rather than confirming it.

## What the build corrected

Four things the spikes had right in isolation and wrong in composition. All
four were found by running it against the real GUI, none by a test.

**1 — the label walk and the selection walk are different walks.** S6 climbed
render parents to the first `debugSemantics` and matched 60 of 60, so the build
used one walk for both fields. Wrong for labels: semantics *merges*, so a
header inside `MergeSemantics` owns one node whose label is every string under
it and whose descendants own nothing. Climbing from a `Text` in that header
returned the whole header — eight different texts on one screen all reporting
`"Changes / … / Watching / 14 files / +583 / …"`.

A label describes the thing it is on, so it is read **off the render object
itself**. Selection still climbs, because a selection state genuinely belongs to
the control above — a `Tab`'s flags live on the tab's semantics node, not on the
`Tab` widget's 38pt label box.

**2 — and a third walk, downward, for one case.** A `TextField`'s hint is built
by the framework's internals, so it is in no summary tree and no roll-up can
reach it: `find "Filter"` matched nothing on a screen with a "Filter paths"
field on it. The `EditableText` inside does publish it. So the label also
accepts **the one semantics node in the subtree, when there is exactly one** —
one node is the widget describing itself through a child; two or more is a
container, and the roll-up is the honest answer there. Bounded at the second
node found and six render objects down, because it runs per node of every read.

**3 — geometry needs ancestry.** S5 concluded "roll up by geometry" because
label-first left the Brewline cards anonymous. True, and not sufficient: a row
whose box overflows its viewport reaches down over whatever is painted below,
and live, one file row swallowed the address bar. A text is a control's words
only when it is **inside its box *and* under it in the tree** — the ids are the
paths, so the second test is a prefix comparison. Neither half alone is right:
ancestry alone loses the cards, geometry alone eats the neighbours.

**4 — a node out of the middle of a tree carries its subtree.** `find
"Watching"` matched a container near the root and came back as **36,512
tokens** — a hundred times the tree it exists to replace. `find` and `at` emit
flat nodes: no children, a child *count*, and the source spelled relative to
the worktree. 313 tokens for the same query afterwards.

One more, smaller: an item that contained another item swallowed it, leaving a
hole in the numbering and hiding a control the agent could see in the
screenshot and not in the reply. Items nest.

### Measured, live, on the Changes screen

| | |
|---|---|
| the screen, default | 42 items, **~1080 tokens**, 142–213 ms |
| its widget tree | 255 nodes, ~19 500 tokens |
| `find "Watching"` | ~313 tokens |
| `at "756,76"` | ~781 tokens, reaching `Row @ changes_screen.dart:402` and its flex |
| `styles` | ~553 tokens, 19 rows |

## What M1 corrected

**Full resolution was the wrong archive.** The plan said "archived at full
resolution even when the reply asks for no picture", written before the picture
was the measured bottleneck. It is: 234 ms at 1200 against 46 ms at 600, and
~70% of a round trip. One capture per step, at one cap — the reply's when a
picture is wanted, 600 when it is not — and the manifest says which. Two
encodes would have been the obvious way to have both, and would have paid the
expensive one on the common path.

**The archive and the testimony are two files, and now say so.** The artifacts
hold the whole screen; `JournalEntry.reported` holds what the step handed back
(`["screen"]`, `["screen","tree","screenshot"]`). That is the split the old
comment at `run_core.dart:2890` was reaching for with one file, and the reason
it lost: 17 steps had left 5 screenshots.

**A failed step shows its picture without being asked.** Flipping `screenshot`
to false is right for the loop and wrong for the moment something breaks —
"look at it yourself" is the one useful thing to say to an agent whose target
was refused or whose app threw. It is archived either way, so this decides what
enters a context window, not what exists.

**Not every leg was speculative.** The semantics tree was the one leg with no
consumer yet, and it stays: a scenario step has kept it for two milestones, so
archiving it makes a run step and a scenario step the same four things — which
is the unification the rest of this plan is for, arriving for 7 KB.

### Measured, live

| | |
|---|---|
| default step | ~24–130 ms, no picture returned, 600×450 archived, `reported: ["screen"]` |
| `screenshot: true` | ~133 ms, 900×675 archived and returned |
| every step leaves | `.png`, `.tree.json` (**439 nodes**, unfiltered), `.semantics.json`, `.texts.json`, `.capture.json` |
| the address | `fw:///worktrees/<wt>/flutterware.run/<run>/steps/<stamp>` |

The archived tree is the whole one — 439 nodes where the reply's filtered tree
is 255 — which is what makes a second question about a past step answerable at
all.

## Should the artifact directory be exposed?

Asked during the build, and the answer is that it already is — one level up, in
a better form than a directory.

**The journal is the index.** Every reply carries `journal`, the absolute path
of a JSON-lines file with one object per step, each holding that step's
`capture` address and the absolute paths of its picture, tree, semantics and
texts. A client that can read files can answer "what did step 7 look like" or
"which step changed this" without asking anything. A bare directory would give
less: filenames without verbs, targets or times.

So no new field — repeating a constant path on every step would cost more than
it says. What was missing is that nothing *told* anyone, which is a
documentation fix and now done, in `RunActResult.journal` and in the
`flutterware_act` description.

**With one warning attached, because the invitation is not uniform.** The
`.png` and the `.capture.json` manifest are small and are the point. The
`.tree.json` is ~120 KB of raw nodes: reading it whole is precisely the
19,500-token mistake `screen`, `find`, `at` and `styles` exist to avoid. An
agent told "the files are over here" and not told which ones are traps will
read the biggest one. Both halves are in the docs.

## What the lens corrected

**Three of the four mitigations were right; the fourth was unnecessary.** The
plan called for the reply to name the lens, for setting one to report what it
changed from, and for explicit flags to win — all three built, all three earn
their place. It also implied a pin needed a staleness story. It does not: a pin
is a preference, not an observation, and the only thing that can go wrong is
somebody being surprised by it. `lens: "design (pinned)"` on every reply is the
whole fix, and it separates the two cases that matter — *this is the default*
from *someone chose this*. A lens named for one call reports unmarked and
leaves the pin alone.

**Where it lives is the same answer as the journal's.** Every surface opens a
fresh session per call, so a preference in a field lasts exactly one call, and
one held in the MCP server would be invisible to `fw` and to the GUI. It is a
file beside the handle: `app-<key>.lens`, one word.

**`raw` is documented by its price.** ~20 980 tokens, measured, and said in the
parameter doc, the schema and the enum. A friendly name on an expensive thing
is how a budget disappears; the name is worth having because the thing is
occasionally worth doing, and the number is worth repeating everywhere it is
offered.

**Shared, honestly.** The vocabulary is in `app/lib/src/inspect/lens.dart`,
which the previews and scenarios cores reach as easily as run's — but only run
reads it today. That is adoption pending, not a second design, and saying
otherwise is how a plan starts describing something nobody built.

*(Adopted the same day — see below. The pin was not.)*


## What previews and scenarios corrected

The three surfaces now answer the same questions. The build turned up four
things the plan had wrong, one of them about the plan's own shape.

**1 — the selector was the easy part; the *reply shape* was where they diverged.**
The plan warned against unifying the selector and was right, but it assumed
everything after it already matched. It did not: previews had answered `find`
under a field called `matches` since it shipped. Same flag, different word for
the answer — which is exactly the "learn it twice" the unification exists to
remove, hiding one level below where the plan was looking. It is `find` now.

**2 — the shared code is a function of a tree, not a base class.**
`ScreenRead` (`app/lib/src/inspect/screen_read.dart`) takes an `InspectTree`
and an argument map and returns the screen, the scoped tree, `find`, `at` and
`styles`. It knows nothing about apps, entries, runs, sockets or files. That is
the whole reason three surfaces could adopt it in an afternoon: each already
had a tree, and the only genuinely different question — *which* tree — stayed
where it belongs. Moving it out of `run_core.dart` was a cut-and-paste; the two
adoptions after it were about fifty lines each.

**3 — `scenarios read` needed one selector with a browse ladder, not four.**
The plan said "a capture (or `live: true`)" and left the rest open. Four
plausible selectors exist here — package, run directory, scenario, step index —
and any three of them are noise on a given call. What shipped is one `step`
parameter that takes whatever the caller has in hand: a `tree` path, an `image`
path, a bare index, or nothing at all (which takes the step the scenario failed
on, the read that happens most). Anything that names a *directory* is refused
with a listing of what is in it, spelled as values that can be passed straight
back. Browsing costs a refusal instead of a guess, which is the same rule the
drive refusals already follow.

**4 — the pin is not part of the shared grammar, and pretending it was would
have been the mistake.** The plan said pinned state should live "in the session
for a preview, the run's output directory for a scenario". Both are wrong for
the same reason: a pin pays for itself in a loop against one long-lived
subject, and neither of these is one. A preview render and an archived step are
addressed afresh by every call. A pin there is hidden state with nothing to
amortise it. So `lens` is per call on all three surfaces and pinnable only on
run, where the loop actually exists.

### The screen is now previews' default, and it costs nothing

`inspect` used to answer "did it render without the framework complaining",
which says a build happened and nothing about what it drew. It answers both
now. Measured on the flutterware catalog's own `actionButton` demo:

| | |
|---|---|
| default reply, before | ~50 tokens (`ok` + an empty error list) |
| default reply, now | **523 tokens** — 14 items, nested, 3 regions |
| `screen: false, styles: true` | 215 tokens, and the type ramp is in it |
| `lens: raw` | 5 055 tokens |
| wall clock, screen on vs off | **6124 ms vs 6111 ms** over 3 runs each |

The 13 ms is noise: a preview is a compile-and-render, and walking a
45-node tree is not measurable beside it. The cost of the new default is
tokens and only tokens — which is the trade the design argued for, and it buys
the thing the old default could not say at all.

`styles` on a component demo is the surprise. Four distinct text styles on one
`ActionButton` page, two of them 11.5/400 in different greys, in 185 tokens.
That question had no cheap form on any surface before.

### Reading an archived step

| | |
|---|---|
| `read` default, one step of the example's Counter | **235 tokens** |
| `lens: raw` on the same step | 780 tokens |
| `find "Text"` on the same step | 458 tokens |

Note the last row: on a three-widget screen a query is *dearer* than the whole
screen, because a found node carries its source, its properties and its box
while a screen item carries a word and a rectangle. The queries earn their
keep against the **tree**, and the margin scales with the screen — 313 against
19 500 on the GUI's Changes screen. Worth saying plainly so nobody reaches for
`find` on a small screen expecting a saving.

One thing got trimmed after measuring. The reply lists the scenario's other
steps so walking a failing flow backwards is one call each — and spelled as
full paths that was **137 of 365 tokens**, the same eighty-character directory
five times over. They are bare file names beside `step` now: 365 → 235.
