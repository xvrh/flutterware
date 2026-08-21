# The fake keyboard — a phone's keyboard in previews and scenarios

**Date:** 2026-08-21
**Status:** Designed. Three measurements were taken *before* the design, and
two of them changed it (§ What was measured). The owner decided four things on
2026-08-21, marked **owner** where they land. **PR 1 — staging the platform —
is built**; the keyboard itself is not.

**Lineage:** `2026-07-30-scenarios-design.md` (the substrate every scenario
verb runs on), `2026-08-15-previews-audit-on-flutter-tester.md` (the second
previews lane, which is a test binding and therefore shares the scenario
driver), `2026-08-13-screen-handback-design.md` (the screen grammar the
keyboard must not pollute), `2026-05-15-flutter-embedder-step3b-design.md`
(the guest with no platform channels, which is why we already own a
`TextInputControl`).

## The goal

A phone screen is not 844 points tall the moment somebody touches a field —
it is 508. Everything a layout gets wrong about that is invisible in every
tool we have: a preview renders the full screen, and a scenario taps a field
and photographs a screen no phone would ever show.

Two asks, one mechanism:

- **Previews.** A keyboard that behaves the way a phone's does — up when a
  field takes focus, down only when the view lets go of it — plus a toggle in
  the bar for raising it against a layout with nothing focused.
- **Scenarios.** The same, automatic, so a flow that fills a form is a flow a
  phone could have performed, and its shots are pictures a phone could have
  taken.

## What was measured

**A widget test, pinned SDK, iPhone-16 geometry.** Three facts, and the
second is the whole feasibility of the scenario half:

| Probe | Result |
| --- | --- |
| `tester.tap` on a bare `TextField` | `testTextInput.isVisible` → **true** |
| `primaryFocus?.unfocus()` | → **false** |
| `view.viewInsets.bottom = 336×3`, one `pump()` | `Scaffold` body **844 → 508** |

So the focus signal is already there, with no cooperation from the app, and
the inset alone is enough to make a real layout meet the smaller space.

**A live guest**, markers in `GuestTextInput`, driven through the C host with
real pointer events:

```
boot, field has autofocus:1     attach(text) → show
tap field A → field B           detach → attach(multiline) → show    ← no hide
tap field B → field C           detach → attach(text) → show         ← no hide
tap empty background            detach → hide
```

**The SDK source**, which explains that transcript and is the reason this
design has no heuristics in it:

- `TextInput._show()` has exactly one caller, `TextInput._hide()` exactly one
  (`services/text_input.dart:2358`, `:2364`).
- The hide is deferred: `_clearClient()` → `_scheduleHide()` posts a microtask
  that calls `_hide()` **only if nothing re-attached in the meantime**
  (`:2314`). That is why field → field produces no hide, and why nothing here
  needs a debounce of its own.
- `TextInputControl.show()/hide()` (`:2540`) are unimplemented no-ops on our
  `GuestTextInput`, which is installed in every previews guest because the
  guest has no platform IME.

## The mechanism: two signals, one meaning

The keyboard is up between a `show()` and the `hide()` that follows it. That
is the entire state machine, in both lanes:

- **Guest lane** (previews live, headless captures): override `show()` and
  `hide()` on the `TextInputControl` we already install.
- **Test-binding lane** (scenarios, the flutter_tester previews lane): read
  `binding.testTextInput.isVisible`, guarded on `isRegistered`. The harness's
  `_SpyMessenger` sees the same traffic raw, but `isVisible` also works under
  a bare `flutter test`, so one mechanism serves both.

`show()` arrives **twice** per focus (an `EditableText` requests the keyboard
on focus and on tap). The driver is edge-triggered on state, never on calls.

## The arithmetic

Three numbers, and getting only the first is how a fake keyboard ends up with
a `SafeArea` floating 34 points above it:

```
viewInsets.bottom  = keyboardHeight
padding.bottom     = max(0, deviceInsetBottom - keyboardHeight)   // → 0
viewPadding.bottom = deviceInsetBottom                            // untouched
```

This is what a real embedder reports, and `MediaQueryData.fromView` reads
`view.padding` directly rather than deriving it — so a driver that sets the
insets and leaves the padding alone is reporting a phone that does not exist.

In the test binding these are `FakeViewPadding`, which speaks **physical**
pixels while the device table speaks logical — the same trap
`applyScenarioRunArgs` already documents.

In the guest they are applied in the entrypoint's existing `MediaQuery`
override, which today turns the host's view insets into padding because
`FlutterWindowMetricsEvent` has no padding field. The keyboard cannot ride
that same channel for exactly that reason: the guest could not tell a notch
from a keyboard. It arrives as its own fact over the VM service.

## Staging the platform (owner, 2026-08-21)

The measurement's last line — *tap empty background → hide* — is correct
behaviour for what the guest currently is, and wrong for what it is drawn as.
The default tap-outside action (`widgets/editable_text.dart:6882`) unfocuses
on desktop unconditionally, and on mobile for every pointer kind **except**
touch. The guest fails both tests:

