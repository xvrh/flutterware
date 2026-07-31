# The inspection panel — and what it changes above and below itself

**Date:** 2026-07-29
**Status:** design. "What is already true" is verified against the code on this
branch; everything else is a proposal. Nothing here is measured — the one item
that needs measuring is named as a spike.
**Extends:** `2026-07-29-ui-catalog-inspection-design.md` (this is its S5, plus
two things S5 turns out to force), `2026-07-27-gui-cli-mcp-architecture.md`.

## The question

S1–S4 landed the inspection *data*. What does the GUI do with it — and what
does building the GUI half tell us about the surface the other two already have?

## The short answer

A Chrome-devtools-shaped bottom panel, reading the **live** guest rather than a
headless one. That single choice reorganises the work above and below it: it
forces a shared reader that does not exist yet, and it makes an idea that was
filed as future work — an agent reading the session a human is driving — nearly
free. Meanwhile the action surface it does *not* use turns out to be cut wrong,
for a reason the panel makes visible.

## What is already true (verified)

### 1. The GUI holds a live guest and a live VM service

[`CatalogSession._vmService`](app/lib/src/catalog/catalog_session.dart:343),
connected at start and held for the life of the session. So the panel can call
`ext.flutterware.tree`, `hitTest` and `errors` against the guest that is
rendering the texture on screen. It does not need `HeadlessCatalog` and must not
use it — see the design line.

### 2. There are already two readers of the same extensions, in two files

| extension | headless | live |
|---|---|---|
| `ext.flutterware.axes` | [`settledAxes`](app/lib/src/catalog/headless_catalog.dart:653) | [`_readAxes`](app/lib/src/catalog/catalog_session.dart:592) |
| `ext.flutterware.parameters` | `settledKnobs` | `_readKnobs` |
| `ext.flutterware.tree` | `settledTree` | — |
| `ext.flutterware.hitTest` | `settledHitTest` | — |
| `ext.flutterware.errors` | `settledErrors` | — |

The drift this predicts has not bitten yet because the live side only reads two
of the five. Wiring the panel makes it five, in two files, with no test that
they agree.

The difference between the two columns is **settling, not reading**: the
headless side retries until the tree names the entry it asked for, because it
does not know when the build landed. The live session drives the build and does.
So the shared thing is the read, and how patiently to poll is a property of the
guest rather than of the call — which is why `InspectPatience` is set once on the
client and never passed to a method.

**And the drift had already produced a defect, found by doing the extraction.**
S0b split `callExtension` into a tolerant form and a `requireExtension` that
throws, because the tolerant form swallowing JSON-RPC 32601 is how `setParameter`
survived a week after being renamed to `setParameters` — applying nothing and
reporting success. The fix was applied to the headless writes. **The panel's two
writes were still tolerant** (`_pushKnobs`, `_pushAxes`), so the same rename
would have silently done nothing to the GUI's knobs again. Routing both callers
through `InspectClient.setKnobs` / `setAxes`, which require, closes it in one
place — and is most of why the class earns its keep beyond deduplication.

### 3. `screenshot --annotate` reads its own tree

[`headless_catalog.dart:94`](app/lib/src/catalog/headless_catalog.dart:94). A
caller that runs `tree` and then `screenshot --annotate` renders twice, in two
processes, and gets two trees. The ids on the picture match the ids in the tree
because the build is deterministic, not because they are the same object — and
closing the pixels↔structure loop was the entire point of `--annotate`.

### 4. The bottom of the catalog panel is already occupied

[`_buildBody`](app/lib/src/catalog/catalog_view.dart:205) is
`Row[entryList, Column[topBar, canvas, knobs?, statusBar]]`. The knob drawer is
already a bottom panel, and it is *absent* rather than empty when an entry
declares no knobs — so a user who has never opened an entry with knobs does not
know the feature exists.

### 5. Every pointer is forwarded to the guest

[`_guestInput`](app/lib/src/catalog/catalog_view.dart:351) sends enter, hover,
exit, down, move and up, scaled by `dpr`. There is no mode in which the host
keeps an event. A picker needs one.

### 6. Node rects are already in the coordinate space the overlay needs

