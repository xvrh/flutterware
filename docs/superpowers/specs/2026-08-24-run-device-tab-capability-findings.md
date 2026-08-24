# S-D1 … S-D6 — the device layer measured on six targets

**Date:** 2026-08-24
**Status:** Four of six ran on real hardware this session. S-D1: iOS simulator
(iPhone 17 Pro, iOS 26.2). S-D2: Android emulator (API 35, Android 15).
S-D3: macOS 26.2 host. S-D4: web, Chrome 151 under `flutter run -d chrome`.
S-D5 (physical iOS) and S-D6 (physical Android) could **not** be measured —
neither known iPhone was connected and no Android phone was attached — so what
is written about them is the mechanism's own documentation, marked as such and
never as a measurement. Every number below is from this session unless it cites
a prior spike by name.

**Context:** the run cockpit has six tabs and every one of them *reads* the app.
A seventh, "Device", would be the first that **writes** — appearance, text size,
contrast, rotation, locale, deep links, clipboard, media, push, status bar,
location. The premise under test is that the capability table is the design and
the panel is a list over it. It survives, with one correction: a cell in that
table cannot be a single word.

**Method.** A 150-line Flutter probe (`flutter create`, no dependencies beyond
`flutter_localizations`, built once per target) prints one line whenever
anything the platform can push at an app changes: `platformBrightness`,
`textScaler` sampled at **two** sizes, `boldText`, `highContrast`,
`invertColors`, `disableAnimations`, `accessibleNavigation`, the resolved and
platform locales, size, DPR, orientation, insets, plus `didChangeLocales` /
`didChangePlatformBrightness` / `didChangeAccessibilityFeatures` /
`didChangeMetrics` / lifecycle, a `SystemChannels.navigation` handler, and an
on-demand clipboard read. Every host command below was timed, fired against a
running app, and correlated with what the app printed within 2.5s.

---

## The four findings nobody ordered

### 1. A readback can be your own echo

This is the one that changes the design. Three separate controls, on two
platforms, **accept the write, read it straight back, survive an app relaunch,
and are never seen by the app**:

| write | reads back as | app sees |
|---|---|---|
| `simctl spawn <udid> defaults write com.apple.Accessibility BoldTextEnabled -bool true` | `BoldTextEnabled = 1` | `boldText: false`, before *and* after a relaunch |
| `… ReduceMotionEnabled -bool true` | `ReduceMotionEnabled = 1` | `disableAnimations: false` |
| `defaults write com.example.deviceProbe AppleInterfaceStyle Dark` (macOS) | `AppleInterfaceStyle = Dark` | `platformBrightness: light`, launched by `flutter run` *and* by LaunchServices |

`BoldTextEnabled` is the sharpest case: the key **did not exist** in that domain
before the write. `defaults write` invented it, `defaults read` returned it, and
a grep of every domain on the device (`simctl spawn <udid> defaults read | grep
-i bold`) found the key I had written and nothing else. There is no other place
bold text lives on that simulator, so the honest reading is: **no host command
sets bold text on the iOS simulator**, and the one that looks like it does is a
write to a file nobody reads.

The project memory rule — *report what the device answered back, never predict
what it will do* — is necessary and, measured, **not sufficient**. A `defaults`
domain answers with whatever you last put in it. Only two kinds of answer are
evidence:

- a readback from a **command that owns the setting** — `simctl ui appearance`,
  `cmd uimode night`, `settings get`, `wm density` (which even distinguishes
  `Physical density: 420` from `Override density: 320`), `cmd locale
  get-app-locales`, `simctl status_bar list`;
- the **app's own** `MediaQuery`.

A cell in the capability table therefore has to be two facts, not one: *what the
device answered* and *whether the app was seen to observe it*. Everywhere those
two disagree, the panel must say so rather than paint the control green.

### 2. Text scale is not one number, and it nearly produced a false finding here

