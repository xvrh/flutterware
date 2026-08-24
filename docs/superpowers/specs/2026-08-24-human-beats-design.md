# A human tap lands the way an agent's does

*2026-08-24. Designed, not built. Came out of a feature discussion with the
owner: what an "instant replay" would be here, and what of it is worth v1.*

## The journal is one-eyed

`RunJournal` is the story of a run, and it tells half of it. Every agent step
lands with its picture, its texts and what the app printed. What the human did
between those steps lands as a bare line of prose, and only if an agent was
driving at all.

Two mechanisms cause that, and neither is the tagging — the tagging is already
right:

- **Nothing triggers a capture when a human acts.** `HumanActions` buffers
  pointer-ups and they ride the *next* `act`/`observe` reply as a
  since-last-step delta. With nobody driving, the buffer fills to its 100-entry
  cap and the rest are counted and dropped.
- **A human entry carries no picture.** By decision, recorded in
  `app/lib/src/run/journal.dart`: *"No screenshot on those; the step that
  follows photographs the screen they produced."*

So the journal knows the human tapped "Pay" and has no idea what happened next.

## What already exists

Worth listing, because it is most of the feature:

| | where | state |
|---|---|---|
| pointer interception | `lib/src/drive/human_actions.dart` — a global pointer route, down/up paired within `kTouchSlop`, long-press split on `kLongPressTimeout` | **done** |
| naming a hit | `describeHit` → hit test, leaf-most element, walk up to 100 hops for `Text` → `Tooltip` → `Semantics(label)` → `ValueKey<String>`, else `at (x, y)` | **done** |
| `actor: human` in the journal | `JournalEntry.actor`, rendered by the Steps tab | **done** |
| capturing the root view as PNG | `_screenshot` in `lib/src/drive/guest_drive.dart` — `toImage`, `ImageByteFormat.png`, `maxSide` | **done, reused as-is** |
| stale-run cleanup | `sweepRunDir`, called once per launch from `run/launch.dart` — age gate (1 day) plus a liveness check | **done, and not what this needs** |
| frame playback UI | `app/lib/src/scenarios/motion_player.dart` | **done** |

## The premise change

One line is architecturally significant, and it is the whole of v1:

> **The guest captures on its own trigger, not only when asked.**

Everything else on this wire is pull — the guest answers, never announces. That
rule is not broken here: the guest captures into its own ring and the host
still pulls, on its own schedule. What changes is that the guest stops throwing
away what it already saw — see *Where a beat lives*.

## The unit: a human beat, shaped like a step

A human beat is **the same transaction an agent step is** — act, settle,
observe — with the actor different and the act not ours:

    pointer-up  →  settle (bounded)  →  capture  →  append to the journal

That shape is the point. It needs no new vocabulary, no new file format and no
new UI: the Steps tab already renders journal entries, and human beats stop
being second-class rows in it. It also gives the right thing to an agent
reading back — *"tapped X, and then the screen showed Y"* — which is the same
sentence an agent's own step makes.

## What a beat carries

| field | v1 |
|---|---|
| `actor` | `human` |
| `verb`, `target` | from `HumanAction` — `tap` / `longPress`, named or `at (x, y)` |
| `screenshot` | yes — PNG, capped by `maxSide` |
| `texts` | yes |
| `tree` | **no** — 47 ms of UI thread at 34k elements; see *Measured* |
| `semantics` | no |

**The tree is deliberately out**, and the archive is the argument rather than
the wire. Measured 2026-08-13: a drive step archives **~730 KB**, of which the
`tree.json` alone is **~460 KB** — the "~120 KB" the docs quote is the wire
spelling, not what lands on disk. Dropping it is most of a beat's cost, and it
is exactly what `lens` gates for this reason. A beat defaults to the equivalent
of `lens: act`.

**When the name fails, a node id would beat bare coordinates** — it turns
`at (312, 640)` into something a reader can look up exactly. But it is *not*
free, and an earlier draft of this spec said it was: a beat walks no tree, so
there is no numbering to borrow. `nameHit` does hold the leaf element from its
hit test, so the question is whether an id can be minted from that without the
inspector's walk. **Unresolved — see Open.** Bare coordinates plus the screen's
texts are the v1 fallback, and they are legible enough for the consumer this is
built for.