[`InspectLayout`](lib/src/inspect/node.dart:61) carries `x/y/width/height` in the
guest's own logical coordinates. A painter placed *inside* the texture's box
therefore needs no transform at all, and inherits the device `FittedBox` and
`DeviceFrame` scaling for free.

### 7. The shell has no back/forward history

It remembers where each open worktree was left
([`shell_controller.dart:66`](app/lib/src/shell/shell_controller.dart:66)).
So writing the address on every node selection cannot bury anything, which
removes the main objection to putting selection on it.

### 8. Guest stdout is printed, not captured — **closed**

[`embedded_engine.dart:101`](app/lib/src/embedder/embedded_engine.dart:101)
`debugPrint`s each guest line into the *host's* console. Nothing in the GUI can
show it and nothing in `fw` can return it.

**Closed by `GuestLogs`, in the guest rather than the host, and the reason is
the live attach.** The host does hold the guest's stdout — but only because the
host spawned it. A reader attached to a session somebody else is driving has a
VM service URI and nothing more, so a host-side capture would have given the
panel a console and left `fw` and an agent with none. The buffer sits beside
`GuestErrors`' for exactly the reason that one does.

**Both pulled and pushed.** The buffer answers "what has been printed"; the
events say "and here is another one" without waiting for a poll — a console
three seconds behind the demo is a console nobody trusts, and the `GuestWatch`
measurement had already established that the channel carries 60Hz without
batching. A reader takes the buffer and subscribes at the same moment and drops
the overlap by sequence number. Matching on text and time instead would still be
wrong about a demo printing the same word twice in a frame.

**The one thing that had to be right, and could only be checked against a real
guest.** `PlatformDispatcher.onBeginFrame` captures `Zone.current` when it is
*set*, and the binding sets it in `initInstances` — so the zone has to wrap
`WidgetsFlutterBinding.ensureInitialized()`, not just `runApp`. Wrap only
`runApp` and every build, layout and paint callback runs in the zone that came
before: a demo printing from `build`, which is the whole case, prints into the
root zone and is captured by nothing. Every unit test passes and the console
stays empty for ever. `headless_check` therefore prints from a fixture's `build`
and reads it back over the VM service, which is the only assertion that can see
this.

**And it forwards, always.** The host reads the VM service URI off that same
stdout and the headless check reads `FW-PROBE:` lines off it, so a zone that
kept a line to itself would not merely lose a log — it would stop the session
starting. `FW-PROBE:` is dropped from the *record* only: it is the harness
talking to itself, and a console showing it would show five lines a second of it
and nothing else.

### 9. The discovery pattern for "attach to what is already running" is written

[`DaemonAddress`](app/lib/src/catalog/daemon_address.dart:14), for the compiler
daemon: *"the address is derived, not assigned, so every consumer that wants the
same catalog — the GUI, `fw`, an agent, a test — arrives at the same socket
without being told about each other."* The live-guest attach below is the same
sentence one level up.

## The design line

> **The panel inspects the guest that is on screen. The shared unit is the guest
> extension and the plain-Dart model, not the `PluginAction`.**

The first half is a correctness claim, not a performance one. If you opened a
dropdown, hovered a row or scrolled a list, a headless re-render has none of it.
An inspector that inspects a *re-render* of what you are looking at is answering
a different question from the one asked.

The second half is how parity survives that. The prior doc's rule was "everything
below Viewer tier reaches all three surfaces from one `PluginAction`". That rule
cannot hold for the panel, because the panel does not call actions. The rule that
does hold: a capability is shared when the **`ext.flutterware.*` extension** and
the **model in `lib/src/inspect/`** exist. `HeadlessCatalog` mounts them for the
actions; `CatalogSession` mounts them for the panel. Two mounts, one capability.

Which makes finding 2 a prerequisite rather than a cleanup.

## The panel

Chrome's shape, docked at the bottom: **collapsible, resizable**, a tab strip,
and inside the Elements tab a **resizable tree │ detail split** with the detail
pane the narrower of the two.

The height objection — a widget tree is deep and 300px is not much — is answered
by resizability. 300px is the resting state, not the working one.

