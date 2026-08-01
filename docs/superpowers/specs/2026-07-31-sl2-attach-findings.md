# S-L2 — Attaching to an app we did not launch: findings

**Date:** 2026-07-31
**Status:** Complete for Android, **negative for iOS**. The asymmetry is the
result, and it lands on the primary target.
**Brief:** `2026-07-31-app-launcher-cockpit-brainstorm.md` § Spikes.
**Follows:** `2026-07-31-sl1-detached-launch-findings.md`, which established that
reload/restart are tool-owned capabilities and asked whether attach *acquires*
them.

## The question

Ask 7 of the brainstorm: the cockpit must work "however the app was launched" —
by us, by the IDE's run button, or by a human tapping the icon. Can we find such
an app, and does attaching restore what a dead launcher took with it?

## Verdict

| case | Android (SM-G970F, wired) | iOS (iPhone 16, wired) |
|---|---|---|
| launched by `flutter run`, launcher then **killed** | found in **5.9s** | n/a — the app dies with the launcher (S-L1) |
| launched from the **device**, no host tooling at all | found in **5.9s** | **not found** (two attempts, ~5 min of waiting) |
| does attach restore reload/restart? | **yes** | untested (nothing to attach to) |

**Android: ask 7 holds completely.** **iOS: it does not, in this spike.**

## Android — everything works, and attach is a capability upgrade

### An orphaned app is found and re-empowered

After killing the `flutter run` that started it (the app survives — S-L1),
`flutter attach --machine -d RF8M12L8GHW` — knowing only the **device id**, not
the URI — reported `launchMode: attach` and the same `wsUri` **5.9s** later.

An unrelated process then found the full service set restored:

```
registered services: [compileExpression, flutterMemoryInfo, flutterVersion,
                      hotRestart, reloadSources]
reloadSources: 201ms   hotRestart: 1585ms
```

So S-L1's phrasing is confirmed literally: **`flutter attach` is not discovery,
it is how reload capability is acquired.** A cockpit session that lost its
launcher is repairable in ~6s rather than a ~10–100s relaunch.

### An app launched from the phone itself is also found

The stronger case, and the one ask 7 is really about: the app was started with
`adb shell monkey -c android.intent.category.LAUNCHER` — no flutter tool
involved at any point — and every host-side `adb forward` was removed first.

`flutter attach --machine -d <device>` found it in **5.9s**, created its own
forwards (`tcp:49258 → tcp:45663`, `tcp:49263 → tcp:36777`), and an unrelated
process then read the tree (122ms) and hot-reloaded it (341ms) with the full
service set present.

**Android debug builds publish a VM service unconditionally**, which is what
makes this work.

## iOS — the app runs, and nothing can find it

Installed with `flutter install`, launched with
`xcrun devicectl device process launch` (no debugger, the closest reachable
equivalent of tapping the icon). The app **runs** — `devicectl device info
processes` shows `Runner.app/Runner` at pid 959.

`flutter attach --machine -d <iPhone>` printed *"Waiting for a connection from
Flutter on Xavier's iPhone16…"* and **never progressed past `app.start`**: no
`app.debugPort`, no error, for over three minutes. `dns-sd -B _dartVmService._tcp`
saw no advertisement.

A second attempt passing `--enable-dart-profiling --enable-vm-service
--vm-service-port=0` through `devicectl` behaved identically. **Cause not
isolated** — it is unresolved whether those flags reached the process as argv at
all (devicectl may have consumed them), so this is "did not work here", not
"cannot work".

The plausible mechanism, consistent with both results: **on iOS the VM service
is opt-in at launch**, enabled by the arguments `flutter run` passes through its
debug session, whereas the Android engine starts it by default in debug builds.

## What this means for the cockpit

1. **On iOS, the cockpit must be the launcher** — or the IDE must be, since an
   IDE run goes through the flutter tool. The case that fails is the human
   tapping the app icon, and combined with S-L1 (a wired iOS app dies with its
   launcher) it means an iOS session is *owned* by whoever started it, start to
   finish. Ask 7's "however it was launched" is an Android property.
2. **`attach` belongs in the plugin as an action, not as internal plumbing.**
   On Android it is the repair path for a session whose launcher died, at ~6s,
   and it is how an app nobody launched through us becomes drivable.
3. **Capability is per-app state and it is *mutable*** — `{canReload,
   canRestart}` can go false when a launcher dies and true again after an
   attach. The UI must reflect a transition, not a constant.
4. **Do not promise iOS attach until the flag question is settled.** Whether a
   deliberately-launched iOS app can be made discoverable (correct argv, an
   entitlement, a foreground requirement) is worth one focused follow-up,
   because it is the difference between "the cockpit owns iOS sessions" and
   "the cockpit can join any iOS session".

## Also measured, while the harness was up

- **Two concurrent clients on one app work.** Two unrelated processes attached
  to the same Android app simultaneously; both saw the same isolate, one
  screenshotted (136ms) while the other hot-reloaded (265ms). No contention —
  DDS multiplexes, which is what it is for. *Caveat:* both used the same
  inspector **object group** name, and object groups are shared per name — two
  clients using one group name will dispose each other's ids. Another argument
  for our own structural ids over the framework's.
- **A warm Android relaunch is 9.6s**, against 98.4s cold (S-L1). The 82.8s
  Gradle build is a one-time cost, not the steady state. Install was ~1.5s.
  Steady-state Android is therefore ~10s to relaunch against ~1.5s to hot
  restart — a 6× gap rather than the 65× the cold figure implied, which softens
  (without removing) D8's argument on Android. On iOS the gap stays wide: 23s
  warm relaunch against 0.76s.

## Machine state

Probe app uninstalled from both phones, helper processes killed, `adb` forwards
removed, spike run directory deleted.
