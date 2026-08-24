# The device strip — design

**Date:** 2026-08-24
**Status:** Design. Nothing built from this yet.
**Gated on:** `2026-08-24-run-device-tab-capability-findings.md` (what each
target can do and what it costs, measured) and
`2026-08-24-run-device-tab-ui-research.md` (how it reads, with a mockup rendered
in the app's own theme at `app/tool/catalog/demos/device_strip.dart`).

The run cockpit's six tabs all read the app. This is the first surface that
**writes**, and it writes to the device rather than to the app: appearance, text
size, rotation, locale, and the accessibility flags, set from flutterware
instead of from four terminal commands you have to remember.

## Decisions taken before writing this

Three, all on 2026-08-24, all confirmed rather than assumed:

1. **A strip over the Screen pane, not a seventh tab.** A tab strip is
   exclusive: opening *Device* would close *Screen*, which is the second
   dev-stack study's finding 12 — a control writing to a page you are not on —
   rebuilt from scratch. The brief announced a tab; the research argued the
   strip; the strip is what we build.
2. **No guest extension in v1.** The *did the app see it* half needs a new guest
   service extension, and an app on an older flutterware could not answer it.
   v1 annotates from the measured table instead: the disagreements in the
   findings are facts, not predictions. The extension is the natural v2 and the
   anatomy leaves its slot open.
3. **iOS simulator and Android emulator only.** The two fully measured targets,
   where every setting that ships is live and observed. macOS, web and both
   physical kinds draw as refusal rows carrying their reason and, where one
   exists, the by-hand command.

## 1. The model

### A setting is four facts

Finding 1 of the capability pass — *a readback can be your own echo* — is what
shapes this class. Three measured controls accept a write, return it from a
`defaults read`, survive a relaunch and are never seen by the app. So a value on
its own is not evidence, and the model has to carry where the value came from.

```dart
class DeviceSetting {
  final String id;           // 'brightness', 'textScale', 'orientation',
                             // 'language', 'invertColors', …
  final String noun;         // 'Theme', 'Text', 'Turn', 'Lang', 'A11y'
  final String? value;       // the platform's own spelling: 'dark',
                             // 'accessibility-large', 'font_scale 1.5'
  final DeviceProvenance provenance;
  final DeviceSettingState state;
  final DeviceCost cost;
  final DeviceScope scope;   // device | app
  final List<String> options;
  final String? refusal;     // set exactly when state is unavailable
  final String? command;     // the by-hand line, for a refusal or a footnote
}
```

**`provenance` is the new idea and it is load-bearing.**

- `answered` — a command that *owns* the setting reported this value:
  `simctl ui appearance`, `simctl ui content_size`, `simctl ui
  increase_contrast`, `cmd uimode night`, `settings get`, `cmd locale
  get-app-locales`, `wm density`. This is evidence.
- `written` — the only read available is the store we wrote:
  `defaults read com.apple.Accessibility InvertColorsEnabled`, `defaults read -g
  AppleLanguages`. It is an echo, and the picker's footnote says so.
- `derived` — read from the app's own geometry rather than from the device.
  Orientation on the iOS simulator is the only case: `simctl` has no verb for it
  and no read for it, but the run's own root node has a width and a height, so
  the app answers a question the device will not.
- `unknown` — nothing answered. The device's own third state (`simctl ui`
  returns `unsupported` and `unknown` as first-class values; a `settings get` on
  an unset key returns the string `null`, which is not `0`). Drawn as `—`, never
  as a default.

Provenance is **not** drawn on the chip. It lives in the picker's footnote,
where the mockup already has the slot: *"per-app · cmd locale
get-app-locales"*, and for an echo, *"as written; the simulator has no command
that reports it"*.

### The four states, and where v1 gets them

`set` · `asked` · `notObserved` · `unavailable`, exactly as the UI research
draws them. In v1:

- `unavailable` comes from the backend, which knows what it cannot do.
- `notObserved` comes from a **constant** — `knownNotDelivered`, a
  `Set<(String platform, String settingId)>` built from the findings and citing
  them in its doc comment. Two entries: `('ios-simulator', 'disableAnimations')`
  and `('android', 'highContrast')`. A setting in it is refused on that platform
  rather than offered, because half a control is worse than none.
- `asked` is the window between a write returning and the next read completing.
  On both v1 targets every shipped write is live, so this is milliseconds and
  usually invisible. It exists because the anatomy has to hold it before the
  guest extension makes it common.
- `set` is everything else.

**Consequence, and it is worth stating plainly:** in v1 the amber *notObserved*
chip never appears, because everything we know is not delivered is refused
instead. The state is built and drawn in the demo, and the first thing that
fills it live is the guest extension. Nothing in v1 asserts an observation it
did not make.

### The vocabulary is `ScenarioAxes`'

The setting ids are `ScenarioAxes`' field names — `brightness`, `textScale`,
`orientation`, `language`, `boldText`, `highContrast`, `invertColors` — so there
is one vocabulary and not two, and so the promotion (v2) is a rename away rather
than a mapping. What the **chip shows** is the platform's own spelling, because
`accessibility-large` and `font_scale 1.5` are not the same kind of thing and a
shared `×1.9` is an iOS truth and an Android lie.