**One trap worth recording, because it looked like it worked.** A `Column` lays
a non-flex child out with an *unbounded* main axis, so a `LayoutBuilder` inside
the panel reads `maxHeight: infinity` and every clamp against it is a clamp
against nothing — the panel resizes straight past the bottom of the window,
taking the canvas with it. The available height has to be measured by an
ancestor and passed down, and measured by the ancestor that wraps **only** the
canvas and the panel: a reserve that has to guess at the top bar and the status
bar above and below is wrong the moment either changes height.

| tab | contents | status |
|---|---|---|
| **Elements** | tree left, detail right (properties, box, constraints, flex, `file:line`) | data exists |
| **Problems** | `errors` for this entry, `audit` for the catalog; badge on the tab and on entry rows | data exists |
| **Controls** | today's knob drawer, moved in | a move |
| **Console** | what the demo printed, live | **landed** — see below |
| **A11y** | semantics tree and the three framework evaluations | S3b |
| **Perf** | rebuild/repaint counts | later |

Knobs become a tab rather than a second drawer. Two stacked drawers under a
phone-shaped preview is not a layout, and a tab is also how the feature stops
disappearing (finding 4).

### Hover and picker: one lookup, two directions

- **hover a tree row → highlight it in the preview** — node id → rect
- **picker over the preview → select it in the tree** — point → node id

Both run **host-side against the tree already in hand**. No round trip, so the
highlight tracks the mouse at frame rate. The one RPC is the *commit*: on click
the picker asks the guest's real `ext.flutterware.hitTest`, because host-side
rectangle containment does not know about transforms, clips, opacity or
`IgnorePointer`. Optimistic highlight, authoritative selection — Chrome's split.

**The picker swallows pointers** (finding 5). Neither the click nor the hover
reaches the demo while picking: forwarding the click taps the button you were
trying to inspect, and forwarding the hover lights up the demo's own hover states
underneath the thing you are trying to see. Escape cancels; a successful pick
exits the mode.

**The overlay is painted inside the texture's `Stack`** (finding 6), so it is
correct under every device without a line of coordinate maths.

### Freshness — and what hover does to it

A tree is of one build. Entry switch, reload, knob and axis change all notify.
Nothing notifies when the *demo's own* state moves.

Today that is invisible: a stale tree shows slightly wrong numbers. Once hovering
a row draws a rectangle on screen, **a stale tree visibly lies** — you hover
`Padding` and a box appears over nothing. Hover-highlight is therefore what makes
the watch load-bearing rather than a nicety.

The instinct is to push the tree every frame. That is the wrong primitive, and
the reason is worth stating: **an animation almost never changes tree structure.**
It changes geometry. Pushing the whole tree per frame re-sends fifty identical
nodes with different rects, sixty times a second, to move one rectangle — and the
walk-plus-encode is most likely to cost a frame in exactly the case you turned it
on for.

So three tiers, of which one is probably never right:

| tier | pushes | when | cost |
|---|---|---|---|
| **geometry** | the *selected* node's rect | every frame while something is selected | one node — this is what makes the overlay track an animation |
| **structure** | the tree, when its shape changed | hash the shape in a frame callback, push on mismatch | one walk per frame, one payload per real change |
| full | the whole tree | every frame | not proposed |

**A fourth tier turned up while building it, and it is the one that fixes a bug
somebody actually hit: resize.** Dragging the panel divider changes every rect
in the tree and not one widget in it — so the shape hash cannot see it, by
construction, and geometry-watch only covers the node under the pointer. The
tree went on reporting the widths it had before the drag, *including whether
anything overflowed at them*, which is how it was found. It costs a `hasSize`
and a compare, riding along with the walk that is already happening.

It also carries the errors, and that is the half worth stating. The error record
is of what the framework **said**, and nothing ever arrives to say an overflow
stopped — so a `Row` that overflowed at one width went on being listed under
Problems at every width after it. A resize is exactly the moment that record
becomes a claim about a layout that no longer exists, so it is cleared and
re-read there.

