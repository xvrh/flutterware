# S-N1 / S-N2 / S-N3 — the native layer measured on all three targets

**Date:** 2026-08-12
**Status:** All three ran, same day as the brainstorm they gate. S-N1:
Android emulator (API 35). S-N2: iOS simulator (iPhone 16 Pro, iOS 18.1).
S-N3: macOS, same app on the `macos` device, plus the TCC attribution
question. Every number from this session. The four questions S-N1 was sent
to answer are answered; two things it was not sent to find are among the
most consequential findings in it.

**Context:** the native-fallback brainstorm — give the drive loop a second
layer that sees and taps what the Flutter tree cannot: platform views, the
soft keyboard, native dialogs. Candidate mechanism on Android: plain adb
(`uiautomator dump` + `input`), zero new dependencies. The design these
findings gate is `2026-08-12-run-native-fallback-design.md`.

## The two findings nobody ordered

**1. The dump arms Flutter semantics by itself.** The first
`uiautomator dump` — no guest cooperation, no `ensureSemantics`, nothing —
came back with the *complete* Flutter tree: every text, the `EditText`, the
`Switch` as `checkable/checked`, "OK" as an `android.widget.Button`, the FAB
as its tooltip "Increment", all with pixel bounds. UiAutomation registers as
an accessibility service; Flutter's `AccessibilityBridge` sees accessibility
turn on and publishes. The whole "should native observe ask the guest to
enable semantics first" decision from the brainstorm evaporates on Android:
**the merged tree is what you get by asking.** (The drive engine only arms
semantics lazily for `label` targets — verified in `lib/src/drive/drive.dart`
— so this was not us.)

**2. A native tap is a human to the guest.** The `adb shell input tap` on
the FAB came back in the next observe's `human` field as
`tap tooltip 'Increment'` — the recorder cannot tell adb from a finger.
Attribution design follows: when the native layer taps, the host should
journal the native step and expect (or suppress) the twin `actor: human`
entry the guest will report for it.

## The four questions

**Latency and flake rate.** Idle app: **~2.5s per dump**, flat across five
runs (uiautomator spawns a JVM per invocation; that is the floor, first run
4.5s cold). Under a `CircularProgressIndicator` animating continuously:
**3.7–5.3s, 6/6 succeeded** — the idle-wait burns ~1.5s extra and then dumps
anyway. The feared `could not get idle state` hard failure never appeared on
API 35. `input tap` is **100ms**; `screencap -p` **~2.3s**;
`input text 'hello-from-adb'` **6.5s** (it types key by key — usable, not
pleasant; the Flutter-layer `enterText` stays primary for text).

**Do dumped bounds and `input tap` agree?** Yes — both speak physical
pixels. Tap at the dumped center of "Increment" → counter 0→1, first try,
confirmed from the Flutter side. Tap at the dumped center of a *web* button
→ its JavaScript `onclick` fired ("web tapped" in the re-dump). No
coordinate mapping layer needed on Android.