## The cost, and why it is affordable

Measured under `flutter_test` for the motion recorder
(`2026-08-11-scenario-motion-capture-findings.md`), phone size, 1×:

| | |
|---|---|
| read as rawRgba | **0.24 ms/frame**, **1.29 MB** |
| encode as PNG | **7.4 ms/frame**, **~12 KB** |
| pump | 2.3 ms/frame — **not paid here**, a live app produces its own frames |

**PNG, not raw — and not for the reason the motion recorder chose raw.** That
recorder runs in `flutter_tester` *on the host* and writes to local disk, so
there is no wire and CPU is the only cost; raw halves it. A run guest may be on
a phone, and then every byte crosses the VM service base64'd, at +33%. ~12 KB
against ~1.29 MB is the whole argument, and `_screenshot` in
`lib/src/drive/guest_drive.dart` already made this call for agent steps, with
the reason in the comment: *"base64 over the wire is the cost being bounded"*.
A beat matches it — same `toImage`, same `ImageByteFormat.png`. (`toImageSync`
is the motion recorder's trick for staying inside a frame budget; a beat
captures after its settle and has no budget to protect.)

**The encode is affordable because of when it happens.** 7.4 ms would be
unaffordable inside a frame budget, and it is not inside one: a beat encodes
after its settle, when the app is idle by definition — the same moment an agent
step pays the same cost today.

**`maxSide` is the lever, and it already exists.** It scales the render before
encoding, so it cuts the encode *and* the bytes together, and `_screenshot`
takes it today. A beat is for scanning a timeline, not for reading fine print,
so it should take a smaller cap than an agent step. This is the largest cost
reduction available and it costs nothing to take.

## Measured, 2026-08-24 — and the risk is not where this spec put it

`test/drive/beat_cost_bench.dart`, JIT under `flutter_tester`, one 2400x1800
view capped by `maxSide: 900`. Tree size is varied with a non-lazy `Column`,
because a lazy list builds only what is visible and the tree stops growing.

| elements | inspect tree | tree + json | `visibleTexts` | semantics | `toImage` | PNG | base64 |
|---|---|---|---|---|---|---|---|
| 8,732 | 9.9 ms | 13.7 ms | 0.7 ms | 0.5 ms | 2.7 ms | 14.1 ms | 1.0 ms |
| 34,232 | **46.6 ms** | **63.4 ms** | 3.1 ms | 1.0 ms | 0.7 ms | 10.9 ms | 0.4 ms |
| 102,232 | **165.3 ms** | **211.2 ms** | 10.5 ms | 3.1 ms | 0.7 ms | 11.3 ms | 0.03 ms |

**The inspect tree walk dominates everything and scales linearly** — about
1.6 µs per element, pure Dart, on the UI thread. The picture does not scale
with the tree at all: `maxSide` already bounds it, and PNG sits at ~11 ms for
~11.8 KB whatever the tree does. That ~11.8 KB is the ~12 KB figure quoted
above, now confirmed against something other than the example app.

Three consequences, and the first two change the design.

**A beat must not carry the inspect tree, and this is a stronger reason than
the archive bytes.** The earlier argument here was about ~460 KB of
`tree.json`. The real argument is 47 ms of UI thread at 34k elements — four
dropped frames at 60 Hz, seven at 120 Hz — fired *immediately after the user
taps*, which is the exact moment they are watching for a response. `texts` is
15x cheaper than the tree for the same screen, because a predicate walk filters
where `InspectTree` builds an object per node.

**A beat therefore cannot reuse the observe bundle, which this spec assumed it
could.** `_dispatch` builds the tree unconditionally — *"the guest built this
tree on every observe already, including calls that asked for no tree at
all"* — so a beat needs a leaner path beside it: picture, texts, the tap.
That is new code rather than the pure reuse claimed above, and it is small.

**JIT is the honest number here, not a pessimistic one.** A driven run is a
debug build, because hot reload needs one. AOT would be faster and is not what
this runs on.