## 2. The seam

**`DeviceSettings` sits beside `NativeDriver`, not on it.** The brief left this
open and the platform matrix answers it: `NativeDriver` is an input and
observation abstraction (`observe`, `tapNode`, `tapAt`, `enterText`,
`foreground`) whose implementations are the Swift AX helper and `adb`
`uiautomator`. Device settings share neither the mechanism nor the matrix —
`simctl` is not the AX helper, macOS has settings but publishes almost no
Flutter accessibility, and web has settings over CDP and no `NativeDriver` at
all. Bolting five setting verbs onto a driver whose brief is *the layer below
the widget tree* would make one interface answer two unrelated questions.

What they **do** share is identity, and that is already solved:
`NativeSession._resolve` answers *which device is this, really* in exactly three
ways — adb owns the serial, it is a booted simulator, it is a macOS bundle. So:

```
app/lib/src/run/device/
  device_settings.dart     DeviceSettings, DeviceSetting, the enums, DeviceRefusal
  simctl_settings.dart     SimctlDeviceSettings
  adb_settings.dart        AdbDeviceSettings
  known_gaps.dart          knownNotDelivered, with the findings cited
```

`NativeSession` gains one member beside `driver()` and `logSource()`:

```dart
Future<DeviceSettings?> settings();
```

resolved by the same three-way identity check, cached including the null, for
the same reason the driver is: asking `adb devices` on every strip mount to be
told again that a macOS run is not an Android device is a round trip with one
possible answer.

Host code, plain Dart, no Flutter — the run plugin's files are shared by the
CLI, the GUI and the MCP server alike, which is why `NativeBounds` exists rather
than `Rect`.

## 3. The backends, command by command

Every line below was run in the capability pass and its cost measured there.

### `SimctlDeviceSettings` (`ios-simulator`)

| setting | read | write | provenance | cost |
|---|---|---|---|---|
| `brightness` | `simctl ui <udid> appearance` | `… appearance light\|dark` | answered | free, 0.11s |
| `textScale` | `simctl ui <udid> content_size` | `… content_size <category>` | answered | free, 0.12s |
| `highContrast` | `simctl ui <udid> increase_contrast` | `… increase_contrast enabled\|disabled` | answered | free, 0.12s |
| `invertColors` | `simctl spawn <udid> defaults read com.apple.Accessibility InvertColorsEnabled` | `… defaults write … -bool` | **written** | free, 0.28s |
| `orientation` | the run's root node size | Simulator ▸ Device ▸ Rotate, via System Events | **derived** | **takes the Simulator's focus** |
| `language` | `simctl spawn <udid> defaults read -g AppleLanguages` | `… defaults write -g AppleLanguages -array <tag>` | **written** | **relaunches the app** |
| `disableAnimations` | — | — | — | refused: `knownNotDelivered` |
| `boldText` | — | — | — | refused: no mechanism exists |

`textScale`'s twelve categories and their measured multipliers are a constant in
`simctl_settings.dart`, cited to the findings. The picker's footnote renders one
of them — *"a11y-large is ×1.94 · simctl ui content_size"* — which is the whole
of what a designer needs and none of what a slider would imply.

**Rotation is the one that can lie.** The menu click reports success and does
nothing unless the Simulator is frontmost (measured twice, both directions). So
the implementation activates the Simulator, clicks, and then **verifies against
the app's root size** before reporting success; if the geometry did not turn, it
refuses with the reason rather than returning ok. A verb that reports success
without checking is the failure this whole surface exists to prevent, and this
is the one place in v1 where the platform offers it for free.

### `AdbDeviceSettings` (`android`)

| setting | read | write | provenance | cost |
|---|---|---|---|---|
| `brightness` | `cmd uimode night` | `cmd uimode night yes\|no` | answered | free, 0.24s |
| `textScale` | `settings get system font_scale` | `settings put system font_scale <f>` | answered | free, 0.06s |
| `orientation` | `settings get system user_rotation` | `settings put system accelerometer_rotation 0` then `user_rotation <n>` | answered | free, 0.06s |
| `language` | `cmd locale get-app-locales <pkg>` | `cmd locale set-app-locales <pkg> --locales <tag>` | answered, **app-scoped** | free, 0.07s |
| `invertColors` | `settings get secure accessibility_display_inversion_enabled` | `settings put …` | answered | free, 0.06s |
| `disableAnimations` | `settings get global transition_animation_scale` | `settings put global transition_animation_scale 0\|1` | answered | free, 0.07s |
| `highContrast` | — | — | — | refused: `knownNotDelivered` |
| `boldText` | — | — | — | refused: restarts the app |

`adb` is located the way `AdbNativeDriver.findAdb` already locates it — from the
SDK directory, not from `PATH`, where it was not present on this machine.

