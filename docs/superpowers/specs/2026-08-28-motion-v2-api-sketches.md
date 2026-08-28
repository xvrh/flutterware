# Motion v2 — seven files, written to be read

**Date:** 2026-08-28
**Status:** **speculative.** None of this compiles; none of these classes exist.
Written to expose what prose could not, in the practice v1 records — *"what
looking at them changed"*. Read the files, then the findings.
**Companion to:** `2026-08-28-motion-v2-design.md`. Findings here should be
folded back into that document once reacted to.

The five cases, in order of how hard they push on the grammar:

1. a screen entrance — the baseline
2. a nested motion, retimed by its parent
3. a state machine on a slot, in both clock provenances
4. a custom value bundle — the extension point
5. a video composition
6. the edit API at depth *(second round)*
7. two motions on one screen *(second round)*
8. a motion under a state machine under a composition *(third round)*

**Fifteen findings came out of writing them, and most were not predicted.** They
are collected at the end. Findings 1, 2, 5, 11 and 12 change the design rather
than decorate it. Finding 14 is the only one that *confirmed* a prediction
instead of correcting it.

Finding 12 was an open hole when written and has since been decided — two
writers **compose like transforms**, with the operator derived from each
property's identity element. See the design document.

The second round also settled the time literal: **integer milliseconds**, and
finding 4 records the hard reason the obvious alternative was never available.

---

## First, what other formats do about the keyframe unit

v1 open question 1 asks whether the tuning unit is a `Key` (an instant) or a
`Seg` (a span). The field has an answer and it is close to unanimous.

| format | unit | where the curve lives |
|---|---|---|
| After Effects | keyframe | in/out easing per keyframe |
| Lottie | keyframe | in/out bezier handles per keyframe |
| Rive | keyframe | interpolation type + cubic points per keyframe |
| Unity `AnimationCurve` | `Keyframe` | `inTangent` / `outTangent` |
| Blender F-curve | keyframe | tangents per keyframe |
| CSS `@keyframes` | percentage block | `animation-timing-function`, outgoing edge |
| Web Animations API | keyframe | `easing` per keyframe, outgoing edge |
| **Flutter `TweenSequence`** | **segment** (`tween` + `weight`) | the tween |
| **Flutter `Interval`** | **span** (`begin`, `end`) | the curve |

Two things worth noticing.

**The world is key-shaped, and the one exception is Flutter itself.** Which is
why v1 reached for `Seg` — it was matching `Interval`, the thing next to it.
That is a weaker reason than it looked, because `Interval` is a *staggering*
mechanism for one controller, not a storage format.

**Lottie migrated.** As recorded in its schema, a keyframe carried both `s`
(start value) and `e` (end value) — segment-shaped — and `e` was deprecated in
favour of reading the next keyframe's `s`. A format that shipped the redundancy
and then removed it is the strongest single data point available. *(Worth
verifying against the current lottie-web schema before this is quoted as fact.)*

**Why the redundancy is fatal.** A segment repeats the junction value: `to` of
one is `from` of the next. Two places to edit, two places to drift, and a
validation rule to catch the drift. v1 already carries the consequence — its
**overlap rule**, *"two segments on one property with intersecting windows is an
error the editor cannot produce and the parser reports"*. With keys that rule
does not exist: a sorted list of instants cannot overlap. **A rule you delete is
worth more than a rule you enforce.**

The one thing segments state better — *"this property animates between 100ms and
400ms and is otherwise untouched"* — keys cover with v1's hold rule, which is
needed anyway. And a property that should not be touched at all is an absent
track, not an empty span.

**Recommendation: keys.** The curve lives on the key and describes how you
*arrive* at it, so the first key's curve is unused. Chosen over the outgoing
edge (CSS, WAAPI) because `Key(at: 240ms, value: 1, curve: easeOut)` reads as
one sentence — *arrive at 1 by 240ms, easing out* — where an outgoing curve
makes the last key's curve the meaningless one instead. Symmetric problem,
better-reading half.

---

## 1 — A screen entrance

The baseline. Deliberately realistic rather than minimal, because the question
this file answers is *what does the noise look like at volume*.

```dart
//@flutterware:motion=2.0
// Owned by the flutterware Motion editor, which reads and writes this whole
// file. A SOURCE OF TRUTH, not a derivative. Validate with `fw motion check`.

import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart';

class SignInMotion extends Motion {
  final duration = 820.ms;

  final title = Slot<TextValues>(
    opacity: Track<double>([
      Key(at: 0.ms, value: 0),
      Key(at: 280.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track<double>([
      Key(at: 0.ms, value: 20),
      Key(at: 280.ms, value: 0, curve: Curves.easeOutCubic),
    ]),
  );

  final subtitle = Slot<TextValues>(
    opacity: Track<double>([
      Key(at: 80.ms, value: 0),
      Key(at: 360.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track<double>([
      Key(at: 80.ms, value: 20),
      Key(at: 360.ms, value: 0, curve: Curves.easeOutCubic),
    ]),
  );

  final email = Slot<FieldValues>(
    opacity: Track<double>([
      Key(at: 160.ms, value: 0),
      Key(at: 440.ms, value: 1, curve: Curves.easeOut),
    ]),
    values: FieldValues(
      fillColor: Track<Color>([
        Key(at: 160.ms, value: Color(0xFFF2F2F7)),
        Key(at: 620.ms, value: Color(0xFFFFFFFF), curve: Curves.easeInOut),
      ]),
    ),
  );

  final cta = Slot(
    opacity: Track<double>([
      Key(at: 300.ms, value: 0),
      Key(at: 560.ms, value: 1, curve: Curves.easeOut),
    ]),
    scale: Track<double>([
      Key(at: 300.ms, value: 0.94),
      Key(at: 820.ms, value: 1, curve: Curves.easeOutBack),
    ]),
  );
}
```

