# S-P1 to S-P5 findings — Android, the iOS simulator, why macOS is out, what a real iPhone can do, and notifications

**Date:** 2026-08-12 (S-P5 completed 2026-08-13)
**Spikes:** S-P1 through S-P5 of `2026-08-12-run-permissions-design.md`. Every
spike the design named is now done except S-P6, which S-P1 demoted to optional.
**Verdict:** S-P1's load-bearing assumption **holds** — the pre-launch model in
Decision 3 is viable. S-P2's **premise was wrong in the best possible way**: the
risky mechanism it existed to evaluate turns out to be unnecessary. S-P3
**confirms macOS is out**, for a sharper reason than expected — not because the
state cannot be read, but because a write there cannot be verified. S-P4 found
that its own question could not be asked — there is no native layer on a
physical iPhone at all — but that the one write available there is the
`first-run` reset, which is the one worth having. S-P5 found notifications to be
an ordinary permission whose *second* data source should be dropped rather than
read. Between them, nine things corrected the design rather than confirming it —
and the platform work is now fully scoped.

---

# S-P1 — the Android round trip

**Setup.** `examples/example` gained four runtime permissions in its
`AndroidManifest.xml` (`CAMERA`, `ACCESS_FINE_LOCATION`,
`ACCESS_COARSE_LOCATION`, `POST_NOTIFICATIONS`) and two usage-description keys
in its iOS `Info.plist`, as a fixture — an app that declares no runtime
permission cannot exercise this path at all. Target: `emulator-5554`,
`sdk_gphone64_arm64`, API 35, via `../../fw flutter run --machine`.

| question | answer |
|---|---|
| Does held state survive `flutter run`'s reinstall? | **Yes** — the one that matters |
| Does `grant` kill the app? | No |
| Does `revoke` kill the app? | Yes, **and it ends the run** |
| Can granted / denied / undetermined be told apart? | **Not from `grant`/`revoke` alone** — the flags are the vocabulary |
| Is `reset-permissions` usable for one app? | **No — it is global** |

## 1. Grants survive the reinstall (Decision 3 stands)

The whole pre-launch half rests on this, so it was measured first. With
`ACCESS_FINE_LOCATION` granted and the other three not, the run was ended and a
second `flutter run` started. Its log shows a real reinstall —
`Installing build/app/outputs/flutter-apk/app-debug.apk...` — and afterwards:

```
android.permission.ACCESS_FINE_LOCATION:   granted=true,  flags=[ USER_SENSITIVE… ]
android.permission.ACCESS_COARSE_LOCATION: granted=false, flags=[ USER_SENSITIVE… ]
android.permission.CAMERA:                 granted=false, flags=[ USER_SENSITIVE… ]
android.permission.POST_NOTIFICATIONS:     granted=false, flags=[ USER_SENSITIVE… ]
```

**Apply-then-launch works**, and S-P6 drops from "might be necessary" to "might
be convenient".

## 2. Revoke does not restart the app — it ends the run

The design said a revoke "restarts the app", and the sketched UI put *restarts
the app* on the control. Too gentle. Measured:

```
pid before = 20399
$ adb shell pm revoke … android.permission.CAMERA        rc=0
pid after  =                                             (gone)
```

and in the same second, in the launcher's log: `Lost connection to device.`
followed by `{"event":"app.stop"}`. `flutter run` itself exited.

**Consequence for Decision 6:** the control cannot say *restarts the app*.
Since the cockpit owns the launch parameters, the only usable version is that it
**relaunches**, and the control says *revoke — relaunches the app*.

## 3. `grant` and `revoke` cannot express three states — the flags can

The most consequential finding, because `first-run` is the feature's reason to
exist and this is how you verify it landed. After `pm revoke`, `CAMERA` and the
never-touched `POST_NOTIFICATIONS` are **byte-identical** in `dumpsys`, and
`appops` says `ignore` for both:

```
android.permission.CAMERA:             granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
android.permission.POST_NOTIFICATIONS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
```

`pm set-permission-flags` closes it, and `dumpsys` reads it straight back:

