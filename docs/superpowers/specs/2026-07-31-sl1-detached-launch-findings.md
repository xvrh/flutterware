# S-L1 — Detached launch and third-party control: findings

**Date:** 2026-07-31
**Status:** Complete across five targets — macOS, iOS simulator, **wireless
iPhone**, **wired iPhone**, **wired Android**. The core question is answered
**yes**, with one platform-specific exception that puts a design decision back
on the table.
**Brief:** `2026-07-31-app-launcher-cockpit-brainstorm.md` § Spikes.

## The question

Can a `flutter run` launched **detached** be controlled afterwards by an
**unrelated process** — the D1 claim that lets the cockpit answer every surface
without a resident supervisor?

## Verdict

**Yes on every target.** A process that shares nothing with the launcher
connects to the app, reads its widget tree, screenshots it, hot-reloads and hot-
restarts it.

Two qualifications, both load-bearing:

1. **Reload and restart are *tool-owned* capabilities.** They are registered on
   the VM service by `flutter run` itself, so they vanish the moment it exits —
   everywhere. Inspection and drive verbs live in the app and do not.
2. **On a wired iPhone, killing the launcher kills the app.** Nowhere else.
   That is the primary target, so "detached but alive" is a hard requirement
   there rather than a preference.

## What ran

Three throwaway scripts (session scratchpad, nothing committed): `launch.dart`
spawns `flutter run --machine` with `ProcessStartMode.detached` writing to a log
file and a handle; `watch.dart` reads the log from a different process;
`control.dart` connects to the VM service knowing only the `wsUri`. SDK
3.47.0-0.1.pre.

Targets: macOS; iPhone 16 simulator (iOS 18.1); **iPhone 11 Pro, iOS 26.5,
wireless**; **iPhone 16 Pro, iOS 26.5.2, cabled**; **Samsung SM-G970F, Android
12 (API 31), cabled**.

`examples/example` cannot sign for a device (`No Account for Team
"B7V224LKE4"`), so the hardware legs used a **throwaway probe app built in the
scratchpad**, signed manually against the locally-installed wildcard profile
`PS45A9TPZ7.*` (owner-approved). Nothing in the repo was touched, no account was
signed in, no profile was minted.

## Results

### Third-party control works everywhere

| | macOS | iOS sim | iPhone wireless | **iPhone wired** | **Android wired** |
|---|---|---|---|---|---|
| VM service connect | 35ms | 34ms | 36ms | 33ms | 36ms |
| widget tree | 17–25ms | 34ms | 69ms | **41ms** | **125ms** |
| `inspector.screenshot` | 38ms | 50ms | 110ms | **72ms** | **172ms** |
| `reloadSources` | 54ms | 75ms | 1571ms | **289ms** | **283ms** |
| `hotRestart` | 218ms | 232ms | 894ms | **760ms** | **1508ms** |

Registered services are identical on all five: `compileExpression`,
`flutterMemoryInfo`, `flutterVersion`, `hotRestart`, `reloadSources`. So
`hot_reload.dart`'s documented claim — the tool registers reload and restart as
VM-service methods any client may call — is confirmed from a process that did
not launch the app and shares nothing with it.

**The wire matters more than the device.** The same iOS operation is 5× cheaper
cabled than wireless (reload 289ms vs 1571ms). Wireless is not merely slower to
install onto; it taxes every interaction, which is a per-call cost the cockpit
pays forever.

iOS reports its VM as `ios_simarm64` — Dart's *simulated* ARM64 backend, the
interpreter used where JIT codegen is not permitted. Android reports
`android_arm64`, i.e. real JIT. That is the standing explanation for iOS debug
being slow, and it taxes the whole cockpit loop rather than reload alone.

### Cold launch: install dominates on iOS, compile dominates on Android

| | build | install + launch | **total to `app.started`** |
|---|---|---|---|
| macOS | 14.8s | — | 24.2s |
| iOS simulator | 27.8s | ~6s | 41.2s |
| **iPhone 11 wired** | ~11s | **14.2s** | **40.7s** |
| **iPhone 16 wired** | 28.1s | **11.8s** | **48.4s** |
| iPhone 16 wired, *warm* rebuild | ~10s | 10.9s | **23.0s** |
| iPhone 11 wireless † | 24.8s | 55.0s | 93.6s |
| iPhone 16 wireless † | ~12s | ~330s | 342.7s |
| iPhone 16 wireless, retry † | 22.4s | ~106s | 128.1s |
| **Android wired** | **82.8s** (cold Gradle) | **4.5s** | **98.4s** |
| Android wired, *warm* | warm | ~1.5s | **9.6s** |