**And a fifth, found the same way: scroll.** Scrolling the demo moves every rect
under the scrollable while changing no widget's type, no widget's depth and not
the demo's own box — so structure and resize are both blind to it by
construction, exactly as they are to a divider drag. The tree kept the rects
from before the scroll and the picker drew its overlay from them, so hovering
named whatever *used to* be under the pointer and put the box wherever that had
since gone; refresh was the only way back, which is how this one was found too.
A `NotificationListener<ScrollNotification>` above the demo counts what it
scrolls — nothing per frame, because notifications arrive from scrolling and
from nothing else — and the tier reports the count moving.

**It says "still moving", not "moved", and the host waits it out.** A fling
notifies on every frame of itself; a host re-reading on each would queue 17ms
walks faster than they complete, for layouts the hand has already left behind.
So the flag resets a 120ms timer and the read happens once the pushes stop —
one walk per gesture. This is also the one tier whose flag is *held* across a
debounced push rather than overwritten: a scroll nobody was told about leaves
the picker lying with nothing else ever coming to correct it.

**Which is why the watch's lifetime is the panel, not the Elements tab.** The
tree read stays behind `inspecting` — it is the expensive half, and nobody
looking at Controls should pay for it. But the watch itself is 0.3ms a frame and
nothing at all when nothing is drawn, and tying it to Elements would have left
Problems — the one tab where a resize genuinely changes the answer — unable to
learn that the preview had been resized.

**The refresh button stays.** The tiers cover shape, the demo's own box, what it
scrolls, and the node under the pointer; they do not cover every rect of a demo
that resized one of its own children without changing shape. Removing the button
would be claiming a completeness the measurement does not support.

Both behind one `ext.flutterware.watch`, on when the panel opens and off when it
closes, so a guest nobody is inspecting pays nothing.

**This is not a behaviour change, and semantics is.** The distinction was
muddled in conversation and is worth fixing here. A tree watch changes what the
process *spends time on*. `ensureSemantics()` changes what the app *does*: while
the handle is held the framework builds and maintains a second tree every frame,
render objects take the `markNeedsSemanticsUpdate` path, and anything keyed off
`semanticsEnabled` flips. That is why S3b is a separate decision and this is not.

### Measured — `app/tool/catalog/watch_spike.dart`

The spike this document owed. Against the real embedder guest, the real demos,
and the production `GuestWatch` rather than a benchmark shaped like it.

**Cadence — no batching at all.** The `Counter` demo, whose `RotationTransition`
moves its child's box on every frame, watched for five seconds:

| | |
|---|---|
| frames drawn | 300 in 5s — a clean 60fps |
| pushes | 300 — one per frame, nothing coalesced |
| arrivals at the host | 60.0/s |
| gap p50 / p95 / max | 16.8ms / 21.1ms / 26.1ms |
| gaps under 2ms | **0%** |

Batching would show as a run of near-zero gaps behind one long one. There are
none: the p50 *is* a frame, and the tail is about one frame of jitter. VM-service
extension events sustain 60Hz smoothly.

**Cost — the shape hash is free and the tree read is not.** Per frame, over the
element tree; the round trip is `ext.flutterware.tree`, averaged over five reads:

| demo | summary nodes | elements walked | hash mean | hash max | `tree` round trip | id→render resolve |
|---|---|---|---|---|---|---|
| Counter | 19 | 229 | 0.137ms | 0.592ms | 3.8ms | 1.4ms |
| Palette (results) | 140 | 547 | 0.299ms | 0.878ms | 10.2ms | 4.0ms |
| Palette (many) | 286 | 863 | 0.285ms | 0.368ms | 17.7ms | 8.7ms |

**Decision: per-frame is allowed, and the debounce stays as a knob.** On the
largest tree in the repo the hash costs ~2% of a 16.7ms frame and never exceeded
5%. The comparison that settles it is the last two columns: reading the tree
costs **17.7ms — more than a whole frame** — which is why the structure tier
pushes a flag and the host pulls, and why resolving a node id is cached rather
than repeated. The instinct to push the tree per frame was not merely wasteful;
it was over budget by itself.

**Two things the spike got wrong first, both worth keeping.** It watched the
deepest node with a box, and so measured a demo rendering 180 clean frames and
pushing *once* — the right answer to the cost question and no answer at all to
the cadence one. A spinner repaints without moving anything, and a watch that
fired on it would be a watch reporting repaints. And a watch restarted on an
entry that never draws kept reporting the *previous* entry's node count, so a
run of static demos each claimed the size of whichever animating one preceded
them.