```
$ adb shell pm set-permission-flags … android.permission.CAMERA user-set user-fixed
android.permission.CAMERA: granted=false, flags=[ USER_SET|USER_FIXED|USER_SENSITIVE… ]
```

`clear-permission-flags` reverses it. **Both are live — pid unchanged across
each.**

| state | `granted` | flags |
|---|---|---|
| granted | `true` | — |
| undetermined (`first-run`) | `false` | no `USER_SET` |
| denied | `false` | `USER_SET` |
| denied-forever | `false` | `USER_SET\|USER_FIXED` |

## 4. `pm reset-permissions` is global — do not use it for one app

No package argument; its help says *"Revert all runtime permissions to their
default state."* It reverted the example's grant as intended, and would have
done the same to every other app on the device. `first-run` for one app must be
**composed**: per declared permission, `pm revoke` then
`pm clear-permission-flags … user-set user-fixed`.

## 5. The live/lethal split, complete

| command | process | run |
|---|---|---|
| `pm grant` | survives | survives |
| `pm set-permission-flags` | survives | survives |
| `pm clear-permission-flags` | survives | survives |
| `pm revoke` | **killed** | **ended** |
| `pm reset-permissions` | **killed** | **ended** (and global) |

Pre-launch application is unaffected by all of it — nothing is running, so
nothing can be killed. During a run the split is not grant-vs-revoke as guessed
but **anything that takes a permission away vs everything else**.

---

# S-P2 — the iOS simulator

**Setup.** Run entirely on a **throwaway device** (`simctl create
fw-perm-spike`, iPhone 16 / iOS 26.2), created for the spike and deleted after,
because the failure mode this spike was written to evaluate is a corrupted
simulator. The developer's own booted device was never touched. The example app
was built and installed on the throwaway for the second half.

## 6. The premise was wrong: `simctl privacy` supports camera

S-P2 existed to ask whether a hand-written `TCC.db` row could grant what
`simctl privacy` omits. It turns out `simctl privacy` does **not** omit camera —
the *help text* omits it. The command works:

```
$ xcrun simctl privacy <udid> grant camera com.example.flutterwareExample   rc=0
kTCCServiceCamera|com.example.flutterwareExample|2|4|1|0
```

`revoke camera` sets `auth_value` to 0. So **no TCC writing is needed**, and the
recommendation not to ship it now costs nothing.

Probing the whole plausible namespace against the real command:

| accepted | refused (`Operation not permitted`) |
|---|---|
| the 11 documented, plus **`camera`** and **`calls`** | `bluetooth`, `local-network`, `tracking`, `notifications`, `health`, `homekit`, `speech-recognition`, `focus`, `faceid`, `nearby-interaction`, `addressbook` |

The design's "eleven services" line was reading the docs. Thirteen work.

## 7. Hand-written rows do work — the mechanism is real, just unnecessary

Measured before finding the above, and kept because it settles the stated
question. A row inserted with plain `sqlite3` in the shape `simctl` itself
writes (`client_type=0`, `auth_reason=4`, `auth_version=1`, `csreq` NULL):

- persists immediately, with **no device shutdown required**;
- **survives a full shutdown/boot cycle** — `tccd` does not clobber it;
- is removed by `simctl privacy reset all <bundle>` exactly like a row `simctl`
  wrote itself.

So the escape hatch exists for a service that is genuinely unreachable. It is
still not worth shipping: concurrent writes to a live daemon's sqlite buy
nothing now that camera is covered.

## 8. `simctl privacy` works on an app that is not installed

