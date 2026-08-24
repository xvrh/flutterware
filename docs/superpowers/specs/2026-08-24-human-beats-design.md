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
| capture without waiting for pixels | `OffsetLayer.toImageSync`, proven by the motion recorder | **done** |
| stale-run cleanup | `sweepRunDir`, called once per launch from `run/launch.dart` — age gate (1 day) plus a liveness check | **done, and not what this needs** |
| frame playback UI | `app/lib/src/scenarios/motion_player.dart` | **done** |

## The premise change

One line is architecturally significant, and it is the whole of v1:

> **The guest captures on its own trigger, not only when asked.**

Everything else on this wire is pull — the guest answers, never announces. That
rule is not broken here: the guest writes into the run dir and the host still
pulls the journal when it wants it. What changes is that the guest stops
throwing away what it already saw.

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
| `screenshot` | yes, 1× |
| `texts` | yes |
| `tree` | **no** |
| `semantics` | no |

**The tree is deliberately out**, and the archive is the argument rather than
the wire. Measured 2026-08-13: a drive step archives **~730 KB**, of which the
`tree.json` alone is **~460 KB** — the "~120 KB" the docs quote is the wire
spelling, not what lands on disk. Dropping it is most of a beat's cost, and it
is exactly what `lens` gates for this reason. A beat defaults to the equivalent
of `lens: act`.

**When the name fails, record the node id**, not only the coordinates. The tree
was walked for the capture on the same beat, so the id is free, and it turns
`at (312, 640)` into something a reader can look up exactly.

## The cost, and why it is affordable

Measured under `flutter_test` for the motion recorder
(`2026-08-11-scenario-motion-capture-findings.md`), phone size, 1×:

| | |
|---|---|
| `toImageSync` | returns without waiting for pixels |
| read as rawRgba | **0.24 ms/frame** |
| encode as PNG | **7.4 ms/frame** |
| pump | 2.3 ms/frame — **not paid here**, a live app produces its own frames |
| decoded size | **1.29 MB/frame** against a 100 MB image cache |

Two conclusions follow.

**The encode is affordable because of when it happens.** 7.4 ms would be
unaffordable inside a frame budget, and it is not inside one: a beat encodes
*after* its settle, when the app is idle by definition. That is the same moment
an agent step pays the same cost today.

**Memory cannot hold this; disk can.** At 1.29 MB decoded a ring of any useful
length exceeds the whole image cache. The journal is already files-not-memory
for the same reason, and disk buys the case that matters most: a replay that
survives the crash it was recorded for.

**The bound is new work, and the existing sweep is not it.** `sweepRunDir` runs
once per launch and clears what *dead* runs left behind — an age gate of a day
and a liveness check. It says nothing about a live run's own captures, which is
exactly what beats are: a long session accumulates them with nothing counting.
That this matters is already measured — 2026-08-13, **161 MB of step captures,
none of it reachable**, which is what gave the sweep its caller in the first
place. Beats need a ring *within* the run, bounded and stated, and the sweep
keeps its own separate job.

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

## Decided by the owner, 2026-08-24

**Capture is on for a run launched from the cockpit, and off elsewhere.** A run
the human started from the cockpit is an explicit enough act, and a replay that
has to be armed is a replay nobody has when they need it. The cost is one
`toImageSync` per human tap and nothing per frame.

## Open, deliberately

- **Retention.** How many beats a ring holds, and whether the bound is a count
  or bytes. A count is easier to state to a user; bytes is what actually hurts,
  and the 161 MB measurement is the argument for bytes.
- **Privacy.** This records a human's session in an app with real data. The
  frames stay on their disk and never leave it, but the retention window is a
  decision rather than a default, and it should be said out loud somewhere the
  user reads.
- **Naming quality.** `_nameFrom` finds the *first* name walking up, so an
  unlabelled icon button can be named for the card that contains it. Under the
  evidence framing this is tolerable. It should be measured on a real screen
  before it is called fine.

## Order of work

1. `HumanActions` settles and captures on pointer-up instead of buffering;
   emits a beat.
2. The beat is appended to the run journal as `actor: human`, with
   `screenshot` and `texts`, no tree.
3. Node id on the beat when `nameHit` returns null.
4. A bound on the run's own beats — a ring, counted or in bytes, stated where
   the user can see it. Separate from `sweepRunDir`, which keeps its job.
5. Steps tab: confirm human beats render as steps with no change. If they need
   one, the beat shape is wrong.
6. Measure a real session — beats per minute, bytes, and the app's own frame
   times with capture on and off.

The gate is step 6. If a human tap costs the app anything visible, the premise
change is wrong and the feature goes back to an explicit toggle.
