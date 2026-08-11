# Run drive — acting in the live app

**Date:** 2026-08-11
**Status:** Designed; the spike ran the same day
(`2026-08-11-run-drive-spike-findings.md`, five iterations, macOS debug) and
**green-lit the build**. It amended four things, each marked **Amended by the
spike** below: the reach check's API, the shape of the actionability fallback
(retry ladder, not settle-before-resolve), the settle algorithm (forced
frames — a hidden window disables frames and wedges transitions), and
`enterText` (no longer an unknown).

**Lineage:** `2026-07-31-app-launcher-cockpit-brainstorm.md` §D7/D9/D10 (the
verb set, the reliability ladder — this design supersedes its "same names,
separate code" call, see § One verb engine), `2026-07-31-sl3-inspect-surface-findings.md`
(what the bare VM service can and cannot do — actions are firmly in "cannot"),
`2026-08-10-inspect-consolidation.md` (the three-host inspect kit this makes
whole for run), `2026-08-11-scenario-transition-events.md` (the attribution
model a live step reuses), `2026-07-31-sl2-attach-findings.md` (iOS: the
launcher owns the session — which makes "launched by flutterware" not much of
a precondition at all).

## The goal

An AI working on a Flutter app run by flutterware should never need
computer-use. Not because we forbid it — because this surface is strictly
better on the three axes computer-use loses on:

- **Addressing.** Computer-use clicks pixels; pixels go stale the moment
  anything animates. We address by Target — text, key, semantics label — and
  resolve it at act time, in-process, failing loud on zero or many matches.
- **Synchronization.** Screenshot → think → click races the app. We make
  act-and-observe one transaction with a settle barrier between them.
- **Observation.** A screenshot is one modality. Every step here returns the
  widget tree, the visible texts, the screenshot, the logs and channel events
  since the last step — the same bundle a scenario step carries.

The first user is flutterware's own development: the GUI (`main_dev.dart` on
the macos device) is just another app the Run plugin can launch in debug, and
the loop *edit → reload → act → observe* replaces most uses of `fw capture`
in the AI's hands.

## The workflow this serves (owner, 2026-08-11)

> I'm a human, I navigate to somewhere, then ask the AI to do some checks and
> iterate on a piece of screen — it inspects the current screen, edits the
> code, reloads, inspects again, clicks a few things, then tells me it's good.
> Then I look at the screen and do my own investigation to confirm I'm happy.

Human and AI collaborate on the *same* running app, from any surface — GUI,
CLI, MCP all equal, per the run plugin's files-not-memory rule. Two
consequences drive the design:

- The AI's opening move is **`observe`**, not history. It does not need to
  know how the human got to this screen; it needs to know what the screen is
  now. Recording human actions is therefore *not* in v1 (§ Not in v1).
- The human's closing move is **review**. The journal (§ The journal) is how
  the run panel shows what the AI did while the human wasn't looking — each
  tap, each reload, each screenshot — the way a scenario's steps are reviewed
  today, instead of trusting "it's good".

## The unit: a step transaction

One guest call, executed entirely in-process:

1. **Resolve** the Target against the live element tree. Exactly one match or
   a loud error listing the candidates (`describeTarget` spelling, shared with
   scenarios).
2. **Actionability**: center-point hit test; on failure `ensureVisible` +
   re-check; still unreachable → the covered-vs-off-screen diagnosis,
   verbatim from `ScenarioTester._ensureReachable`. **Amended by the spike:**
   in a live app, unreachable is usually *temporary* — a route transition
   holds an `IgnorePointer` up by framework design, so a blind tap into an
   entering page is a silent no-op (measured 10/10). The verb therefore
   retries resolve + actionability until its deadline, **settling between
   attempts** (a plain wait advances zero frames on a hidden window); the
   covered/off-screen error surfaces only at deadline. Measured: 10/10
   correct taps landing on the first frame after the IgnorePointer lifts,
   uniformly ~360ms. The check itself must use
   `RendererBinding.hitTestInView`, not `hitTestOnBinding` (whose default
   view is test-typed and throws on a live binding).
3. **Act**: dispatch the verb.
4. **Settle**: bounded wall-clock (§ Settle). Never hangs; reports
   `settled: false` rather than throwing.
5. **Observe**: tree (full `InspectNode` shape — layout, offstage,
   properties, since we are the guest), visible texts, screenshot, events and
   log lines since the previous step.

