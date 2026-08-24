# The device controls on screen — UI research

**Date:** 2026-08-24
**Status:** Research. No code written from this yet.
**Subject:** the run cockpit's seventh surface — appearance, text size,
contrast, rotation, locale and the rest, set from flutterware rather than by
hand. Gated on `2026-08-24-run-device-tab-capability-findings.md`, which was
written first on the theory that the capability table is the design.

## Why

Six tabs (`app/lib/src/plugins/native/run_plugin.dart:667`) and every one of them
reads: Screen, Steps, Logs, Network, App, Knobs. Nothing in the cockpit reaches
past the app to the device it is running on, so *"does this look right in dark
mode at 200% text in French"* is four terminal commands away and only if you
remember them. Radon IDE ships seventeen of these controls in a dropdown, which
is the obvious shape and the reason to look before building.

The capability pass changed the brief, twice. It cut the list — three of the
twelve controls are refused on evidence, not on taste. And it found that the
cost of a control is the most variable thing about it: measured on one device,
through one mechanism, in the same minute, appearance is free, locale needs a
relaunch, bold text is unreachable, rotation steals the keyboard focus and a
permission revoke ends the run. **A row of identical switches is a lie about the
one thing the user needs to know before pressing.**

This is a research pass before drawing anything: what the repo already provides,
what the rest of the world does, where the obvious design goes wrong, and a
direction.

## 1. What the repo already provides

### The strip already exists, one plugin over

`app/lib/src/previews/catalog_view.dart:1366` — `_TopBar`, a **36px row above
the stage** carrying a device picker, the staged device's turned size, and the
shell's declared axes as scrolling controls. Two of its doc comments are the
whole design of this feature, written for a different one:

> *The turned size: the one number on the bar that says whether the axis took,
> and the cheapest possible proof of it.*

> *The guest's own answer, not the mode's: in `auto` the app is what decides,
> and the bar saying otherwise would be a control describing its own setting
> rather than the picture.*

That is the readback rule, in the house's own voice, already shipped. A device
strip is the same bar pointed at a real phone instead of a staged one — and the
capability findings say the phone answers back at least as well as the guest
does (`simctl ui appearance`, `cmd uimode night`, `wm density`'s
`Physical`/`Override` pair).

### The Knobs tab is the closest sibling and the wrong transaction

`app/lib/src/run/knobs_tab.dart` is a list of named controls over a run, with an
apply bar and a *pending* rendering for an edit that has not landed. Its docs are
explicit about why:

> *It does not apply live. A value reaches the app only through `main`, so
> showing a new one while the process holds the old would look correct and be
> wrong.*

A device setting is the mirror image: it applies **at once**, and the question is
not "has it been applied" but "did the app see it". So the anatomy transfers and
the transaction inverts — no batch, no apply button, and the *pending* state
becomes something more interesting. Three of the measured controls write
successfully and are never observed; that is not `pending`, it is a settled
disagreement between the device and the app, and it needs its own word.

### The kit has every part, at the right weight

- **`KnobField`'s `_Toggle`** (`app/lib/src/run/knob_field.dart:308`) — a 26×14
  switch *"at the weight of the fields around it"*, hand-rolled because
  Material's is the heaviest thing on the pane; it carries its own `Semantics`.
- **`_OptionChip`** (`:377`) — one offered value *"small enough to read as a
  suggestion"* rather than as a button. Twelve iOS content-size categories are
  chips, not twelve buttons.
- **`FieldRow`** (`app/lib/src/ui/field_row.dart`) — label, value, and a `note`
  provenance slot set small and muted at the end. The splash panel puts the
  config key that won the cascade there. *"As the device answered"* is the same
  kind of thing.
- **`FwPalette.statusFill` / `statusBorder`** (`palette.dart:161`) — the
  tint-is-the-frame tokens from the second dev-stack study, already used by the
  dependencies panel.
- **`Popover`**, **`SplitButton`**, **`EmptyState`**, **`ErrorState`**,
  **`ActionButton`**, **`PanelHeader`** — the overflow, the two-verb control,
  and the three arms of the load triad.

### The table's key is already computed, twice