**Read it for:** the ratio of syntax to information. Ten keys carry twenty
numbers, and the numbers are now the most visible thing on every line — which is
the point, because the reader of this file is always scanning for a number.

This is the **second** draft of this file. The first spelled every instant
`Duration(milliseconds: 280)`, which appeared eighteen times in sixty lines and
was louder than any value it wrapped. The owner agreed to drop it. What replaced
it, and the reason the obvious alternative is impossible, is finding 4.

Also visible, and unprompted: **the explicit type argument on `Track<double>`
is not decoration.** See finding 3.

---

## 2 — A nested motion, retimed by its parent

The card has its own entrance, authored and tunable on its own. The screen
places it and runs it at half speed.

```dart
class CardMotion extends Motion {
  final duration = 400.ms;
  final badge = Slot(
    scale: Track<double>([
      Key(at: 0.ms, value: 0.6),
      Key(at: 400.ms, value: 1, curve: Curves.easeOutBack),
    ]),
  );
  final label = Slot<TextValues>(
    opacity: Track<double>([
      Key(at: 120.ms, value: 0),
      Key(at: 400.ms, value: 1),
    ]),
  );
}

class FeedMotion extends Motion {
  final duration = 1200.ms;

  final header = Slot<TextValues>(
    opacity: Track<double>([
      Key(at: 0.ms, value: 0),
      Key(at: 240.ms, value: 1),
    ]),
  );

  // Embedded: the parent owns the clock. Placed at 200ms and run at half
  // speed, so it occupies 800ms of the parent's 1200ms and is scrubbable
  // from the parent's playhead.
  final card = Nested(
    CardMotion(),
    at: 200.ms,
    speed: 0.5,
  );
}
```

Binding into it, from the host:

```dart
MotionScope(
  motion: FeedMotion(),
  builder: (context, m) => Column(children: [
    MotionSlot(m.header, child: const Text('Recent')),

    // The extra hop. `m.card` is the placement; `m.card.inner` is the motion.
    MotionSlot(m.card.inner.badge, child: const NewBadge()),
    MotionSlot(m.card.inner.label, builder: (v) => Text('3 new', style: v.style)),
  ]),
)
```

**Read it for:** `m.card.inner.badge`. The hop is honest — placement and motion
really are two things — but it is on every read site of every nested slot, and
it gets worse at depth 3 (`m.section.inner.card.inner.badge`).

Two alternatives, neither obviously better:

```dart
// (a) placement moves out of the field; the field is just the child motion.
//     Reads as m.card.badge. But where does `at:`/`speed:` then live?
final CardMotion card;

// (b) Nested forwards by implementing a common interface. Not possible in
//     Dart without codegen, which this design has none of.
```

The `at:` + `speed:` pair is the time transform from the design doc, spelled
concretely for the first time. Worth noting it is exactly two of the three
`Sequence` parameters, and the third (`duration`, to *stretch* rather than
scale) is missing here — **stretch and speed are the same knob expressed
differently**, and only one should exist. `speed:` composes multiplicatively
under nesting; `duration:` does not. Prefer `speed:`.

---

## 3 — A state machine on a slot

The case called blurriest, and the one that broke the grammar. Both clock
provenances in one file.

```dart
/// User-declared, and it must live **in this file** — see finding 1.
enum FieldState { idle, focused, invalid }

class SearchFieldMotion extends Motion {
  final duration = 300.ms;

  final field = Slot<FieldValues>(
    machine: StateMachine<FieldState>(
      initial: FieldState.idle,

      states: {
        // A state's content is a motion on its own clock — so `idle` is a
        // looping breathe, and nesting is what makes it expressible.
        FieldState.idle: StateDef(
          content: Nested(BreatheMotion(), loop: true),
        ),
        FieldState.focused: StateDef(
          content: Pose(
            values: FieldValues(fillColor: Color(0xFFFFFFFF)),
            elevation: 2,
          ),
        ),
        FieldState.invalid: StateDef(
          content: Pose(
            values: FieldValues(fillColor: Color(0xFFFFEBEE)),
          ),
        ),
      },

      transitions: {
        // Records as map keys. The pair reads as from → to.
        (FieldState.idle, FieldState.focused): Transit(
          duration: 180.ms,
          curve: Curves.easeOut,
          // Trigger: the child owns the clock. Fires on a real event, is not
          // on anybody's timeline, and is drawn as a marker not a span.
          clock: Clock.own,
        ),
        (FieldState.focused, FieldState.idle): Transit(
          duration: 240.ms,
          curve: Curves.easeIn,
          clock: Clock.own,
        ),
        // Rate-governed: fires on an event, but runs at the rate the parent
        // dictates — so a 0.5x demo recording slows it too.
        (FieldState.any, FieldState.invalid): Transit(
          duration: 120.ms,
          curve: Curves.easeOut,
          clock: Clock.inheritedRate,
        ),
      },
    ),
  );

}
```