† **Every wireless row waited on a human dismissing an OS dialog** — a device
trust prompt, then macOS local-network permission, which re-fired on the retry.
They are upper bounds of unknown looseness and should not be quoted as the cost
of wireless. The wired and Android rows had no dialogs.

All for a hello-world app, so a real app is worse.

**The 55.0s wireless install figure is not clean** (owner, 2026-07-31): it
includes a human tapping a trust/accept prompt on the phone. Treat it as an
upper bound.

**Neither is the 342.7s one** (owner, 2026-07-31): that run raised macOS's
*"allow to discover devices on your network"* prompt and sat waiting for a
human to answer it. **Every wireless install figure in this spike is
human-contaminated**, and the honest position is that the wireless install
penalty was never cleanly measured here — see the re-measurement below.

What *is* clean, because no human is in the loop: the per-interaction costs.
iOS reload is **289ms wired against 1571ms wireless**, tree 41ms against 69ms.
The flutter tool's own `ios-wireless-slow` warning for iOS 26 has support in
those numbers, not in the install ones.

### The permission prompt is the finding, and it does not fire only once

A wireless run blocks on a **macOS local-network permission dialog**,
indefinitely, while the daemon reports only `Installing and launching…`. From
the outside that is indistinguishable from a slow install.

A re-measurement was attempted after the permission had been granted, and
**the prompt appeared again** (owner-observed) — so the grant did not stick
across runs. Its 128.1s is therefore contaminated too, and **no clean wireless
install figure exists from this spike**. The wireless install penalty is
*unquantified*, not 28× and not 9×; the three measurements taken (55.0s,
342.7s, 128.1s) differ mostly by how fast a human noticed a dialog.

Two consequences, and the second is the one that matters:

- **The cockpit must model "waiting for permission" as a state**, not spin on
  a progress bar. It is the only phase of a launch that can block forever on
  something outside the tool.
- **Re-prompting is plausibly an artifact of launching from a CLI.** macOS
  attributes local-network access to an application; a bare `dart`/
  `flutter_tools` process launched from a terminal is a weak subject for that
  attribution, whereas the flutterware GUI is a real bundle and would be
  expected to prompt once and stay granted. That difference — `fw` prompting
  repeatedly while the GUI prompts once — is worth verifying before v1 promises
  CLI parity on wireless devices, because it would be a genuine capability
  gap between surfaces rather than a cosmetic one.

What survives all of this unaffected: **the per-interaction costs**, which
involve no dialogs. Those are the numbers the "prefer a cable" recommendation
should rest on.

This is the number D8 was waiting for, and it says something more interesting
than "reinstalling is slow": **the two platforms are expensive at opposite
ends.** On iOS the install is the cost and a cable removes 4.7× of it; on
Android the Gradle build is the cost and the install is nearly free (the 82.8s
figure is a cold build — a warm one is far cheaper, and was not isolated here).

Either way, an entry-point switch that goes through a rebuild costs tens of
seconds, and one that goes through a hot restart costs **0.76–1.5s** on the same
hardware. That is the whole argument for D8's dispatcher.

### The finding that splits the platforms: what survives the launcher dying

Killing the `flutter run` process:

| target | app survives | reload/restart survive | what holds the connection |
|---|---|---|---|
| macOS | **yes** | no | — (local) |
| iOS simulator | **yes** | no | — (shared network) |
| iPhone 11, wireless **and** wired | **yes** | no | wireless: the device's own LAN address, DDS only a proxy. wired: `iproxy` + DDS, both survive |
| iPhone 16, **wireless** | **yes** | no | as above |
| iPhone 16, **wired** | **no — the app is terminated** (×2) | n/a | `iproxy` (survives), DDS (survives) |
| Android **wired** | **yes** | no | `adb forward` (survives, held by the adb server), DDS (survives) |

The **two-tier capability split is universal**: tree, screenshot, logs and drive
verbs live in the app; reload and restart die with the tool. The cockpit must
therefore **report capability, not just liveness** — a reload button that
silently does nothing is worse than a greyed-out one. It also means
`flutter attach` is not merely *discovery*: it is how reload capability is
**acquired** for an app somebody else launched.

The iPhone-16 exception was **reproduced twice**, and confirmed from the device
side: after the kill, `devicectl device info processes` lists 679 processes and
none of them is the app. The first probe caught it mid-death
(`(112) Service has disappeared`); a later connect is refused outright.

### The 2×2, run after swapping the cable — and it is *not* the transport

The obvious hypothesis was "a cabled launch runs under a debug session the tool
owns". The owner swapped the cable (iPhone 11 wired, iPhone 16 wireless —
`connectionInterface` confirmed `attached` and `wireless` in the daemon events)
and it does not survive contact:

| | wired | wireless |
|---|---|---|
| **iPhone 11 Pro**, iOS 26.5 | **survives** (tree 27ms after the kill) | **survives** |
| **iPhone 16 Pro**, iOS 26.5.2 | **dies** (×2) | **survives** (tree 24ms after the kill) |

So neither the transport nor the OS family explains it. **One cell dies, and it
dies reproducibly.** What is *not* controlled across these runs is the phone's
screen state — an app whose debug session has just ended, on a device that
locks, is a plausible termination the harness never pinned down. That is the
next thing to vary, and it is cheap.

**The alarming reading is dead: "wired iOS kills the app" is false.** What
survives is weaker and still actionable — *on iOS, do not assume the app
outlives its launcher.* Keep the child alive, and detect its death, as
robustness rather than as a known platform rule.

### Connection topology, per transport

- **Android USB** — device VM service → `adb forward` (`tcp:64237 → tcp:45663`,
  held by the adb server daemon) → DDS on 64241. Both survive the tool.
- **iOS USB** — device → `iproxy` on 64420 → DDS on 64426. Both survive the
  tool; the app does not.
- **iOS wireless** — no forward at all. DDS proxies
  `http://10.0.0.8:51153/…`, the **phone's own LAN address**, and connecting
  straight to the device bypasses DDS and is *faster* (30ms vs 69ms for the same
  tree read).

In every case DDS (`dart development-service`) is a **separate process,
reparented to init** — which is why the localhost URI outlives the tool. This
was the source of the mid-spike claim that "nothing host-side is required"; that
holds for a wireless device, and the wired-iOS result is why it cannot be stated
in general.

## Consequences for the design

1. **D1 survives, narrowed.** Detached launch plus VM-service control is sound.
   But one iOS configuration kills the app with its launcher, reproducibly and
   for reasons not yet established — so on iOS the cockpit must keep the child
   alive and notice when it dies. That is the smallest useful supervisor, not
   the full PTY/heartbeat daemon, and it is justified by robustness rather than
   by a known platform rule.
2. **Capability is per-app state.** `{canReload, canRestart}` belongs on the
   running-app record, next to device and entry point.
3. **Prefer a cable, and say so.** 4.7× on install and 5× on every interaction
   is not a preference, it is a different product experience.
4. **D8's dispatcher is worth more than "second"** — tens of seconds against
   ~1s, on both platforms, for opposite reasons.

## What is still unrun

- **Screen state** as the remaining candidate for the iPhone-16-wired anomaly:
  repeat the kill with the device demonstrably unlocked and awake, then locked.
- **A wireless install with no dialog in the way** — which needs the
  local-network grant to actually stick, so start by finding out why it does
  not (and whether a bundled app fares better than a CLI).
- Cable pull / wireless roaming mid-session.

Closed since the first draft: the transport hypothesis (ruled out by the 2×2
above), two concurrent clients (works — see `2026-07-31-sl2-attach-findings.md`),
and the warm Android build (9.6s).

## Incidental

- `ext.flutter.inspector.screenshot` takes an inspector **object id**, not a
  sentinel: `'root'` fails with `Id does not exist`. The id comes from
  `getRootWidgetTree`'s `valueId` (`inspector-0`), minted per object group and
  dead with the process — the exact non-determinism the 07-29 inspection design
  rejected for the AI surface, met here in practice. Another argument for the
  guest runtime carrying the screenshot verb rather than leaning on the
  framework's.
- The isolate id changes across a hot restart, so a client caching one across a
  restart is caching a stale handle.
- `flutter devices --machine` reports `screenshot: false` for macOS, Chrome and
  every iOS 17+ device (`ios/devices.dart:1321-1328` — `idevicescreenshot` broke
  with Xcode 15, flutter#128598); Android reports true. Device-level screenshots
  are not a capability the cockpit can build on.
- A device stream is genuinely a stream: a second, non-connected iPhone appeared
  and disappeared repeatedly during single runs. Identity is stable, presence is
  not — which is what `device.added`/`device.removed` already model.

## Machine state

The probe app was **uninstalled from all three phones**, the spike's helper
processes (`iproxy`, DDS) were killed, `adb` forwards were removed, and the
spike run directory was deleted. Older DDS processes belonging to the owner's
own sessions were left alone.

One thing was left deliberately: running `examples/example` on macOS and iOS
made the flutter tool **auto-migrate the project** — 11 modified files
(`project.pbxproj`, `AppDelegate.swift` off deprecated `@UIApplicationMain`, the
UIScene lifecycle migration, `Info.plist`, both `Podfile`s, the macOS project).
They are the SDK's own migrations and unrelated to this spike; they should be
committed deliberately or discarded, not carried along by accident.