`run devices` reports `platform`, `kind` (`physical|virtual|host`) and
`emulator` per device — the exact discriminator the capability table keys on.
And `NativeSession` (`app/lib/src/run/native/native_session.dart`) already
resolves the same identity three ways for the native driver: adb owns the
serial, it is a booted simulator, it is a macOS bundle. Nothing new has to be
discovered to know which mechanism a run is on.

### The refusal voice is written

`NativeRefusal` / `NativeUnsupported` (`native_driver.dart`) and `RunRefusal` —
one exception type with a written message, because *"the message is the
product: it says what to do next, and lists what the layer did see"*. Every
mechanism in the capability pass refuses in a quotable way and every one of them
has a by-hand command to print.

### The journal is the correlation surface

The drive journal and its Steps tab already interleave agent steps with the
human's (`actor: human`, from S-N1). A device write is the third actor, and the
only one that changes a screen while leaving no trace in the app.

### And one thing the repo already decided against

`docs/permissions-panel.md` and PR #129: the permissions feature was built in
five phases and removed a day later, before shipping. Whatever this surface is,
it is not that.

## 2. What the rest of the world does

**Radon IDE** (the reference in the brief) — one dropdown from the bottom-right
of the preview, seventeen entries: Device Appearance (dropdown), Text Size
(slider), Press Home Button, Open App Switcher, Rotate Device (dropdown),
Biometrics (iOS only), Send File, Location, Localization (*"reboots device"*,
iOS only), Volume, Action Button, Reset Permissions, Open Deep Link (input),
Enable Replays, Show Touches, Clipboard Sync, Show Device Frame.

Three things to take from it and three not to.

- **Take:** the controls sit *on the preview*, not on a separate page. Whatever
  it is called, it opens over the picture.
- **Take:** heterogeneous control shapes in one list — a slider next to a
  dropdown next to a bare button — rather than forcing everything into a toggle.
- **Take:** platform-only entries are named as such (*iOS only*).
- **Leave:** four of the seventeen are not device settings at all. *Show
  Touches*, *Show Device Frame* and *Enable Replays* are settings of the
  **preview**; in this repo those live in the previews plugin, the device frame
  is `device_frame`, and replays are the drive journal. Mixing them in makes the
  menu longer and the concept fuzzier.
- **Leave:** no cost is shown anywhere. *Reset Permissions* sits between
  *Action Button* and *Open Deep Link* at the same weight, and on Android it is
  measured here to end the run.
- **Leave, on evidence:** *"Localization … reboots device"* is wrong for the
  path measured in the capability pass. An app relaunch was enough on iOS 26.2,
  and on Android the per-app locale is live with no restart at all. A design
  that copies the claim inherits a twenty-second lie.

**Android Studio's extended controls** — a separate window with a left rail of
fifteen categories (Location, Displays, Cellular, Battery, Camera, Phone,
Directional pad, Microphone, Fingerprint, Virtual sensors, Snapshots, Record and
Playback, Google Play, Settings, Help) and a form per category. It is the
completest thing anyone ships and the clearest warning: **letting the mechanism
choose the categories produces a rail of fifteen for the four things anyone
touches.**

**Xcode's Simulator** — a menu bar (Device ▸ Rotate, Features ▸ Increase
Contrast, …) with checkmarks as state. It has no cost annotations and no
readback surface, and *Rotate* is the item the capability pass had to press
through accessibility because `simctl` has no verb for it.

**Chrome DevTools' Rendering pane** — a flat list of emulation controls each
labelled with the CSS media feature it forces (`prefers-color-scheme`,
`prefers-reduced-motion`, `forced-colors`). Its lesson is the opposite of a
unifying abstraction: **name the platform's own setting.** The capability pass
argues the same from measurement — iOS has a named content-size *category*,
Android has a font-scale *curve*, and a shared "Text size ×2.0" is true on one
and false on the other.

**Device farms** (BrowserStack, Sauce) — almost nothing, because a real device
is a real device. That is the honest shape of the `ios/physical` row too.

**flutterware's own** — the previews top bar (above), the scenarios matrix
toolbar, and the address-as-state discipline that both use: an axis on its
default writes nothing to the address.

## 3. Where the obvious design goes wrong