The reply is the whole bundle. There is deliberately no separate
"tap" that an agent must correlate with a later "screenshot" — two calls
against a live app are two moments, and the gap between them is where
computer-use's bugs live.

**`observe` is a verb**: the same transaction minus steps 1–3. It is what the
AI calls on arrival and after every hot reload.

**Verbs:** `tap`, `longPress`, `drag`, `scrollTo`, `enterText`, `back`,
`wait`, `observe`, `navigate` (§ Navigate). Names and semantics identical to
`ScenarioTester`'s — same docs, same mental model, same error text.

## One verb engine, two bindings

The cockpit brainstorm said "keep the verb *names* identical to scenarios'
but do not unify the code yet". Reversed, for a concrete reason found on
re-reading: `WidgetTester` and `LiveWidgetController` share
`WidgetController`, and everything that makes the scenario verbs trustworthy
already lives at that level or can be pushed to it — `finderForTarget`, the
exactly-one rule, `ensureVisible`, `hitTestOnBinding`, the reachability
diagnosis. The generated entrypoint is debug-only, so the guest can import
`package:flutter_test` and hold a `LiveWidgetController` over the real
`WidgetsBinding`.

So: refactor `ScenarioTester`'s resolve/reach ladder from `WidgetTester` down
to `WidgetController`, and scenarios and live drive become one engine with
two bindings, differing only where they must:

| | scenarios | live drive |
|---|---|---|
| binding | `AutomatedTestWidgetsFlutterBinding` | the app's real `WidgetsBinding` |
| time | fake, `Settle.standard` = 5 fake seconds | wall clock, bounded (§ Settle) |
| pump | test binding pump | real frames (`LiveWidgetController`) |
| capture | `_emit` (layer raster, fake-time cheap) | guest screenshot (§ Screenshots) |
| `enterText` | `testTextInput`, proven | `EditableTextState.userUpdateTextEditingValue` (amended twice — see § Mobile) |

One place to fix an actionability bug, one Target grammar on the wire, one
`describeTarget`. `package:flutter_driver` stays out (master-plan decision 9
stands); `flutter_test` compiling into a `flutter run` target on a real
device is spike question 1.

## Addressing

**Targets are primary** for agents: `text`, `key`, `label`, `tooltip`,
`containing`, `within`, `nth` — re-resolved at act time, so a rebuild between
the AI reading a tree and issuing the tap cannot silently retarget.

**Node ids are accepted** — they are the natural spelling for "the thing I
just picked in this tree" (GUI picker → act). But ids are shape-derived
child-index paths; the guest re-walks before dispatching and a stale id is a
loud error, never a wrong-target tap that "succeeds". That failure mode —
acting on the wrong thing and reporting success — is the one this design
treats as unforgivable.

## Injection: the generated entrypoint

Actions need code in the app; S-L3's findings are unambiguous that the bare
VM service dispatches nothing. The guest rides the same vehicle previews and
scenarios already use: `fw run` launch (from any surface) generates a wrapper
`main` that installs `GuestInspector`, `GuestLogs`, `GuestErrors`,
`GuestImages` and the drive engine, then calls the user's real `main`. No
user code change, debug/profile only, and entrypoint discovery
(`app/lib/src/run/entrypoints.dart`) already knows what to wrap.

An app launched outside flutterware (bare `flutter run`, or Android attach)
gets today's VM-only inspect and **no act** — stated plainly in tool output,
not discovered by a hung call. On iOS this costs nothing: the launcher owns
the session anyway (S-L2).

`Devbar` as an opt-in mount for apps that can't be launched by us: a door
left open, not built.

## Settle

Wall-clock `Settle.standard`: pump until nothing is pending and
`GuestImages` reports images settled, bounded by a budget (default in the
hundreds of ms, configurable per call). On budget exhaustion — an infinite
animation, a spinner — return the observation anyway with `settled: false`
and the count of frames still being produced. The agent always gets its
bundle back; a hung tool call is the one behavior this surface may never
exhibit.

**Amended by the spike — the settle owns the hidden-window problem.** A
hidden/occluded macOS window sets `SchedulerBinding.framesEnabled` false:
`scheduleFrame` no-ops, transitions wedge mid-flight with their
`IgnorePointer` stuck up, rebuilds never flush, and `hasScheduledFrame`
reads false on a wedged app — a naive settle reports settled on a frozen
screen and an observation reads stale state. The validated algorithm:

1. Pending = `hasScheduledFrame || transientCallbackCount > 0` (tickers are
   the honest probe when frames are disabled).
2. When frames are disabled, **force one frame unconditionally first**
   (`scheduleForcedFrame`) — a dirty element is invisible to both probes.
3. Loop while pending and in budget: force a frame if frames are disabled,
   await `endOfFrame` capped per wait.
4. Every observation carries `lifecycleState` and `framesEnabled`.

Measured: the full verb suite — retry ladder included — runs green on a
window that is hidden the whole time, with identical timings to the visible
case (push settles ~530ms, spinner bounds out at budget). An agent can drive
an app nobody is looking at.

`enterText`, resolved by the same runs: **`TextInput.updateEditingValue`**
(the static control-side API pushing to the attached connection) is the
mechanism — no `TextInputControl` installed, so the platform IME stays in
place. The focused-`EditableTextState` variant also works and stays as the
documented fallback. Open on device only: the platform IME's own editing
state diverges (we never inform it) — harmless on desktop, unverified with a
soft keyboard up.

**Superseded on 2026-08-11 by the mobile runs (§ Mobile): the divergence is
real, and the mechanism is now
`EditableTextState.userUpdateTextEditingValue`.**

## Screenshots

`ext.flutter.inspector.screenshot` is the wrong organ for this: debug-only,
blind to embedded-guest textures (which the GUI — our first user — has), and
already known to omit platform views. The guest grows its own screenshot:
raster the root layer as `ScenarioTester._emit` does, plus the
`WindowCapture`-style composite of embedded guest frames when driving the
flutterware GUI itself. Works in profile mode, where the inspector extension
does not exist.

**Defaults (owner, 2026-08-11): screenshot on every step.** It is what makes
the loop self-verifying, and ~100ms/step is noise against a 2.5s CLI hop. Two
spam controls: a `tree-only` flag for tight loops, and the inline MCP image
is size-capped (bounded width) while the full-resolution PNG lands on disk in
the journal for the GUI and for any agent that asks.

## The journal

Every completed step is appended to a per-run journal beside the `RunHandle`
(same directory, same files-not-memory rule, same "any process can read it"
payoff): actor (GUI / CLI / MCP), verb, target description, result,
`settled`, and paths to the observation artifacts. Reload and restart are
journal entries too — they are steps in the story of the run.

Three things the journal is *for*:

- **Human review of AI work** — the run panel renders it as a step strip, the
  scenarios step-page grammar reused (screenshot, tree, texts, events per
  step).
- **Agent memory across hops** — a CLI invocation is a fresh process; the
  MCP server can restart. Step 7 knows what steps 1–6 did by reading the
  journal, not by re-observing.
- **Attribution** — events and logs buffered since the last step flush into
  the step that closes, exactly the transition-events model: what is in the
  buffer at observe time is what happened on the way here.

What it is **not**, in v1: a recording of human actions. The mechanism is
known and cheap — a global pointer route
(`GestureBinding.instance.pointerRouter.addGlobalRoute`), hit-test on
pointer-up, name the nearest nameable widget — but the owner's workflow
doesn't need it (the AI needs *where we are*, not *how we got here*), so the
journal format merely leaves room for entries with `actor: human`.

Caps stated rather than discovered, per the transition-events precedent:
entries per run, bytes per artifact, with visible truncation markers.

## Navigate (owner, 2026-08-11: yes, by declaration)

Tap-walking to a screen is the reliability ladder's bottom rung; addressing
the screen is its top. Any routing system can declare a handler on the guest
(`GuestDrive.navigator = (route) {...}`); `router_outlet` ships an
implementation, the flutterware GUI registers its address system, a bespoke
router is three lines in the app's wrapper-visible setup. `navigate` with no
handler registered is a loud "this app declares no navigation" error — never
a fallback tap-hunt.

## The held session

`RunCore._withInspector`'s connect-read-dispose is right for probes and wrong
for a drive loop. A `DriveSession` holds one `RunConnection` for the loop's
duration: extension stream subscribed, log and event cursors for the
"-since" deltas, tree generation invalidated on reload (a reload announces
itself; ids minted before it are stale by definition). Per-call connections
stay for everything that isn't driving. Concurrent actors are legal — the
journal is the coordination mechanism, not a lock; two writers interleave as
two actors in one story.

## Surfaces