**`font_scale` is a float and its effect is a curve.** The chip shows
`font_scale 1.5`, the picker offers the ladder Android's own settings offer
(0.85, 1.0, 1.15, 1.30, 1.50, 1.80, 2.00), and the footnote states the measured
consequence: *"2.0 is ×1.86 at 14sp and ×1.00 at 100sp"*. No multiplier is ever
shown as *the* scale.

**Locale is the one app-scoped setting on this target**, and `scope: app` is
what the `per-app` badge in the mockup renders. It needs the package id, which
the run handle already carries.

### The accessibility control

One chip over three flags, because they are off on a real phone and each other's
neighbours — the same grouping `ScenarioAxes.anyAccessibility` already makes.

**Wording, settling a loose end in the mockup:** the chip reads `A11y off` or
`A11y 2 on` — a count of flags that are on, not the mockup's *"1 of 2 seen"*,
which conflated *on* with *observed*. Flags refused on this target are listed
inside the popover with their reason, not counted.

Per target, after the refusals above: **iOS offers contrast and invert**;
**Android offers invert and reduce motion**. Neither offers bold text.

## 4. What the strip shows, per target

| | ios/virtual | android/virtual | everything else |
|---|---|---|---|
| Theme | ✓ | ✓ | refusal row |
| Text | ✓ 12 categories | ✓ ladder | refusal row |
| Turn | ✓ costs focus | ✓ | refusal row |
| Lang | ✓ relaunches | ✓ per-app | refusal row |
| A11y | contrast, invert | invert, reduce motion | refusal row |

A refusal row is drawn, not hidden. Its absence would read as an oversight, and
the reason is the useful part: *"A physical iPhone answers to `devicectl`, which
sets orientation and nothing else here."*

## 5. The actions

Everything in the panel is an action; the GUI adds no abilities. Two, on the run
plugin, taking the existing `_appSelector` parameters like every other run
action.

**`run/device`** — read every setting this target has, with its value,
provenance, state, cost and options. Returns `RunDeviceResult`. Costs one
subprocess per setting: measured, seven on iOS is ~0.6s, six on Android
~0.4s. No arguments beyond the app selector.

**`run/setDevice`** — write one setting. Takes `setting` and `value`, both
required. Answers with the same shape `run/device` returns **for that one
setting, re-read after the write** — so the reply is what the device says now
rather than what was asked for, which is the readback rule expressed in the
protocol rather than in the UI. A refusal is a `RunRefusal` carrying the reason
and the by-hand command.

Deliberately not a batch write. Four settings is four calls, four journal
entries and four re-reads; the cost is ~0.1s each and the alternative is a
partial failure with no honest way to report which half landed.

## 6. The journal

**One entry per write.** A device change is the only actor that can alter a
screen while leaving no trace in the app — a native tap at least comes back in
the next observe's `human` field (S-N1 finding 2), and a device write comes back
as nothing at all. Without the entry the Steps tab shows a screen changing with
no cause.

The entry is a drive step with `verb: 'set'` and `actor: 'device'`. Both fields
already exist on `JournalEntry` as free-form strings, so this needs no schema
change — only two doc comments widened, since one currently says *"a drive verb,
or `reload` / `restart` / `stop` / `launch`"* and the other *"`agent`, `human`,
or absent"*. The entry carries what the action returned: the setting, the value asked
for, the value the device answered with, and the provenance. When those last two
disagree the entry says so, because that is the case the journal exists to make
legible.

Per write rather than per settled screen: setting four axes before looking is
four things that happened.

## 7. The UI

Drawn and argued in the UI research; the mockup is
`app/tool/catalog/demos/device_strip.dart`. What the implementation adds to it:

- **Split View from Screen**, per the house rule the launcher-icon research
  named. `DeviceStrip` takes `List<DeviceSetting>` plus callbacks and reads
  nothing; a `_DeviceStripHost` in the run plugin holds the `DeviceSettings`,
  does the reads and writes, and owns the busy state. The mockup's widgets are
  already shaped this way and become the demo of the shipping one.
- ~~**The fold needs a measured layout.**~~ *A chip is its natural width until
  the bar cannot hold it* was a `LayoutBuilder` plus a `TextPainter`. **Deleted
  in §10e** — the bar scrolls, like the previews top bar next door, and nothing
  needs a chip's width before it is laid out. The research rejected scrolling
  for clipping `Turn Portrai|` "with no affordance saying more existed", which
  is wrong twice: clipping at the edge *is* the affordance every scrolling row
  in this app uses, and the fold hid the same chip behind a number.
- **Read on mount, and after every write.** Never draw a cached value as
  current. The ledger bargain the dev-stack explorer strikes — cache and show
  the age — was struck for a surface that only reads; a stale value here is a
  lie you are about to act on. A read in flight draws the previous value muted,
  not a spinner in the chip's slot.
- **The strip belongs to the device.** It draws for any run on a device this
  machine can reach, including a run another worktree launched, because a device
  control is the device's rather than the run's. It announces nothing to those
  other runs: cross-worktree signalling is the over-reach the worktree leak
  audit found in a shared `variables.json`, and re-reading on mount already
  catches whatever somebody else changed.
