# Validating the scene model against one real onboarding flow

Built 2026-08-28. The question was not "can Flutter do this" — it obviously can
— but **can it be done under the constraints a scene tool would impose**, and
does the result survive translation, resize and a live widget.

The artifact is `app/tool/catalog/demos/onboarding.dart` and the three files it
composes. No editor was built, deliberately: if the hand-written thing is not
good, no editor rescues it.

## The rules it was written under

- A small widget vocabulary: text, image, box, row/column/stack, spacer, clip.
- **Flex layout only.** No `Positioned`, no hard-coded x/y. `Align` with a
  fractional alignment is the strongest positioning used.
- **Animation only through the values files.** No `AnimationController`, no
  `Tween`, no `Interval` computed by hand.
- Every varying value is a target property or a prop.

The unit of authorship is a **component with props**, not a screen.
`OnboardingPage` is what an editor would author; `onboarding.dart` is what a
person writes to use it. Content — images, strings, the control at the bottom —
is handed in at the use site and never owned by the tool.

## What held

**`evaluate(t)` paid for itself twice.** Every page's entrance is driven by the
`PageView`'s own offset: the current page sits at `t = 1`, its neighbours at
`t = 0`, and a swipe scrubs between them. Nothing calls `play()`. The same
component would render to video by writing a frame counter into the same input,
with no second code path — which is the whole argument for the law.

**A real widget survives the animation.** `app/test/motion/onboarding_binding_test.dart`
asserts that a `TextFormField` at `progress: 0.4` — translated, scaled and
half-transparent — still takes focus, still receives text, and still runs its
validator. This is the thing Lottie and Rive structurally cannot do.

**Transform-only animation keeps layout invariant.** The same test asserts the
headline's box is identical at `t = 0.15` and `t = 1`, though its halves are
120px apart at the start. That is not a nicety: it is what makes auto-fit safe,
because the fit is computed once and the text does not breathe through its own
entrance.

**Nesting works, and reuse follows.** The fuse is a component with two string
props and its own timeline in its own file, driven by whatever progress its host
hands it. The page neither knows nor sets its timing.

**Percentage units survive resize.** The wave's amplitude is a fraction of the
image height, so it scales correctly from a phone to an iPad.

## The headline is a pass, not an entrance

Revised after looking at the first filmstrip. The two lines sit on **different
rows**, travel in opposite directions, cross, decelerate into a settled reading
moment at the middle of the timeline, then continue the way they were already
going and re-accelerate off the page.

Three consequences, all of them improvements:

- **The `Row` overflow dissolves.** Each line lays out on its own, so a long
  German line shrinks or wraps without the other one caring. The fix below is
  still needed per line, but the structural problem is gone.
- **The host hands in a signed position, not a progress.** `-1` is still to
  come, `0` is the settled frame, `+1` is already gone. An unsigned progress
  cannot tell arriving from leaving, and the sign is exactly what tells a line
  which way it is already travelling.
- **A component wants more than one continuous input.** The page's entrance
  reads presence (`0..1`, peaks when current); the headline reads position
  (`-1..1`). Same gesture, two derived numbers, because they answer different
  questions.

## What broke

**German overflowed by 35 pixels**, with Flutter's yellow stripe — a hard
failure, not a graceful degrade.

The cause is worth stating precisely, because it is a tension rather than a bug:
two halves that fuse must be laid out side by side, side by side means a `Row`,
and **a `Row` cannot wrap**. Taking two strings solved translation for *content*
— a translator sees two entries and chooses word order — and broke it for
*layout*.

Fixed with auto-fit (`BoxFit.scaleDown`), which is a presentation policy the
tool must own rather than something a caller should think about. So: **a text
element in a scene needs a fit policy — max lines, min scale — as a first-class
property.**

**The tablet held but looked wrong.** Nothing overflowed; the composition simply
does not adapt. 38px type and a full-width button are right on a phone and wrong
on a 1620px canvas. **Flex layout survives resize; it does not respond to it.**
Responsive means breakpoint variants, not just flexible boxes, and no amount of
constraint-based layout substitutes.

## The gap list

Ranked, after the build rather than before it.

1. **The vocabulary is a closed global set of 16 property names**, and it breaks
   the moment elements have kinds. A parametric wave needs `amplitude`, `phase`
   and `frequency`; there is only one unnamed `progress` per target, so one
   shape is spelled here as two targets whose names mean nothing to the model,
   with the third parameter hard-coded. **Elements need per-type property
   schemas** — which is the same mechanism as registering an external widget
   with its editable properties. The registration feature is not only for user
   widgets; the built-ins need it too.