The probe originally sampled `textScaler.scale(100)`. Against the Android
emulator that produced a clean, repeatable, **wrong** result: `settings put
system font_scale 2.0` written, read back as `2.0`, and `textScale=100.0`
unchanged across a live change *and* a full cold start. I wrote it down as "the
single most-requested device control does not propagate on Android."

It does. Android 14+ uses **non-linear font scaling**, and the curve flattens to
1.0× for very large text. Re-sampling at 14sp:

| `font_scale` | `textScaler.scale(14)` | `textScaler.scale(100)` |
|---|---|---|
| 1.0 | 14.00 | 100.0 |
| 1.5 | 22.00 | 100.0 |
| 2.0 | 26.00 | 100.0 |

iOS is linear over the same axis. The full `simctl ui content_size` ladder,
measured at 100 logical px on iOS 26.2:

| category | scale | category | scale |
|---|---|---|---|
| `extra-small` | 0.824 | `accessibility-medium` | 1.647 |
| `small` | 0.882 | `accessibility-large` | 1.941 |
| `medium` | 0.941 | `accessibility-extra-large` | 2.353 |
| `large` (default) | 1.000 | `accessibility-extra-extra-large` | 2.765 |
| `extra-large` | 1.118 | `accessibility-extra-extra-extra-large` | 3.118 |
| `extra-extra-large` | 1.235 | | |
| `extra-extra-extra-large` | 1.353 | | |

**Consequence for the panel:** a control that renders "Text size ×2.0" is
telling an iOS truth and an Android lie, because on Android there is no single
multiplier — the factor depends on the text. iOS has a **named category**;
Android has a **device setting whose effect is a curve**. They are not one
control with two backends, and the panel should show each platform's own
vocabulary. (This is also what breaks the ScenarioAxes promotion; see §
*Promoting a live assignment*.)

### 3. The Screen pane cannot show a status bar

Measured rather than argued. `examples/example` launched on the simulator
through `run/launch`, `simctl status_bar override --time 09:41 --cellularBars 2
--batteryLevel 42`, then two pictures of the same moment:

- `simctl io screenshot` — the real device screen: **09:41, two bars, the notch,
  the home indicator.**