| | Guest today | The iPhone it is drawn as |
| --- | --- | --- |
| `defaultTargetPlatform` | macOS — nothing stages it | iOS |
| pointer kind | `kFlutterPointerDeviceKindMouse`, always (`app/native/input.c:50`) | touch |

So a keyboard staged on an iPhone would drop on the first click on the
background. A narrow fix exists — the framework registers that action through
`Action.overridable(context:)` (`editable_text.dart:5811` → `:5506`) precisely
so an ancestor can win, and a fifteen-line `Actions` override in the guest
wrapper would restore the phone rule for tap-outside alone.

**The owner chose the broad fix instead: the guest is staged as the device it
is drawn as.** The narrow one buys the keyboard and nothing else, and it
leaves in place a disagreement that is a bug in its own right — *the scenario
lane already stages the platform* (`applyScenarioRunArgs` sets
`debugDefaultTargetPlatformOverride`) and previews does not. Two lanes,
crossed over the same devices, rendering different apps.

Staging means two things:

1. **`debugDefaultTargetPlatformOverride`** from the staged device, pushed by
   the host through the framework's own `ext.flutter.platformOverride` — the
   switch DevTools' platform selector drives, registered by every debug
   binding, and already spelled in this repo as the `platform` debug flag. Its
   setter reassembles the application, so a `ThemeData` built at the top of a
   demo is rebuilt rather than left describing the machine the studio runs on.
   Debug-only, which every lane here is (the guest is JIT with a VM service;
   flutter_tester is debug). It moves page transitions, scrollbars, selection
   handles, `.adaptive` widgets and the tap-outside rule — every preview
   screenshot moves once, and moves *towards* the truth.

   **A guest-side extension of our own was built first and deleted.** It
   worked, in a widget test and in a live guest, and it was still the wrong
   answer: it did the same thing less completely, and only we would have known
   it existed. Look for the framework's switch before writing one.
2. **Touch pointers** when the staged device is a phone or tablet — the tap
   outside rule needs the kind as well as the platform. One field appended to
   `PointerEventMessage` and one line in `input.c`, following the length-guard
   versioning the file already uses for pan/zoom.

Three consequences to build for, not around:

- **Hover dies on phone staging**, which is faithful — phones do not hover —
  but a `MouseRegion` demo staged on a phone will stop reacting. Desktop
  devices and `Fit` keep the mouse.
- **The wheel must survive.** Plain hover moves are suppressed under touch
  staging; a hover *carrying a scroll signal* is not, or the human loses the
  only way to scroll a list. A phone has no wheel; the human has no phone.
- **A drag inside the picture now scrolls like a phone**, which collides with
  the stage's own pan under zoom. `_setPanning`/`_demoInput` in
  `catalog_view.dart` already arbitrate this; touch staging is what makes the
  arbitration visible, so it gets a test rather than a hope.

**Ordering.** Staging travels over the VM service, like axes and knobs,
because the C host has no channel for arbitrary data — that is why
`CatalogAxes` is pushed rather than passed. The reassemble is what makes that
safe: a push that lands after the guest has already built rebuilds it, so the
first frame of a fresh session is the only one that can be a frame early, and
headless captures await the push before capturing.

## The artwork: a schematic slab (owner, 2026-08-21)

Rows of rounded rectangles at the right height, tinted per platform, light and
dark. No glyphs: they would need a font that differs between the harness and a
bare `flutter test`, and a per-locale layout to not be a lie.

**Painted, never built.** A keyboard composed of widgets would put key caps in
front of `find.text`, a hundred nodes into the semantics and transcript
audits, and a wall of junk into `screen()`. A `CustomPainter` under
`ExcludeSemantics` is one leaf, one paint call, and invisible to every finder.

It lives **inside the guest / inside the pumped tree**, above the app, so that
every capture that exists already contains it — embedder captures, tester
captures, scenario shots, motion frames, web exports — with no compositing
step anywhere. Shots come off the render view's layer
(`scenario.dart:1517`), so this is free.

## Occlusion (owner, 2026-08-21)

The slab hit-tests true. A tap that lands on it does not reach the app,
because that is what a keyboard does.

One place must know about it beyond the painter: a scenario's `_resolve`
gains a check for a target whose centre lies under the band, so the failure
says *the keyboard is over this* and names `s.keyboard.dismiss()` — rather
than surfacing as a tap that silently did nothing. A refusal is the feature
here; a warning in a console the flow sails past is not.

## Previews: the control surface

The keyboard is autonomous by default and the bar is an override on top of it:

- **Auto** (default) — exactly what the app asks for, per the two signals.
- **Forced up** — raised with nothing focused, which is how you ask "what does
  this layout do with 336 points less" without hunting for a field. Sticky
  until cleared or dismissed.
- **Forced down**.

`?keyboard=` in the address so a link, a screenshot and the panel agree;
`--keyboard` on `screenshot`, `inspect` and `compare`; `keyboards:` on
`PreviewCanvas` beside `devices:` and `orientations:`, because in previews the
keyboard genuinely is a staging axis — nothing focuses on its own, so crossing
it is how a matrix covers it. (In scenarios it is not an axis; see below.)