**Idle costs nothing, and by construction rather than by care.** The watch
re-arms a post-frame callback, and a post-frame callback does not schedule a
frame — so a guest with nothing moving is never walked at all. Six of the twenty
demos recorded zero frames across three seconds. A persistent frame callback
would have had to build that, and could not have been removed when the panel
closed.

## The address

`AddressScope` already namespaces `axis.` and `knob.`. The panel adds `inspect.`.

**On the address** — what you are looking at:

| | |
|---|---|
| `inspect.node` | the selected node id |

**`inspect.tab` was on this list and came off, once the lifetime was checked.**
Namespaces are not dropped automatically by nesting; the drop is an explicit
list at
[`ui_catalog_plugin.dart:197`](app/lib/src/plugins/native/ui_catalog_plugin.dart:197),
and `inspect` has to be on it — a node id names a position in *one* tree, so
carried across an entry switch it would not merely be stale, it would name some
unrelated widget of the next demo with complete confidence. A tab dropped by the
same rule would flip back to Elements on every click through the entry list,
which is exactly when you least want it to. So the selection is on the address
where it dies correctly, and the tab is session state — beside
`CatalogBrowsing.listVisible`, surviving both an entry switch and the panel
being rebuilt.

`inspect.node` earns its place beyond bookmarking: **`--node` is already a
`screenshot` parameter.** With the selection on the address, "screenshot what I
am looking at, cropped to what I selected" needs no new plumbing — it is the
address feeding the action it already feeds.

**Off the address** — window furniture: panel height, collapsed state, splitter
position. Putting them on means every splitter drag rewrites the address. They
follow `CatalogBrowsing.listVisible` instead: in-memory session state.

Known cost: node ids are structural and stable only while the tree is, and
`nodeAt` returns null rather than a nearest match. An address saved before an
edit restores with nothing selected. Honest, and the alternative — selecting
whatever moved into that position — is a confident wrong answer.

## Below the panel: attach to the live session

`fw` and MCP open a fresh session, hold nothing, and build their own guest. When
a GUI session is already running for the worktree, they should read *that* one.

Mechanically it is finding 9 one level up: the live session publishes its guest's
VM service URI at a derived path under `~/.flutterware/run`; `fw` and MCP look
there before building anything. And because the panel work already produces
`InspectClient(GuestVmService)`, attaching is **the same reader pointed at a
different URI** — no new inspection code.

**Keyed on the project root, not on the `DaemonConfig`** — and the reason is a
finding, not a preference. The two sides build *different* configs for the same
package today: `CatalogSession` passes the app tool directory as
`appPackageRoot` while `UiCatalogCore._headlessFor` passes the package itself.
So they hash to different `DaemonAddress` keys and **the GUI and `fw` do not
share a compiler daemon**, despite that class's docstring describing exactly
that sharing. A config-derived handle would therefore never match. The project
root is what both sides genuinely agree on, and it is the identity that matters
anyway: *is anyone looking at this package's catalog right now.* The daemon
divergence is left alone here — it is a separate question with its own
consequences — but it is now written down.

**Liveness is decided by connecting, not by a pid.** A GUI that crashed cannot
delete its own file, and Dart offers no way to probe a pid without signalling
it — where trying the URI answers the only question that matters. A handle that
will not connect is deleted on the way past, so a stale file costs one timeout
once rather than forever.

**The attach reads what is on screen; it never puts something there.** It
engages only when a session is open on the *exact* entry asked about, which
makes the whole thing safe by construction: an agent asking about another entry
gets a fresh render, and the person's window does not move. That refusal is
verified against a real guest in `headless_check`, along with the fact that the
guest is still holding its original entry afterwards — because a decline and a
crash would otherwise look the same.

What it buys: `tree`, `find`, `at` and `errors` become *what I am looking at
right now* — no build, no cold start, and truthful about the state a human put
the demo in. `errors` gains the most: attached, the list includes throws reached
by *clicking*, which no fresh render can ever produce because no fresh render
performs the click. The commands get faster **and** more honest when the GUI is
open. "The GUI is never a required participant" survives intact; it gains "when
present, it is an upgrade".