Everything is `PluginAction`s on `RunCore` (`act`, `observe`, `navigate`,
plus today's `reload`/`restart`/`stop`), so GUI/CLI/MCP parity is the
architecture's default. One addition: **promote the act transaction to a
first-class MCP tool**. The gui-cli-mcp architecture reserved tool promotion
for "the drive loop, decided with a real client in front of us" — the real
client has arrived (us, developing flutterware), and the hot loop deserves a
tool whose reply is `ImageContent` + bundle rather than a generic
`flutterware_invoke` envelope.

## fw capture (owner, 2026-08-11)

Not the driver of this design. Most AI-driven development should stop using
`fw capture` and live in the Run loop instead. A debug-mode capture built on
Run — launch if needed, `navigate(address)`, `observe`, write the PNG — is
the ideal end state and lands *after* the drive loop proves itself. The
release env-var path (`captureRequestKey`, `WindowCapture`) is untouched
until then; a release build has no VM service, so it is not replaceable by
this surface anyway.

## Not in v1

- Human-action recording (door open in the journal format, mechanism noted).
- Journeys — named, composable, resilient walk-scripts (cockpit §D10). Still
  parked as the last thing; the ladder's middle rung waits for evidence the
  bottom rung is solid.
- Assertions. Drive observes and reports; it does not `expect`. Scenarios
  are where contracts live.
- Windows (`launch.dart` already refuses), release mode, attach-based acting.

## The spike is the gate

~~One spike, superseding S-L3~~ **Ran, 2026-08-11** —
`2026-08-11-run-drive-spike-findings.md`. All four questions answered on
macOS debug, visible and hidden windows:

1. **`flutter_test` in a live app** — yes; `LiveWidgetController`, finders
   and `scrollUntilVisible` all work against the real binding. One trap
   (`hitTestOnBinding` is test-typed) with a public replacement.
2. **Tap-by-Target under animation** — ~250 taps across five runs,
   **zero wrong targets**. Steady motion 120/120 blind; route transitions
   silently swallow blind taps by design, and the reach-check + retry ladder
   converts that into 10/10 landings. The guessed fallback
   (settle-before-resolve) was the wrong shape; retry-until-reachable is in
   the transaction (§ The unit).
3. **`enterText`** — both mechanisms work end to end;
   `TextInput.updateEditingValue` chosen. Device IME divergence is the one
   remaining device-spike item.
4. **Wall-clock settle** — behaves as specified, and surfaced the
   hidden-window frames problem plus its forced-frame fix (§ Settle), the
   most load-bearing finding of the spike.

~~Still open, needing hardware: one run on a physical phone (compile checked
from here; input + IME behavior is the question).~~ **Answered on an emulator
and a simulator the same evening — § Mobile.** Input works; the IME question
had a real bug behind it. A physical phone remains unrun (signing), and the
one thing only hardware can still tell us is whether a *real* iOS device
suspends harder or sooner than the simulator does.

## Order of work

1. ~~The spike.~~ **Done, 2026-08-11** — findings doc written; this spec
   amended in place.
2. ~~Verb engine refactor to `WidgetController`.~~ **Done, 2026-08-11** —
   `lib/src/drive/`: `resolve.dart` (the shared ladder + `TargetMessages`
   flavoring, scenario wording byte-identical), `live_settle.dart` (the
   forced-frame settle), `drive.dart` (`Drive`, the live verbs with the
   internal retry ladder), exported for generated code via
   `package:flutterware/drive.dart`. Scenarios delegate and stay green
   (62 tests); the spike app re-ran on the production engine — the whole
   journey lands with no driver-side pacing, including a tap through a route
   entrance absorbed by the verb's own retries.
3. ~~Guest: `GuestDrive` (transaction, settle, screenshot),
   generated-entrypoint wiring for run launches.~~ **Done, 2026-08-11** —
   `lib/src/drive/guest_drive.dart` (`ext.flutterware.act`: one serialized
   transaction, refusals still observe, logs/errors ride as since-last-step
   deltas, guest screenshot off the root layer), `lib/src/drive/run_guest.dart`
   + `lib/run_guest.dart` (`runGuest`, the previews-guest wiring minus the
   embedder-only input replacements), `GuestDrive.navigator` as the `navigate`
   registration point, and `writeGuestEntrypoint`
   (`app/lib/src/run/guest_entrypoint.dart`) wired into `launchApp` — every
   run launch now targets a generated wrapper under
   `.dart_tool/flutterware/run/`; entries it cannot wrap launch uninstrumented
   with the reason logged. Node-id targets deliberately wait for the picker
   integration. Verified over the real wire on the spike app: bundle carries
   step, tree, screenshot, texts, lifecycle, logs-since; a refusal returns the
   live-flavored message *plus* the bundle; `navigate` without a handler
   refuses as specified.
4. ~~`DriveSession` + `RunCore` actions + the journal files.~~ **Done,
   2026-08-11** — `app/lib/src/run/drive_session.dart` (one held connection
   per run, dropped on any error, reconnects next call; no lease — the guest
   serializes and the journal coordinates), `app/lib/src/run/journal.dart`
   (`app-<key>.journal.jsonl` beside the handle, JSONL because two processes
   append; artifacts under `journal/app-<key>/`; 5MB cap with one rotation
   and a marker entry), and three `RunCore` actions — `act`, `observe`,
   `navigate`, one funnel — with `RunActResult` in the generated shapes and
   `docs/capabilities.md`. Reloads/restarts journal as steps too. A guest-less
   app answers "launched outside flutterware, inspect-only" rather than an
   RPC error; a hidden window is called out in the result's note. Verified:
   10 new tests over the `debugAct` seam, and `DriveSession` live against
   the spike app (23ms first transaction including connect).
5. ~~The run panel's step strip.~~ **Done, 2026-08-11** — a third run pane,
   `steps` (addressable, between Screen and Logs): the journal as a strip
   pinned to the newest step, each row a thumbnail + `tap "Pay"` sentence +
   actor/time/tries caption, the detail the step's screenshot with facts and
   the refusal in red, falling back to the text projection when a step kept
   no picture. Reachable while the app builds and after it dies — the
   journal is a file, so the pane skips the `_NotYet` gate the live panes
   sit behind. To make review carry the same three legs a scenario step has,
   `act` now persists `.tree.json` and `.texts.json` artifacts beside every
   step's PNG (the tree still rides the *reply* only on request). Not yet
   eyeballed against a real driven session — that is the dogfood step's
   job, and layout verdicts wait for it.
6. ~~MCP tool promotion; agent-facing docs.~~ **Done, 2026-08-11** —
   `flutterware_act`, the fourth (and first promoted) MCP tool: fixed
   plugin/action, typed schema with the Target grammar spelled out, the
   screenshot inlined as `ImageContent` via a new `ProducesArtifacts` on
   `RunActResult` (so plain `flutterware_invoke` inlines it too), and a
   deliberately lean reply — no report attach on the loop's hot path. The
   inline image is bounded by a guest-side `maxSide` render scale (tool
   default 1200px; GUI/CLI keep full resolution). The tool description is
   the authoring string: the edit→reload→act loop, refusal semantics,
   `settled: false` meaning, and the steering line — scenarios for headless
   flows, act for the real thing. Server instructions updated;
   `docs/capabilities.md` regenerated; the MCP suite covers the new tool
   list and an act round-trip against an empty run dir.
7. ~~Dogfood: drive the GUI itself via Run on `main_dev`.~~ **Done,
   2026-08-11** — `tool/flutterware.dart` now declares `app`'s
   `lib/main_dev.dart` as the Run entry point "Studio (dev)" (the config's
   "app is this GUI" exclusion predated drive), and
   `app/tool/drive_spike/dogfood.dart` ran the full stack exactly as an
   agent does: real `Session`, `run.launch` (guest-wrapped, waited through
   the build), then five drive transactions steering the GUI to its own Run
   panel and Steps tab, plus a 114ms hot reload. **The final screenshot is
   the GUI showing the journal of the steps that produced it.** The whole
   drive was 2.1s for six journal entries; acts ran 100–600ms each
   including settle. One honest artifact of that speed: the Steps strip
   polls at 700ms, so the in-flight screenshot showed three steps where the
   journal held five — lag a human never sees and a 2-second robot does.
   Findings on the strip itself await the owner's eyes on the running app.

   **Capture's verdict, from evidence:** the debug lane exists already —
   `observe` *is* launch-navigate-photograph, and the loop's screenshots
   made `fw capture` unnecessary for agent work in this session. `fw
   capture` keeps its release env-var path untouched; a capture-shaped
   convenience on top of Run can be wired the day somebody wants the
   one-liner.

## The wire dogfood, 2026-08-11 (later the same day)

The step-6 dogfood drove through `Session` in-process; the question "is
there a gap between that and what an agent actually gets" deserved its own
run. A real MCP client (stdio, newline-delimited JSON-RPC — the transport
Claude Code speaks) was pointed at the server from source and ran the loop
the feature exists for: **observe → edit `run_plugin.dart` → `run/reload` →
observe → tap the freshly-edited widget → revert**, against the still-running
Studio window from the first dogfood — by then moved to another panel by the
human, which is the co-driving premise doing its job (the agent's opening
`observe` absorbed it without ceremony).

Numbers, over the real wire: the **edit-reload-observe round trip is ~2.1s**
(hot reload 1.3s of it); a single `act` is 0.6–1.4s wall including the
per-call session open; screenshots arrive inline at 180–320KB. The tap of
the widget edited seconds earlier landed on attempt 1. The whole probe ran
against a `lifecycle: hidden` window — the forced-frame settle carrying it,
as designed. Every step, including the `navigate` refusal, appeared in the
journal with `actor: agent` and on the human's Steps tab live.

Three gaps surfaced, none in the loop itself:

1. **The installed `fw` is the agent's front door, and it was two weeks
   stale.** `.mcp.json` said `fw mcp`; the PATH binary predated drive
   entirely — an agent opening the repo would have gotten a server with no
   `flutterware_act`. Fixed for this repo: `.mcp.json` (tracked) now runs
   `fvm dart run flutterware_app:mcp`, so the server is always the
   checkout's own code. For *hosted* installs the binary tracks the
   dependency version and this cannot happen; the trap was specific to a
   dev machine with a globally installed `fw`.
2. **`navigate` has a grammar, a refusal, and zero registered handlers.**
   Not even the GUI's own address system — the flagship case in the owner's
   decision — sets `GuestDrive.navigator`. The refusal message teaches
   correctly, but the verb is currently all door and no room. Registering
   the shell's address system is the highest-leverage follow-up: it turns
   three taps into one call for every trip an agent makes through the GUI.

   **Closed the same day** (`app/lib/src/shell/drive_navigator.dart`,
   registered by both entry points): a route *is* a
   [`ShellController.go`] — the `fw://` grammar the address bar accepts,
   with go's own semantics riding along whole, including opening a closed
   worktree. Two refusals guard the door: not the grammar (taught, with the
   current address), and not a worktree git knows (the known names listed).
   Verified over the MCP wire against the live window: one `navigate` to
   `fw:///worktrees/<wt>/flutterware.run/<runKey>/steps` landed on the Steps
   tab of the very run being driven, 1.4s wall. One trade recorded: the
   handler registers in `main`, so it arrives by hot *restart*, not reload.
3. **The Logger panel makes `texts` expensive.** Each visible log row
   contributes its full text, and daemon-protocol rows run to hundreds of
   characters — an observe on the Logger screen is ~99 texts, several of
   them essays. Not wrong, but a per-string cap (with an ellipsis) would
   keep the worst screen from taxing every reply. Undecided; needs a number.

The agent-facing documentation now lives where the next agent starts:
`CLAUDE.md` gained "Driving the running GUI (the agent inner loop)" — the
launch line, the loop, the refusal grammar, the co-driving rule
(open with `observe`; the human may have moved the app), and when scenarios
beat drive.

## Mobile, measured 2026-08-11 (evening)

The spike's one hardware-shaped item — "input + IME behavior on device, one
afternoon with hardware" — ran against an **Android emulator (API 35)** and
an **iOS simulator (iPhone 16 Pro, iOS 18.1)**, driving `examples/example`
over the real MCP wire. A physical iPhone was attached and refused at the
door: `No Account for Team "B7V224LKE4"`, i.e. Xcode signing on the dev
machine, reported legibly by the `RunFailure` path and nothing to do with
this feature.

**The verdict is that the port is free.** Nothing about the launch → guest →
act path is desktop-shaped: `flutter_test` compiles into iOS and Android
debug builds, `writeGuestEntrypoint` wraps the same way, the guest
screenshot (`OffsetLayer.toImage`) is correct under Impeller on both, and
the numbers are desktop numbers — observe 17–21ms, tap 500–800ms including
settle, hot reload 190ms on the iOS simulator. Taps, `enterText`, tree,
texts and the journal all landed on both platforms with no code change.

Three things were wrong, none of them visible from a desktop:

1. **The platform IME diverged, on both platforms.** After `enterText` wrote
   a sentence, a keystroke from the *platform* — the host keyboard into the
   iOS soft keyboard, `adb shell input text` on Android — **replaced** the
   agent's text instead of appending: the platform still held the pre-act
   value, because `TextInput.updateEditingValue` is control-side and tells
   only the framework. This breaks co-driving precisely where it is supposed
   to work, and a desktop run cannot show it (no IME shadow state of its own
   to disagree). Fixed by moving to
   `EditableTextState.userUpdateTextEditingValue`, which formats, fires
   `onChanged`, and pushes `setEditingState` back down the live input
   connection. Verified on both: the human's next keystrokes now append.
2. **A backgrounded iOS app hung the call, forever.** iOS suspends the
   process; the guest is never scheduled, so `ext.flutterware.act` is never
   dispatched and no answer comes — measured, the MCP client aborted at
   **1800s**, violating this design's one hard rule. Android is fine and
   behaves exactly like the hidden macOS window (`lifecycle: paused`,
   `framesEnabled: false`, forced frames carry it). The guest's own "never
   hang" guarantee only ever covered a guest that runs, so the deadline
   belongs on the host: `DriveSession` now bounds the call by what that call
   asked the guest to spend (settle + act timeout + wait, `scrollTo`'s
   count-bounded drags allowed for, plus 20s of slack) and, on expiry, asks
   the VM whether it answers at all — which separates "a verb is wedged"
   from "the process is not being scheduled". **Two doors, both measured:**
   the held connection times out at the deadline (23s), and — because a
   failed probe drops the session — the *next* call times out in the connect
   instead, 5s in, where the raw `TimeoutException after 0:00:05` said
   nothing about apps at all. Both now answer with the same sentence,
   including the surprising part: the step is not lost, a suspended guest
   runs its request on resume (observed — a tap sent to a backgrounded app
   landed when the app came forward).
3. **A focused text field on iOS never settles.** The Cupertino cursor
   animates, so `transientCallbackCount > 0` forever: every step after a
   field takes focus burns the whole 800ms budget and reports
   `settled: false`. Android's cursor blinks on a `Timer` — 152ms, settled.
   Not fixed: the honest fix is to stop counting the caret ticker as work,
   and the cheap wrong fix is to stop trusting tickers, which is the probe
   that makes the hidden-window settle correct. Left as a known cost with a
   number on it.

Two facts worth stating rather than fixing. **The soft keyboard is invisible
in the guest screenshot** — the raster is the Flutter layer tree, so the
agent sees a blank band where the keyboard is (confirmed against a `simctl`
screenshot of the same moment); the same holds for platform views, which are
far more common on a phone than on desktop. And **the run must be
foregrounded to be driven on iOS**, which is not a limitation we can lift:
waking a suspended app from outside is the OS's call, not ours.

## Decided by the owner, 2026-08-11

1. **Launched-by-flutterware is an acceptable precondition** for acting;
   inspect-only otherwise. All surfaces (GUI/CLI/MCP) equal — human and AI
   co-drive the same app.
2. **Screenshot on every step** — good practice, as long as the inline copy
   doesn't spam the agent (size-capped inline, full-res on disk).
3. **The journal records tool steps only** in v1. The envisioned workflow is
   collaboration on the current screen, not replay of human history.
4. **`navigate` is in**, for any app that declares a handler (`router_outlet`,
   the GUI's address system, or bespoke).
5. **Scenarios remain the preferred surface** for flows expressible
   headlessly; drive exists for the live app — real plugins, real backends,
   real data (a production-shaped bug), and the GUI itself.

## Open, deliberately

- ~~The `enterText` mechanism — spike question 3.~~ Closed, § Mobile:
  `userUpdateTextEditingValue`, because the platform has to be told too.
- ~~`flutter_test` on-device viability — spike question 1.~~ Closed, § Mobile:
  it compiles and runs on both mobile platforms.
- Whether the caret ticker should count as pending work (§ Mobile item 3).
- Journal file format details (one file vs. per-step, rotation) — falls out
  of building it against the panel.
- The promoted MCP tool's exact shape (one `act` tool vs. `act`+`observe`) —
  decide with the first real agent transcript in hand.
- Human-action entries in the journal — door open, mechanism noted, no date.