- **It survives the app being dead.** The strip is the second exception to the
  tab strip's `!canInspect` disable, after Steps: a device answers while a build
  is running and after an app has died. The two settings whose provenance is
  `derived` — orientation on iOS — go `unknown` in that window and say so.

## 8. Refusals

The message is the product. Every one of these is a measured line, not a guess.

- **A setting the target has no mechanism for.** *"`simctl` cannot rotate a
  simulator. The Simulator's own Device ▸ Rotate menu can, and only while it is
  the front window."*
- **A setting the platform accepts and never delivers.** *"Android accepts
  `high_text_contrast_enabled` and reads it straight back, and no Flutter app
  sees it. Measured 2026-08-24."*
- **A target with no backend.** *"A physical iPhone answers to `devicectl`,
  which sets orientation and nothing else here. The rest are Settings on the
  device."*
- **A rotation that did not turn.** *"The rotate went to the Simulator and the
  app is still portrait — the Simulator was probably not the front window. Bring
  it forward and try again."*
- **A write that needs a relaunch.** Not a refusal: the picker states it above
  the options and the button carries the verb, *Set and relaunch*.

## 9. Testing

The backends are subprocess wrappers, so the seam that makes them testable is
the runner. Both take an injectable `Future<ProcessResult> Function(String,
List<String>)` defaulting to `Process.run` — the shape `DevStackCore` already
uses for its scripted probes and its demo.

- **Parser tests, from real output.** Every read command's output in this design
  is a verbatim capture from the capability pass, including the awkward ones:
  `Night mode: yes`, `Locales for com.example.x for user 0 are [fr-FR]`,
  `Physical density: 420 / Override density: 320`, and `settings get` returning
  the *string* `null` for an unset key. That last one is the S-P5 trap — an
  empty parse is an error, not an empty answer — and it gets a test that pins
  `null` to `unknown` rather than to `0`.
- **A refusal per known gap**, asserting the message names the platform and the
  measurement date.
- **Widget tests over `DeviceStrip`** with hand-built `DeviceSetting` lists —
  the same lists the demo uses, so the previews and the tests cannot drift.
- **No device is needed for any of it.** Nothing in the test suite spawns
  `simctl` or `adb`; the capability pass is where hardware was involved and its
  numbers are in the doc.

## 10. Phases

One PR, batched — a phase is not a PR here. The order is what makes each step
verifiable.

1. **The model and the two backends**, with the parser tests. No UI. **Done
   2026-08-24** — `app/lib/src/run/device/`, 48 tests, and both backends
   exercised against a booted simulator and emulator through a throwaway script
   that phase 2's `run/device` replaces. See §10a for what that exercise
   changed.
2. **The actions** — `run/device`, `run/setDevice`, the refusals, the journal
   entry. **Done 2026-08-24** — both driven end to end against a real
   simulator with no UI in the process, which is the test that the GUI adds no
   abilities. See §10b.
3. **`DeviceStrip`**, taking plain data, with the demo file rewritten from
   mockup to demo and the fold done with a real measured layout (the fold
   itself was deleted in §10e). **Done
   2026-08-24** — `app/lib/src/run/device_strip.dart`, 23 tests, and every
   variant photographed with `previews screenshot`. See §10c.
4. **Wire it into the Screen pane**, above the picture, with the read-on-mount
   and read-after-write behaviour and the enable rule that survives a dead app.
   **Done 2026-08-24** — `_DeviceStripHost` in the run plugin, over two new
   public `RunCore` methods the actions call too. See §10d.
5. **Look at it** — `previews screenshot` for every variant in the research's
   §6 list, and `flutterware_act` against a real run on both targets, in dark
   and light. **Done 2026-08-24**, and the first person to use it found three
   things in the popover that no rendering had shown. See §10e.

## 10a. What building it changed (2026-08-24)

Phase 1 landed as designed with three corrections, and two of the three came
from running the backends against a booted simulator and emulator rather than
from the tests. That step is worth keeping in every later phase: 48 unit tests
over captured bytes were green while the Android orientation was reporting the
opposite of the truth.

- **Android orientation is read from `am get-config`, not `user_rotation`.**
  The obvious read is a *request* the sensor overrides, and it keeps its last
  value forever afterwards: on the emulator it said `1` — landscape — while the
  display was 1080×2400. `am get-config` prints the configuration the device
  actually resolved to, carrying `-port-` or `-land-`. The two `settings`
  writes stay, because they are how the turn happens; they are simply not how
  it is *known*. This is finding 1 again, one level up: `user_rotation` is an
  echo of what somebody asked for.
- **A rotation is polled, not looked at once.** The write lands instantly and
  the configuration does not — a re-read 170ms after `settings put
  user_rotation 0` still said landscape, and the device was portrait two
  seconds later. Both backends now poll for up to two seconds, and running out
  is a refusal that names the case worth naming: an app pinning its own
  orientation with `SystemChrome.setPreferredOrientations` takes the device
  setting and never turns.
- **iOS rotation goes through System Events rather than the accessibility
  helper.** The helper has no menu-item verb and is scoped to the device
  window; adding one is a Swift change this phase did not need, and the AX
  grant is the same either way (S-N3: the responsible process holds it, and
  every child inherits).