**The dismiss key is drawn by the host**, over the keyboard band, inside
`StageSpecimen` (`stage_ground.dart`, rewritten by #233 — the picture now has
a ground and an edge, and this is chrome on that picture). Host-side keeps the
tool's affordances out of the guest's tree and out of every capture, while the
slab itself stays in the guest so the captures contain the keyboard.

Pressing it calls `client.connectionClosed()` in the guest, which is what a
platform sends when the user closes the IME without touching the app — the
framework then unfocuses the field (`editable_text.dart:4213`). It is the only
gesture on a real phone that dismisses a keyboard from outside the app, and it
makes the app *react* rather than making artwork disappear.

**Trap:** on that path `TextInput._clearClient()` never runs, so the control
receives no `detach`. It has to clear its own client and key listener, or the
next keystroke goes to a field that no longer believes it is focused.

## Scenarios: a policy, not an axis

Focus drives the keyboard, so crossing it would double every run to produce
the same pictures. It is a policy on the profile.

**On by default, with one off switch (owner, 2026-08-21).** `keyboard: off`
restores today's behaviour byte-for-byte, and it has to cover *both* new
behaviours — the insets and the occlusion — because a suite that fails on one
fails on the other in the same update. `lib/src/scenarios/` is published: this
moves every existing suite's pictures from the first tap on a field onward,
once, and `compareScenarioRuns` is how a consumer reads that delta.

**Where it fires.** Inside the `Settle` pump loop, which already owns a
between-frames hook for landing real work. Each iteration checks the flag;
when it flips, the inset is stepped over ~250ms of *fake* time. The raise
therefore animates, the motion recording shows it slide the way a phone does,
and it costs nothing because the clock is not real.

**Verbs.** `s.keyboard.show()`, `s.keyboard.hide()`, `s.keyboard.dismiss()`
(the platform-closed path above), for a scenario that wants to say it
explicitly.

**Reporting.** The step records `keyboard: up (336)`. The `screen()` reply
carries it as a **note**, not a node — a real phone's keyboard is not in the
app's tree either, and an agent that cannot see why half the screen is gone is
the only reason to mention it at all.

## The heights are declared, not computed

`Device` grows a `DeviceKeyboard(portrait:, landscape:)`, measured, exactly
like `Device.landscape` insets and for the same reason: permuting geometry is
wrong on the devices it matters on. An iPhone's portrait keyboard is not its
landscape one scaled.

A measurement pass produces them — a throwaway app reading
`MediaQuery.viewInsetsOf` on a simulator and an emulator, one number per
device per orientation. **Devices we cannot boot inherit the nearest measured
device of the same platform and size class, and say so in the doc comment**
rather than being quietly interpolated.

`attach` carries the `TextInputConfiguration` — the live probe read
`TextInputType.multiline` and `TextInputType.text` off it — so per-input-type
heights are available whenever they are wanted. They are not wanted in v1:
each one is another measured number per device, and a numeric pad that is
wrong by 40 points is worse than a text keyboard that is right.

## Not in v1

- IME composition, dead keys, CJK. Unchanged from today: the guest has no IME.
- Per-input-type heights (above).
- The accessory / suggestion bar as a separate fact. It is inside the measured
  number.
- Android's `adjustPan`. Flutter defaults to resize and so do we.
- The split and floating iPad keyboards.
- A phone with a hardware keyboard attached, which shows no soft keyboard at
  all. Our fake is always the soft one.
- Web.

## Order of work

Three PRs, each doing something visible on its own (and in this order because
the first is what makes the second faithful):

1. **Stage the platform.** `debugDefaultTargetPlatformOverride` pushed with
   the device, touch pointers for phone and tablet staging, the hover and
   wheel rules, the pan arbitration test. Moves every preview screenshot once,
   for its own reasons, before a keyboard is anywhere near it.
2. **The previews keyboard.** The shared core (`DeviceKeyboard`, the
   arithmetic, the slab), the guest driver, the tri-state control, the
   address, the canvas axis, the host-drawn dismiss key.
3. **The scenarios keyboard.** The test-binding driver, the settle hook, the
   occlusion refusal, the profile switch, the step and `screen()` reporting,
   an example scenario that fills a form on a phone.

The measurement pass for the heights gates PR 2, not PR 1.

## Verification

`app/tool/embedder/keyboard_probe.dart` — the spike tool, returning as a real
check rather than as prints. The transcript in § What was measured is its
contract: autofocus raises, field → field does not flicker, an outside tap on
a phone-staged guest does **not** dismiss, and the dismiss key does.

Written down because this repo has learned it the expensive way: a smoke test
that proves the guest survived a message proves nothing about arrival, which
is how keyboard input looked implemented for months while every key sat in a
framework queue.

## Open, deliberately

- Whether `Fit` (no device) should have a keyboard at all. It has no device,
  therefore no measured height; forced-up on `Fit` would have to invent one.
- Whether forced-up survives an entry switch. It is a property of the stage,
  not of the entry, which argues yes — but a demo with no field in it and a
  keyboard over the bottom third argues no.
- Whether the scenario off switch also belongs per-scenario, or only per
  profile. Per-profile is the smaller promise, and nothing yet asks for more.