**`screenshot` is not in that list, and this document was wrong to imply it
would be free.** The headless guest is spawned with `--capture-raw` and answers
a `CaptureMessage`; the GUI's `EmbeddedEngine` speaks the same protocol and
already receives `CapturedMessage` — but only to ignore it
([`embedded_engine.dart:177`](app/lib/src/embedder/embedded_engine.dart:177)),
and it exposes no `capture()` at all. So capturing what a person is looking at
is a small addition to the engine rather than nothing, and it is not in S5a′.

Three constraints:

- **Provenance is in the result.** Running `tree` twice and getting different
  answers because someone clicked in between is the point — but only if the
  result says so. Every affected result carries `readFrom`: `live` or `render`,
  always present rather than only on the interesting case, because a caller
  that gets two answers to one invocation has to be able to see why and an
  absent field is not an answer. Silent nondeterminism would be the worst
  version of this.
- **Reads attach; writes do not.** Pushing knobs or axes into the guest a human
  is driving yanks their window around. So any call carrying `--knobs` or
  `--axes` goes headless, whatever else is true. The fast path is the read-only
  one, which is also the safe one.
- **Opt-out exists.** `--live=false` on every action that can attach. CI always
  wants a clean build; it also gets one for free, having no GUI open.

This also completes the interaction story rather than deferring it — see below.

## Above the panel: the action surface is cut wrong

Nine actions, but not nine of one thing:

| kind | actions | takes |
|---|---|---|
| about the repo | `entries`, `check`, `audit` | `--package` |
| about the declaration | `describe` | `--entry` |
| **about one rendered build** | `screenshot`, `tree`, `find`, `at`, `errors` | **`--entry --knobs --axes`, and each must render first** |

The third group is not five commands. It is five projections of one observation —
same inputs, same precondition, and each paying a full render to answer one
question about a frame the others also had to produce. A sixth (`logs`) and a
seventh (`semantics`) were about to be added to it by reflex.

Two arguments for collapsing them, and the second is the deciding one:

- **Economy.** Three questions is three renders, and for an agent in a UI edit
  loop that is the dominant per-iteration cost.
- **Consistency.** Finding 3: `--annotate` and `tree` are two renders, so the
  loop it exists to close is closed on an assumption. One render, one tree, both
  projections off it, and the assumption goes away.

**Landed**, as declared:

```
fw run ui_catalog inspect --entry=X [--knobs= --axes= --debug= --live=]
    [--tree] [--find=Save] [--at=120,300] [--node=0/1/2] [--depth=N]
    [--errors] [--logs]
    [--screenshot=out.png] [--annotate]
```

Nine actions became six. Four result shapes became one — `CatalogTreeResult`
and `CatalogRenderResult` were deleted rather than left unused, since the
capability document is generated from the shapes and a dead one reads as an
offer.

**What the collapse changed beyond the cost.** `--at` used to be `--x` and `--y`:
two required integers that are only meaningful together, which is two ways to get
a point half-wrong. It is one parameter now, validated before anything is
compiled — a typo in a flag should cost nothing, and a compile-and-render is the
most expensive thing here.

Sections are **absent unless asked for**, not empty. Null means nobody asked;
empty means asked and there is nothing. A demo that printed nothing and a demo
whose logs were not requested are different answers, and `at` present-and-empty
is how a caller sees that its point missed rather than that it forgot to probe.

**`--screenshot` forces a render.** A picture has to come from a frame this call
composited, and an attached session offers a VM service and no frames. So does
`--device`, for a sharper reason: framing changes what is *drawn*, and nothing
here may reframe a window somebody is watching.

### What `screenshot` and `inspect --screenshot` are for

Asked directly, and the first answer was wrong: `inspect` rendered at the panel
viewport and nothing else, so *"why does this look wrong on a phone"* — which
needs the picture **and** the constraints — was two renders and two trees again.
Exactly what the collapse existed to remove. `inspect` takes `--device`,
`--width` and `--height` now, and `headless_check` asserts a device reframes what
it *reports* rather than only what it draws: 900pt panel, 390pt phone, in the
tree.