**Does a webview expose its content?** Yes, with one condition measured the
hard way: with webview_flutter's default `JavaScriptMode.disabled` the dump
shows the `android.webkit.WebView` node (bounds, clickable) and **no
children** (one measurement — possibly also an a11y-injection warm-up
artifact). With `JavaScriptMode.unrestricted` the **full DOM appears**:
`<h1>` and `<p>` as `TextView`s with their text, `<button>` as an
`android.widget.Button`, correct bounds, and the tap-through works
end-to-end. A JS-disabled webview is rare in the wild; for the rest, the
CDP-over-adb route (what Appium's chromedriver does) stays in the pocket and
was not needed.

**The keyboard and the blank-band story.** `screencap` shows what the guest
raster never will: the soft keyboard, the autofill strip above it, and the
text as the platform sees it. One correction to the brainstorm's premise
though: **the Android webview was *not* a blank band in the guest
screenshot** — webview_flutter's texture-layer composition puts it in the
layer tree, so `toImage` captures it. The gap on Android is *addressing*
(no verb can target "Web Button"; observe's `texts` has no web content),
not pixels. iOS `UiKitView` platform views and both platforms' keyboards
remain pixel gaps; the real-pixel screenshot stays worth having.

## What this settles for the design

- **Android v1 is plain adb, no on-device server.** ~2.5–4s per native
  observe and zero flakes is fallback-grade; the Patrol-style automator APK
  stays as an escalation nobody has earned yet.
- **A native act should re-dump to verify, not trust silence** — `input tap`
  reports nothing. The re-dump (or a Flutter-side observe when the guest is
  alive) is the transaction's observe half, and at ~2.5s it is affordable.
- **Semantics negotiation is not a feature** on Android. Dump and receive.
- **Native steps need an attribution rule** before the journal tells a
  double story (finding 2).
- The adb binary came from `~/Library/Android/sdk/platform-tools/adb` —
  locate it the way `flutter` does (SDK dir), not from PATH (it was not on
  PATH here).

## S-N2 — the iOS simulator through the host's accessibility bridge

Mechanism under test: the macOS AX API pointed at the **Simulator host
app** — what Xcode's Accessibility Inspector does — as the zero-dependency
alternative to idb (which was not installed on this machine, itself a data
point: the dependency is not there by default, and after this spike it is
not needed).

**The walk is the whole story, and it is fast.** One 130-line Swift probe
(compiled by `swiftc` in 3.7s — the compile-on-demand helper is viable)
walked the Simulator's AX tree in **~260ms** and got the complete simulated
app: every Flutter text, the text field with its content, the switch as
`AXCheckBox` with state, "OK", the FAB as "Increment" — labeled, with
host-window coordinates. Like Android, nobody armed semantics. The bridge
also reads whatever else the device shows: Safari's chrome, the home screen
(every app icon a pressable `AXButton`), and the Simulator's own controls —
the Home button, the Device menu. Scope the walk to the device `AXWindow`:
at application level it drags in the whole menu bar, including the host
user's recent files.

**Two injection mechanisms, one clean and one conditional.** `AXPress` on
an element works **coordinate-free and without raising the window** —
counter incremented, home-screen icons launch, the Home toolbar button
presses. CGEvent coordinate clicks only land with three ingredients found
the hard way: `mouseEventClickState = 1`, the app activated, and the window
raised — a frontmost-window constraint AXPress does not have. Prefer
AXPress wherever an element exists; coordinates are for gestures and
unlabeled space.

**The suspended-app dead end is now recoverable, and `simctl launch` is
not the recovery.** Measured end-to-end against the live drive loop:
backgrounding the app produced the documented `DriveTimeout` ("bring the
app to the front and retry"); `xcrun simctl launch` on the already-running
bundle **restarted** it — fresh pid, counter reset, state gone. The
user-shaped path is the right one: `AXPress` Home, `AXPress` the app's
icon — after which the next `observe` answered in **18ms with the counter
preserved**. "The step is not lost" now has an agent-executable recovery
instead of a sentence asking the human.

**Two honest negatives.**
- `AXSetValue` on the text field returned success and set **nothing** — a
  silent no-op on both the AX and Flutter side, the embedder-gap failure
  mode again. `enterText` on the drive layer stays the only text path on
  iOS.
- **WKWebView interiors are invisible** to the host bridge: Safari on
  example.com showed its chrome but no page DOM, and the
  `AXEnhancedUserInterface`/`AXManualAccessibility` levers were refused.
  Opposite of Android, where the webview DOM came through. iOS web content
  is screenshot-and-coordinates territory, or a future Safari Web
  Inspector lane.

**TCC.** This process was already trusted, so the grant *flow* — which app
name the prompt shows when `fw` or the GUI spawns the helper, first-run UX —
is still S-N3's question. The mechanism behind the grant is proven.

**Attribution, again.** The AX/CGEvent taps surfaced in the next drive
reply's `human` field, same as adb on Android. The rule is cross-platform:
the native layer's own steps must be reconciled with the guest's
human-action recorder before the journal tells a double story.

## What S-N2 settles for the design

- **The Swift AX helper is the iOS-simulator backend.** idb is unnecessary:
  the AX bridge reads more than expected (system UI included), presses
  without coordinates, and costs one 3.7s compile, cached. One helper
  serves macOS and the simulator, as the brainstorm hoped.
- The un-suspend verb exists and is cheap: Home + icon press, ~4s total
  including settling.
- Not tested: a hidden/minimized Simulator window (AXPress plausibly
  survives it, CGEvent by definition does not), and the iOS 26 runtime.

## S-N3 — macOS, and who holds the accessibility grant

Same probe (`--app` generalized it beyond the Simulator), pointed at
`examples/example` running on the `macos` device, plus Finder as the
control.

**The macOS Flutter AX bridge is dormant, and nothing we can reach wakes
it.** The app's AX tree held only the menu bar; its one `AXWindow` answered
with a degenerate element (role `AXApplication`, children looping back to
the menu bar). Everything that might arm it was tried and measured:
`AXEnhancedUserInterface` / `AXManualAccessibility` on the app element —
both refused (-25208/-25205, unlike Electron, which implements them) — and
the guest's own `ext.flutterware.semantics` extension, which built the full
framework tree (verified: 2.2KB of nodes over the wire) while the native
bridge stayed dark. Framework `ensureSemantics` sends semantics *updates*
to the embedder; it does not make the embedder *publish* NSAccessibility
nodes. Only a genuine assistive client (VoiceOver) does, and scripting
VoiceOver is not a tool we should hold. The probe is not at fault: Finder
walked perfectly (three windows, sidebar, full content), and the same probe
read the entire Simulator.

**Why this costs the design nothing on the flagship path.** For a
flutterware-launched macOS app, Flutter content is already the *drive
layer's* territory, where it is strictly better served (widget tree,
targets, settle). What the macOS fallback exists for is **native chrome** —
file dialogs, alerts, menus, other apps — and that is plain AppKit,
fully exposed (the Finder control is the proof; the Flutter app's own menu
bar walks fine too). The one real loss: a macOS Flutter app *not* launched
by flutterware is opaque to the native layer too — unlike the iOS
simulator, whose runtime keeps the bridge awake for the host without any
assistive client. The asymmetry is the simulator doing extra work, not us.

**TCC attribution, read straight off this session's process tree.** The
probe ran `trusted: true` without ever being granted anything: macOS
attaches the Accessibility grant to the *responsible process* — the app
bundle at the top of the spawn chain — and every child inherits it. This
session's own ancestry demonstrates the whole design space:
`zsh ← claude.app ← disclaimer ← Claude.app` — that `disclaimer` helper is
`responsibility_disclaim`, the API that makes a child its own TCC client.
So, per surface: helper spawned by the **Studio GUI** → the grant and the
prompt carry the flutterware app bundle's name (good, ours to control, one
`AXIsProcessTrustedWithOptions` prompt); spawned by **`fw` in a terminal**
→ the grant belongs to the *terminal* (often already granted on a dev
machine — this one was); and if we ever want "flutterware" to stand alone
in System Settings regardless of who spawned it, the disclaim API is the
lever, at the cost of a tiny spawn shim. The user TCC database itself is
Full-Disk-Access-gated (read attempt refused), so a helper cannot *check*
the grant except by asking `AXIsProcessTrusted` — which is the right way
anyway.

## What S-N3 settles for the design

- macOS backend scope is **native chrome only**: dialogs, menus, other
  apps, real-pixel window capture. Flutter content on macOS stays with the
  drive layer, and the tool output should say so rather than let an agent
  hunt for Flutter texts in the AX tree.
- The helper needs no install and no grant of its own: compiled on demand,
  it inherits whatever app spawned it. First-run UX is one system prompt
  naming the GUI (or the terminal), then never again.
- The spike's own probe (a Swift walker with `--press`, `--tap`,
  `--settext`, `--app`, `--enhanced`, plus a Dart script arming guest
  semantics over the VM wire) is not kept: the production helper,
  `app/lib/src/run/native/ax_helper.swift`, subsumes all of it. What the
  probes established is above; what they did is reproducible from it.

## Not answered here

Physical iOS stays out of scope, as decided. VoiceOver-armed macOS AX was
deliberately not measured (it would speak over the owner's session); if a
future need appears, measure it in a sandboxed user account.