The obvious design is a seventh tab holding one row per control, a switch or a
picker each, greyed out where the target does not support it. Every one of these
is tied to a measurement in the capability pass.

| Problem | Why it matters |
|---|---|
| **A seventh tab replaces the picture.** The tab strip is exclusive: opening *Device* closes *Screen*. | This is dev-stack finding 12 rebuilt from scratch — *"a control on the overview wrote to a screen you were not on"*. Pressing *dark* and then navigating back to look is the exact gesture that got reported as *"there are some buttons we don't know what they do"*. |
| **One row per control implies one cost per control.** | Measured costs range from 0.06s-and-live to *takes the Simulator's keyboard focus* to *restarts the app* to *ends the run* to *thirty seconds and cannot fail*. Uniform rows put `Rotate` and `Revoke` at the same weight. |
| **A toggle asserts the state it shows.** | Three controls accept a write, read it straight back, and are never seen by the app — iOS bold text and reduce motion, macOS appearance written to the un-sandboxed domain. A switch reading *Bold text: on* over an app rendering regular weight is worse than no control, because it is evidence for a conclusion that is false. |
| **A single "Text size" number.** | Android's font scale is non-linear: `2.0` is ×1.86 at 14sp and ×1.00 at 100sp. iOS is a twelve-step named ladder, linear, 0.824×–3.118×. One slider cannot be honest about both. |
| **Greying out is not a refusal.** | Grey carries none of the three facts a cell holds — is there a mechanism, what does it cost, will the app see it — and none of the by-hand commands, which exist for every mechanism measured. |
| **Four controls have no visible result anywhere in the cockpit.** | Measured: the guest's raster of the Flutter layer tree has **no status bar, no notch, no home indicator**. Location needs a plugin the app may not have. `addmedia` writes to a library. The iOS clipboard read raises a native modal the drive layer cannot see. |
| **A category rail.** | Android Studio's answer. Fifteen categories for four controls anybody uses. |

### The rule, checked rather than repeated

The second dev-stack study's rule is *a glance surface may only carry controls
whose result is visible on that surface*. The brief's premise is that a device
setting passes it because the Screen pane is right there. Checked:

- **The rule does not apply as written.** The Device surface is a working page,
  not a glance surface — the same category as the dev-stack *panel*, which is
  where the commands were moved **to**.
- **Its reason applies, and harder.** The run page has one content area. As a
  seventh tab, every device control is a control whose result is on another
  page — which is finding 12 exactly, and worse than the original, because at
  least `Logs` wrote somewhere the user could go and find. Here the result is a
  repaint that has already happened by the time you navigate back.
- **The premise is therefore false for the shape the brief proposes and true for
  a different one.** *"The Screen pane is right there"* only holds if the
  controls are **beside** the picture rather than instead of it.
- And it is only half true even then: measured, `content_size` is plainly
  visible in the guest raster and `status_bar override` is structurally absent
  from it. The rule sorts the control list into two piles, and it is the same
  cut the capability pass made on other grounds.

One measurement worth keeping in view while drawing this. `simctl ui appearance
dark` against `examples/example` produced **no visible change**, because that
app pins a light theme. That is not a failed control and not a failed pane — it
is the single most useful thing this feature can say (*your app does not respond
to dark mode*), and it is only legible because the picture comes from the app
rather than from the OS. A design that hides the picture to show the switch
throws away its own best output.

## 4. Direction

### Three shapes

**A — the seventh tab.** Cheapest: one `RunViewKind`, one entry in
`InspectTabStrip`, the address already carries a tab name and tolerates unknown
ones. And it has finding 12 built in, per §3. Its one real advantage is that the
**capability table** — what this target can and cannot do, and why — is a
*reading* surface and wants a page.

**B — a strip on the Screen pane.** The controls live in a row above the
picture, the previews `_TopBar` one plugin over. Passes the rule by
construction: every control's result is in the frame below it. Costs vertical
space on the pane that is already the most crowded, and only fits controls whose
value is a word.

**C — B, with a sheet behind the last control.** The strip carries the axes;
one trailing control opens a `Popover` holding the rest — the controls that need
a text field or a file (deep link, media), the ones whose result is not a
repaint (status bar, location), and the capability table itself.