Unlike Android's `pm grant`, which needs the package present, `simctl privacy
grant photos <bundle>` wrote a valid row for a bundle id that had never been
installed on the device.

**Consequence for Decision 3:** the "run it once first" rule is an *Android*
rule, not a universal one. On the iOS simulator a permission profile can be
applied before the app has ever existed on the device. The UI copy in § The
surface should not say "not installed yet" on iOS the way it must on Android.

## 9. Location is not in TCC.db — it is a second store

The design's iOS read path assumed one file. `simctl privacy grant location`
returns rc=0 and writes **no TCC row at all**, with the app installed or not.
Location lives in `data/Library/Caches/locationd/clients.plist`, keyed by
`i<bundle-id>:`:

```
"icom.example.flutterwareExample:" => {
  "Authorization" => 2
  "BundleId" => "com.example.flutterwareExample"
  "Registered" => true
  "SupportedAuthorizationMask" => 3
}
```

Readable with `plutil`. Two consequences: the iOS held-state reader needs
**two sources**, not one; and unlike a TCC row, this entry only appears once the
app has been installed and has registered with `locationd` — so the read (not
the write) has the install precondition for the single most-tested permission.

## 10. Notifications are not settable host-side on the simulator

`simctl privacy grant notifications` is refused outright — *"Operation not
permitted"*. Nothing for the bundle appears in `TCC.db`, `Library/BulletinBoard`
or `Library/UserNotifications` for an app that has never asked. This answers
**S-P5's iOS half negatively**: iOS notification authorization cannot be set
from the host, and the only paths are the app provoking its own dialog (the
adapter's `request`) with the native layer answering it.

## 11. iOS state semantics, confirmed

Absent row = undetermined · `auth_value` 0 = denied · 2 = allowed · 3 = limited.
The same three-plus-one model as Android, reached by a completely different
route — which is what makes Decision 1's single row across platforms hold up.

---

# S-P3 — macOS

**Setup.** The example built and run with `../../fw flutter run -d macos`
(bundle `com.example.flutterwareExample`), plus read-only inspection of macOS
Flutter apps already running from other worktrees, identified by executable
path rather than by name. **Verdict: macOS is declared-and-observed only in
v1** — as suspected, but for a sharper reason than "reading is blocked".

## 12. The reason is not the read — it is that a write cannot be verified

The host `TCC.db` is unreadable without Full Disk Access, so there is no read
path. That was known. What S-P3 adds is that the *write* is unverifiable too:

```
$ tccutil reset Accessibility com.example.flutterwareExample
Successfully reset Accessibility approval status for com.example.flutterwareExample
… rc=0
```

The example has never requested Accessibility and holds nothing. `tccutil`
reports success anyway. So on macOS a reset always claims to have worked, and
nothing on the machine can contradict it.

**This is what disqualifies macOS, and it is a principle rather than a
platform gripe.** Decision 7's read-back rule is the thing that makes the write
path safe everywhere else; macOS is the one target where it cannot be honoured.
Shipping a control there would mean shipping exactly the "I pressed it and
nothing told me" failure the rest of the design is built to prevent.

## 13. `tccutil` does validate the bundle id, which is worth one thing

A bundle id LaunchServices does not know is refused:

```
$ tccutil reset Camera com.example.definitely.not.installed.xyz
tccutil: No such bundle identifier … (OSStatus error -10814.)   rc=64
```

and an unknown service gives rc=70. So `tccutil` is a usable *identity* check
even though it is not a usable state check — it can confirm the cockpit is
naming an app the system has heard of.

## 14. The bundle id is shared by every worktree, so a reset cannot be scoped

`tccutil reset Camera com.example.flutterwareExample` printed **"Successfully
reset" nine times** — once per registered macOS copy. Spotlight confirms the
scale:

| bundle id | registered copies on this machine |
|---|---|
| `com.example.flutterwareExample` | 19 |
| `com.example.app` (Flutter's macOS default) | 28 |

Every worktree builds an app with the same bundle id, so **macOS permission
state is not per-worktree and cannot be made per-worktree** — a reset issued
from one checkout lands on all of them, and on any other default-configured
Flutter app on the machine. This is the same family as the leaks in
`project_worktree_leak_audit`, and it is another reason not to offer the
control rather than a bug to fix.

## 15. `flutter run -d macos` execs the binary directly

The running app's parent is `dartvm` (flutter_tools), not `launchd` — so the
app is spawned directly rather than through LaunchServices, which is the
mechanism behind the responsible-process rule already recorded at
`ax_driver.dart:126`. Worth stating precisely, because that comment is about a
bare helper binary with no bundle, and this is a registered `.app`
(`lsappinfo` reports it under its bundle id).

**Not verified:** which process TCC would actually attribute a *request* to.
`launchctl procinfo` needs root, and no app in this repo requests a macOS
permission, so nothing here proves whether a dialog would name the app or the
terminal. The direct-exec launch is consistent with the responsible-process
rule; it is not proof of it. If macOS ever becomes worth supporting, that is
the measurement to make first — and it needs an app that asks.

**A note on what this spike touched:** `tccutil reset Camera` and `reset
Accessibility` were run against `com.example.flutterwareExample`. Both are
machine-wide for that bundle id per finding 14. Neither permission was ever
granted to that demo app, so the practical effect is nil — but it is a write,
and it is recorded here rather than left unsaid.

---

# S-P4 — physical iOS

**Setup.** Read-only throughout on the developer's own paired iPhones —
`devicectl` reports an iPhone 16 Pro and an iPhone 11 Pro, both *available
(paired)*. **Nothing was installed, uninstalled or changed on either.** The one
mechanism worth measuring was measured on a throwaway simulator instead, using
the already-built `Runner.app` so it cost no rebuild.

## 16. The question cannot be asked as posed: there is no native layer on physical iOS

S-P4 asked how far `layer: native` gets into Settings.app. It gets nowhere,
because it does not exist there. `NativeSession.isAvailable`
(`native_session.dart:50`) resolves in order: adb owns the device → no; the
device is `macos` → no; the device is a **booted simulator** → no, a physical
UDID is not in `simctl list devices booted`. So it returns false and every
`layer: native` call against a physical iPhone is refused as unavailable.

The mechanism explains itself: the AX driver reads the *Mac's* accessibility
tree, and a simulator is addressable only because it is a Mac app whose window
contains the simulated device. A physical iPhone is not on that tree at all.
The same reasoning removes `foreground` — so on physical iOS a suspended app
cannot be brought back by the drive layer either, only by a human.

## 17. `devicectl` has no privacy verb

Present and current (506.6). Its whole device surface is `copy`, `info`,
`install`, `notification`, `orientation`, `process`, `reboot`, `sysdiagnose`,
`uninstall` — nothing privacy-, permission- or TCC-shaped, and no grep hit for
any of those words in its help. So there is **no host-side read and no
host-side set** on a physical device.

## 18. But there is exactly one write, and it is the valuable one

`uninstall` clears permission state outright. Measured on a throwaway
simulator, granting camera and photos and then removing the app:

```
rows while installed:  kTCCServiceCamera=2  kTCCServicePhotos=2
rows after uninstall:  (empty)
```

Empty means undetermined. So **`first-run` — the profile the whole feature
exists for — is achievable on a physical iPhone**, via `devicectl device
uninstall` followed by the reinstall `flutter run` performs anyway. It is the
only profile available there, and it is the one worth having.

Two caveats stated rather than buried. This was measured on the simulator, not
on hardware; TCC semantics are the same but that is an inference, and proving
it means uninstalling an app from someone's personal phone. And an uninstall
destroys the app's data along with its permissions, so it belongs behind a
confirmation, unlike every other write in this design.

## 19. iOS has no "run it once first" rule at all

The iOS counterpart to S-P1's load-bearing test, which the design had left
unmeasured. Both halves hold:

| sequence | result |
|---|---|
| grant with the app **absent** → install | row survives the install |
| grant → **reinstall over** the existing app | both rows survive |

So on iOS a profile can be applied to an app that has never been installed, and
it is still there after the launch that installs it. Decision 3's "run it once
first" is **Android-only**, and the § The surface copy must not show the
"not installed yet" state on an iOS target. The exception remains location,
which per finding 9 lives in `locationd` and only appears once the app has
registered.

**Physical iOS, settled:** read via the adapter only; no host-side set; one
host-side reset by uninstall, behind a confirm; everything else is the app
provoking its own dialog for a human to answer.

---

# S-P5 — notifications

iOS was answered as a side effect of S-P2: `simctl privacy grant notifications`
is refused outright, and nothing appears in `TCC.db`, `BulletinBoard` or
`UserNotifications` for an app that has never asked. **iOS notification
authorization cannot be set from the host.** This section is the Android half.

## 20. `POST_NOTIFICATIONS` is an ordinary runtime permission

Nothing special. `pm grant` works, the state reads back from `dumpsys package`
like any other, and — measured — **the grant is live**: pid 2042 unchanged
across it. The revoke ended the run, reproducing S-P1 finding 2 on a second
permission (`app.stop` in the log again). So it needs no special handling in
Decisions 5 or 6; it is a row like the others.

## 21. The appop is a mirror, not a second gate — so do not read it

The suspicion going in was that notifications have a gate behind the
permission, which would break Decision 1's single *held* cell. They do not.
`pm grant` and `pm revoke` **drive the uid-level appop themselves**: a grant
clears the `ignore`, a revoke restores it. Even `cmd appops set … default` did
not clear the uid mode — only the permission did. The permission is
authoritative and the appop follows.

**The important part is the second-order finding.** Across one round trip on a
single permission, `cmd appops get <pkg> POST_NOTIFICATION` rendered its answer
in **four different shapes**:

| state | what `appops get` printed |
|---|---|
| baseline, ungranted | `Uid mode: POST_NOTIFICATION: ignore` |
| after `pm grant` | `No operations.` / `Default mode: allow` |
| after a package-level `appops set` | `POST_NOTIFICATION: allow` |
| after `pm revoke` with that override present | *both* lines, disagreeing |

A parser keyed on one regex silently mis-reads at least one of these — and the
one it is most likely to mis-read, `No operations.`, appears on the **success
path**, where an empty parse would be reported as "no permission data" for a
permission that was just granted. This is the "empty parse is an error, not an
empty answer" rule from § Where the bugs would come from, caught in the wild
before a line was written.

**Consequence: the design should read `dumpsys package` and nothing else for
Android held state.** `cmd appops get` was listed in the platform table as
covering "what the permission model does not"; for `POST_NOTIFICATION` it
covers nothing extra and reports it four ways. This spike *removes* a data
source rather than adding one.

The one genuinely separate axis is `dumpsys notification`'s
`AppSettings: … importance=DEFAULT userSet=false` — the user switching an app's
notifications off in Settings independently of the permission. Out of scope for
a permissions view, unmeasured here, and noted so it is not rediscovered as a
disagreement later.

## 22. The emulator is a shared singleton across worktrees

Not what the spike was looking for, but it happened during it. The example's
APK on `emulator-5554` **reverted to a build without the fixture permissions**
between spikes — another worktree ran `examples/example` onto the same emulator
and replaced it.

So a device is not per-worktree, and neither is anything on it: the installed
APK, the held permissions, the app's data. This is the same family as finding
14's shared macOS bundle id and as `project_worktree_leak_audit`. It bears on
the design directly — the *wish* is keyed per worktree-and-package
(Decision 4), but the *held state it applies to* is keyed by device and package
alone, so two worktrees pointing at one emulator will overwrite each other's
permission state with no warning. Worth a line in the UI rather than a
surprise.

---

## What did not need changing

Decision 7's read-back rule survives both spikes and is now triply justified:
`pm grant`'s silent no-op, `granted=` under-reporting the Android state, and
`simctl`'s help text under-reporting its own surface. Nothing here is
trustworthy without reading it back.

## Still open

- The **observed** column is untouched by both spikes; it needs the adapter
  (Phase 4). Neither spike verified that an app *honours* what was written —
  only that the stores hold it. For `simctl`-written state that is Apple's own
  contract; for anything hand-written it remains unverified.
- Whether the `USER_SET`/`USER_FIXED` vocabulary and the two iOS store layouts
  read the same on older API levels and runtimes.
- S-P3 (macOS) and S-P4 (physical iOS) are unaffected. S-P5 is now half
  answered: iOS no, Android untested.