- `run/screenshot` (the guest's raster of the Flutter layer tree, 71ms) — the
  app's pixels edge to edge and **no status bar, no notch, no home indicator at
  all.**

The status-bar override is a real capability with a clean readback
(`status_bar list`) whose result is invisible on the surface it would be
operated from. The same is true of Android's `am broadcast
com.android.systemui.demo`, which worked (clock forced to 9:41, full bars,
confirmed by `adb exec-out screencap`) and is equally absent from the guest
raster.

A counter-measurement from the same run, so this is not read as "the Screen pane
shows nothing": `simctl ui content_size accessibility-large` **is** plainly
visible in the guest raster — the app's own text grew. And `simctl ui appearance
dark` produced **no visible change**, because that example app pins a light
theme. That non-change is not a failure of the pane; it is the most useful thing
the pane can say — *your app does not respond to dark mode* — and it is only
legible because the picture came from the app rather than from the OS.

### 4. macOS has more than expected, behind one wrong path

S-P3 wrote macOS off for permissions because a write there cannot be verified.
For *appearance and locale* the answer is better, and it turns on the sandbox.

A Flutter macOS app is sandboxed in debug and release alike
(`com.apple.security.app-sandbox` is `true` in both `DebugProfile.entitlements`
and `Release.entitlements` from `flutter create`). So its preferences live in
`~/Library/Containers/<bundle-id>/Data/Library/Preferences/`, and the obvious
host command writes somewhere else:

```
defaults write com.example.deviceProbe AppleInterfaceStyle Dark   # reads back, does nothing (finding 1)
defaults write ~/Library/Containers/com.example.deviceProbe/Data/Library/Preferences/com.example.deviceProbe \
        AppleInterfaceStyle Dark                                  # works, across a relaunch
```

With the container path, a relaunch came up `platformBrightness: dark`,
`locale: fr`, `platformLocales: fr_FR` — **per-app, with no change to the
developer's own Mac.** That is the whole reason macOS looked hopeless: the only
mechanism anyone reaches for first is `defaults write -g`, which repaints every
window the developer has open.

---

## S-D1 — the iOS simulator

Target: iPhone 17 Pro, iOS 26.2, booted by `simctl boot`. Every command is
`xcrun simctl … <udid>`.

| control | command | host cost | live | app observes | readback |
|---|---|---|---|---|---|
| appearance | `ui appearance dark` | 0.11s | yes | yes, `didChangePlatformBrightness` | `ui appearance` |
| text size | `ui content_size <category>` | 0.12s | yes | yes | `ui content_size` |
| high contrast | `ui increase_contrast enabled` | 0.12s | yes | yes, `didChangeAccessibilityFeatures` | `ui increase_contrast` |
| invert colours | `spawn … defaults write com.apple.Accessibility InvertColorsEnabled -bool true` | 0.28s | yes | yes | domain (echo — but the app confirms) |
| reduce motion | `… ReduceMotionEnabled` | 0.26s | — | **no** | echo only |
| bold text | *(none exists)* | — | — | **no** | echo only |
| rotation | Simulator's own **Device ▸ Rotate Left/Right** menu item, pressed through accessibility | 0.15s | yes | yes, `didChangeMetrics`, portrait→landscape | none |
| locale | `spawn … defaults write -g AppleLanguages -array fr-FR` | 0.28s | **no** | **after an app relaunch** | `defaults read -g AppleLanguages` |
| status bar | `status_bar override --time … --cellularBars …` | 0.11s | yes | n/a (not a `MediaQuery` fact) | `status_bar list` |
| deep link | `openurl fwprobe://checkout/42` | 0.12s | app foregrounds | **nothing on `SystemChannels.navigation`** | — |
| deep link, bad scheme | `openurl nope://x` | 0.11s | — | — | refuses: `NSOSStatusErrorDomain -10814`, *"Simulator device failed to open …"* |
| clipboard | `pbcopy` / `pbpaste` | 0.13s | yes | **blocked by a native paste alert** | `pbpaste` |
| media | `addmedia <file>` | 0.18s | — | — | refuses non-media loudly |
| location | `location set 48.8584,2.2945` | 0.10s | — | needs a location plugin | `location list` (named scenarios) |
| push | `push <bundle> payload.json` | **30.14s / 30.11s** | — | **nothing appeared** | prints `Notification sent` for a bundle id that is not installed |
| permission grant | `privacy grant photos <bundle>` | 0.11s | yes | — | — |
| permission revoke | `privacy revoke photos <bundle>` | 0.10s | — | — | **ends the run** |

Six of these need saying out loud.

**Rotation is not a `simctl` capability, and the mechanism that does it lies.**
`xcrun simctl help` lists forty-eight subcommands and none of them rotates. The
only route is the Simulator host app's *Device ▸ Rotate Left/Right* menu item —
which S-N2 already established is reachable through the accessibility helper. It
works, in 0.15s, and Flutter sees it. But it **only works when the Simulator is
frontmost**: pressed with Finder in front, the click returned the menu item
reference exactly as it does on success and the device stayed in portrait
(verified twice, both directions). This is the `AXSetValue` failure mode from
S-N2 again — a mechanism that reports success and does nothing — and it means
the control's real cost is *"takes the keyboard focus away from you"*, which
belongs on the button before it is pressed.

**Locale needs a relaunch and does not need a reboot.** Radon IDE's device
settings say localization *reboots the device*. Measured: `defaults write -g
AppleLanguages -array fr-FR` reads back immediately, the running app never sees
it (`platformLocales` unchanged after 6s), and the very next `flutter run` came
up `locale=fr platformLocales=fr_FR`. **An app relaunch is enough.** No
simulator reboot happened at any point in this spike.

**`simctl push` costs 30 seconds and cannot fail.** Two runs against the
installed bundle: 30.14s and 30.11s — a flat timeout, not work. Nothing appeared
on screen, because the app had never asked for notification authorization, which
S-P5 already established cannot be granted from the host on iOS. And a push at a
bundle id that is not installed returns in **0.11s** with *"Notification sent to
'com.example.nope'"*. So the command's exit code carries no information: a
caller must check `listapps` itself before believing it.

**The clipboard is fought over by three parties.** The simulator syncs the
host's pasteboard by default — the probe's first clipboard read came back
holding this session's own prompt, before any command was issued. `pbcopy` then
worked and `pbpaste` confirmed it. But the *app's* read is gated: iOS 16+ raises
a system alert — *"Flutterware Example would like to paste from
CoreSimulatorBridge"* — which is a native dialog, invisible to the drive layer's
`texts`, and which stalls the awaiting `Clipboard.getData` until somebody answers
it. A "set clipboard" control on this platform hands the user a modal.

**A registered scheme is necessary and not sufficient on iOS.** With
`CFBundleURLTypes` declared, `openurl fwprobe://checkout/42` brought the app to
the foreground (lifecycle inactive → resumed) and delivered **nothing** to
`SystemChannels.navigation`. Adding `FlutterDeepLinkingEnabled = true` to
`Info.plist` and rebuilding changed nothing: a second `openurl` produced no
lifecycle event and no route. Android, same probe, same URL, delivers
`pushRouteInformation {location: fwprobe://checkout/42}` with no opt-in at all.
The cold-launch path on iOS (URL delivered as the initial route) was **not**
measured.

**Revoke ends the run here too.** S-P1 measured this on Android. Confirmed today
on the simulator: `privacy revoke photos` in 0.10s, and in the same second the
launcher's log reads `Lost connection to device.`

---

## S-D2 — the Android emulator

Target: `Medium_Phone_API_35`, Android 15 / API 35, `emulator-5554`. `adb` from
`~/Library/Android/sdk/platform-tools/adb` — as S-N1 noted, not on `PATH` here.

| control | command | host cost | live | app observes | readback |
|---|---|---|---|---|---|
| appearance | `shell cmd uimode night yes` | 0.24s | yes | yes | `cmd uimode night` → `Night mode: yes` |
| text size | `shell settings put system font_scale 2.0` | 0.06s | yes | yes (×1.86 at 14sp) | `settings get system font_scale` |
| bold text | `shell settings put secure font_weight_adjustment 300` | 0.06s | — | yes, **after the activity is recreated** | `settings get` |
| high contrast | `shell settings put secure high_text_contrast_enabled 1` | 0.10s | — | **no** | `settings get` (echo) |
| invert colours | `shell settings put secure accessibility_display_inversion_enabled 1` | 0.06s | yes | yes | `settings get` |
| reduce motion | `shell settings put global transition_animation_scale 0` | 0.07s | yes | yes | `settings get` |
| rotation | `settings put system accelerometer_rotation 0` then `user_rotation 1` | 0.06s each | yes | yes, portrait→landscape | `settings get` |
| locale | `shell cmd locale set-app-locales <pkg> --locales fr-FR` | 0.07s | yes | yes, `didChangeLocales=[fr_FR, en_US]` | `cmd locale get-app-locales <pkg>` |
| display size | `shell wm size 1080x1920` | 0.26s | yes | yes | `wm size` → `Physical` / `Override` |
| density | `shell wm density 320` | 0.16s | yes | yes | `wm density` → `Physical` / `Override` |
| status bar | `shell am broadcast -a com.android.systemui.demo …` | 0.07s | yes | n/a | none |
| deep link | `shell am start -a android.intent.action.VIEW -d <url> <pkg>` | 0.07s | yes | yes, `pushRouteInformation`, **app not restarted** | intent echo |
| deep link, bad scheme | same, `nope://x` | 0.06s | — | — | refuses: *"unable to resolve Intent"* |
| location | `adb emu geo fix 2.2945 48.8584` | 0.04s | — | needs a location plugin | none |
| media | `adb push …` + `content call --method scan_volume` | 0.24s + 1.32s | — | — | — |
| clipboard | *(none)* | — | — | — | `cmd clipboard` → **"No shell command implementation."** |
| permissions | `pm grant` / `pm revoke` | — | grant live; **revoke ends the run** | — | `dumpsys package` (S-P1) |

Four things Android does better than the simulator, and one it does worse.

**Per-app locale, live, with a readback.** `cmd locale set-app-locales` (API 33+)
is scoped to one package, takes 0.07s, and the running app answered with
`didChangeLocales` in the same breath. `alwaysUse24HourFormat` flipped to `true`
along with it, which is exactly the kind of second-order effect a device-level
control is *for*. iOS has nothing comparable: device-wide, and only across a
relaunch.

**Rotation costs nothing and steals nothing.** Two `settings put` calls, 0.06s
each, live, observed, no window has to be frontmost and no focus moves.

**A deep link reaches a running app without an opt-in and without restarting
it.** `am start` printed *"Warning: Activity not started, intent has been
delivered to currently running top-most instance"* — which is the good case
wearing a warning's clothes — and the probe logged the route while the process
kept its state.

**The readback vocabulary is already right.** `wm density` answers `Physical
density: 420` / `Override density: 320`. That is a value **and** whether it is
overridden, in one line, which is precisely what a device panel has to render
per row and what nothing on the iOS side offers.

**Bold text costs the app's state.** `font_weight_adjustment` is observed —
`boldText: true` — but the log shows the activity torn all the way down and back
up: `inactive → hidden → paused → detached`, then `PROBE boot`, a fresh
`main()`. Every other control here is live; this one is a hot restart in
disguise, and it must be labelled as one.

---

## S-D3 — macOS

The host is the device, which is why the interesting question is not *can it be
set* but *can it be set for one app*.

| control | mechanism | cost | app observes |
|---|---|---|---|
| appearance | `AppleInterfaceStyle` in the **sandbox container** prefs domain | relaunch | yes |
| locale | `AppleLanguages` in the same domain | relaunch | yes |
| text size | *(none — macOS has no system text scale)* | — | — |
| rotation, status bar | *(meaningless)* | — | — |
| accessibility flags | `com.apple.universalaccess`, **system-wide** | — | not attempted: it changes the developer's session |
| clipboard | the host's pasteboard **is** the app's | — | trivially |
| deep link | `open <url>` via LaunchServices | — | not measured |
| permissions | TCC — S-P3: a write cannot be verified | — | out |

Both working controls need the container path (finding 4) and a relaunch; both
were measured by launching the built `.app` under `open --stdout <file>`, which
is how a LaunchServices launch can still be read.

The rule that falls out is a scoping rule: **on a host target, a device control
is admissible only if it can be scoped to the app under test.** Appearance and
locale can. Everything else on macOS is either absent or global, and a global
one is a control that reaches out of the cockpit and repaints the developer's
whole desk.

---

## S-D4 — web

`flutter run -d chrome` launches Chrome with `--remote-debugging-port=<port>`
and a private `--user-data-dir`. The port is a live DevTools endpoint —
`http://127.0.0.1:<port>/json` listed the page target and `/json/version`
answered `Chrome/151.0.7922.173, Protocol-Version 1.3`. So a web run already has
a full Chrome DevTools Protocol surface with no extra flag; the only work is
holding a websocket.

Measured through it, each command answering in ~0ms with a 400ms settle:

| CDP call | app observes |
|---|---|
| `Emulation.setEmulatedMedia` `prefers-color-scheme: dark` | **yes** — `platformBrightness: dark` |
| … `prefers-reduced-motion: reduce` | **yes** — `disableAnimations: true` |
| … `prefers-contrast: more` | **no** — `highContrast` stayed false |
| `Emulation.setLocaleOverride` `fr-FR` | **no** — locale and `platformLocales` unchanged |
| `Emulation.setDeviceMetricsOverride` `390×844, mobile: true` | **yes** for size and orientation |
| … `deviceScaleFactor: 3` | **no** — `devicePixelRatio` stayed 2 |

And one property that has no analogue on any other target: **the media overrides
are owned by the DevTools session.** Closing the websocket reverted
`prefers-color-scheme` and `prefers-reduced-motion` within a second, measured on
the same log. The metrics override outlived the close. So on web, half the
controls are only true while flutterware is connected, and the connection is the
setting.

---

## S-D5 / S-D6 — the physical targets, unmeasured

**Physical iOS.** Both known iPhones reported `unavailable` to `devicectl list
devices`, so nothing here was run. What the tool documents:
`xcrun devicectl device` offers `copy`, `info`, `install`, `notification`
(`post` / `observe` Darwin notifications), **`orientation` — "Query or set
simulated device physical orientation"** — `process`, `reboot`, `sysdiagnose`,
`uninstall`. There is no appearance, no text size, no locale, no status bar and
no privacy subcommand. So a physical iPhone plausibly has **one** control the
simulator does not have a clean route to (orientation, with a `get` as well as a
`set`) and none of the rest. `--json-output <path>` is stated to be the only
supported machine interface and is what any implementation should read.
**Everything in this paragraph is documentation, not measurement.**

**Physical Android.** Not measured either, but the mechanism is `adb`, and every
S-D2 command above is plain `adb shell` — the same binary against a different
serial. The one thing that provably drops is `adb emu geo fix`, which is the
emulator console, so **location has no route on a physical Android**. S-P1's
`pm` findings were themselves taken on an emulator and carry the same caveat.

---

## Promoting a live assignment into `ScenarioAxes`

The idea worth testing: a device assignment reached by hand in the cockpit is
also a headless, deterministic scenario waiting to be written, so the tab should
be able to hand one over. `ScenarioAxes` (`app/lib/src/scenarios/axes.dart`)
carries `device, orientation, language, textScale, brightness, boldText,
highContrast, invertColors`. Tested against what the six targets can actually
produce:

| axis | promotable from a live run? |
|---|---|
| `brightness` | **yes**, both mobile targets and web |
| `language` | **yes** — Android per-app live, iOS after a relaunch, macOS after a relaunch |
| `orientation` | **yes** — Android free, iOS at the cost of focus |
| `invertColors` | **yes**, both mobile targets |
| `highContrast` | **iOS only.** Android accepts `high_text_contrast_enabled` and the app never sees it |
| `boldText` | **Android only, and only through a restart.** Unreachable on the iOS simulator by any key that exists |
| `textScale` | **lossy, and silently so.** The axis is a `double` applied by the harness as a linear `TextScaler`. iOS's category ladder promotes faithfully (the table in finding 2 *is* the mapping). Android's `font_scale` is a curve: `2.0` is ×1.86 at 14sp and ×1.00 at 100sp, so no single `double` reproduces it |
| `device` | **blocked.** A live run is on a real device with real geometry (measured: 402×874 @3.0, insets 62/34 on the iPhone 17 Pro; 411×914 @2.625 on the emulator). `ScenarioAxes.device` is a *catalog* id resolved against `Devices.all`, and it has no geometry field to fall back on, so a live device that matches no catalog entry cannot be expressed at all |

So the feature is real for four axes, wrong for two, lossy for one and blocked
for one. **"Promote this assignment to a scenario" as a single button would
produce a scenario that claims to reproduce a screen it does not** — which is
the failure mode this repo spends most of its refusal messages preventing.

The version that survives is the house shape: promote the axes that survived and
**name the ones that did not**, in the offer, before the click. *"Four of six
carry over. `textScale` cannot: Android's font scale is a curve and the axis is
a multiplier. `boldText` cannot: it is not reachable on this target."* That is a
better feature than parity with Radon, and it is honest, but it is a **second**
version — it depends on the table below being right first.

---

## What this settles for the design

**The key of the capability table is `platform × kind`** — the pair `run
devices` already reports (`platform` = `ios|android|macos|web`, `kind` =
`physical|virtual|host`). Six rows: `ios/virtual`, `ios/physical`,
`android/virtual`, `android/physical`, `macos/host`, `web/host`. That pair, and
nothing finer, selects the **mechanism**: `simctl`, `devicectl`, `adb`,
container-scoped `defaults`, CDP. `NativeSession` already resolves exactly this
identity, in exactly these three ways, for the native driver
(`app/lib/src/run/native/native_session.dart`) — adb owns the serial, it is a
booted simulator, it is a macOS bundle — so the discriminator is built.

**A cell is three facts, not one word:** *reach* (is there a command),
*cost* (live · needs a relaunch · restarts the app · ends the run · steals
focus · N seconds), *observation* (was the app seen to see it). The measurements
refuse to let these collapse. On one device, through one mechanism, in the same
minute: appearance is live-and-observed, locale is relaunch-only, reduce motion
is written-and-invisible, and bold text is unreachable. There is no property of
`ios/virtual` from which those four follow.

**Ask the device, do not compile the answer in.** `simctl ui` already answers
`unsupported` and `unknown` as first-class values for a runtime that lacks a
setting; `cmd locale` exists from API 33; `wm density` distinguishes physical
from override. Wherever an owning command has a readback, the table's *reach*
cell should be the device's answer at probe time and not a version comparison in
our source.

**Costs measured, for the controls worth shipping:**

| cost | controls |
|---|---|
| free (≤0.3s, live, observed) | appearance, text size (iOS+Android), contrast (iOS), invert colours, reduce motion (Android+web), rotation (Android), locale (Android), display size/density (Android) |
| **takes focus** | rotation (iOS simulator) — and silently no-ops without it |
| **relaunches the app** | locale (iOS, macOS), appearance (macOS) |
| **restarts the app** | bold text (Android) |
| **ends the run** | any permission revoke (iOS confirmed today, Android S-P1) |
| **30 seconds, and cannot fail** | `simctl push` |
| **invisible on the Screen pane** | status bar (both), location (both), media (both), clipboard (both) |

**Three controls are refused outright, on evidence:**

- **Permissions.** Not on cost — a grant is live and costs 0.11s. On history:
  this repo built the feature across five phases and **removed all of it one day
  later** (#129, *"A permissions panel belongs to the app that has the
  permissions"*), because there is no honest list of an app's permissions before
  a build and the merged manifest goes stale the moment anyone acts on it. The
  Device tab inherits that problem unchanged and adds nothing that solves it, and
  the recipe that replaced the feature already lives in
  `docs/permissions-panel.md`. Revoke also ends the run, re-confirmed on iOS
  today.
- **Push.** 30 seconds against an installed app, silent success against one that
  is not installed, and nothing to show for it unless the app has notification
  authorization — which S-P5 established cannot be granted from the host on iOS
  and which is an ordinary runtime permission on Android, i.e. the previous
  bullet.
- **Bold text.** Unreachable on the iOS simulator and a hot restart on Android.
  Half a control on one platform is worse than none, because the missing half is
  the one a designer is checking.

**Clipboard and location are a different kind of refusal** — the write works
everywhere it exists, and the *result* is unobservable. Location needs a plugin
the app may not have; the clipboard needs the app to read it, and on iOS reading
it raises a native modal. Neither belongs in v1; both are honest v2 candidates
once there is somewhere in the cockpit that can show what came back.

**Device changes should land in the drive journal as steps.** S-N1 finding 2
recorded that a native tap surfaces in the next observe's `human` field, because
the guest's recorder cannot tell `adb` from a finger. A device write has the
opposite problem: **nothing in the app reports it at all.** So without a journal
entry, the Steps tab shows a screen that changed with no cause — the one thing
the journal exists to prevent. The entry must carry the same two facts as the
table cell: what was asked, and whether the app was observed to see it. A locale
change on iOS journals as *asked, not observed* or the journal lies.

**Half the table has no reader yet, and it is our half.** Every cell above is
two facts — what the device answered, and whether the app was seen to observe it
— and the second one is measured here by a probe app that prints its own
`MediaQuery`. **Nothing in flutterware can read that today.** The guest
registers `ext.flutterware.tree`, `.semantics`, `.hitTest`, `.watch`, `.logs`,
`.errors`, `.motion.*`, `.knobs`, `.axes`; none of them reports
`platformBrightness`, `textScaler`, `boldText`, `highContrast`, `invertColors`,
`disableAnimations` or `locales`, and the inspect walk carries layout and
resolved text style rather than arbitrary widget properties. So the observation
half needs a new guest service extension — small (a read of
`WidgetsBinding.instance.platformDispatcher` and the root `MediaQuery`) and
additive, but guest-side, which means **an app built against an older
flutterware cannot answer it at all**. That is a version floor on the feature's
better half, and the design has to choose whether v1 waits for it or ships
without it and says so. What v1 can do with no guest change is annotate from
*this table*: the disagreements measured here are facts, not predictions, and a
control that is known never to be delivered on this platform can say so from a
constant. What it cannot do without the extension is tell *"the platform does
not deliver it"* from *"your app ignores it"* — which is the more valuable of
the two.

**Refusals have real commands to print.** Every mechanism refuses in a way worth
quoting, and the by-hand command exists in every case: `simctl openurl` on an
unregistered scheme gives `NSOSStatusErrorDomain -10814`; `am start` gives
*"unable to resolve Intent"*; `addmedia` gives *"File type unsupported"*;
`cmd clipboard` gives *"No shell command implementation."* This is the pattern
the native log already follows for physical iOS.

**The panel writes to the device and nothing else.** No config file, no
remembered preference, no project state. Everything above is live device state
that a `simctl`/`adb` readback can confirm and that survives nothing except the
device. Two consequences to state on the surface itself: a value set here is
still set after the run stops, and a value set here is set for **every** app on
that device except where the mechanism is per-app (Android locale, macOS
appearance and locale).

---

## Not answered here

- **Both physical targets.** No iPhone was connected and no Android phone was
  attached. `devicectl device orientation` is the one physical-iOS control that
  looks worth having and it is unmeasured.
- **The iOS cold-launch deep link.** `openurl` against a *stopped* app, where the
  URL would arrive as `defaultRouteName`, was not run. Only the warm path was,
  and it delivers nothing.
- **Whether the iOS simulator's Settings app can set bold text**, and what key it
  writes. Driving Settings was out of budget; if the key exists it is created
  there, because it does not exist on a fresh device.
- **macOS deep links and the system-wide accessibility flags.** `open <url>` was
  not measured, and `com.apple.universalaccess` was deliberately not touched — it
  would have changed the developer's own session mid-spike.
- **Whether `prefers-contrast` and `setLocaleOverride` fail on web because Chrome
  does not apply them or because Flutter's web engine does not read them.** The
  measurement is the app's, so it cannot separate the two.
- **Anything about the *panel*.** That is the second pass:
  `2026-08-24-run-device-tab-ui-research.md`.
- The spike's own probe app is not kept. It lives under the session scratchpad
  and is reproducible from the method note at the top: `flutter create`, one
  `build` that prints its `MediaQuery`, and the four `WidgetsBindingObserver`
  callbacks.
