# Run native fallback — the layer below the widget tree

**Date:** 2026-08-12 (macOS scope corrected the same day, after the merge — § The macOS counterexample, explained)
**Status:** Designed. The three spikes that gate it ran the same day and
all passed — `2026-08-12-run-native-fallback-spike-findings.md` (S-N1
Android, S-N2 iOS simulator, S-N3 macOS + TCC). Every mechanism claim in
this doc has a measurement behind it there; nothing below rests on an
assumption a spike could have tested.

**Lineage:** `2026-08-11-run-drive-design.md` (the drive loop this extends,
and § Mobile's list of what the guest cannot see — the soft keyboard, the
platform view, the suspended iOS app), `2026-08-10-inspect-consolidation.md`
(semantics is off until someone holds a handle — and § S-N1 shows Android's
native layer arming it from outside), the capture-button work (scale
factors are a known trap; § Coordinates inherits the lesson).

## The goal

The drive loop addresses the widget tree, and the widget tree ends at the
platform's edge. Four things live past that edge, and an agent hits all
four in ordinary work:

1. **Platform views** — webview, maps, camera. On Android the pixels
   *are* in the guest screenshot (texture-layer composition), but no verb
   can target "Web Button" and `texts` sees nothing inside. On iOS they
   are blank bands.
2. **Native dialogs** — permission prompts above all. A flow that asks
   for camera access currently dead-ends the agent with a screen it can
   see and a button it cannot press.
3. **The suspended iOS app.** `DriveTimeout` says "bring the app to the
   front and retry" — to an agent with no hands.
4. **The real pixels** — keyboard, platform views, system UI: what the
   device actually shows, as opposed to what Flutter rasterized.

The native layer is a **fallback, taught, never taken silently**: the
drive layer stays primary for everything it can address, and the one
unforgivable failure stays the same — acting on something other than what
was addressed and reporting success.

## What the spikes settled

The design converges on **two backends, zero new dependencies**:

| | Android (emulator *and* physical) | iOS simulator + macOS |
|---|---|---|
| driver | `adb` (located via the Android SDK, not PATH — it was absent from PATH on the dev machine) | one Swift helper, `swiftc`-compiled on demand (3.7s, cached like the CLI build) |
| observe | `uiautomator dump` — **arms Flutter semantics by itself**, full merged tree, ~2.5s idle / ~4s animating, 0/12 flakes | AX walk of the host app, ~260ms; the Simulator bridge is always awake |
| tap | `input tap`, 100ms, bounds and taps share one px space | `AXPress` — element-addressed, coordinate-free, works unraised; CGEvent (clickState 1 + activate + raise) for coordinates |
| text | `input text` — ASCII-ish, 6.5s, secondary | none: `AXSetValue` is a silent no-op on the sim |
| screenshot | `screencap -p`, ~2.3s, real pixels | `simctl io screenshot` / window capture |
| webview | DOM exposed when JS is enabled, tap-through verified | invisible to AX — coordinates + real pixels only |
| un-suspend | not needed (backgrounded Android drives fine) | `AXPress` Home + `AXPress` the app icon — **`simctl launch` restarts instead** |

macOS is the same helper with a narrower brief: **native chrome** — file
dialogs, alerts, menus, other apps. A Flutter app's own widgets usually do
not appear, and for a flutterware-launched app that costs nothing: Flutter
content is the drive layer's territory, where it is strictly better
served. The tool output says so instead of letting an agent hunt the AX
tree for Flutter texts.

**Corrected 2026-08-12, after the merge — see § The macOS counterexample,
explained.** The first version of this section said the bridge is *dormant
to everything short of VoiceOver*. That is wrong, and the mechanism is
simpler: Flutter builds a semantics tree only when the **platform** asks,
and flutterware's `ensureSemantics()` is framework-side and never asks. So
nothing we do turns publication on — but something else can, and an app in
that state publishes its whole tree here.

Physical Android rides the adb backend unchanged. Physical iOS stays out
of scope, as decided at the brainstorm.