Two smaller divergences from the mockup, both settled toward what the platform
actually offers:

- **`language` has no fixed option list.** On iOS the offered values are the
  device's own preferred-language list, which is real and short; on Android
  there is no honest source at all host-side, so the row carries a note saying
  it takes any BCP-47 tag. The picker is a field with suggestions, not the six
  chips the mockup drew.
- **The a11y chip counts flags that are on**, and refused flags are listed
  inside the popover rather than counted — so iOS offers contrast and invert,
  Android offers invert and reduce motion, and neither offers bold text.

**Measured on real devices, 2026-08-24:** a full read is 776ms on the iOS
simulator (eight settings, seven subprocesses) and 205–488ms on the Android
emulator; a write plus its re-read is 179ms and 273ms; a rotation, including
the settle, is 406–873ms.

## 10b. Phase 2, and the third bug running it found

`run/device` and `run/setDevice` on the run plugin, `RunDeviceResult`,
`JournalEntry.device`, and `NativeSession.settings()` resolving all four
targets (`AdbDeviceSettings`, `SimctlDeviceSettings`, and a refusal naming what
would work for macOS and web). Driven with `tool/drive_spike/step.dart`, since
the connected MCP server is frozen at the session's start and cannot know an
action written after it.

**The bug: `summary: false` is not a cheaper tree, it is a different one.**
Orientation came back `unknown` against a running simulator. `inspectRead` only
asks the **guest** for the tree when the read is a summary one, and the guest's
walk is the one with boxes on it — asking for the full service tree instead
returns nodes with no layout at all. Reaching for the "lighter" read cost the
one field it was being read for. A second, smaller version of the same mistake
sat under it: `tree.root.layout` is null on a healthy app, because the root is
above the app's own widgets and `RootWidget` lays nothing out. The reader now
walks to the first node that has a box, which is the app's outermost widget.

Both were invisible to the tests and to the analyzer, and both showed up in the
first end-to-end call. That is now three for three: **every phase of this
feature has had a bug that only appeared when it was pointed at a real device.**

**Two decisions the actions settle:**

- **No batch write.** Four settings is four calls, four journal entries and
  four re-reads, at ~0.2s each. A batch would have to report a partial failure,
  and there is no honest shape for *"two landed, one was refused, one turned
  the device somewhere you did not ask for"*.
- **A refusal is journalled too.** A journal that only kept successes would read
  as a cleaner session than anyone had, and a refused rotation is exactly the
  step somebody comes back to when explaining a screenshot.

**Measured through the action, on a booted simulator:** a full `device` read is
under a second including the app's own tree walk; a `setDevice` write plus its
re-read is ~0.2s. Refusals arrive as `RunRefusal`, so they land verbatim in the
cockpit's error pane and in an MCP reply, carrying the by-hand command under
the sentence.

## 10c. Phase 3, and what the rendering caught

`DeviceStrip` takes a `List<DeviceSetting>` and two callbacks and reads
nothing, per the split the launcher-icon research named. One pure function
carries the thinking — `deviceChips`, eight settings to five chips — and it is
tested without a font, so what is pinned is the decision rather than a metric.
(A second, `deviceChipsThatFit`, carried the fold until §10e deleted it.)

**The demo is wired to the real backends.** `app/tool/catalog/demos/
device_strip.dart` no longer hand-builds `DeviceSetting`s; it runs
`SimctlDeviceSettings` and `AdbDeviceSettings` against a scripted
`RunDeviceProcess` holding the state a device would, the way the dev-stack
demos wire a real core to a scripted probe. So every sentence in every picker
is the backend's own and cannot drift from it, and pressing `Set` in the panel
runs the real write and the real re-read. Two states are bent afterwards by a
named function — `notObserved` and `asked` — because no v1 backend produces
them, and that is said in the file rather than left to be noticed.

**The bug the picture found: a chip that was permanently loud.** `atDefault`
was never set on the simulator's language row, so on an untouched simulator
`Lang en-US` drew bold and bordered beside four muted chips — a false alarm,
every session, saying somebody had changed something. The fix is the honest
reading of what the platform offers: there is *no default language to be at*,
because the list is whatever the machine was set up with and flutterware
remembers nothing that would let it tell a value it wrote from one it found. So
a language that was read at all reads as quiet, and nothing answering stays
loud. Android says this properly — there the default is *no per-app override*,
and an empty list is exactly that.

**Two wordings collapsed into one.** The picker draws the cost sentence from
`DeviceCost`, so it is the same on every platform that has that cost; the
`note` is what the platform measured. Both iOS notes had grown the cost
sentence inside them, and the rendering put the same words twice in one card.
Trimmed to what the cost does not say.

**The footnote is three lines, not a paragraph.** Drawn as one first, and a
simulator UDID is 36 characters: `xcrun simctl spawn A97ABCFD-… defaults read
-g AppleLanguages` ran to three lines of grey and swallowed the two words that
carry the meaning. Now the provenance leads, the command sets itself apart in
dimmed monospace, and the measurement follows.