And the embedded case, where the parent schedules the state change and can
therefore put it on its own timeline:

```dart
class CheckoutMotion extends Motion {
  final duration = 2400.ms;

  final button = Slot<ButtonValues>(
    machine: StateMachine<PayState>(
      initial: PayState.ready,
      states: { /* … */ },
      transitions: { /* … */ },
      // Embedded: the parent knows *when*, so the machine is a schedule and
      // the whole thing is a pure function of the parent's t.
      schedule: [
        At(400, PayState.pending),
        At(1800, PayState.done),
      ],
    ),
  );

}
```

**Read it for:** whether `transitions:` keyed by a record survives. It is const,
it is typed, and `(from, to)` reads correctly — but a real machine has
guards, priorities and multiple edges between one pair, and none of that fits a
map key.

**And read it for the thing that nearly did not fit at all:** see finding 1.

---

## 4 — A custom value bundle

Hand-written by the project, in the project's own file. The generated motion
file instantiates it.

```dart
// lib/charts/chart_values.dart — YOURS. The tool never writes here.
class ChartValues extends SlotValues {
  ChartValues({Track<double>? barScale, Track<Color>? accent,
               Track<double>? gridOpacity})
      : barScale = barScale ?? Track.empty(),
        accent = accent ?? Track.empty(),
        gridOpacity = gridOpacity ?? Track.empty();

  // Never null — an unanimated property is an empty track. See finding 5.
  final Track<double> barScale;
  final Track<Color> accent;
  final Track<double> gridOpacity;
}
```

```dart
// lib/charts/revenue.motion.dart — the tool's.
import 'chart_values.dart';

class RevenueMotion extends Motion {
  final duration = 900.ms;
  final chart = Slot<ChartValues>(
    opacity: Track<double>([
      Key(at: 0.ms, value: 0),
      Key(at: 200.ms, value: 1),
    ]),
    values: ChartValues(
      barScale: Track<double>([
        Key(at: 200.ms, value: 0),
        Key(at: 900.ms, value: 1, curve: Curves.easeOutCubic),
      ]),
      accent: Track<Color>([
        Key(at: 200.ms, value: Color(0xFF8E8E93)),
        Key(at: 900.ms, value: Color(0xFF0A84FF)),
      ]),
  );
    ),

}
```

Read site:

```dart
MotionSlot(m.chart, builder: (v) => BarChart(
  scale: v.barScale,
  accent: v.accent,
  gridOpacity: v.gridOpacity,
))
```

**Read it for:** the dependency direction. **The generated file imports yours.**
A rename in `ChartValues` breaks the generated file — loudly, which is the
design's stated preference, but it is the first time the tool's file depends on
a file the tool cannot fix.

---

## 5 — A video composition

Written last, and it came out looking nothing like the other four. That is the
finding, not an accident of style.

```dart
// tool/films/release_notes.dart — YOURS. Ordinary Dart, no grammar.
Composition releaseNotes(ScenarioRun run) {
  final steps = run.steps.where((s) => s.named).toList();

  return Composition(
    fps: 30,
    size: const Size(1920, 1080),
    children: [
      Sequence(
        from: 0.ms,
        duration: 1400.ms,
        child: MotionClip(TitleCardMotion()),
      ),

      // The reason this file cannot be in the grammar: the number of segments
      // is not known until a scenario run is in hand.
      for (final (i, step) in steps.indexed)
        Sequence(
          from: 1400 + _offsetOf(steps, i),
          duration: step.durationMs + 600,
          child: PhoneRig(
            // Tuned in the editor, and the only part that is model.
            motion: PhoneShowcaseMotion(),
            // Slot injection: the glass is a texture, fed by anything.
            screen: ScenarioClip(run, step: step.name),
            caption: step.label,
          ),
        ),

      AudioClip(
        const AssetSource('audio/bed.m4a'),
        from: 0.ms,
        volume: Track<double>([
          Key(at: 0.ms, value: 0),
          Key(at: 800.ms, value: 0.4),
        ]),
      ),
    ],
  );
}
```

**Read it for:** the `for` in the middle. It is ordinary Dart and it has to be.

---

## 6 — The edit API at depth

Written second-round, at the owner's request, because the first five files never
exercised it past one level.

```dart
// Retune a nested motion, its placement, and a key inside it.
final calmer = FeedMotion().edit((d) {
  d.duration = 1400.ms;

  d.header.opacity.last.curve = Curves.easeInOutCubic;

  // The placement — the parent's time transform over the child.
  d.card.at = 300.ms;
  d.card.speed = 0.75;

  // Into the child. Three hops before the property.
  d.card.inner.badge.scale.last.value = 1.05;
  d.card.inner.label.opacity.insert(at: 200.ms, value: 0.5);
});

// Whole-track and whole-slot operations, which are what retiming actually needs.
final slowIntro = SignInMotion().edit((d) {
  d.title.shiftBy(80.ms);              // every track on the slot
  d.subtitle.shiftBy(80.ms);
  d.email.opacity.scaleBy(1.5);     // one track
  d.cta.scale.last.curve = Curves.easeOutCubic;
});

// A custom bundle edits exactly like a framework one.
final muted = RevenueMotion().edit((d) {
  d.chart.values.accent.last.value = const Color(0xFF48484A);
  d.chart.values.barScale.scaleBy(0.6);
});

// A state machine. Note the method rather than a map lookup — see finding 6.
final snappier = SearchFieldMotion().edit((d) {
  d.field.machine.transit(FieldState.idle, FieldState.focused).duration = 120.ms;
  d.field.machine.state(FieldState.invalid).content.values.fillColor =
      const Color(0xFFFFCDD2);
});
```