## The surface: a `layer`, not a second tool

One decision was delegated with a constraint: the agent must discover the
native layer easily, not forget it, and feel at home. That points at
**`layer: native` as a parameter on the existing `act`/`observe` funnel**
rather than parallel verbs or a second tool, because at-home is exactly
what the funnel already is: same Target grammar, same transaction shape,
same journal, same reply bundle, same refusal style. A native step is the
same sentence with one extra word.

Discovery is the refusals' job, per the house rule that refusals are
instructions:

- A Flutter-layer `notFound` on a device with a native driver appends one
  line: *"The native layer may see it — retry with `layer: native`."*
- A `DriveTimeout` on iOS appends: *"`act {verb: foreground, layer:
  native}` brings it to the front."*
- A native-layer `notFound` lists what the native tree *does* see — the
  Android refusal quotes dumped labels, the AX refusal quotes element
  labels — so a wrong guess teaches the right next call.
- The tool description carries the one-paragraph story: what the native
  layer sees that the Flutter layer cannot, and that it is slower
  (~2.5–4s per Android observe) so the Flutter layer stays the hot path.

**Never a silent fallback.** The layer is always the caller's word. An
automatic downgrade would reintroduce the wrong-target-tap-that-succeeds,
one tree removed.

## Verbs on the native layer

v1 is deliberately small: `observe`, `tap`, `foreground`, and `enterText`
on Android only. `drag`/`swipe` have obvious mechanisms (`input swipe`,
CGEvent drag) and wait for a need; `scrollTo` does not exist here — there
is no `ensureVisible` below the widget tree.

- **`observe`** — the platform tree (filtered: labeled or interactive
  nodes, bounds, state flags; the same visible-text cap as the Flutter
  layer) plus the **real-pixel screenshot**. Cheap to call alongside a
  Flutter observe, and the answer to "what does the screen actually look
  like" — keyboard, platform views, dialogs included.
- **`tap`** — resolve the Target against a *fresh* dump at act time,
  exactly-one rule, then `input tap` at the node's center / `AXPress` on
  the element. `AXPress` is preferred wherever an element exists; it needs
  no coordinates and no raised window.
- **`foreground`** — Android: launcher intent (resumes, does not
  restart); simulator: Home + icon press, measured end-to-end (the next
  `observe` answered in 18ms with state preserved); macOS: activate/raise.
  This closes the suspended-iOS dead end with an agent-executable
  recovery.
- **`enterText`** (Android only) — `input text` after a native tap
  focuses the field. Slow and ASCII-bound; the drive layer's `enterText`
  remains the text path everywhere it reaches. On iOS there is no native
  text: the spike caught `AXSetValue` returning success and writing
  nothing, and a mechanism that lies about success is disqualified.

**The transaction shape survives.** Resolve → act → observe, one reply.
The native settle is honest about its crudeness: re-dump until stable or
budget, `settled: false` past it. And when the guest is alive, a native
act closes with a *Flutter* observe in the same reply — "tap Allow
natively, then show me the app" is one call.

## Targets and coordinates

Targets are the same grammar, resolved against the native tree: bare text
matches label/text/content-desc, `nth` and `containing` carry over.
`key`/`tooltip` have no native meaning and refuse with that sentence.

One addition, and it is the iOS-webview escape hatch: an explicit
coordinate target, `{"at": {"x":…, "y":…}}`, valid only on the native
layer. WKWebView interiors are invisible to AX, so the only path in is
the real-pixel screenshot plus a point. Coordinates are a loaded gun, so
the reply makes the space unambiguous: every native observe carries the
coordinate space it speaks (`px` on Android — dump and tap already agree —
window points on the sim) **and the screenshot's scale factor**, because
retina-vs-points is precisely the trap the capture-button work already
paid for once. `at` is interpreted in the observe's stated space, never
in screenshot pixels.

## The journal, and the twin-step problem

Native steps journal like any step — actor, verb, target sentence,
artifacts, plus `layer: native` — and render in the Steps strip with the
real-pixel screenshot as thumbnail.

Both spikes surfaced the same wrinkle: **the guest cannot tell a native
tap from a finger.** An adb tap and an AXPress each arrive as platform
input, so the human-action recorder reports them in the next reply's
`human` delta, and the journal would tell every native step twice — once
as the agent's, once as a phantom human's. The reconciliation is
host-side, because the guest by design knows nothing: when a reply's
`human` entries arrive, the host drops those that match a native step it
itself performed since the previous step (same run, act window, target
sentence when one exists — a time-windowed match, and the window is the
native step's own transaction). A human tap during that same window is
rare, and losing its journal line is the cheaper error: the alternative
is every native step gaslighting the review strip. The dropped entries
are counted in the step's record (`reconciled: n`), per the stated-caps
rule.

## Semantics, per platform

Nothing to negotiate. Android: the dump arms Flutter semantics itself —
the merged tree is what asking returns. iOS simulator: the runtime keeps
the bridge awake for the host. macOS: out of scope, because the guest
cannot ask on the platform's behalf (§ The macOS counterexample,
explained). The guest's `ensureSemantics` handle stays what it always
was — the *framework* tree for the semantics tab — and this feature
neither needs it nor touches it, which is precisely why it cannot turn
macOS publication on.

## Apps launched outside flutterware

The native layer needs no guest, so it works against them — on Android
and the simulator that is a real capability upgrade: today's
"inspect-only, no act" tier gains native observe and tap. The tool output
states the tier plainly ("launched outside flutterware: native layer
only — Flutter targets need a flutterware launch"), never discovered by a
hung call.

## TCC, distribution, and the helper

The helper compiles on demand (`swiftc`, ~4s, cached beside the other
build products) and holds no grant of its own: macOS attaches the
Accessibility permission to the **responsible app** and children inherit
it. Per surface:

- **GUI spawns it** → the prompt and the Settings row carry the
  flutterware app bundle's name. One `AXIsProcessTrustedWithOptions`
  prompt, then never again.
- **`fw` in a terminal spawns it** → the grant is the terminal's, and on
  a dev machine it usually already exists.
- Denied or unprompted → the refusal teaches the System Settings path;
  `AXIsProcessTrusted` is the only check (the TCC database is
  FDA-gated — measured).
- The `responsibility_disclaim` shim — "flutterware" as its own TCC
  client regardless of spawner — is a door left open, not built.

adb needs no permission story; it is located the way `flutter` locates
it, from the Android SDK.

## Latency and the deadline

A native observe on Android costs ~2.5–4s; the act funnel's deadline
derivation (`DriveSession._deadlineFor`) learns a native allowance so a
slow dump is never misread as a hung app. The never-hang rule is
inherited whole: a native step that cannot complete returns a diagnosis,
not silence. The one new failure mode — `uiautomator`'s idle-wait on a
permanently animating app — measured as added latency, not failure, and
the budget absorbs it.

## Decided (owner constraints honored)

1. **`layer: native` on the existing funnel**, refusal-taught — the
   delegated discoverability constraint is the deciding argument.
2. **Never silent fallback.** The layer is the caller's word.
3. **Real-pixel screenshot on every native step**, same inline size cap
   as the Flutter layer's.
4. **Host-side twin-step reconciliation**, with a visible count.
5. **macOS scope is native chrome.** Stated in tool output.

## Not in v1

- `drag`/`swipe`, native gestures beyond tap.
- WKWebView DOM (Safari Web Inspector protocol is the future lane) and
  webview CDP on Android — coordinates + real pixels cover the near term.
- A Patrol-style on-device automator server — the escalation nobody has
  earned; plain adb passed its spike.
- Coordinate-space unification with Flutter logical coordinates.
- Physical iOS; VoiceOver-armed macOS.
- Windows, as everywhere in run.

## Order of work

1. ~~**`NativeDriver` + `AdbNativeDriver`**, the `layer` parameter through
   `RunCore.act`, journal entries with reconciliation, deadline allowance,
   refusal lines on both layers.~~ **Done, 2026-08-12** —
   `app/lib/src/run/native/`: `native_driver.dart` (the driver contract,
   the node model, `NativeTarget` and its refusals), `adb_driver.dart`,
   `native_session.dart` (one held driver per run, the transaction).
   Verified on the emulator: native observe 3.7s, tap 4.8s, the twin-step
   reconciliation catching its own echo (`reconciled: 1`) on the next
   drive observe, and every refusal shape reading as designed. 14 unit
   tests over the parser and target grammar.
2. ~~**The Swift helper + `AxNativeDriver`**.~~ **Done, 2026-08-12** —
   `ax_helper.swift` (compiled by `swiftc` in 2.0s, cached by source hash
   under `~/.flutterware/native/`, 1ms warm) and `ax_driver.dart`.
   Verified on the simulator: observe **546ms**, tap 743ms — seven times
   faster than Android — and the suspended-app recovery end to end
   (§ What the build changed).
3. ~~**macOS chrome scope**.~~ **Done, 2026-08-12.** The re-confirmation
   claimed here — "frontmost, semantics armed *and* frames forced, still
   nothing but a window title" — was itself confounded: on a hidden
   window `ensureSemantics()` builds no tree, so those runs never had the
   semantics they reported having. The scope survives on a better
   mechanism; see § The macOS counterexample, explained.
4. ~~**Dogfood as acceptance.**~~ **Done, 2026-08-12**, with the flow
   changed for a reason (§ What the build changed): a system window over
   the app rather than a camera prompt.

## What the build changed, 2026-08-12

Seven things the design could not have known, each measured while
building.

**The acceptance flow moved, because the keyboard is not addressable.**
`uiautomator dump` describes the **focused window**, not the screen. A
permission dialog, a system alert or another app takes focus and appears
in full (measured: launching Settings over the app made the dump
Settings). The soft keyboard does not take focus, so its keys are absent
even while the screenshot plainly shows it — the design listed the
keyboard as a target and it is not one. Every Android observation now
says this in its note, because the confusing case is exactly the one
where an agent cannot tell "not on screen" from "not in this window".
The acceptance walk (`app/tool/native_spike/dialog_check.dart`) uses a
system window instead, which is the shape every permission prompt has,
and it lands: with Settings over the app, the *drive* layer still
confidently reports the app underneath — blind, and wrong about what is
on screen — while the native layer reads the intruder, dismisses it, and
hands control back.

**AXPress is invisible to the human recorder; only synthetic clicks are
not.** The twin-step problem the design predicted is real on Android
(`reconciled: 1`, verified) and absent on the simulator: an accessibility
press is a semantic action, not a touch, so the guest never sees it.
Reconciliation is therefore a correction for adb taps and coordinate
clicks, not for the Apple platforms' normal path.

**Identity, one layer down.** The macOS driver first attached to *another
worktree's* app: two checkouts building the same package produce two
running apps with the same product name, and picking by name drove
somebody else's window. It is the machine-global selection hole the drive
layer closed with `ownHandles`, met again — and the same answer applies.
The driver now identifies its app by **bundle path** under this
worktree's build directory.

**`Isolate.resolvePackageUri` throws in AOT**, which is what `fw` is. The
helper's source is found by package URI when running from source (MCP,
tests) and by the launcher's own `APP_TOOL_PATH`/`FW_APP_TOOL_PATH` in
the compiled CLI.

**Collapsing wrappers must not collapse identity.** The first tree filter
folded any single-child unlabelled node into its child — which deleted
the `WebView` node itself, the one word telling an agent *why* Flutter
could not see the thing inside it. Only generic containers (`*Layout`,
`android.view.View`) collapse now.

**Resolution searches the whole tree; refusals quote the speaking part.**
A node with no label and no click handler can still be the one you mean
(`{"role": "android.webkit.WebView"}`), so the two lists are separate —
`nodes` for resolving, `speaking` for texts and candidate lists.

**A window in transition answers `ERROR: null root node`.** Measured one
second after launching an activity over the app; it is a moment, not a
state, so the dump retries once before reporting. Without it, "observe
right after tapping something that opens a dialog" would be a coin flip.

**The tool nearly shipped unreachable.** `layer` reached the *plugin
action* — which is what `flutterware_invoke` and the CLI use — but the
promoted `flutterware_act` tool has a hand-written schema of its own, and
it did not carry the parameter. The feature existed and the agent it was
built for could not ask for it. Closed the same day, with a test that
asserts the whole argument set rather than the parameter of the day,
because the identical bug was already sitting there: **`run` was
advertised by the schema and dropped by the handler**, so two runs
separable only by run key — exactly what that refusal tells you to pass —
were unseparable through the tool. Any promoted tool is a second place
the wire has to be kept in step, and nothing was checking it.

**Numbers.** Android: observe 3.7s, tap 4.8s (dump + dump + screencap),
`input text` 6.5s. iOS simulator: observe 546ms, tap 743ms, un-suspend
6.5s end to end. macOS: observe ~550ms. Helper compile 2.0s once, 1ms
cached. The Android cost is the reason the drive layer stays the hot
path, and the tool description says so.

## Open, deliberately

- Whether `drag` earns its native spelling (first real need decides).
- The reconciliation window's exact width (falls out of building it
  against the journal).
- Whether `foreground` should auto-suggest itself inside the existing
  iOS `DriveTimeout` message immediately (yes in spirit — the exact
  wording lands with the implementation).

## The macOS counterexample, explained (2026-08-12, after the merge)

The PR shipped with a loose thread: one Flutter app on the dev machine
published its content to macOS accessibility while the example app refused
to under every condition tried. The scope decision rested on that, so it
was worth chasing.

**The measurement was confounded, twice.**

*Identity.* Three apps were running, all named `flutterware_example`, built
from the same package in three worktrees — the two "Brewline" devbar runs
are the same package with a different entry point. The S-N3 probe matched
by **name**, so "our app is dormant" and "Brewline publishes" were two
observations of whichever process `runningApplications` happened to list
first. (S-N3's own log says `pid 43609` — the *devbar-run-integration*
app, not the one it claimed to be measuring.) Addressed by bundle path,
the two Brewline twins turn out to **differ from each other**, which no
code-level explanation survives.

*Frames.* "Semantics armed" was not armed. `ensureSemantics()` schedules a
frame with `ensureVisualUpdate()`, and a hidden macOS window produces
none — so the tree stayed empty (2 chars over the wire) in exactly the
runs that concluded arming changes nothing.

**The mechanism, in the framework's own words.** Asked for a tree it has
not built, Flutter answers: *"the framework only generates semantics when
asked to do so by the platform"*. That is the whole rule. Flutterware's
`ensureSemantics()` is framework-side — it builds a tree for in-process
readers (scenarios, inspect, `label` targets) and never tells the embedder
to publish. The publishing app had **platform** semantics on; its twin did
not (`ext.flutter.debugDumpSemanticsTreeInTraversalOrder` says which, and
does not change the answer — `app/tool/native_spike/semantics_state.dart`).

**So the scope holds, for a better reason than the one shipped.** Not
"Flutter never publishes on macOS", but "nothing flutterware does asks the
platform for semantics, and only the platform can grant it". The brief
stays native chrome.

**What is not resolved, and is left alone deliberately.** Publication can
be provoked from outside — a probe setting `AXEnhancedUserInterface` was
observed flipping a process from *not generated* to a live semantics tree,
and our own example app was seen publishing all ten of its labels. But the
same treatment on a fresh instance of the same app produced platform
semantics **and no AX content**, through a forced frame and twenty seconds
of polling. One instance publishes, the next does not. There is no recipe
honest enough to put behind a verb, so none was added.

The risk of leaving it is one-directional, which is why this is a
documentation fix rather than a code one: an agent either sees the chrome
it came for, or that plus Flutter content it can also use. The tool note
now says *usually*, and says what to do when the tree is only a window
title.