**`DeviceSheet` and `DevicePicker` are public**, which is the one concession
the surface makes to being photographable: a popover exists only while
something holds it open, so a preview that could not build one directly could
not show the surface where every cost and every refusal is written.

Three smaller things settled by drawing them:

- ~~**The trailing control opens every chip, not only the folded ones.**~~
  There is no trailing control: §10e deleted the fold and the bar scrolls.
- **A flag writes on the tap; a value needs the verb.** Every flag on both v1
  targets is a free write, and a confirm button per row would be three buttons
  saying `Set`. The verb button exists where the cost does.
- **The border is in the measurement whether or not it is painted**, so the bar
  does not reflow the moment a value departs from its default.

## 10d. Phase 4, and the fourth thing running it found

`_DeviceStripHost` sits between the tab strip and the pane, drawn only on the
Screen view and **outside** the `switch` that falls through to *not yet* — so it
survives `!canInspect`, which is the second exception to the tab strip's disable
after Steps. `readDeviceSettings` and `writeDeviceSetting` moved onto `RunCore`
as public methods and `run/device` and `run/setDevice` now call them, so the
panel and the actions are one code path and the journal entry is written once,
wherever the write came from.

**Mounting a panel may not spawn a process, and this one spawned nine.**
`run_panel_test.dart` went red the moment the strip was mounted: *a Timer is
still pending even after the widget tree was disposed*. Working out which device
a run is on costs two subprocesses and reading it costs seven more, and a pumped
widget test can settle none of them. The seam already existed — `RunCore.
debugLive`, which is exactly the bargain `track()` makes about the daemon and
the probe — so `readDeviceSettings` answers with an empty list under it. The
strip then draws its bar and stays inert, which is the correct rendering of *no
device answered*, and the wiring is still tested: one test asserts the strip is
above the picture on Screen and gone on Logs.

**The bug the live run found: a strip that mounts before the app exists.** The
strip is drawn while the build is still running — that is what *survives
`!canInspect`* means — and at that moment `orientation` on an iOS simulator is
honestly unknown, because it is read from the running app's own width and
height and there is no running app. It then stayed unknown: the chip went on
saying `—` next to a tree reporting 402×874. `canInspect` is now passed in, not
as an enable flag but as a **read trigger** — the app started answering, so one
of these has an answer now — and the false→true edge re-reads. Every unit test
was green and the strip was wrong on screen within four seconds of a real
launch.

**A write splices, it does not re-read everything.** `writeDeviceSetting`
already answers with that setting re-read from the command that owns it — the
reply *is* the read — so a second full pass would be seven subprocesses asking
about settings the write cannot have touched. The tab strip's refresh reads both
halves, which is where *read it all again* belongs.

That is five bugs across four phases, **every one of them found by pointing the
thing at real hardware and none of them by the 3327 tests, the analyzer or the
formatter.**

Verified end to end on 2026-08-24 against a booted iPhone 17 Pro simulator: the
strip reads `Theme light · Text large · Turn portrait · Lang en-US · A11y off`,
the text-size picker opens with the twelve-category ladder and its footnote, and
`Set` writes, journals and splices — after which a refresh of the picture beside
it shows the app's own text at 302×270 where it was 302×56. The result of
pressing a control is in the frame underneath it, which is the whole argument
for the strip not being a tab.

## 10e. Phase 5, and three things a rendering could not have told me

All three came from somebody using it, and all three are about the popover
rather than the strip.

**A locale could be set and not unset.** The picker drew a field *or* a row of
chips — chips when the setting had options, a field when it had none — and on
Android the only "option" is the locale already in force, so the picker offered
exactly one choice and no way to type another or to clear it. Two facts were
missing from the model and are now in it: `openOptions` says the options are
**suggestions rather than the whole set**, so the picker draws a field *and*
them; and `clearLabel` says what an empty value means where it means anything —
*"Device language"* on Android, and null on iOS, where emptying `AppleLanguages`
is not "use the default" but a language list with nothing in it. The confirm
button used to refuse an empty value outright; it now refuses one only where
the platform has no off position.

**The accessibility popover was a wall.** iOS refuses two of its four flags and
Android one of three, and each refusal drew its whole measured sentence and a
monospace command box — ten lines of grey around two switches, in a card 288
pixels wide. The refusals now collapse to one line, *"Not on this device: Bold
text ⓘ High contrast ⓘ"*, with the sentence and the command in a tooltip; the
per-flag footnotes do the same, keeping the two words that carry the meaning
(`device-wide · as written`) and hiding the 36-character simulator UDID behind
the same hover. A single-setting picker keeps everything visible, because there
it is the only thing in the card and there is nothing to crowd.

**The flags wrote on the tap, and every other picker did not.** Argued as a
saving — a flag is one bit, and a verb button per row would be three buttons
saying `Set`. It was wrong for a reason no measurement finds: it made this the
only control on the strip whose click was final, and it did so in the one
popover with several things in it, where changing your mind is most likely.
Now it picks and applies like the rest, one button, applying only what moved —
still one write, one re-read and one journal entry each, because there is no
batch.