**Chosen: B for v1, C as the shape it grows into.** The tab is not chosen, and
that is a deliberate departure from the brief: measured, a device write from a
page that is not showing the app is the failure this repo has already shipped
once and written a rule about. What survives from A is that the table wants a
page eventually — and it can have one when there is enough on it to read, which
is the same bargain the dev-stack panel struck.

### The strip

Above the picture in the Screen pane, at the previews bar's height. Its
overflow rule is the one thing it does **not** take from that bar — see *What
the rendering changed*, below.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Theme Dark ⌄  Text accessibility-large ⌄  Turn Portrait ⌄  Lang fr ⌄      │
│ A11y 1 of 2 seen ⚠ ⌄                                          Device ⌄   │
├──────────────────────────────────────────────────────────────────────────┤
│ ⚠ Reduce motion is on for the device and the app does not see it.        │
├──────────────────────────────────────────────────────────────────────────┤
│                        the app's own pixels                              │
```

**Drawn, in the app's own palette and type ramp:**
`app/tool/catalog/demos/device_strip.dart`, group **Device** — six previews over
seven target-and-state cases: light and dark, wide and narrow, the open pickers,
and the strip in situ under the tab row and over the Screen pane. A mockup rather than a
component: nothing is wired to a device and every value in it is a literal from
the capability findings. If the strip ships, that file is replaced by a demo of
the shipping widget.

Seven settings in five controls, all of them measured live-and-observed on at
least one target: appearance, text size, rotation, locale, and one accessibility
control holding contrast, invert colours and reduce motion — three flags that
are off on a real phone and each other's neighbours, and that `ScenarioAxes`
already groups behind a single `anyAccessibility`.

**Every control renders the device's answer, never the last thing asked.** The
strip reads on mount and after each write, from the command that owns the
setting — `simctl ui appearance`, `cmd uimode night`, `settings get`, `cmd
locale get-app-locales`, `wm density`. A `defaults` domain is never a readback,
because it answers with whatever was last written to it.

**Cost is on the control, before the click, and only when it is not free.** Five
words, in the house's status vocabulary:

| cost | wording | which controls |
|---|---|---|
| free | *(nothing shown)* | appearance, text size, rotation and locale on Android; the `simctl ui` trio on iOS |
| relaunches the app | on the control | locale on iOS and macOS, appearance on macOS |
| restarts the app | on the control | bold text on Android — if it is ever shipped |
| takes the Simulator's focus | on the control | rotation on the iOS simulator |
| ends the run | *not shipped* | permission revoke |

**Four states per control, anatomically constant** (P3 from the first dev-stack
study — a failure takes the value's slot, it does not rearrange the row):

- **set** — the device answered with this, and the app was seen to observe it.
  Neutral. No tone, no badge; this is the ordinary day.
- **asked** — the write landed and the app has not answered yet. The Knobs tab's
  *pending*, borrowed.
- **not observed** — the device confirms the value and the app's `MediaQuery`
  does not carry it. **Amber, with the sentence**: *the simulator has Reduce
  Motion on; the app does not see it.* This is the state three measured controls
  live in permanently and it is the whole reason the strip cannot be switches.
- **unavailable** — no mechanism on this target. Not greyed: the control is
  replaced by its reason and, where one exists, the by-hand command. *"`simctl`
  cannot rotate. The Simulator's Device ▸ Rotate menu can, and it only works
  while the Simulator is frontmost."*

**The strip belongs to the device, and says so.** Two runs on one simulator share
its appearance; `run devices` already reports `running: [RunHolder]` across
worktrees. A write here reaches every app on that device except where the
mechanism is per-app — Android locale, macOS appearance and locale — and those
three are the only ones that may be drawn as belonging to the run.

**Every write is a journal step.** A device change is the only actor that can
alter a screen while leaving no trace in the app: a native tap at least comes
back as `actor: human` (S-N1 finding 2), and a device write comes back as
nothing at all. Without the entry, the Steps tab shows a screen changing with no
cause. The entry carries the same two facts as the strip: what was asked, and
whether the app was observed to see it — so a locale change on iOS journals as
*asked, not observed*, or the journal lies.

### What ships in v1, and what is refused

**Ships — seven controls, all live and observed where they exist:**

| control | iOS sim | Android | macOS | web |
|---|---|---|---|---|
| appearance | ✓ live | ✓ live | ✓ relaunch | ✓ live, while connected |
| text size | ✓ live, 12 named categories | ✓ live, a curve | — | — |
| rotation | ✓ live, takes focus | ✓ live | — | ✓ via metrics |
| locale | ✓ relaunch, device-wide | ✓ live, per-app | ✓ relaunch, per-app | ✗ not observed |
| high contrast | ✓ live | ✗ not observed | — | ✗ not observed |
| invert colours | ✓ live | ✓ live | — | — |
| reduce motion | ✗ not observed | ✓ live | — | ✓ live |

Eight of those twenty-eight cells are a refusal or a cost, which is the
argument for drawing the state rather than the switch.

**Refused, with the reason on the surface:**

- **Permissions** — built and removed here in a day (#129); revoke ends the run.
- **Push** — thirty seconds, silent success against a bundle that is not
  installed, and it needs a notification authorization that cannot be granted
  from the host on iOS.
- **Bold text** — unreachable on the iOS simulator by any key that exists, and a
  full restart on Android. Half a control on the platform where a designer is
  least likely to be checking.

**Deferred, because the cockpit has nowhere to show the result:** status bar,
location, media, clipboard. All four write cleanly and all four are invisible in
the guest raster. They are the natural first contents of direction C's sheet,
once there is a reason to open one.

**Deep link is the interesting borderline.** It takes a text field, so it does
not fit the strip; its result *is* visible on the picture, so it passes the
rule; and the platforms disagree — Android delivers `pushRouteInformation` to a
running app with no opt-in, and iOS delivered nothing to the framework with a
registered scheme and `FlutterDeepLinkingEnabled` both set. It is the first
entry in the sheet, not the eighth control in the strip.

### What the rendering changed

Three decisions came out of looking at it rather than out of arguing about it,
which is the argument for rendering a mockup in the real theme at all.

- **Nouns, not icons.** The first draft carried a 12px glyph per chip and the
  value alone — `Dark`, `large`, `Portrait`, `en`, `2`. Rendered, three of those
  five are unreadable: `large` what, `2` of what. No icon at that size supplies
  the missing noun. The chips now read `Theme Dark`, `Text large`, `A11y 2 on` —
  a muted qualifier and a value in ink, which is the Run panel's own pattern
  named in the first dev-stack study, and it is *narrower* than the icon version
  as well as legible.
- **No border until the value departs.** Five bordered chips saying nothing has
  happened is a busy rendering of a quiet fact — study 2's finding 13, that the
  frame existed mostly to give a hairline an edge to be. A chip on the
  platform's default is now muted text with no frame, so the untouched strip
  reads as untouched and one that has been touched reads as loud without any
  colour being spent.
- **Fold, don't scroll.** The previews bar scrolls its overflow, and copying
  that clipped `Turn Portrai|` at 360px with nothing on screen to say more
  existed. What is off the end of *that* bar is another axis to pick; what is
  off the end of *this* one is the device's current state, on the one surface
  whose job is to report it. Chips now fold into the trailing control, which
  carries the count — amber when one of the folded chips is not at its default,
  because then what is hidden is something somebody changed. Chips fold from the
  end and never reorder (P3).

The last one is unfinished. The rule *a chip is its natural width until the bar
cannot hold it* needs a measured layout — a `LayoutBuilder` and a `TextPainter`
— and the mockup fakes it with a per-variant flag. Three intermediate drawings
were rejected on the way and each cost a render: an always-flexible chip elided
`accessibility-large` at 900px because five flexible chips split the bar five
ways whether or not they need it; a fixed `maxWidth` on the value overflowed the
bar by 49px, because a `MainAxisSize.min` row hands unbounded width to an
inflexible child; and a horizontally scrolling row hid state with no affordance
at all.

### The promotion, deliberately not v1

*"Promote this live assignment to a `ScenarioAxes`"* is the thing that would make
this more than parity. Tested in the capability pass: of the eight axes, four
promote faithfully, one is wrong on Android, one is unreachable on iOS, one is
lossy in a way no `double` can express, and `device` cannot be expressed at all
because a live phone's geometry has no home in that class. A single button would
hand back a scenario that claims to reproduce a screen it does not.

The version that survives is a refusal with a list — *four of six carry over;
`textScale` cannot, because Android's font scale is a curve and the axis is a
multiplier* — and it needs the per-control state machine above to exist first.
It is the strongest v2 and a bad v1.

## 5. What this does not become

- **Not a preferences editor.** It writes live device state and **nothing** to
  the user's project: no config file, no remembered selection, no address
  parameter that survives the session. Two consequences belong on the surface
  itself: a value set here is still set after the run stops, and — except for the
  three per-app mechanisms — it is set for every app on that device.
- **Not a permissions panel.** #129 settled that, and `docs/permissions-panel.md`
  is where the answer lives.
- **Not a device manager.** Booting, creating, erasing and pairing are the New
  run page's business; `run/emulators` and `run/bootEmulator` already exist.
- **Not a second axis vocabulary.** The words are `ScenarioAxes`' and the
  address bar's — `brightness`, `language`, `orientation`, `textScale`,
  `boldText`, `highContrast`, `invertColors` — even where the platform's own
  spelling has to be shown beside them.
- **Not a preview-settings drawer.** Radon's *Show Touches*, *Show Device Frame*
  and *Enable Replays* are settings of the preview; here they are the previews
  plugin, `device_frame`, and the drive journal.
- **Not a seventh tab**, for v1. See §3.

## 6. Variants to enumerate before coding

Per the skill's step 3, stacked rather than behind a picker.

- **Target** — `ios/virtual`, `android/virtual`, `android/physical`,
  `ios/physical` (a strip that is nearly all refusals), `macos/host`,
  `web/host`, and *no device answering at all*.
- **Per-control state** — set · asked · **not observed** · unavailable-with-a-
  command · `unknown` (the device's own third answer: `simctl ui` returns
  `unsupported` and `unknown` as first-class values, and a `settings get` on an
  unset key returns `null`, which is not `0`).
- **Cost annotation** — none · *relaunches the app* · *takes the Simulator's
  focus* · a control mid-relaunch.
- **Run state** — building (the device answers while the app does not — this is
  the second exception to the tab-strip's `!canInspect` disable, after Steps) ·
  running · app dead but device alive · a run this worktree does not own · two
  runs on one device.
- **Width** — chips fold into the trailing control rather than scrolling under
  the edge, the fold badge goes amber when a folded chip is not at its default,
  and the trailing control is never itself pushed off the end.
- **Theme** — light and dark, with `statusFill`/`statusBorder` for the amber
  *not observed* state in both.
- **The picture below** — a change the app shows · a change the app ignores (the
  light-theme example) · a change the raster structurally cannot show.

## 7. Open questions

1. **Does the strip read the device on mount?** Reading the iOS trio plus the
   accessibility domain is roughly five subprocesses per open, ~0.6s. The first
   dev-stack study's ledger bargain says cache and draw the age — but that
   bargain was struck for a surface that only *reads*. A stale value here is a
   lie you are about to act on. Probably: read on mount, and never draw a
   cached value as if it were current.
2. **Whose is it — the run's or the device's?** Everything except three
   mechanisms is device-wide, and `run devices` already knows which other
   worktrees are holding the same device. Does a write from one run announce
   itself to the others, or is that the same over-reach the worktree leak audit
   found in shared `variables.json`?
3. **One journal entry per write, or per settled screen?** Setting four axes
   before looking is four entries and one useful picture.
4. **Does the strip draw for a run this worktree does not own?** The header
   already distinguishes `mine`; a device control is arguably the device's
   rather than the run's, which would argue yes.
5. **Is there a reference?** There is no `figma_links.json` for the run page. The
   previews `_TopBar` is the closest thing to a house precedent and the direction
   above leans on it heavily; if a design source exists, it outranks this.
6. **Where does the capability table itself live** when direction C arrives — the
   sheet, or the page the brief originally asked for? It is the one part of the
   original tab idea that survives on its merits.