It also hands back an [`Artifact`] rather than a path, with the output path
derived from the address when none is given — the same identity `screenshot`
mints. So the two are now equivalent **on the picture**, which is what makes the
remaining differences worth stating rather than guessing at:

| | `screenshot` | `inspect` |
|---|---|---|
| with no flags | draws a picture | answers "did it render", draws nothing |
| the result *is* | the artifact | one section of an observation |
| `--live` | never — it needs frames | yes, and says so in `readFrom` |

The first row is the whole reason both exist, and is the spec's original
argument: "give me a picture" should not require flags. The rest follows from it.

**Two surfaces are fine. Two implementations are not** — and there were briefly
three copies of one rule between them. `observe` was written with a byte-for-byte
copy of `capture`'s crop-and-annotate logic, and `inspect` with its own address
builder that omitted `formFactor`, so the same picture would have derived two
different filenames the moment both could take a `--device`. Both are one
function now (`_Framing`, `_pixelAddress`, `_framing`).

**One render path now.** `capture` is `observe` plus unwrapping, so `screenshot`
is a flag-free front door onto the same code rather than a second implementation
of it. `captureAll` stays separate and is not a third copy: it is a different
thing — many entries against one warm guest — and folding it in would destroy the
economy it exists for.

Folding also settled a divergence that had already appeared: `capture` applied
the debug flags *before* the knobs and `observe` after. Nothing was visibly
broken by it, which is exactly why two copies of an ordering rule is a bad
place to be.

**Measured, because the economy argument was asserted and never checked** — and
that is exactly the kind of claim that turns out to be wrong, since the daemon
stays warm between calls and it was not obvious up front how much of the cost
was really per-call. `headless_check` now asks the same five questions both ways:

| | |
|---|---|
| five separate calls | 2479ms |
| one `observe` | 517ms |
| | **4.8×** |

Printed rather than asserted: a threshold would fail on a loaded laptop and
teach nobody anything.

**And "one render" was not true when it was first claimed.** It meant one
*guest*. Each `settled*` helper drew its own scratch frame — correct when each
was a standalone call, wrong the moment one call wanted five answers — so an
observation drew five or six frames, each writing a PNG to disk and deleting it.
Worse, `settledHitTest` read a **second** tree to resolve against, so the ids on
an annotated screenshot matched the ids in the reported tree because the build is
deterministic, *not* because they were the same tree. Which is precisely the
assumption this step existed to remove, preserved intact one layer down.

Rendering is now separated from reading (`settle()` beside `readTree`,
`readErrors`, `readLogs`, `readKnobs`, `readHitTest`; the `settled*` forms remain
for standalone callers, defined as one plus the other). One frame, then every
read off it, and the hit resolved against the tree that was reported by argument
rather than by luck. The ratio above is from after that change; before it, on the
same machine, it was 3.9×.

One frame rather than two, even for a plain picture: when a screenshot is wanted
and nothing has to be read *before* it is taken, the screenshot **is** the
settling frame. A crop or an annotation needs the tree first, so those still
settle separately. That is not a micro-optimisation — `screenshot` is the
commonest call there is, and folding `capture` into `observe` would otherwise
have quietly added a frame to it.

**And the collapse found a bug, the way these keep doing.** The old `tree`
action declared `--debug` and passed it **nowhere** — not to the live path,
which never applied it, and not to the headless one, whose call site read
`tree(entryId:, knobs:, axes:)`. Accepted, documented in
`docs/capabilities.md`, and silently ignored: the same class of defect as
`setParameter`, and found for the same reason the panel's tolerant writes were
— writing the one handler forces every declared parameter to be threaded
somewhere. `--debug` now applies, and it also switches the attach off, since a
debug flag changes the guest *process* and pushing it into somebody's open
window would reach past the call's business exactly as knobs and axes would.

**No flags gives the "is it OK" answer** — render, report build throws and
overflows, nothing else. Everything heavier is opt-in, which is what the prior
doc's token measurements already concluded (`summary` always, details opt-in,
`find` before `tree`).

Kept separate: `entries`, `check`, `describe`, `audit` (many entries, different
cost model), and `screenshot` — "give me a picture" should not require flags.