**What this bench cannot answer:** `flutter_tester` single-threads the engine,
so it cannot say which of these land on the UI thread on a real device. The
Dart-side walks certainly do. `toImage` rasters off it, and `toByteData(png)`
is believed to encode off it — that belief is load-bearing for the ~11 ms and
**was confirmed on a device — see the next section.**

## The encode is off the UI thread — confirmed, 2026-08-24

The gate the bench above could not answer. `flutter_tester` single-threads the
engine, so it was measured on a real one: a macOS debug build (what a driven
run is, because hot reload needs one), window visible and animating, Impeller.

**Method.** A `Timer.periodic(1ms)` on the UI thread records the largest gap
between its own ticks. A timer cannot fire while the isolate is busy, so if the
encode runs on the UI thread the gap rises to the encode's duration. Three
phases: idle, back-to-back `toImage` + `toByteData(png)`, and a deliberate 11 ms
busy-loop as a control that the probe can detect blocking at all.

| phase | median gap | p95 | max gap |
|---|---|---|---|
| idle | 1.20 ms | 1.47 ms | 8.09 ms |
| **126 encodes back to back** | 1.15 ms | 1.19 ms | **1.70 ms** |
| 11 ms block (control) | 11.05 ms | 12.21 ms | 12.28 ms |

**Neither `toImage` nor `toByteData(png)` blocks the UI thread.** Through
roughly 2.95 s of encode work inside a 3 s window, the worst gap was 1.70 ms —
*lower* than the idle phase's worst, and the control shows an 11 ms block is
seen as an 11 ms gap. `dart:ui` agrees in shape: `Image::toByteData` is a
callback-based native binding, not a synchronous return.

**So the load-bearing assumption holds, and the picture is not the risk.** What
remains on the UI thread is Dart-side only: the tree walk (which a beat does not
do), `visibleTexts`, and base64.

Two things the probe corrected on the way past:

- **~107 KB a beat, not ~12 KB.** The bench's 11.8 KB was flat `ListTile` rows;
  this screen — an antialiased rotating logo over 40 text rows, output 900x675 —
  encodes to **107.3 KB**. Real screens carry gradients and photographs, so the
  ring and the wire should be budgeted near 100 KB a beat, not 12. A 100-beat
  ring is still only ~10 MB, so nothing about the design changes; the arithmetic
  above does.
- **23.4 ms mean per encode**, twice the tester's. Off-thread, so it costs no
  frames — but it bounds how fast beats can be produced, and a burst window
  shorter than one encode would simply queue behind it.

**Still unmeasured: a phone.** The engine's task-runner architecture is shared,
so the *threading* answer should carry. What will not carry is the assumption
that off-the-UI-thread means free: a four-core phone runs that worker pool on
cores the UI thread also wants. Worth a repeat on an Android emulator before
this is called done.

## Where a beat lives

The guest cannot write the run dir — on a phone it is not even the same
machine. So the shape is three parts, and only the middle one is new:

    guest: ring of encoded beats  →  host: poller  →  the journal on disk