**And the fix for the crowding had a bug of its own, reported within minutes.**
Opening the accessibility popover produced *"a huge tooltip shown without moving
the mouse"*. `Tooltip` opens on `onEnter`, and a mouse region that appears
*underneath* a stationary pointer is sent a synthetic enter on the very next
frame — so a popover opening under the cursor drew a paragraph-sized black box
over itself 300ms later, unasked. It is in the run journal as taps *on* a
tooltip nobody opened. `_HoverTip` arms on `onHover`, which fires on movement
inside the region and never on that synthetic entry, and disarms on the way out:
the difference between *the pointer is here* and *somebody put the pointer
here*. Worth remembering the next time a tooltip goes anywhere that can appear
under a cursor.

**And a seventh bug, which turned out to be the design and took three rounds to
land** — *"there is a Device button on the right but it's not showing anything
when I press it."*

`_More`'s own doc comment claimed the §10c decision above: it opens **every**
chip rather than only the folded ones. The code beneath it passed `folded` to
the sheet, and at the width the studio actually opens at nothing folds — so the
sheet had zero children and the popover was a 288-pixel border around nothing.

Round one made the code do what the comment said. **Wrong, and the next question
caught it in one line: *what is the goal with the duplication?*** None. Every
chip on the bar already opens its own picker one click away, so a popover
listing all five was the bar a second time, scrolling.

Round two split the slot in two: a flat label with nothing folded, a badge and a
caret once something did. **Wrong too, and the round after caught it in four
words: *what does it do?*** A word at the *right* end of a row reads as a button
whatever it is made of, because the right end of a row is where controls live —
so it kept getting pressed, and kept doing nothing.

Round three was the one that was actually asked for, and it is a deletion:

> *"I think we should just remove that Device thing and have no overflow by just
> having a horizontal scroll if needed. That folding when overflow is totally
> novel no??"*

Yes. **The fold was invented here and nowhere else in the app**, and the
previews top bar this strip is otherwise modelled on has scrolled all along.
§7's rejection of scrolling — it clips `Turn Portrai|` "with no affordance
saying more existed" — is wrong on both halves: clipping at the edge is the
affordance every scrolling row uses, including that one, and a fold hides the
same chip behind a number that says even less. The argument for the fold was
that what runs off *this* bar is the device's own state rather than another axis
to pick, so it must not be hidden. It was hidden either way. All the fold bought
was novelty, and the novelty was the whole cost: three bugs, and each of them
was somebody asking what that control was for.

So the bar is now a `SingleChildScrollView` of chips and nothing else. Deleted
with the fold: `deviceChipsThatFit`, the `TextPainter` half of
`DeviceChipMetrics` (`chipWidth`, `leadingWidth`, `trailingWidth`, and the type
ramp they measured against), `_More`, `_Name`, and the eight tests that pinned
the arithmetic. **A target with no backend still draws no bar at all** — macOS
today, where the `_Notice` naming the mechanism that would work is the whole
strip — and the bar *is* drawn while the first read is in flight, so the
ordinary case fills a bar that already exists rather than pushing the picture
down a second after the page opens.

Worth noting how all of it was found. Every one of the six earlier bugs came
from pressing the thing on real hardware. This one took three rounds and none of
them was a test: pressing it (the popover was empty), asking what it was for
(the fix was duplication), asking what it did (the label was in the wrong
place), and finally asking why it existed at all (it should not have). **A
control that draws correctly and answers no question is invisible to every check
in this repo** — and a bespoke mechanism is where that hides best, because there
is no sibling to compare it against.

**And one thing that looked like a bug and is the feature.** Clearing the
Android locale left the sample app in French, while the finding says the change
is live and the app answers `didChangeLocales` in the same breath. A hot restart
brought it back to English: the platform delivered it, and *this app* resolves
its translations once at boot. That is exactly the distinction `known_gaps.dart`
says a constant can never catch — *your app ignores it* as against *the platform
drops it* — and the guest extension is what will let the strip say which.

### Three found by review

A careful pass over the diff before merge. Two of the three are writes going
somewhere they should not, and none of the three is a slip — each is a
reasonable line whose consequence is somewhere else in the file.

**The package the locale belongs to was resolved once and kept forever.**
`_packageId()` reads whatever is resumed on screen and latched the first answer,
success or failure. But the strip reads **on mount**, and by decision it mounts
while the build is still running — so the ordinary first read happens with the
*launcher* resumed. That was cached, and from then on the Locale row read and,
pressing `Set`, **wrote the launcher's locale**, for the rest of the session,
with refresh unable to correct it. The row's only warning was the package name
in six-point grey, which the comment above the parser had explicitly relied on:
*"visibly not in the case where somebody has walked off into Settings — so the
value is shown on the row rather than assumed."* True of a fresh lookup; the
cache is what made it false.

Two changes, and the second is the one that matters: a **success** is cached and
a **failure** is not — an application id cannot change under a run, and not
finding one is a fact about this moment — and `parseResumedPackage` now filters
the platform's own packages (`android`, `com.android.*`, `com.google.android.*`,
the same rule `AdbNativeDriver` uses to learn its own). The launcher and Settings
therefore answer *nothing* rather than themselves, so the row is the refusal
that says to bring the app forward, and a write refuses instead of landing on
the wrong app. Measured on the emulator both ways.

