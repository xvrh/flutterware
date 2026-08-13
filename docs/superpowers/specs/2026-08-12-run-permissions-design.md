# Permissions in the Run cockpit — three facts, one profile, a matrix

> **REMOVED 2026-08-13, one day after it was built.** Everything below
> describes a feature that no longer exists in this repository: all five
> phases, the devbar adapter and its five exported types, the four run actions,
> and `launch --permissions`. It never shipped — the removal landed before
> 0.5.2, so no public API was ever committed. **Read the section
> [Why it was removed](#why-it-was-removed) at the end before rebuilding any of
> it**; three of the failures there are properties of the platform rather than
> of the code, and they will be waiting for the next attempt.
>
> The runtime panel — the part people actually asked for — now lives in
> consumer projects. Recipe: `docs/permissions-panel.md`.

**Date:** 2026-08-12
**Status:** Brainstorm, third pass. **Every spike this design named is done
except S-P6** — S-P1 through S-P5, 2026-08-12/13, findings in
`2026-08-12-run-permissions-spike-findings.md`. S-P6 was demoted to optional by
S-P1. Details below (2026-08-12,
`2026-08-12-run-permissions-spike-findings.md`) and their results are folded
into Decisions 3, 5 and 6 and the platform table below. Four findings corrected
this document rather than confirming it, and S-P2's premise turned out to be
wrong outright — the risky mechanism it was written to evaluate is unnecessary.
**S-P5's iOS half is answered as a side effect: no**, and **macOS is confirmed
out of the write path entirely.** The owner answered the two blocking
questions on 2026-08-12: **both surfaces** — set permissions ahead of a launch
*and* report (and where possible switch) them during a run — and, on identity,
*"in an ideal world we display only the permissions that actually apply to the
app, but if we can't deduce it we need a fallback that won't confuse a user."*
Decisions 1–9 below are shaped by those answers and still need the owner's
word before anything is built. The platform behaviour is measured on this
machine today, not recalled.

**Lineage:** `2026-08-12-run-native-fallback-design.md` — the native layer
already taps permission dialogs, which is what makes an *undetermined* profile
testable end to end rather than merely settable.
`2026-08-12-run-knobs-design.md` §A5 — **the staging rule**: a value that
cannot be applied live gets a "Restart to apply" row rather than a silent
restart. That decision answers this feature's runtime question outright, so it
is adopted rather than re-argued.
`2026-08-11-devbar-run-bridge-design.md` — `panelKnob`'s rule ("answers with
the knobs **after** the write … a reply that echoed the request would be a
lie") turns out to be the single most important rule here, for a reason
measured below.
`2026-08-12-sqlite-watch-design.md` — the adapter precedent: flutterware
defines a seam, the app pastes a recipe, no dependency is taken.
`app/lib/src/run/flag_memory.dart` — the wish model, already built and already
carrying the lesson this feature needs.

## The goal

The app is about to run, or is running. What permissions does it ask for, what
does the OS currently hold for it, and what does the app itself think? Set them
before a launch — *off, because today I am testing the grant flow; all on,
because today I am testing something else entirely* — and watch them during the
run. From the cockpit, from `fw`, from MCP. Then run the same app across every
configuration of them and look at the results side by side, because "what does
this screen do when location was denied forever" is a question nobody currently
answers without a phone in hand and five minutes of tapping through Settings.

## What a permission actually is: three facts, not one

The mistake available here is to draw one column called "status". A permission
row has **three independent facts**, and every disagreement between them is a
distinct bug class:

| fact | where it lives | needs a device? | needs the app running? |
|---|---|---|---|
| **Declared** — the app asks for it in its manifest / plist / entitlements | the checked-in source, and the build output | no | no |
| **Held** — what the OS records for this install | the device's own store (TCC.db, package manager) | yes | no |
| **Observed** — what the app believes when it asks | inside the process | yes | yes |

The disagreements are the product:

- **Declared, never requested at runtime** → a permission the store will ask
  about and the app never uses.
- **Requested, not declared** → on iOS an access that crashes for a missing
  usage-description key; on Android a `pm grant` that *silently does nothing*
  (measured below).
- **Held ≠ Observed** → the app cached a status across a change. This is a real
  bug, and today nothing anywhere shows it.

Naming all three up front is what keeps this feature from becoming a
grant/revoke button with no memory.

## What the host can actually do — measured 2026-08-12

Measured on this machine: Xcode's `simctl` as installed, an API 35 emulator
running (`emulator-5554`), `adb` found where `AdbNativeDriver.findAdb()`
already looks (`~/Library/Android/sdk/platform-tools/adb`, not on PATH).

| target | read held state | set | reset to undetermined | how |
|---|---|---|---|---|
| **Android** (emulator + physical) | yes | yes | yes | `dumpsys package <pkg>`, `cmd appops get`, `pm grant/revoke`, `pm reset-permissions` |
| **iOS Simulator** | yes, but not from `simctl` | 11 services | yes | `simctl privacy grant/revoke/reset`; read from the device's `TCC.db` |
| **macOS** | **no** | no | **offered by `tccutil`, but unverifiable and machine-wide — so no** | declared + observed only (S-P3) |
| **iOS physical** | no (adapter only) | no | **yes — by uninstall, behind a confirm** | `devicectl device uninstall`; **no native layer exists here** (S-P4) |
| **Windows / Linux** | n/a | n/a | n/a | no per-app permission model to manage for an unpackaged Flutter app |
| **Web** | via CDP | via CDP | via CDP | `Browser.grantPermissions` / `resetPermissions` — deferred, § Open |

The specifics that shape the design:

**`simctl privacy` writes but cannot read**, and **its help text under-reports
what it writes**. The help lists eleven services; S-P2 probed the namespace
against the real command and found **`camera` and `calls` work too** — they are
simply undocumented. Genuinely refused: `bluetooth`, `local-network`,
`tracking` (ATT), `notifications`, `health`, `homekit`, `speech-recognition`,
`focus`, `faceid`, `nearby-interaction`. There is still no query verb.

**`simctl privacy` also works on an app that is not installed** — unlike
Android's `pm grant` — and S-P4 measured the rest of that sequence: the row
**survives the install that follows**, and survives a reinstall over an
existing app. So Decision 3's "run it once first" is an *Android* rule, not a
universal one, and the § The surface copy must not show the "not installed yet"
state on an iOS target.

**The simulator's TCC database is the read path — but it is not the whole
read path.** `simctl privacy grant location` writes **no TCC row at all**;
location lives in `data/Library/Caches/locationd/clients.plist`, keyed
`i<bundle-id>:` with an `Authorization` integer, and that entry only appears
once the app has installed and registered with `locationd`. The iOS reader
therefore has **two sources**, and the install precondition falls on the read
side for the most-tested permission of all. Notifications are in neither, and
`simctl` refuses them outright.

TCC itself is plainly readable.
`~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/TCC/TCC.db`,
mode `-rw-r--r--`, opened with `/usr/bin/sqlite3` with no Full Disk Access and
no entitlement. `select service, client, auth_value from access` answers
directly; `auth_value` is 0 denied / 2 allowed / 3 limited, and **an absent row
is "not determined"** — which is why a fresh app has no rows at all, as this
emulator's only third-party app does not. Two schema facts matter for the
write question: `client_type` is 0 (a bundle id) and `csreq` is NULL on the
simulator, so a row here carries no code-signing blob to forge.

**macOS is out, and S-P3 found a better reason than the unreadable database.**
The host `TCC.db` is `authorization denied` without Full Disk Access, so there
is no read path — that was known. What settles it is that **the write cannot be
verified either**: `tccutil reset Accessibility <bundle>` reports
*"Successfully reset"* for an app that has never requested Accessibility and
holds nothing. A control there would always claim success and nothing on the
machine could contradict it, which is precisely the failure Decision 7's
read-back rule exists to prevent.

Two further findings seal it. `tccutil` is **machine-wide per bundle id**, and
every worktree builds the same one — 19 registered copies of the example's
bundle id on this machine, 28 of Flutter's default `com.example.app` — so a
reset cannot be scoped to a checkout. And `flutter run -d macos` execs the
binary directly (its parent is `dartvm`, not `launchd`), which is consistent
with the responsible-process rule at `ax_driver.dart:126`, though S-P3 did not
prove what TCC would attribute a request to; that needs root and an app that
asks.

**A running app names itself on both platforms, with no parsing.** Android:
`dumpsys activity activities` → `topResumedActivity=ActivityRecord{… u0
com.example.app/.MainActivity …}`. iOS simulator: `simctl spawn <udid>
launchctl list` → `UIKitApplication:com.example.app[…]`, one line per running
app, Apple's own excluded by prefix exactly as `_installedApps` already does.
This is what makes Decision 2 cheap.

**The measurement that sets a rule.** On API 35, granting a permission the app
never declared:

```
$ adb shell pm grant com.example.flutterware_example android.permission.CAMERA
exit=0
$ adb shell dumpsys package com.example.flutterware_example | grep -c CAMERA
0
```

**Exit 0, no output on stdout or stderr, nothing granted.** A permissions tool
that reported success from an exit code would lie on the most common mistake
its users will make. `panelKnob` already had this lesson from the other side of
the wire; here it is again with a shell in place of an app.

`dumpsys package` splits its answer usefully — `requested permissions:`,
`install permissions:` (with `granted=true/false`) and `runtime permissions:`
are three separate sections, so **declared** and **held** come out of one call
already distinguished. **`cmd appops get` should not be read at all — S-P5 removed it.** It was listed
here as covering what the permission model does not. For `POST_NOTIFICATION` it
covers nothing extra: `pm grant`/`pm revoke` drive the uid-level appop
themselves, so it is a mirror of the permission rather than a second gate. And
it renders that mirror **four different ways** across one round trip —
including `No operations.` on the success path, where a single-regex parser
reads an empty answer for a permission that was just granted. `dumpsys package`
is the one Android source.

**But `granted=` alone is only two of the states, and S-P1 found the other
two.** After a `pm revoke`, a revoked permission and a never-touched one are
byte-identical in `dumpsys` and both say `ignore` to `appops` — yet one prompts
and one does not. The **flags** field is the real vocabulary, and
`pm set-permission-flags` / `clear-permission-flags` write it live:

| state | `granted` | flags |
|---|---|---|
| granted | `true` | — |
| undetermined (`first-run`) | `false` | no `USER_SET` |
| denied | `false` | `USER_SET` |
| denied-forever | `false` | `USER_SET|USER_FIXED` |

And `pm reset-permissions` takes **no package argument** — its own help says
*all* runtime permissions. `first-run` for one app is therefore composed per
permission (`revoke`, then `clear-permission-flags user-set user-fixed`), never
delegated to it.

## Decision 1 (proposed) — three columns, one row, and the disagreement is the headline

The Permissions view is one list per run. Each row is a capability — Camera,
Location, Notifications — carrying its platform-native identifier, and three
cells: declared, held, observed. Rows where the three disagree sort to the top
with the disagreement named in words, not colour.

The capability, not the identifier, is the row. `NSCameraUsageDescription` and
`android.permission.CAMERA` are one row seen from two targets, which is what
lets the same view mean something on a phone and a simulator without the reader
re-learning it. The platform string stays visible, because the moment you need
to act on it — a `pm grant`, a plist edit — the abstraction is in the way.

## Decision 2 (proposed) — the list is the app's own manifest, never a catalogue; identity is a ladder that ends in a text field

Two halves of the owner's answer, and they come apart cleanly.

**Which rows to show** has no hard problem in it. `android/app/src/main/
AndroidManifest.xml` and `ios/Runner/Info.plist` are checked-in files: readable
with no build, no device, no run, on every platform, always. So the list is
**never empty and never a catalogue of every permission the platform has ever
defined**. After a build, re-read the *merged* manifest
(`build/app/intermediates/merged_manifests/<variant>/AndroidManifest.xml`) and
the built `Info.plist`, because that is the only place a permission contributed
by a dependency's manifest appears — and those are the ones people discover at
store review. The list therefore grows once, from "yours" to "yours and your
dependencies'", and the header says which it is showing. A smaller true list
that grows is not confusing; a greyed-out catalogue would be.

**Which app to talk to** is the part with a real constraint, because
`pm grant` and `simctl privacy` need the **application id**, which is
flavor- and build-type-dependent (`applicationIdSuffix`, `.dev`, `.debug`) and
is *not* `RunHandle.package` — that is the Dart package name. Rather than pick
one derivation and be wrong on the projects that most need this, use a ladder,
most-authoritative first, and always show which rung answered:

1. **The running app names itself** — `topResumedActivity` on Android,
   `launchctl list` on the simulator. No parsing, measured above. This rung
   answers whenever there is anything to configure at runtime.
2. **The build output** — the merged manifest's `package`, the built
   `Info.plist`'s `CFBundleIdentifier`. Exact, and free: the same file read for
   the declared list.
3. **The checked-in source** — `applicationId` in `build.gradle`,
   `PRODUCT_BUNDLE_IDENTIFIER` in the pbxproj. Marked as a guess, because
   Gradle is a program and this is a regexp.
4. **The user tells us, once.** A single field, prefilled with rung 3's guess,
   remembered per worktree and package the way `FlagMemory` remembers a wish.

Rung 4 is the fallback the owner asked for: never a silent wrong answer, never
a dialog that reappears, and one obvious thing to correct when it is wrong.

## Decision 3 (proposed) — nothing host-side exists before the first install, and that is one rule, not two

`flutter run` builds, installs and launches in one step with no hook between
install and first frame. So a permission cannot be set "before the app exists":
on the very first run of a project there is no install for `pm grant` to name
and no build output to read an id from.

Those two gaps are the same gap, which is what makes this explainable in one
sentence rather than two: **run it once, and from then on every launch is
configurable.** After the first install, the flow is *apply the profile against
the existing install → launch*, and the run picks the state up at first frame.

The load-bearing assumption was that held state survives the reinstall
`flutter run` performs. **S-P1 measured it and it holds** (2026-08-12): a
granted `ACCESS_FINE_LOCATION` was still granted after a second `flutter run`
reinstalled the APK, with the un-granted three still un-granted. Apply-then-
launch works, and S-P6 is demoted from "might be necessary" to "might be
convenient".

Pre-launch is also the *safe* point, which S-P1 made sharper than expected:
nothing is running, so none of the process-killing commands in Decision 6 can
cost anything.

## Decision 4 (proposed) — a permission wish is host state, sticky, and loudly marked

`FlagMemory` already worked this out for feature flags, and its docstring is
the argument: *"a launch-time flag is useless otherwise — and a forgotten one
is the worst debugging hour there is, so the cockpit shows which knobs are
wished rather than merely overridden."*

Every word transfers. A permission you set for a run is a wish recorded on the
host, applied at each launch, surviving the reinstalls, and shown as wished so
that the Tuesday you spend on "why does location never prompt" is a Tuesday you
get back. Keyed the same way — worktree plus package, not entrypoint and not
device, because a permission you set for the app is one you meant for the app.

**One asymmetry to surface rather than hide.** The wish is per worktree; the
*held state it writes to* is keyed by device and package alone. S-P5 watched
another worktree's build of `examples/example` replace this one's on the shared
emulator mid-spike, taking its permissions with it. Two worktrees pointed at
one device will overwrite each other's permission state silently, exactly as
they share one macOS bundle id (S-P3, finding 14). The cockpit should say which
device a state belongs to rather than implying it belongs to the checkout.

## Decision 5 (proposed) — the unit is a named profile, and the owner named two of them

Individual toggles are the mechanism; **profiles** are what people reach for.
The owner's two sentences are exactly two profiles, and they should each be one
click:

| profile | means | the sentence it serves |
|---|---|---|
| `first-run` | everything undetermined — the app will prompt | *"if I'm testing the permission grant feature, I want it off"* |
| `granted` | every declared permission held | *"if I'm testing something unrelated I grant all ahead of time"* |
| `denied` | every declared permission denied | the error paths |
| `denied-forever` | Android: denied twice, so the OS stops prompting | the state most often handled wrong |
| custom | a named set of per-permission values, saved with the project | everything else |

`first-run` is the one that justifies the build. It is the state every app
spends the most code on and the state that is hardest to get back to by hand —
today it means uninstalling, or tapping through Settings, and it is
irreproducible enough that most people simply never test it twice. `simctl
privacy reset all` and `pm reset-permissions` each do it in one call.

`denied-forever` deserves its own name because it is a distinct OS state with
distinct app behaviour (the request returns immediately; the only recovery is
Settings).

Per-permission overrides sit on top of a profile rather than replacing it, so
"all granted except camera" is two clicks and reads as what it is.

## Decision 6 (proposed) — during the run: always a report, a switch where it is live, and a *staged* row where it is not

The owner's worry — *"we could hit some unwanted auto-restart of the app"* — is
answered by a rule this repo already took for knobs (`2026-08-12-run-knobs-
design.md` §A5): **a change that cannot be applied live is staged with a
"Restart to apply", never applied by restarting behind you.** Adopted whole.

What that means per change, once S-P1 has measured the asymmetry:

- **Reporting is always live and always safe.** Poll the held state, show it
  beside the observed state, and the Held ≠ Observed disagreement becomes
  visible during the run — which is where it actually happens.
- **Granting is live** on Android — measured, the pid is unchanged. That row
  gets a real switch. So do `set-permission-flags` and
  `clear-permission-flags`, which is how `denied-forever` is reached from an
  already-ungranted permission without touching the process.
- **Revoking does not restart the app — it ends the run.** S-P1 measured
  `Lost connection to device` and an `app.stop` in the same second as the
  `pm revoke`; `flutter run` itself exited. `pm reset-permissions` does the
  same, and is global besides. So the split during a run is not
  grant-versus-revoke as this design first guessed, but **anything that takes a
  permission away versus everything else** — and the taking-away rows cannot
  merely stage. The cockpit owns the launch parameters, so the only usable
  version is that it **relaunches**, and the control says so:
  *revoke — relaunches the app*.
- **An app that cached its status will not notice a live change at all** —
  which is the Held ≠ Observed disagreement from Decision 1, now reproducible
  on demand. That is a feature, not a wart.

And the wart that is a feature: "the user revokes camera in Settings while the
app is backgrounded" is a real scenario with real crashes that nobody tests. A
row labelled *revoke — restarts the app* is that test, one click, honest about
the cost.

## Decision 7 (proposed) — the verbs, on the run plugin

Named beside `panels` / `panelKnob` / `panelState`, and available on all three
surfaces from one declaration, as everything in this plugin already is:

- `permissions` — the three-column read. Works with no device for the declared
  column alone.
- `permissionSet {permission, value}` — `granted` / `denied` / `undetermined`
  for one row. **Reads back and answers with the state after the write**, per
  the measurement above. A write that did nothing says so, and a write that
  needs a relaunch says that.
- `permissionProfile {profile}` — apply a named set; answers with the resulting
  state, same rule.
- `launch {..., permissions: <profile>}` — the pre-launch application, so the
  configuration is part of the launch rather than a thing you remember to do
  first.

## Decision 8 (proposed) — the app's own view arrives through a devbar adapter, with no dependency taken

flutterware must not depend on `permission_handler`. Same seam as
`DatabaseAdapter`: flutterware declares the shape, the app pastes four lines
against whatever package it already uses.

```dart
PermissionAdapter(
  status: (permission) => ...,        // Future<PermissionState>
  request: (permission) => ...,       // optional — drives the real dialog
  openSettings: () => ...,            // optional
)
```

This buys three things nothing else can: the **observed** column everywhere
including physical devices; a read path on the two targets where the host has
none (physical iOS, macOS); and — via `request` — the ability to *provoke* the
system dialog on demand, which the native layer then answers. That pairing is
the honest end-to-end test: `first-run` profile → provoke → native tap "Allow"
→ observe the app's next screen. Neither half is worth much alone.

## Decision 9 (proposed) — the matrix is the point, and it is a loop over launches

"Great for testing all configurations" means: pick a set of profiles, run the
app once per profile, capture the same screen from each, show the grid.

Mechanically it is a loop over `launch {permissions: …}` plus the drive layer's
existing `navigate` and screenshot, with one honest cost: **each cell is a
relaunch**, because permission state is read at process start and several of
these changes kill the app anyway. At Android's build times a five-cell matrix
is a coffee, not a keystroke. That is worth saying in the UI before somebody
presses it, and it argues for the matrix being deliberate rather than a view
that runs on open.

Deferred to a phase of its own (§ The build), but the verbs in Decision 7 are
shaped so it needs nothing new.

**Built 2026-08-13, and it did need nothing new.** Measured four cells in 95s
on the emulator, which is a coffee as predicted. Two corrections to the
sentences above: it loops over `launch` and *not* over `launch {permissions:}`
— the sticky wish would put one profile on every cell — and the honest cost is
worth stating twice, because the second thing the build learned is that the
launch returning is not the app being ready to photograph. See § The build 5.

## The surface — what it renders before the first run, and after

Sketched with the owner 2026-08-12 against the cockpit's real anatomy: the
launch page is a 560px column of `_Field(label:, hint:, child:)` rows — Entry
point, Device, Flavor, Defines — and `hint` is where a field says what it
cannot do. Permissions is a sixth `_Field` there, and a sixth tab beside
Screen / Steps / Logs / Network / App. That is what "both" means in furniture.

**The constraint is self-cancelling, which is why the before-state is not an
empty state.** The one profile that cannot be applied before the first install
is `first-run` — and a never-installed app *is* in first-run state. So the
field, on a device the app has never been on, shows the declared rows and the
word **will prompt** against each, with the hint *"not installed on Pixel 7
yet — this launch is a first run"*. That is not a placeholder waiting for a
device: it is the truth, and it is the thing you would want to know before
pressing Start.

What the constraint genuinely costs is one case — *all granted, on an app I
have never run* — and it costs one relaunch, under the hint *"applies from the
next launch"*. That case is rare on its own terms: somebody who has never run
the app is about to watch the prompts regardless. Two ways to close even that
gap, if S-P1 says the rough edge is worse than it reads:

- **`flutter install`** puts the app on the device without running it, so the
  order becomes install → apply → run.
- **`flutter run --start-paused`** holds the isolate at `main`, which is a real
  hook between install and first frame. Stronger, and not free: there is **no
  pause/resume plumbing in the run plugin today** (checked), so it is new work.
  That is S-P6.

Four choices the sketch makes, each of which can be argued with:

- **The field never renders disabled or empty.** Before the first run it shows
  what is true; after, the same rows gain controls. One widget that gains
  powers, not two screens with a state flag between them.
- **The application id is a footer line, not a dialog** — `com.example.app.dev
  — read from the running app`. That is where you would notice it is wrong, and
  it is where rung 4's editable field appears when the ladder falls through.
- **The tab is four columns** — name, declared, held, observed — and a
  disagreement gets **a sentence underneath the row**, not a colour to decode.
  *"The app cached its answer. It has not asked again since the grant."* is the
  finding; amber on its own is only alarming.
- **Every column has to be about the run once a device is chosen.** The middle
  column first showed where a capability is *declared* — `Android · iOS` — which
  was right in Phase 1, when no device was involved. Beside a held column it
  reads as if it describes the run, and on an emulator the `iOS` half is
  unactionable. It now shows the **selected platform's own identifier**
  (`CAMERA`, `ACCESS_FINE_LOCATION`) — the thing you would type into a
  `pm grant` — and says **`not on macOS`** when this platform does not declare
  the capability at all, which is the one case where the held column beside it
  can only ever be blank. The platform list comes back when no device is
  chosen, because then it is all that can honestly be said.
- **Anything destructive names its consequence on the control**: *revoke camera
  — restarts the app*. Straight from the staging rule, and it is why there is no
  confirm dialog.

Two things the sketch left unresolved. **The profile chips are not all
cross-platform** — `denied-forever` is Android-only and would be a lie on a
simulator. Filtering them by the device chosen two fields above is the leaning,
at the cost of a chip row whose width moves when you switch device. And **four
columns at 560px** is the layout least likely to survive being looked at; the
tab is wider than the launch page, so the field and the tab may not be able to
share a row widget after all.

## The disagreement report — the part that works with no device at all

Phase 1 ships with no device attached and no run, and it is already useful,
because the declared column plus a source scan finds:

- **Declared, never requested.** A permission in the manifest that no code
  path asks for.
- **iOS: requested without a usage description.** The crash-on-access case.
- **Android: requested without declaration.** The case whose `pm grant`
  silently succeeds — measured above — and therefore the case a developer will
  spend an hour on.
- **`NSLocationAlwaysAndWhenInUseUsageDescription` without the `WhenInUse`
  key**, and its Android twin, `ACCESS_BACKGROUND_LOCATION` with no foreground
  location permission. Both are "the prompt never appears".
- **Post-merge surprises**: a dangerous permission contributed by a
  dependency's manifest that nobody in the project wrote.

## Experiments — what gates the build

- **S-P1 (the Android round trip) — done 2026-08-12, findings in
  `2026-08-12-run-permissions-spike-findings.md`.** `examples/example` carries
  the four runtime permissions as a fixture. Verdict: the load-bearing
  assumption holds; revoke ends the run rather than restarting the app; three
  states need the flags, not `granted=`; `reset-permissions` is global.
  Decisions 3, 6 and the platform table were corrected in place.
- **S-P2 (the eleven services problem) — done 2026-08-12, and the premise was
  wrong.** `simctl privacy` supports `camera` (and `calls`); only its help text
  omits them, so **no TCC writing is needed** and the recommendation against
  shipping it now costs nothing. Hand-written rows were measured anyway and do
  work — they persist with no shutdown, survive a reboot, and `simctl reset`
  removes them like its own — so the escape hatch exists if a service is ever
  genuinely unreachable. Run on a throwaway device, deleted afterwards.
  Notifications are refused outright, which answers **S-P5's iOS half: no.**
- **S-P3 (macOS) — done 2026-08-12. The suspicion was right, the reasoning was
  not.** macOS is declared-and-observed only, but because `tccutil` reports
  success unconditionally (so no write can be read back) and is machine-wide per
  bundle id (so no reset can be scoped to a worktree) — not merely because the
  database is unreadable. What TCC attributes a request to remains unmeasured
  and needs root plus an app that asks.
- **S-P4 (physical iOS) — done 2026-08-12, and the question was unaskable.**
  `layer: native` gets nowhere into Settings.app because **it does not exist on
  a physical iPhone**: `NativeSession.isAvailable` needs adb, `macos`, or a
  *booted simulator*, and a real device is none of them — the AX driver reads
  the Mac's own accessibility tree, which a phone is not on. `foreground` is
  gone for the same reason, so a suspended app there comes back only by hand.
  `devicectl` has no privacy verb either. **But `uninstall` clears TCC
  outright** (measured on a simulator), so `first-run` — the profile that
  justifies the feature — is the one write physical iOS does have. It destroys
  app data too, so it is the only write in this design behind a confirmation.
- **S-P5 (notifications) — done. Android: an ordinary runtime permission**,
  grant live, revoke ends the run, no second gate. Its value was negative in
  the useful sense: it **removed `cmd appops get`** from the design, because the
  appop mirrors the permission and renders four different ways. **iOS: no** —
  answered by S-P2.
- **S-P6 (the pre-install gap), only if § The surface's rough edge is judged
  too rough.** Does `flutter install` followed by `flutter run` preserve the
  applied state, and can `--start-paused` plus a VM resume be driven from the
  run plugin at all? There is no pause/resume plumbing in the plugin today.

## Where the bugs would come from

Worth writing down before building, because the risk is not evenly spread and
one phase carries almost none of it.

**Phase 1 is close to risk-free.** Parse two checked-in files, show a list, run
lints. A pure function of files on disk — fixture-testable, no device, no
async, no process. If it is wrong it is wrong the same way every time.

**The fragile part is `dumpsys` scraping, and the bug has a name.** That output
is not a contract; sections move between Android versions, and the failure mode
is not a crash but an **empty parse that looks like an empty answer**. So the
rule is: a parse that matched nothing is an *error state*, never an empty list.
"No permissions found" and "could not read this device" must not render the
same, and the second must say which command it ran.

**The one compound risk is the one already designed against.** A wrong
application id plus a `pm grant` that exits 0 and does nothing (measured) is
"I pressed grant, nothing happened, and nothing told me" — the bug that would
make the whole feature feel broken. The read-back rule from Decision 7 kills it
structurally rather than by care: every write is followed by a read, and a
change that did not land says so. That single rule is why the write phase is
buildable at all.

**The live/staged split is where state bugs live.** Specifically: revoke,
process dies, and the observed column keeps showing its last value forever
because there is no app left to ask. The observed column must be tied to the
connection and fall to `—` when it drops. The cockpit already has that concept
(`enabled` on the tab strip, `RunProbe`), so it is precedent to copy rather
than a mechanism to invent.

**The one I would not ship was S-P2's write, and the spike removed the
question.** `simctl privacy` covers camera after all, so nothing needs a
concurrent write into a live daemon's sqlite. The escape hatch was measured and
does work, but it stays unbuilt: the failure mode is a corrupted simulator
rather than a wrong answer, and there is now nothing it buys.

**The `plutil` read for location is a new small risk of the same family as
`dumpsys`.** It is a plist whose layout is Apple's, not a contract, and the
"empty parse is an error, not an empty answer" rule applies to it identically.

**What looks risky and is not:** the platform breadth. Each target is an
independent adapter behind one interface, so an Android parsing bug cannot
reach the iOS path, and a platform with nothing to offer renders a sentence
rather than failing. And the feature is read-mostly — four of five phases never
write anything.

**Verification is unusually cheap here**, which is the strongest buildability
argument: an emulator and a simulator are both up, the MCP loop drives this GUI
at ~2s a round trip, and the whole thing is inspectable from `fw`. The caution
from `feedback_generic_panel_render` still applies — a surface verified only
over MCP has shipped unusable before, so the tab gets eyeballed in the cockpit
before it is called done.

## The build — phased so each phase ships alone

1. **Declarations and the disagreement report — BUILT 2026-08-13.**
   `app/lib/src/run/permissions.dart` (catalogue, parsers, lints),
   `RunPermissionsResult` and the `permissions` action on the run plugin — so
   it is on the GUI, `fw` and MCP from one declaration — and a `_Field` on the
   New run page. 18 tests, `flutter analyze` clean, the full app suite green.
   No device, no run, every platform.

   Three things the build changed, each found by looking at the real output
   rather than by design:

   - **Findings only for capabilities the catalogue names.** Unfiltered, the
     first two findings against `examples/example` were
     `android.permission.INTERNET` and Flutter's generated
     `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — engine boilerplate in every
     Flutter app ever built.
   - **Named capabilities are rows; everything else is a footnote.** The same
     two were 2 of 5 rows in the first render, one wrapping onto two lines.
     Both are still reported — dropping a declaration would make the list a
     lie — they are just not what the field is about.
   - **The merged manifest is ignored when the source is newer than it.**
     `fromDependency` means "in the merged manifest and not in this app's", and
     a build older than the last edit turns that into a false accusation: a
     permission deleted seconds earlier was still listed, attributed to a
     dependency that had never asked for it. Caught in the cockpit, not in a
     test.

   Also note: **entitlements are only read where they gate a named
   capability.** `com.apple.security.*` covers JIT and network sockets too, and
   those are not permissions anybody is granted.
2. **Held state, host-side — BUILT 2026-08-13.**
   `app/lib/src/run/permission_state.dart`: the four-state Android read from
   `dumpsys package`, the simulator read from `TCC.db`, the identity ladder,
   and per-device dispatch. `permissions` gained a `device` parameter; the New
   run page gained the held column. 15 more tests, all pure — the parsers are
   separated from the shelling out so CI needs no device.

   Verified end to end against the live emulator: three states set with `adb`
   came back as granted / denied forever / denied in the cockpit.

   Four things worth recording:

   - **The TCC service map is measured, not recalled** — every service
     `simctl privacy` accepts, granted on a throwaway simulator and read back.
     Both location variants confirmed to write **no TCC row at all**.
   - **iOS location and notifications read `unknown`, not blank.** A missing
     value would say "no device asked"; these were asked about and the store
     does not cover them, which is a third thing. Each carries its reason.
   - **A refusal names the device it was asked about.** The first catch-all
     told somebody asking about Chrome that physical iPhones have no store —
     true, and not an answer to the question.
   - **Location on the simulator stayed unreadable even with the app running.**
     `locationd`'s `clients.plist` did not appear on a fresh device at all, so
     the enum behind its `Authorization` value is still unmapped. Reported as
     unknown rather than guessed.

   **Not done in this phase:** the Permissions *tab* in the run cockpit — the
   during-the-run report half of Decision 6. The held column went on the New
   run page instead, because that page already has both a package and a device
   chosen and is where Phase 3's profile control belongs. The tab needs the
   same row widget and a live poll; it is the smaller half and it is deferred
   deliberately, not forgotten.
3. **Writes and profiles — BUILT 2026-08-13, with one known defect.**
   `app/lib/src/run/permission_write.dart` (the command plans, the profiles,
   the read-back), `permission_memory.dart` (the `FlagMemory`-shaped wish),
   `permissionSet` and `permissionProfile` actions, `launch {permissions:}`,
   and profile chips on the New run page. 17 more tests.

   Verified live on the emulator, through the action layer: `granted` set all
   three permissions and read them back; `permissionSet location
   deniedForever` changed one; `first-run` returned everything to undetermined
   and the raw `dumpsys` agreed. The wish is sticky and loud — after
   `launch --permissions granted`, knocking camera back to undetermined by
   hand and launching again with **no** permissions argument re-applied it and
   said *"Permissions: "granted" applied before launch."*

   Two things the build changed:

   - **A write to an undeclared permission is refused before it runs.** Asked
     to grant microphone on an app that never declared it, the first version
     ran four `adb` commands and reported success — because `pm grant` exits 0
     and does nothing, and the read-back cannot expose it: a capability the app
     does not declare has no row to be wrong in. The read-back rule has a hole
     exactly there, and the guard closes it.
   - **The flags are cleared before every write, not just set.** Going
     denied-forever → granted with `pm grant` alone leaves `USER_FIXED` on the
     permission, so the next read shows a granted permission the user
     supposedly refused permanently.

   **The column refresh is fixed.** Pressing a chip now shows the read-back
   immediately — verified both directions on the emulator, `All granted` →
   three greens, `First run` → three "will prompt", each matching `dumpsys`.
   Getting there took three wrong theories and turned up two real defects plus
   one thing that was never a bug:

   - **A NUL byte was acting as a key separator in one of three places.** The
     cache key `'$package $device'` was written three times, and one copy had a
     NUL where the space should be — this repo uses one deliberately in
     `FlagMemory.keyFor` and `closure.dart`, and it is invisible in an editor.
     The write stored its read-back under one spelling while the reader looked
     up another, so the column kept the pre-write answer for ever. There is now
     one `_heldCacheKey` getter and an explicit `|` separator. The same NUL
     made **`grep` treat the whole file as binary and silently report no
     matches** — which cost more time than the bug, because several searches
     came back empty and were believed.
   - **`FutureBuilder` keeps `snapshot.data` when its future changes** — it
     only moves the connection state. Switching device rendered the previous
     device's permissions under the new device's name, with profile chips the
     new device could not offer. Chrome showed the emulator's rows. A
     `ValueKey` on the builder makes it a fresh element that cannot carry a
     stale answer.
   - **And one false alarm worth recording**, because it wasted a full round of
     debugging: for part of the session the column read `—` and the write
     appeared to do nothing. The APK on the emulator had been replaced by
     another worktree's build — the shared-device hazard S-P5 documented — so
     the installed app declared no runtime permissions at all. The display was
     correct; the device was not what I thought it was. **Check what is
     actually installed before believing a permissions bug.**
4. **The adapter — BUILT 2026-08-13.**
   `lib/src/devbar/plugins/permissions.dart` (the seam and its panel) and
   `permissions_plugin.dart` (the devbar wrapper), exported from
   `lib/devbar.dart`. No permissions dependency in flutterware, exactly as
   `DatabaseAdapter` takes no sqlite one. The panel serves a `status` state and
   — only when the app wired them — `request` and `openSettings` actions, so it
   reaches the cockpit, `fw` and MCP with no new plumbing. 9 tests against a
   fake app. `observedPermissions` on the run core reads it; `permissions`
   gained an `observed` field per row and the New run page a fourth column.

   Dogfooded for real: `examples/example` wires `permission_handler` behind an
   adapter (`lib/src/devbar/permission_adapter.dart`). Verified on the
   emulator — granting camera through `permissionSet` flipped **both** held and
   observed to `granted`, read from two entirely different places.

   Three things the build settled:

   - **`permission_handler` has no *undetermined*.** Never-asked and refused
     both arrive as `denied`. The example's adapter maps that to **`unknown`**
     — "this app cannot tell those apart" — because mapping it to `denied`
     would make **every app in `first-run` show a permanent, meaningless
     disagreement**, and `first-run` is the state this feature exists for.
     Choosing that is what an adapter is *for*; flutterware could not have
     guessed it. (Phase 5 found the same argument applies to
     `permanentlyDenied` on Android, and the adapter now maps that to
     `unknown` too — see § The build 5.)
   - **A disagreement is only flagged when both sides are real answers.**
     `unknown` on either side means "cannot tell", not "conflict".
   - **`permission_handler_android` 14 needs Android SDK 37**, which this
     machine does not have; the example pins `^12.0.0`. Nothing in the adapter
     depends on the version — it maps six stable enum values.

   Also worth knowing: **a plain `flutter run` is invisible to the cockpit.**
   Run handles are written by `launch`, so the observed column reads nothing
   from an app started outside flutterware. Cost a debugging round.
5. **The matrix — BUILT 2026-08-13.**
   `app/lib/src/run/permission_matrix.dart` (the profile parsing and the
   comparison), the `permissionMatrix` action, `RunPermissionMatrixResult`
   with an artifact per cell, and `permission_matrix_view.dart` — the dialog
   and the grid. 17 more tests. Decision 9 held: it needed **no new verb**,
   only a loop over `launch` plus the drive layer's existing observe.

   Measured on the emulator, `examples/example`: **four cells in 95s**
   (25 / 24 / 22 / 24), each a stop, a profile write, a full relaunch and an
   observation. The held column of every cell came back as the profile asked
   for, read from `dumpsys` after the picture rather than from the write.

   Four things the build settled, three of them found by running it:

   - **The matrix leaves the wish alone.** It calls `launch` rather than the
     launch *action*, because the action applies the sticky profile and would
     stamp one profile over every cell. A sweep is not a configuration — and
     when a wish *is* in force the reply says so, since it will quietly undo
     the last cell at the next ordinary launch.
   - **`awaitLaunch` returning is not the app being ready to look at.** The
     first matrix ever run came back with two of four cells empty, in the two
     distinct ways a too-early look fails: *"this app is running without the
     drive guest"* (the extension had not registered) and *"Invalid image
     dimensions"* (no frame had been laid out). Both are transient and neither
     is distinguishable from a real refusal. The observe now retries until
     there is a **picture** — not until `ok`, because a genuinely refused
     verb still photographs the screen it was refused on, and re-reading that
     eight times would cost six seconds a cell for nothing.
   - **The first failed launch ends the run.** What fails a launch here is
     nearly always the build or the device, and neither improves by being
     asked three more times at a minute and a half each. The cell keeps its
     slot with the reason in it; the note says the rest were not attempted.
   - **A fixed column width hid the fourth cell** behind a horizontal
     scrollbar nobody could see — in the one view whose entire purpose is
     four things side by side. Columns now shrink to fit and only scroll
     below 150px. Found by looking at it, like every other layout bug in this
     feature.

   **And the matrix found a real one on its second run, which is the point.**
   In the `first-run` cell the OS says *will prompt* and the app says
   **denied forever** — in red, on all three permissions. That is not a bug in
   the matrix: on Android `permission_handler` derives *permanently denied*
   from `shouldShowRequestPermissionRationale`, which is false **both** before
   the first ask and after a "don't ask again". A never-asked permission and a
   permanently-refused one are the same value, so an app that shows *"open
   Settings"* on `permanentlyDenied` shows it to a brand-new user who has
   never been asked anything. Nothing outside the process can see that, and
   nobody was looking for it.

   **Settled by the owner 2026-08-13: the example's adapter maps
   `permanentlyDenied` to `unknown` on Android**, the same rule it already
   applies to `denied`, and keeps `deniedForever` on iOS — where the status
   comes from a real stored answer rather than from a rationale flag. The fix
   is in the app, not in flutterware, which is where a mapping decision
   belongs.

   Measured after the change, all four profiles on the emulator: `granted` →
   observed `granted`; `first-run`, `denied` and `denied-forever` → observed
   `unknown`. So **Android's observed column is granted-or-unknown**, and that
   is the honest size of what `permission_handler` can tell an app there. It
   is not a limit of the design: an app that asks the platform itself, or
   records its own first ask, gets a sharper column from the same seam.

   **Two defects a review pass found afterwards**, both about something
   travelling to the wrong place:

   - **The matrix built a different app from the Start button beside it.** It
     took the entry point's *declared* flavor and none of its knobs, so a
     flavor typed into the override field or a knob the entry point needs was
     honoured by Start and silently dropped by Compare — four cells of
     something else, or four identical build failures. The page now reads its
     fields once (`_choices`) and both buttons launch from that reading, the
     dialog takes `flavor` and `knobs` as *required, nullable* parameters so
     no future caller can inherit a default that drops one, and it prints the
     build it is about to make above the button.
   - **One app's self-report was published under every package's name.** The
     observed column is read once for a device — one device runs one app — but
     `permissions` attached that map to the rows of every package in the
     reply. On a two-package workspace the running app's belief appeared as
     the sibling's, where the disagreement rule then compared it against the
     sibling's held state. Held is a property of the pair (device, package)
     and every package gets its own; observed is a property of one *process*
     and is now filed under that process's package alone.

   **Four more from the same pass**, each one something reported wrongly or
   not at all:

   - **A failed profile write said nothing.** `_applyProfile` rethrew into a
     future invoked as a `ValueChanged` and therefore dropped, so the throw
     reached the console and nothing else: the chip stopped spinning, the
     column kept its pre-write value, and the page looked like the write had
     landed. It now sets `_error`, the same field a failed launch uses.
   - **Profiles no longer refuse what the platform has no concept of.**
     `profileTargets` swept every declared capability regardless of the
     platform being written to, so an app declaring `NSFaceIDUsageDescription`
     sent faceId to the Android writer, which answered *"faceId has no Android
     permission behind it"* — into the launch note of **every** launch with a
     wish in force. It now takes the platform, from the cached device list
     (free) and **null means do not narrow**, because a device nothing can
     name is not grounds for dropping capabilities. Only profiles narrow:
     `permissionSet faceId` on Android is still refused loudly, since there
     the caller named the capability. Both halves measured on the emulator
     with the key temporarily added to the example.
   - **The matrix baseline could silently become a later cell.** `baseline ??=
     act.texts` left it null when the first cell produced no texts, so the
     second became the reference while the grid went on labelling the first
     "compared against". An explicit flag makes the first observed cell the
     baseline even when it is empty — and then every `added` is empty, which
     is the honest reading.
   - **The declarations cache never noticed a build.** It is keyed per package
     with `??=` and nothing cleared it, including on the entry-point change
     its own docstring claimed. Cleared now when the matrix dialog closes —
     the one build that finishes while this page is on screen — and on an
     entry-point change; Start needs none, because it navigates to the run and
     coming back rebuilds the state. A build started elsewhere is still not
     noticed, and the comment now says so instead of promising otherwise.

## Open — still needs the owner's word

- **Where it lives.** The owner said both surfaces, which settles behaviour but
  not furniture: a Permissions tab in the run cockpit, or a section of a wider
  **Configuration** tab alongside simulated location, locale, network
  conditioning and text scale — all of which are "launch the app in a
  configuration and look at it". Phase 1 is identical either way, so this can be
  decided late, but not never.
- **Where the wish lives** — a `permissions` key inside `flags.json`, or its
  own file beside it. The former keeps one memory; the latter keeps two
  vocabularies apart.
- **Web.** Chrome DevTools Protocol has `Browser.grantPermissions` and
  `resetPermissions` — a complete grant/revoke/reset surface, better than macOS
  gets. It needs the run plugin to hold a CDP connection it does not hold today.
- **Windows.** An unpackaged Flutter app has no per-app permission model worth
  managing; a packaged one has capabilities in the appx manifest. Proposed:
  declare-only, and say why rather than showing an empty list.
- **How much source scanning** the "declared, never requested" lint should do.
  The `entrypoint_knobs.dart` precedent — parse with `analyzer`, report where the read
  is — is right there and works; the question is whether a permission asked
  through three layers of a package is findable that way, or whether the lint
  should only fire on high confidence.

## Why it was removed

Written 2026-08-13, the day after the build, with the feature deleted in the
same commit. Everything above stays as written — the measurements are the
expensive part and they remain true. What follows is why they were not enough.

### The declared third cannot answer its own question on Android

This is the finding that decided it, and it applies to the phase the design
called "close to risk-free".

`AndroidManifest.xml` is not the list. Dependencies contribute permissions
through manifest merging, and the merged manifest exists only after a build.
The design knew this and called it "the list grows once". It is worse than
that in two directions:

- **Before a build, the list omits precisely the permissions the feature was
  most valuable for.** This document says it itself about the dependency-
  contributed ones: *"These are the ones people meet for the first time at
  store review."* Those are exactly the entries missing from a pre-build list.
- **After a build, the list is complete only until the next manifest edit.**
  `_isStale` correctly rejected a merged manifest older than the source — a
  stale merge misattributes permissions to dependencies. But editing
  `AndroidManifest.xml` is what you do when you act on this panel's advice, so
  **the feature invalidated its own completeness the moment anyone used it.**

`merged: false` was therefore the normal state, not the pre-build one.
Demonstrated on this repo's own dogfood example, which had a build on disk:
the reader reported Camera, Location and Notifications, said `merged: false`,
and omitted `android.permission.INTERNET` — which the engine contributes to
every Flutter app ever built.

Apple has no equivalent problem: nothing merges into `Info.plist`, so the
Apple half of the list is complete without a build.

### Which lints survive that, and which do not

| finding | sound without a current merge? |
|---|---|
| `emptyUsageDescription` | yes — Apple-only |
| `locationAlwaysWithoutWhenInUse` | yes — Apple-only |
| `unreadable` | yes |
| `backgroundLocationWithoutForeground` | **no** — a dependency contributing `ACCESS_FINE_LOCATION` makes it fire wrongly |
| `platformMismatch`, Android→iOS | **no** — silently misses dependency-contributed permissions |
| `fromDependency` | **no** — definitionally needs the merge |

Three of six. And the three that survive are Apple usage-description checks:
roughly 150 lines of lint, not a cockpit feature.

### `platformMismatch` was wrong in a way worth recording

Shipped, it fired on a consumer app that had been in production for months,
twice: camera and photo library declared on iOS, absent on Android, reported as
*"the other platform will refuse it at runtime"*. Android refuses nothing
there. The lint assumed a capability's declaration requirement is symmetric
across platforms. It is not — Apple wants a usage description for *any* access,
however mediated, while Android wants a permission only for *direct* access,
and the delegated routes (`ACTION_IMAGE_CAPTURE`, the system photo picker,
`ACTION_PICK` on contacts) ask for nothing at all.

**Following that advice would have broken the app**: once
`android.permission.CAMERA` is in the manifest, Android enforces the runtime
grant on `ACTION_IMAGE_CAPTURE` too. A fix landed (directional lint, plus a
per-capability "Android delegates this" fact) and is preserved here rather than
in code. Any future attempt needs both halves of that rule.

### The adapter seam belonged in the consumer's project

`PermissionAdapter` existed so flutterware would not depend on
`permission_handler` — the `DatabaseAdapter` precedent, correctly applied. But
the consumer already depends on a permissions package, so the seam only
translated their vocabulary into ours, and the translation was lossy in the one
place it mattered:

- `permission_handler` has no *undetermined* — never-asked and user-denied both
  arrive as `denied` — so the adapter mapped it to `unknown`.
- Android's `permanentlyDenied` is derived from
  `shouldShowRequestPermissionRationale`, which is false **both** before the
  first ask and after "don't ask again", so a fresh install reported every
  permission permanently denied — also mapped to `unknown`.

Two of six states survived the trip. The shared vocabulary existed so
`observed` could sit beside `held` and `declared` without translating; with
those two columns gone, it was translating into a language nothing speaks.

Written directly against the app's own package, in the app's own project, there
is no mapping and nothing is lost — and `DevbarPanelSource` was already public,
so it needed no new API. That is `docs/permissions-panel.md`, and it is the
better test of the extension point: a real app builds a real panel on it
without flutterware shipping the panel.

### What a future attempt should know

- **The runtime panel is the part with demand**, and it does not need any of
  this. It needs no manifest parsing, no `dumpsys`, no host side at all.
- **`first-run` is the verb worth having** — every permission back to
  undetermined, so the app prompts as it does for a new user. It is the one
  thing the deleted host-side code did that nothing else can, and it is
  impossible from inside the app on either platform.
- **A declared list is only worth showing if it is complete.** That means
  either running Gradle's `processDebugMainManifest` on demand, or unioning the
  app manifest with every plugin's manifest via `.flutter-plugins-dependencies`
  — the latter is cheap and build-free but still misses transitive AAR
  permissions (Firebase, play-services), which is the same disease in a smaller
  dose. Showing the app's own manifest and captioning it as partial is what was
  tried, and it reads as complete however it is captioned.
- **`dumpsys`, `simctl privacy` and `plutil` are not contracts.** The
  empty-parse-is-an-error rule and the read-back-after-every-write rule were
  both right and should be carried forward verbatim by anyone rebuilding this.