2. **Text needs a fit policy.** See German, above.
3. **Responsive variants.** Breakpoints, not just flex.
4. **Parametric shapes are a required primitive.** The wave is the first element
   in the design that is not a widget at all, and it is better as parameters
   than as bezier control points: "animate as we move to the next screen" is two
   number drags on a parametric shape and a keyframe per node on a path. Do not
   build a vector editor.
5. **Units are unlabelled rather than missing.** A fraction can be resolved at
   the read site today, but the editor would show `0.085` with no unit and no
   hint that the author meant "8.5% of the height". Resolving one also needs the
   box, so anything unit-aware sits under a `LayoutBuilder` the tool would have
   to insert.
6. **Nesting has no declared time window.** The page maps its first 80% onto the
   fuse in Dart, so that mapping cannot be dragged in an editor. A real nested
   motion declares the window in the parent's values file.
7. **Nesting multiplies scopes.** Three pages plus three fuses is six mounted
   `MotionScope`s. The guest resolves a scope only when exactly one is mounted,
   and the panel's model is "pick one" — which will not survive nesting.
8. **Computed target names stay invisible to the scan.** The two glow layers
   are reached through `for (var layer in const ['glowB', 'glowA'])`, so
   `motion list` reports this component's targets as `left` and `right` only.
   The same hole as `m.target('row$i')`, met again in ordinary code rather than
   in a demo written to provoke it.
9. **Interactivity must follow visibility.** `Opacity(opacity: 0)` still
   hit-tests, so an invisible element eats taps. Easy to fix, impossible to
   remember, therefore must be automatic.

## A capture rendered a stale guest — found, diagnosed, fixed

Found while re-shooting the revised fuse. The values file changed from 900ms to
1000ms and a whole second segment was added; the strip came back byte-identical
and still reported `durationMs: 900`. Deleting the cached PNG changed nothing,
and it stayed stale across repeated calls, so it was neither an artifact cache
nor a race.

What made it diagnosable: **`motion list` updated in the same call.** The listing
reported the motion's new line number from a fresh syntactic scan while the
picture showed the previous version. Half the panel current, half a version
behind, with nothing saying so.

The cause is an interaction between two correct-looking pieces:

- `ResidentCompiler` starts `frontend_server` with `--initialize-from-dill`, so
  the first compile begins from a kernel an *earlier session* wrote. Its doc
  claimed the compiler "recompiles only what has changed since" and that "an
  edited demo still comes back edited". Neither is true.
- `SourceInvalidator`'s own doc has it right: `frontend_server` invalidates
  nothing on its own, and a caller that names nothing gets its previous program
  back however much the files have moved.
- The daemon takes its baseline sweep *after* the cold compile, recording every
  source's mtime and reporting none — correct when that compile really was cold,
  and wrong after a warm start. A file edited between one daemon saving its warm
  kernel and the next starting from it was recorded as the baseline, so it was
  stale in the program **and** invisible to every later sweep. Permanently.

`touch` on the source fixed it, which is what confirmed the diagnosis: the
invalidation machinery worked, the baseline was a lie.

Fixed by giving the sweep a `compiledAt` — when the kernel the compiler was
initialised from was written — so a first sighting newer than that kernel is
reported rather than recorded, and the daemon recompiles exactly those before
serving anything. Cold compiles keep the old behaviour, so nothing pays for it.
Verified end to end: a fresh daemon now picks up an edit made before it started.

Worth noting why this one matters beyond the bug. It is the exact failure that
makes a tuning tool untrustworthy — change a value, re-render, see the old
picture, conclude the edit did nothing — and the tool this session is trying to
justify is a tuning tool.

## Not verified

The mid-transition frame was never captured. `PageView.jumpTo` snaps to the
nearest page under paging physics, and swapping to clamping physics did not
take. So the wave travelling between pages is asserted by construction and by
the values file, **not by a picture** — and "see the middle" is the whole point
of the tool, so this deserves a real answer rather than a workaround.

## Verdict

Nothing here says stop. Eight gaps, none structural: the two that would have
been — the state machine and dynamic per-fragment targets — were dissolved
earlier by scoping page orchestration to the developer and by taking two strings
instead of splitting one.

The largest single finding is (1): a closed global vocabulary was the right call
for generic boxes and is the wrong call for a scene of typed elements. That is
worth settling before anything else is built on it.