**Read it for:** three things, all of which turned out to be design questions
rather than syntax questions.

**Nullability.** `Slot.opacity` is a `Track<double>?` in the model — a slot need
not animate opacity. In an edit API that would read
`d.header.opacity!.last.curve = …`, with a `!` on nearly every line, and a crash
whenever you tune something not yet animated. Nothing above has a `!`, and
finding 5 is why.

**Depth.** `d.card.inner.badge.scale.last.value` is five hops, and the `inner`
is the papercut already noted on the read side, now compounding on the write
side too.

**The ceiling.** Every line above *retunes*. Not one *restructures* — no line
adds a slot, because a slot is a field on a class and only the editor (which
writes the file) can add one. That asymmetry is not a limitation to fix; see
finding 7.

---

## 7 — Two motions on one screen

```dart
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Motion A — the screen's entrance, played once on mount.
      MotionScope(
        motion: HeaderMotion(),
        builder: (context, m) => Column(children: [
          MotionSlot(m.avatar, child: const Avatar()),
          MotionSlot(m.name, builder: (v) => Text('Ada', style: v.style)),
        ]),
      ),

      // Motion B — a state machine, live for the life of the screen. Different
      // class, so `m.name` above and `m.name` below cannot collide.
      MotionScope(
        motion: FollowButtonMotion(),
        builder: (context, m) => MotionSlot(m.button, child: const FollowButton()),
      ),

      // Three instances of ONE motion class. Each owns its own playhead.
      for (final post in posts)
        MotionScope(
          motion: CardMotion(),
          id: 'post-${post.id}',          // <- see finding 8
          builder: (context, m) => MotionSlot(m.badge, child: PostBadge(post)),
        ),
    ]);
  }
}
```

And the case that has no answer yet — two motions writing the same property of
the same widget:

```dart
// A's entrance scales the button from 0.94 to 1.
// B's `pressed` state scales it to 0.96.
// Both are live at t = 500ms, and both write `scale`.
MotionSlot(entrance.cta, child: MotionSlot(press.button, child: const FollowButton()))
```

**Read it for:** what does *not* break, and the one thing that does.

**Slot identity does not collide, and that is a dividend of the typing
decision.** `HeaderMotion.name` and `FollowButtonMotion.name` are different
symbols on different classes. Under v1's string identity they would both have
been `'name'` in a shared registry, and keeping them apart would have needed a
scoping rule. There is no rule to write.