**The guest's ring is a buffer between polls, not a replay store.** That is the
correction that makes the memory question disappear: it only has to cover one
poll interval plus slack, so a few dozen PNG beats — single-digit MB — is
generous. Raw could never have worked here (a 100-beat raw ring is ~129 MB
inside the user's app); PNG is what makes an in-guest ring viable at all.

**The host polls, and `NetworkTracker` is the shape to copy** — not a new
organ. `app/lib/src/run/network_tracker.dart` already runs a `Timer.periodic`
against the guest with a re-entrancy guard, a give-up-after-failures state, and
"everything since capture was armed" semantics. A beat poller is the same
thing with a different payload.

**The journal is the replay store**, as it already is for agent steps.
`appendJournal` is JSON-lines precisely because *"two processes append to the
same story — a GUI and an `fw` are both actors"*, so a poller is one more
appender and out-of-order arrival is a case the format was chosen for.

This also collapses the desktop/device split: both go through the poller, and
nothing needs device-side disk.

**The cost of that, stated:** beats need a host holding the run. A run launched
from `fw` where the CLI then exits has nobody polling, and its beats age out of
the guest ring unseen. That is a real limit and it should be said in the panel
rather than discovered.

**The bound is still new work, and the existing sweep is not it.**
`sweepRunDir` runs once per launch and clears what *dead* runs left behind — an
age gate of a day and a liveness check. It says nothing about a live run's own
journal, which is what beats grow. That this matters is already measured —
2026-08-13, **161 MB of step captures, none of it reachable**, which is what
gave the sweep its caller. Beats need a bound *within* the run; the sweep keeps
its separate job.

## Why this is not a video

An app cannot encode video. Flutter ships no encoder, so doing it in-process
means an ffmpeg-class plugin inside *the user's app*, which is where the
performance objection becomes unanswerable.

The way out, when it is wanted, is that **the platform records outside the
process** — `xcrun simctl io … recordVideo`, `adb shell screenrecord` — and the
journal's timestamps correlate it. The app pays nothing because it is not
doing it. `screenrecord` caps at ~3 minutes per invocation, so chunking is
forced rather than chosen, and chunks are also the retention ring.

That is a separable layer and it is not v1. Stills at beats answer *"what was
on screen when it broke"*; video only adds *"what did the transition look
like"*, which is one class of bug. It also stops at the simulator, the emulator
and physical Android — a physical iOS device cannot be recorded this way, and
macOS desktop would need window capture instead.

## What this is for

**Immediately:** co-driving stops being half-blind. Today the Steps tab shows
what the agent did in pictures and what the human did as prose.

**The goal:** *"I tested it, it seems to work — write a scenario for that
feature"* becomes a real instruction. The agent reads the journal, finds a
sequence of screens with what was tapped on each, and already has the source.

That framing is the owner's and it sets the fidelity bar, so it is worth
stating plainly: **the recording is evidence, not a program.** It is never
replayed verbatim. Nothing here has to reconstruct a fling as a `scrollTo`,
produce stable selectors, or be gap-free — an agent that can also read the code
fills those in. A name only had to be perfect when it was going to become a
selector in generated code, and it is not going to.

## Not in v1

- **Video.** Above. Separable, and the app must never encode.
- **Screen-change beats.** A tap almost always *causes* the screen change, and a
  beat captured after settle already shows the result; an unprompted change is
  a smaller class. It is also the only part with per-frame cost, so it is the
  only part that could regress the app. If it is built later, the hook is
  semantics updates — the run guest already holds a semantics handle for the
  life of the run — never a per-frame tree walk.
- **Text entry.** The one real hole: a login or search flow will not record what
  was typed. Partial mitigation is that the beat *after* the typing shows the
  resulting screen, so it is often inferable. Reachable through the surface
  `enterText` already uses (`TextInput.updateEditingValue`), by observing the
  focused `EditableText` or interposing a `TextInputControl`. **v1.1**, and the
  first thing after v1.
- **A "save as scenario" button.** There is nothing to build: the agent writes
  the scenario by reading the journal.
- **Scroll intent.** Only ever needed for verbatim replay. Dropped with it.
- **Anything retroactive across runs.** One run, one ring.

## Pictures are per burst, and a late one degrades to prose

The backlog question and the queue question have one answer between them.

**Every tap lands as an entry, immediately.** That part is cheap and already
written — `HumanActions` records the pointer-up and names the hit.

**Pictures are per *burst*, not per tap.** A pointer-up restarts a short window;
when it expires with no further tap, *one* capture is enqueued, and its picture
attaches to the burst's last tap. The window is `kDoubleTapTimeout` (300 ms) —
the framework's own definition of "these taps belong together", and a constant
the drive layer already reasons in.

Three things fall out of that, which is why it is the whole policy:

- **Bounded by construction.** One pending capture regardless of tap rate. No
  queue growth, no coalescing heuristic, no drop rule to state.
- **It is what the screen means.** After a five-tap burst the interesting frame
  is the one the burst produced, and it belongs to the last tap. Capturing per
  tap would write five near-identical mid-flight frames and call four of them
  evidence.
- **Nothing an agent needs is lost.** The *sequence of taps* is what a scenario
  is written from; the pictures are context. Every tap still lands.

**The capture shares the drive queue** — the existing `_queue` future chain in
`GuestDrive`, the same one an agent step goes through. Running beside it was
rejected because it contradicts the doctrine this design already rests on:
*"two calls against a live app are two moments, and the gap between them is
where computer-use's bugs live."* A capture overlapping an agent's gesture
photographs a screen mid-transaction.

**And before it captures, it checks whether another tap has arrived since the
burst closed.** If one has, it abandons the picture — a newer window is already
pending and will take it. This is exact rather than a drift threshold: a
threshold is a guess, and "was there another tap in between" is *the* thing
that makes a picture wrong, is free, and is already timestamped.

**The fallback is today's behaviour, which is what makes this safe.** A beat
whose picture is abandoned is exactly the `actor: human` entry the journal
writes now. So the change is strictly additive: the worst case is what already
ships, and a picture that would lie is never written at all.

## Decided by the owner, 2026-08-24

**Capture is on for a run launched from the cockpit, and off elsewhere.** A run
the human started from the cockpit is an explicit enough act, and a replay that
has to be armed is a replay nobody has when they need it. The cost is one
capture-and-encode per human tap, and nothing per frame.

## Open, deliberately

- **A human tap during an agent step is silently lost.** `HumanActions.suppress`
  is a flag, not a filter on origin, so a real tap landing inside a drive verb's
  injection window is discarded. Minor today (one journal line); still minor
  with beats, but it is a known blind spot rather than an unknown one.
- **Who arms the guest, and who starts the poller.** Capture is on for a
  cockpit-launched run, so something has to tell the guest that. `NetworkTracker`
  already has "armed by the run guest, or by poll" semantics to copy.
- **Poll interval, and therefore ring size.** The two are one decision: the ring
  must cover an interval plus slack. `NetworkTracker`'s own interval is the
  place to start rather than a fresh guess.
- **Retention.** Whether the bound on the run's journal is a count or bytes. A
  count is easier to state to a user; bytes is what actually hurts, and the
  161 MB measurement argues for bytes.
- **Privacy.** This records a human's session in an app with real data. The
  frames stay on their disk and never leave it, but the retention window is a
  decision rather than a default, and it should be said out loud somewhere the
  user reads.
- **A node id without a tree walk.** Whether `nameHit`'s leaf element can yield
  an id the inspector would agree with, without paying for the walk a beat
  deliberately skips. If it cannot, bare coordinates stand and nothing is lost.
- **Naming quality.** `_nameFrom` finds the *first* name walking up, so an
  unlabelled icon button can be named for the card that contains it. Under the
  evidence framing this is tolerable. It should be measured on a real screen
  before it is called fine.

## Order of work

1. `HumanActions` records every tap as now, and drives the burst window above:
   on expiry, one capture on the shared `_queue`, abandoned if a newer tap
   arrived. Beats are held in a bounded ring — `toImage`, `ImageByteFormat.png`, a
   beat-sized `maxSide`.
2. A host poller on `NetworkTracker`'s shape drains the ring and appends each
   beat to the journal as `actor: human`, with `screenshot` and `texts`, no
   tree.
4. A bound on the run's own journal growth — count or bytes, stated where the
   user can see it. Separate from `sweepRunDir`, which keeps its job.
5. Steps tab: confirm human beats render as steps with no change. If they need
   one, the beat shape is wrong.
6. Measure, on a real device and a real screen, not the example app:
   **PNG bytes per beat** (the ~12 KB figure is a demo screen and will not
   hold), **encode time on device** (7.4 ms was a Mac), **the `texts` walk**
   — `visibleTextsOf` walks the widget tree, and dropping `tree` saves the
   archive bytes but not this, so it may well be the dominant per-beat cost
   rather than the encode — beats per minute, and the app's own frame times
   with capture on and off.

The gate is step 6. If a human tap costs the app anything visible, the premise
change is wrong and the feature goes back to an explicit toggle.