**Setting a simulator language deleted every other one.** `defaults write -array`
replaces the array; it does not reorder it. So `set language fr-BE` on a machine
listing `en-US, fr-BE` left `AppleLanguages` as `("fr-BE")` — device-wide,
outliving the run, and **invisibly**, because the picker's suggestions are that
same list read back: the evidence that `en-US` had ever been there was destroyed
by the same command. `_promote` now reads the list first and writes the chosen
tag followed by the rest, which is also what iOS's own Settings does when a
language is dragged up. Verified on the simulator: `en-US, fr-BE` → set `fr-BE`
→ `fr-BE, en-US` → set `en-US` → `en-US, fr-BE`, back where it started.

**And the tooltip bug, once more, in the place it was never applied.** `_Chip`
was still wrapping its anchor in a bare `Tooltip` — the construct `_HoverTip`
exists to replace. The two call sites fixed when it was reported were the ones
inside popovers; the chip is on the strip itself and is the most-hovered thing
on it. Its trigger is the same shape and arrives on the ordinary path: the bar
is drawn empty while the first read is in flight, the chips appear when it
lands, and a pointer resting on that band gets the synthetic enter and a tooltip
nobody asked for. Reproduced live by parking the pointer on a chip, navigating
away and back, and waiting.

One structural note that is the reason it is not a one-line swap. `_HoverTip`
arms by putting a `Tooltip` **above** its child, which changes that subtree's
depth and therefore replaces its element. Harmless around text; not around a
`Tappable`, which would lose its state — and a hover during a press is exactly
when it would happen, so the press would go nowhere. So the chip's tip goes
*inside* the tappable rather than around it, and `_HoverTip` says so where
somebody would next reach for it.

The pattern across all three: **the destructive half of a write is not where the
write is spelled.** One was a cache three methods away, the other a `defaults`
flag whose replace-versus-append behaviour is not visible at the call site. The
strip's own bugs all came from pressing it; these two could not have, because
pressing them looks like success.

## 11. Where the bugs would come from

- **Trusting an echo.** The `provenance` field exists to stop it; the risk is a
  future backend adding a `defaults read` and marking it `answered` because that
  is the enum value that reads nicer. The doc comment on `written` names the
  three measured cases.
- **An empty parse read as an empty answer.** `settings get` returns `null` as
  text, `simctl ui` returns `unknown` and `unsupported` as values. Three
  distinct not-a-value answers, and all three must land on `unknown` rather than
  on a default.
- **Reporting a rotation that did not happen.** Covered above with a
  verification read; it is the only write in v1 that can silently fail.
- **A stale strip.** Read on mount and after every write, and never render a
  cached value as current.
- **The a11y count disagreeing with the popover.** One derivation, in the model,
  from the settings that are `set` and on — not a second count in the widget.
- **Leaking a subprocess per rebuild.** The reads belong to the host object, not
  to `build`; a `DeviceSettings` is cached on the session like the driver.

## 12. Not v1, and why

- **The guest extension** and the live *notObserved* state. Decided today; the
  anatomy holds its slot.
- **The `ScenarioAxes` promotion.** Four of eight axes promote faithfully, one
  is wrong on Android, one is unreachable on iOS, one is lossy in a way no
  `double` can express, and `device` cannot be expressed at all. The honest
  version is a refusal with a list, and it needs the state machine above to
  exist first.
- **Status bar, location, media, clipboard, deep link.** All write cleanly; none
  has a visible result in the cockpit. They are the first contents of the
  research's direction C sheet.
- **Permissions, push, bold text.** Refused on evidence — see the findings, and
  #129 for permissions.
- **macOS, web, physical.** Refusal rows in v1. macOS is the cheapest to add
  next: two settings, one new backend, and the sandbox container path that
  finding 4 uncovered.

## 13. Still open

- **Does the strip draw for a run this worktree does not own?** Answered yes
  above, on the ground that the device is the device's — but the run header
  already distinguishes `mine`, and if that distinction should extend to writes
  it changes the enable rule rather than anything else.
- ~~**What the trailing `Device` control opens in v1.**~~ Nothing: §10e deleted
  it along with the fold, and the bar scrolls. The capability table and the
  deferred controls are direction C and later, and they would have to earn a
  control at the right end on their own merits rather than inherit one.
- **The picker's footnote describes the value the device *has*, not the one you
  have selected.** Selecting `accessibility-large` leaves it reading *"large is
  ×1.00"*, because the note is the backend's and is computed from the read. It
  is consistent with the provenance line above it, which is also about the
  current state — but a reader mid-selection can take it for a description of
  the selection. Making it follow the selection means the view knowing the scale
  table, which is the backend's knowledge.
- **Is there a design reference?** No `figma_links.json` covers the run page.
  The previews `_TopBar` is the house precedent this leans on; a real source
  would outrank both it and the mockup.