**Instance identity is a separate problem and it is real.** Three `CardMotion`s
on one screen are three scopes, each with its own playhead — v1 settled that
(*"because the scope owns the instance, list items each get their own playhead
automatically"*). But the *editor* drives one scope through
`MotionRegistry`, and `seekMotion` takes an id. With three instances of one
class, the class name is not an id. See finding 8.

**Composition of two live motions over one widget has no rule**, and it is the
sharpest thing this file found. See finding 9.

## 8 — A motion, under a state machine, under a composition

Depth 3 across all three mechanisms at once. Written third-round, and it found
more than the previous two combined — including one thing that makes an "edge
case" the normal case.

```dart
// ---------- phone_rig.motion.dart — the tool's ----------

/// Owned by the tool. The composition below imports this file to name its
/// values, which is user-code-imports-generated-code and the safe direction.
enum RigState { presenting, zoomed, leaving }

class PhoneRigMotion extends Motion {
  final duration = 2000.ms;

  // A MOTION-LEVEL machine: its states span several slots, so each state's
  // content is a whole motion. See finding 11.
  final machine = StateMachine<RigState>(
    initial: RigState.presenting,
    states: {
      RigState.presenting: StateDef(content: PresentingMotion(), loop: true),
      RigState.zoomed: StateDef(content: ZoomedMotion()),
      RigState.leaving: StateDef(content: LeavingMotion()),
    },
    transitions: {
      (RigState.presenting, RigState.zoomed):
          Transit(duration: 420.ms, curve: Curves.easeInOutCubic),
      (RigState.zoomed, RigState.presenting):
          Transit(duration: 300.ms, curve: Curves.easeInOut),
      (RigState.any, RigState.leaving):
          Transit(duration: 240.ms, curve: Curves.easeIn),
    },
    // No `schedule:` — this motion does not know when the states change.
    // The composition supplies it. See finding 10.
  );

  // Tracks AND a slot-level machine on ONE slot. Both write `translateY`.
  // See finding 12 — this is the collision, and it is not an edge case.
  final caption = Slot<TextValues>(
    opacity: Track<double>([
      Key(at: 300.ms, value: 0),
      Key(at: 700.ms, value: 1, curve: Curves.easeOut),
    ]),
    translateY: Track<double>([
      Key(at: 300.ms, value: 12),
      Key(at: 700.ms, value: 0, curve: Curves.easeOut),
    ]),
    // A SLOT-LEVEL machine: content is a property bag, not a motion, because
    // it can only ever animate the slot it is attached to.
    machine: StateMachine<CaptionState>(
      initial: CaptionState.resting,
      states: {
        CaptionState.resting: StateDef.properties(),
        CaptionState.nudging: StateDef.properties(
          loop: true,
          translateY: Track<double>([
            Key(at: 0.ms, value: 0),
            Key(at: 900.ms, value: -3, curve: Curves.easeInOut),
            Key(at: 1800.ms, value: 0, curve: Curves.easeInOut),
          ]),
        ),
      },
      transitions: {
        (CaptionState.any, CaptionState.nudging):
            Transit(duration: 200.ms, curve: Curves.easeOut),
      },
    ),
  );

  // The glass. The rig only frames it; the content is injected.
  final screen = Slot<ScreenValues>(
    opacity: Track<double>([
      Key(at: 200.ms, value: 0),
      Key(at: 500.ms, value: 1),
    ]),
  );
}

// One state's content. An ordinary motion, with slots of its own.
class PresentingMotion extends Motion {
  final duration = 3200.ms;

  final device = Slot(
    translateY: Track<double>([
      Key(at: 0.ms, value: 0),
      Key(at: 1600.ms, value: -8, curve: Curves.easeInOut),
      Key(at: 3200.ms, value: 0, curve: Curves.easeInOut),
    ]),
  );

  final glow = Slot(
    opacity: Track<double>([
      Key(at: 0.ms, value: 0.4),
      Key(at: 1600.ms, value: 0.7, curve: Curves.easeInOut),
      Key(at: 3200.ms, value: 0.4, curve: Curves.easeInOut),
    ]),
  );
}
```

```dart
// ---------- tool/films/product_demo.dart — YOURS. Ordinary Dart. ----------

import '../lib/rig/phone_rig.motion.dart';   // for RigState and the motion

Composition productDemo(ScenarioRun run) {
  final steps = run.steps.where((s) => s.named).toList();
  var cursor = 1400.ms;

  return Composition(
    fps: 30,
    size: const Size(1920, 1080),
    children: [
      for (final (i, step) in steps.indexed)
        () {
          final rig = PhoneRigMotion();
          final span = step.duration + 900.ms;

          // The composition owns the schedule the model deliberately omitted.
          rig.machine.schedule([
            At(0.ms, RigState.presenting),
            if (step.zoom) At(step.duration * 0.3, RigState.zoomed),
            At(span - 240.ms, RigState.leaving),
          ]);

          // A local relieves the `inner` hop — possible here, impossible in a
          // motion file. See finding 13.
          final presenting = rig.machine.content(RigState.presenting);

          final sequence = Sequence(
            from: cursor,
            duration: span,
            // The composition knows the target length; the motion knows its
            // natural one. See finding 15.
            fit: TimeFit.speed,
            child: MotionClip(
              rig,
              bind: (b) {
                b.screen.widget = (v) => ScenarioTexture(run, step: step.name);
                b.caption.widget = (v) => Text(step.label, style: v.style);
                b.of(presenting).glow.widget = (v) => DeviceGlow(v.opacity);
              },
            ),
          );

          cursor += span;
          return sequence;
        }(),
    ],
  );
}
```

**Read it for:** the immediately-invoked closure in the `for`. It is there
because a composition needs *statements* — a cursor, a local, a computed span —
and a collection-`for` gives it only an expression. That is ordinary Dart being
strained, not the design failing, but it is ugly and a plain `for` loop building
a list would read better. Worth noting the grammar's absence is felt here as
*freedom*, exactly where finding 2 said it would be.

---
## Measured — the stagger, written and run 2026-08-28

Everything above is speculative Dart. This is not: `app/tool/catalog/demos/motion_inbox.dart`
and its `.motion.dart` are in the tree, they run on the **v1** runtime, and the
filmstrip renders. Written because `motion_receipt.dart` names this shape and
refuses it — *"a stagger of four identical rows is four copies of the same
numbers, and is a thing to generate, not a thing to hand-write."* The refusal was
right; the cost of being right is now a number.

| | |
|---|---|
| the values file | 185 lines, 17 `Seg`s, **15 of them one animation copy-pasted** |
| the build method | says the stagger **once**, in a `for` loop |
| what the scan found | **1 target of 6** |

Two things this settles with evidence rather than argument.

**The scan cannot judge.** The panel's own diagnostic: *"target name is not a
string literal, so it cannot be listed without running the file."* Five of six
targets vanish. The known weakness — *computed names in loops* — is not a corner
case waiting in week three; it fires on the second animation anybody writes. The
owner rejected scanning as the basis for `dead` before seeing this, and the
design document's *the scan offers, the run judges* is now measured rather than
asserted.

**Nesting is what the repetition costs.** The build method has a loop and the
values file has none, so the same three lanes are written five times with one
number changed. One `RowMotion` placed five times at offsets is roughly **30
lines against 185**. Nesting had been agreed on the grounds that it is cheap now
and expensive later; this is the first argument for it that does not depend on
the video half at all.

A third, smaller: **a `Seg` is 7 lines where a `Key` pair is 4.** The keys
decision was argued from a survey of other formats; here it is 40% of a real
file.

### Three more, written and run the same day

`motion_ambient`, `motion_toast` and `motion_signin`, chosen to stress claims
that were still assertions. All three play on the v1 runtime.

**A loop plays; the format just cannot say it loops.** `MotionController.repeat()`
drives the same `evaluate(t)` and a loop is a playhead that wraps, so
`lib/motion.dart`'s *"designed choreography of a fixed duration"* is a statement
about the file format, not the runtime. What the file cannot do is **close**:
every round trip is two `Seg`s (out and back, because a `Seg` carries `from` and
`to`), and the seam at `t = 1 → 0` is six hand-held values that nothing checks.
Change one `to:` by 0.02 and the loop ticks once a cycle, forever.

And the tooling cannot help: **a filmstrip structurally cannot show a loop
seam**, because the seam falls between the last frame and the first — the one
pair a contact sheet never places side by side. Worth stating in the docs before
someone trusts a strip to check a loop.

**One playhead is enough for enter *and* exit.** The toast arrives, waits and
leaves on a single `t ∈ [0,1]`; each lane is simply two segments with a gap. No
second controller, no reversed direction. That closes a question the design had
never stressed.

**But the dwell is not written anywhere.** The 1580ms the toast spends on screen
is the *distance between* two segments, spelled six times across three lanes plus
`duration`. Keeping it up for three seconds instead of two is a seven-number
edit, and getting one wrong is a toast that fades while it is still sliding.
This is *"a hold has no shape, so it should not be authored"* — the argument made
for the phone rig — arriving in the most ordinary in-app animation there is.
The demo had to grow a draining progress bar before the dwell was visible at all,
and **five of its seven filmstrip frames are the hold.**

**Real widgets bind, and the two tiers are visible.** `motion_signin` animates
working `TextFormField`s — focusable and typeable mid-flight. `opacity`,
`translateY`, `scale` and `elevation` are imposed by wrappers and the field never
learns it was animated; `color` only lands because the build method reaches in
and hands it to an `InputDecoration`.

`password.color` is animated and deliberately **not** read. It runs, the panel
lists it beside `email.color`, and it changes nothing on screen. **Two lanes that
look identical in every static view, one of which does nothing** — which is the
whole case for judging by running, built on purpose so it can be pointed at.

## Findings

### 1. A state machine needs a user-declared enum, in the tool's own file

**Not predicted, and it is the one that nearly broke the grammar.**

A machine's transitions must name two states. If states were fields, a
transition would have to reference `this.idle` from inside another default
argument — **which Dart does not allow**, and which is variant 2's
chicken-and-egg returning in a new place. Naming states with strings would work
and would give up the typing decision that round three settled.

An **enum** is the only spelling that is const, typed, and referenceable from a
sibling default argument. Records as map keys (Dart 3) then carry the edge.

The consequence is a constraint on where it lives: parse-never-resolve means the
editor can only enumerate an enum it can *see*, so **the state enum must be
declared in the tool-owned file** — the first time the grammar has to contain a
declaration that is not the motion class itself. Whether the tool can safely own
a type the user's own code imports is unexamined and is the sharpest open
question this exercise produced.

### 2. The composition is code, not model — and that is the right line

File 5 needs `for`, because cardinality comes from a scenario run. A loop is
tier 3 and is banned. So the composition **cannot** be in the grammar, and the
choice is between admitting a `Repeat(over:, template:)` primitive — the first
step down the slide toward tier 3 — or accepting that the composition is
ordinary Dart.

Accept it. It is where round two already put the line, and this is the same line
arriving from the other side:

> **The studio owns shape. The program owns schedule.**

Motion files are model, tuned in the editor, in the grammar. **Compositions are
programs**, hand-written, and the editor reads them at most to *display* a
resolved schedule — never to write. That also explains why the studio scrubs a
resolved schedule with locked spans: the spans are locked because they are
someone else's code.

This makes files 1–4 and file 5 two different artefact kinds, and the design
document currently implies they are one. **It should be corrected.**

### 3. Write the type argument on every `Track`

`Track<double>([…])` rather than `Track([…])`. Unprompted, and it earns its
noise: with the type argument present, the parser knows a track's value type
**without resolving anything**, including inside a custom bundle whose class it
has never seen. Without it, the editor cannot tell a `Track` of doubles from a
`Track` of colors in file 4 and cannot offer the right property editor.

A one-token syntax decision that keeps parse-never-resolve viable at the exact
place it was going to fail.

### 4. Dropping `const` is what makes the syntax affordable

The first draft spelled every instant `Duration(milliseconds: 280)` — eighteen
times in sixty lines, louder than any value it wrapped. The obvious fix is a
`.ms` extension, and v1 had rejected that as a house dialect that "buys nothing".

**The stylistic objection was never the binding one.** An extension getter is a
method invocation, a method invocation is not a constant expression, and
**default parameter values in Dart must be constant expressions**. So
`const Key(at: 280.ms)` does not compile, and neither does any non-const value
in a constructor default. Const and constructor-defaults are one package.

That makes the fork structural rather than aesthetic:

| | const + constructor defaults | **field initializers, no const** |
|---|---|---|
| `.ms` and any other computed literal | impossible | fine |
| each field is declared | **twice** — parameter and field | once, type inferred |
| tweak by constructor argument | works | gone |
| two identical instances | **the same object** | separate trees |
| a bad edit that slips the parser | fails to compile | **compiles** |

**Taken: field initializers.** Decided by the owner — *"const may sound good but
we know the syntax is very limited and I don't want to paint us in a corner for
nothing."* The saving is bigger than `.ms` alone, because the duplicate field
declaration goes with it; file 1 lost about a third of its lines before the time
literals saved anything.

Two consequences worth stating rather than discovering:

- **The edit story inverts, and improves.** Two `const SignInMotion()` are the
  same object, so mutation is unsafe and the design needed immutable-model plus
  mutable-draft. Non-const, every instance is a fresh tree nobody shares, so
  **in-place mutation is safe** and the two concepts collapse into one. What is
  lost is tweak-by-argument, which only ever worked on top-level fields anyway;
  `edit()` becomes the only door.
- **`const` was an accidental second enforcement mechanism.** Today a construct
  that slips past the parser still fails to compile because it is not const.
  Without it **the grammar has to do all the limiting itself**, and a bad hand
  edit compiles cleanly into a file the editor cannot read. That is the argument
  for `fw motion check` running in **CI**, not as a convenience.

### 5. Tracks must be non-nullable and possibly empty

Forced by file 6, and it fixes a problem in two places at once.

If the model's tracks are nullable, the edit API needs a `!` on nearly every
line. The obvious fix — a draft type whose accessors auto-vivify — costs a
**parallel type hierarchy**: every model class needs a hand-written draft
counterpart, and since this design has no codegen, **a project defining a custom
bundle would have to write `ChartValuesDraft` too.** That is a large tax on the
extension point that round four had just made cheap.

The way out is to remove the nullability instead:

> **A track is never null. An unanimated property is an empty track**
> (`Track.empty()`). A draft is then a mutable copy of
> the same shape, with no vivification and no parallel hierarchy.

And it does **not** collide with v1's read-site rule that no-identity properties
return nullable, because those are different nulls: *the track is empty* is a
storage fact, *the evaluated value is absent* is a read-time fact. A property
with an empty track evaluates to `null` and `?? Colors.white` still works.

### 6. A record-keyed map is good storage and bad editing

`transitions: {(FieldState.idle, FieldState.focused): Transit(…)}` is const,
typed and reads correctly as storage. As an edit target it is
`d.…transitions[(FieldState.idle, FieldState.focused)]!.duration = 120` — a
record literal in a subscript, plus a `!` because map lookup is nullable, plus
no way to add an edge that does not exist yet.

The draft should expose a **method that finds or creates**:
`d.field.machine.transit(FieldState.idle, FieldState.focused).duration = 120`.

The general rule, which probably applies beyond this one case: **storage shape
and edit shape are allowed to differ**, and the draft is where they are allowed
to differ.

### 7. The edit API retunes; it cannot restructure — and that is the same line

No line in file 6 adds a slot, because a slot is a field on a class and only the
thing that writes the file can add a field. This is not a gap:

> **The editor owns what and whether. The edit API owns when and how much.**

Which is round two's line — *the studio owns shape, the program owns schedule* —
arriving a third time, now between the file writer and the runtime. Three
independent arrivals at one boundary is worth trusting.

### 8. `MotionScope` needs an explicit id, and the class name cannot be it

Three `CardMotion`s on one screen are three registry entries, and the editor's
`seekMotion` addresses one. v1's registry keys by id and its demos had one scope
each, so the question never came up.

`id:` on `MotionScope` is the obvious answer and it reintroduces a **string** —
in the one place the typing decision cannot reach, because the identities are
created by a runtime loop over data. That is acceptable (it names an *instance*,
not a *property*) but it should be a deliberate exception rather than an
oversight, and the panel needs to show three addressable rows rather than one.

### 9. Two live motions over one widget have no composition rule

The sharpest open thing here. An entrance motion scales a button from 0.94 to 1
while a press state machine scales it to 0.96. Both are live. Both write
`scale`. Nothing in the design says what happens.

Three candidate rules, none chosen:

- **Compose like transforms** — multiply scale and opacity, add translate and
  rotate. Correct for the cases anyone would draw, and it is what the game
  systems' additive layers do. Costs a per-property composition rule in the
  framework.
- **Last writer wins** — trivial, and produces a snap the first time two
  motions overlap.
- **Forbid overlap** — refuse at bind time. Safe, loud, and rules out the
  entrance-plus-hover case that is the whole reason anyone wants a state machine
  on a slot.

The first is almost certainly right, and the design document currently promises
additive layers *for the video half only* while this is an in-app case. **It is
one mechanism and should be decided once.**

### 10. Schedule provenance — the fourth one

An embedded machine needs a schedule: *presenting at 0, zoomed at 30%, leaving
at the end.* In a fixed motion that schedule can be authored in the model. **In
a composition it cannot**, because the timing derives from a scenario step's
duration, which is not known until a run is in hand.

So a machine's schedule has two sources — authored in the model, or supplied by
the program at resolve time. Which is the **fourth provenance**, after child,
box and clock:

> A motion declares what it needs; a host provides it; **which** host provides
> it is settled at bind or resolve time.

Four independent arrivals at one shape. At this point it is not a pattern in the
design, it *is* the design, and it should be named once in the framework rather
than re-derived per feature.

### 11. A state machine needs two scopes, and its content type differs at each

**Not predicted, and it nearly broke the state design.**

The doc says a machine is per-slot, for a good reason: a screen does not have one
state, the card and the button are in different ones. But a real state usually
spans slots — *presenting* moves the device **and** the glow **and** the caption
together. A per-slot machine cannot express that.

And the reverse fails too. Round five justified nesting with *"a state is a
motion"*. But if a machine sits on a slot, its state's content can only animate
**that slot**, so a content-motion's own slots have nowhere to map. The
justification and the placement contradict each other.

Both are true at different scopes:

| machine sits on | a state's content is | animates |
|---|---|---|
| **the motion** | a whole `Motion`, with slots | several slots at once |
| **a slot** | a property bag (`StateDef.properties(…)`) | that slot only |

Same idea, two scopes, two content types. *"A state is a motion"* holds at the
motion level and is false at the slot level, and the design document currently
asserts it without qualification.

### 12. The two-writers collision is the normal case, not an edge case

The design document frames the missing composition rule as *two motions over one
widget* — which sounds rare. File 8 shows it is not.

`caption` has a `translateY` **track** (the entrance, 12→0) and a slot-level
**machine** whose `nudging` state also writes `translateY`. One slot, one motion,
two writers, and this is the ordinary way anyone would author *"slide in, then
idle with a nudge"*.

**Any slot carrying both tracks and a machine has two writers, always.** So the
rule is not an edge case to defer: it is load-bearing for the most obvious thing
a state machine is for. Compose-like-transforms — multiply `scale` and
`opacity`, add `translate` and `rotate` — is almost certainly the answer, and it
reads correctly here: the entrance lands the caption at 0 and the nudge adds ±3
around it.

**This raises open question 12 from "decide eventually" to "decide before the
state system is designed at all."**

### 13. The `inner` papercut is an artefact-kind problem

Predicted to get worse at depth 3. It did not, and the reason is instructive:
**a composition is ordinary Dart, so a local variable relieves it.**

```dart
final presenting = rig.machine.content(RigState.presenting);
… b.of(presenting).glow.widget = …
```

In a **motion file** that move is unavailable — the grammar has no statements,
so no locals, and every reference is written out in full from the root. So the
papercut is not "deep paths are bad", it is **"deep paths in a grammar with no
locals are bad"**, and it is bounded to one artefact kind.

That also suggests the mitigation is not a shorter API but a grammar item:
permitting a `final` local at the top of the motion class, referenceable by
later fields. Whether that is worth the widening is untested.

### 14. Loops are seekable in embedded mode, which confirms rather than breaks

A looping state content (`presenting`, 3200ms, `loop: true`) has no end. Seeking
the film to an arbitrary frame still resolves it: phase is
`((t − stateEntry) / loopDuration) % 1`, and `stateEntry` **is** resolved in
embedded mode. So a loop under a seek is fine, and it is fine for exactly the
reason clock provenance predicted — the parent knows when the state started.

In trigger mode `stateEntry` is a wall-clock fact and the same expression is
unresolvable. The two modes were argued from a different case and hold here
unchanged, which is the first time anything in these sketches has confirmed a
prediction rather than corrected one.

### 15. `Sequence` needs a fit policy, not just a speed

The design chose `speed:` over `duration:` because speed composes
multiplicatively under nesting. But a composition knows the **target** length (a
step's duration plus padding) while the motion knows its **natural** one, so the
call site would have to compute `speed = natural / target` by hand every time.

Wanted: a `fit:` policy on `Sequence` — `TimeFit.speed` (scale to fill),
`TimeFit.hold` (play at natural rate, hold the last frame), `TimeFit.clip`
(play at natural rate, cut). Speed stays the *storage*; fit is how a caller asks
for it without arithmetic.

### Two smaller things

- **`speed:` not `duration:` for a nested motion's time transform.** They are
  the same knob, and only `speed:` composes multiplicatively under nesting.
- **`m.card.inner.badge` is a papercut that compounds at depth.** No good fix
  found: dropping the wrapper leaves nowhere for `at:`/`speed:`, and forwarding
  needs codegen this design does not have.

## What these files did not test

Honest list, so nobody mistakes this for coverage:

- Anything about **how the editor renders** any of this — including how a panel
  shows three addressable instances of one motion (finding 8).
- **A motion under a state machine under a composition** — depth 3 across all
  three mechanisms at once, which is where the `inner` papercut and the
  composition rule (finding 9) would meet.
- **Removing** things: no sketch deletes a key, a state or a transition, and
  deletion is where an editor's structural edits usually go wrong.
- The **failure UX** — what a refused hand edit actually looks like, which is
  still the thing the round-trip spike exists to find.
- Whether `StateDef` / `Pose` / `Transit` are three things or one.
- The **stage file** from the draft-getter correction, which is unwritten.