This also closes a question the prior doc parked. It floated `flutterware_inspect`
as the one candidate for MCP tool promotion, *"bundling tree + layout + annotated
screenshot for one entry"*, and said decide with a real client in front of us. If
the **action** is the bundle, there is nothing left to promote.

**Sequenced late on purpose.** It is a breaking re-cut of a shipped surface, and
the panel is what will teach us the right shape — what the detail pane actually
needs, how ids behave in a real editing loop. This branch already deleted three
capabilities that were designed rather than run; re-cutting before the data has
been used in anger risks doing it twice. Nothing in the attach depends on it.

## What is deliberately not built

**Interaction — tap, type, scroll — is dropped, not deferred.**

The prior doc called it "the largest remaining gap in the AI surface". The
counter-argument is better: a demo whose states are reachable only by tapping is
a demo that should have declared those states as knobs. Building `tap --node=…`
is tooling around a modelling gap, and doing it properly means something close to
the `WidgetTester` API — a large surface for the sake of demos that are underspecified.

The live-session attach replaces it, and more cheaply: **the human is the
interaction API.** Drive the demo by hand into whatever state knobs cannot
express, then have the agent inspect exactly that. This is why the attach moves
up the sequence rather than sitting at the end.

**Live flex editing is not shipped as a mutation.** `setFlexFit` /
`setFlexFactor` are framework extensions and nearly free in the panel, but a
`fw` invocation that sets a flex and exits is meaningless — the change dies with
the guest. If it ships, it ships as a scratch that reports **the source edit you
would have to make**, which is the part an agent can use.

**Blank-frame detection stays dropped**, for the reason the prior doc gave.

## Sequencing

Each step stands alone if the next is abandoned.

| | | depends on |
|---|---|---|
| ~~**S5a**~~ | **landed.** `InspectClient`; the duplicated axis/knob readers retired; the panel's two tolerant writes made required. Live-session `tree` deferred to S5b, where it has a consumer | — |
| ~~**S5a′**~~ | **landed.** `LiveSession` published by the GUI and discovered by `fw`/MCP; `tree`, `find`, `at` and `errors` attach; `readFrom` on both result shapes; `--live=false` to refuse. Verified against a real guest in `headless_check` | S5a |
| ~~**S5b**~~ | **landed.** The panel: collapsible, resizable, tabbed; Elements with a resizable tree │ detail split; knobs moved in as Controls and no longer vanish when an entry has none; `inspect.node` on the address; live-session `tree` wired to the consumer that justifies it | S5a |
| **S5c** | hover-highlight, overlay inside the texture stack, picker with pointer swallow, `inspect.node` on the address | S5b |
| **S5d** | Problems tab over `errors` / `audit`; badges on entry rows | S5b |
| ~~**S5e**~~ | **landed.** The spike (see *Measured*); `ext.flutterware.watch` with four tiers — geometry, structure, **resize**, **scroll**; the panel subscribes for as long as it is mounted and the tree re-read stays behind the Elements tab | S5c |
| **S5f** | **Console tab and guest log capture landed** (finding 8). Flags-as-axes (S4b) and A11y (S3b) still open — S3b is a real behaviour change and stays its own decision | S5b |
| ~~**S6**~~ | **landed.** `inspect` replaces `tree`, `find`, `at`, `errors` and the `logs` that was never shipped; `HeadlessCatalog.observe` is the one render behind it; `--annotate` now genuinely shares the tree it is drawn from | none technically; the panel by judgement |

S5a′ sits second because it depends only on S5a, is independently valuable
without any panel — the GUI already runs a live guest and already forwards
pointers, so a human can put a demo in a state today — and because it lets an
agent inspect the session a human is driving *while the panel is being built*.

## Open questions

1. **Does the picker's optimistic highlight ever disagree with the commit?**
   Host-side rect containment versus a real hit test. If they disagree often
   enough to be visible, the highlight is lying at frame rate, and the fix is
   probably to hit-test on hover with a throttle rather than to accept it.
   Unknown until it is used.
2. ~~**Structure-watch's change detection.**~~ **Answered.** 0.285ms mean on an
   863-element tree, against a `tree` read that costs 17.7ms. Per frame it is,
   with the debounce kept as a host-chosen knob rather than a default. See
   *Measured*, above.
