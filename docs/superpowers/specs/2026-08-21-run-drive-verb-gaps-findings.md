# Run drive — the verbs that are not wired yet

**Date:** 2026-08-21
**Status:** Spiked against the live Studio (`Studio (dev)`, macOS, hidden
window), edit → `run/reload` → `act`. Every claim below was measured on the
running app, not read off the framework. **Verdict: `hover` is a small,
clean addition; `key` and `scroll` are bigger wins and cost one non-obvious
mechanism each; `resize` is still the highest-value missing verb and is the
only one that does not fit the pointer engine.**

**All six are built** — `hover`, `unhover`, `scroll`, `key`, `doubleTap`,
`secondaryTap`. Each section below records what the build changed about its
spike, which in four cases out of six was something the spike had got wrong or
had not thought about.

## What the drive layer speaks today

`tap`, `longPress`, `drag`, `scrollTo`, `enterText`, `back`, `wait`,
`observe`, `navigate` (`lib/src/drive/guest_drive.dart:157`). Every one of
them is a *touch* pointer or a channel push. Nothing in the vocabulary is a
mouse, and nothing is a keyboard — which is the whole gap on desktop.

Adding a verb touches six places, none of them hard: `Drive` (the engine),
`guest_drive.dart` (the wire arm), `run_core.dart` (the `ActionOption` list
and, only if it needs a new parameter, the wire allowlist at
`run_core.dart:3915`), `mcp_server.dart` (the tool description), the icon map
in `run_plugin.dart:1557`, and `docs/capabilities.md`. The verb string itself
is **not** validated anywhere on the host, which is what made this spike
possible: a guest that knows `hover` answers `{verb: hover}` from an MCP
server that has never heard of it.

## hover — built

A synthetic `PointerHoverEvent` with `kind: mouse` reaches `MouseTracker`
on the live binding for free: `RendererBinding.dispatchEvent` feeds *every*
pointer event to `_mouseTracker.updateWithEvent` before `super.dispatchEvent`,
and `GestureBinding._handlePointerEventImmediately` hit-tests hover events
like it hit-tests downs. No test binding, no plugin, no engine cooperation.

Measured on the Studio:

- Rail item `Translations` picked up its hover tint on the first `hover`
  and lost it on `unhover`.
- The toolbar's Tooltip (`Config — what tool/flutterware.dart resolved to`)
  appeared, in the screenshot **and in the reply's `texts`** — a tooltip is
  an `OverlayEntry`, so `screen` reports it like any other widget. That makes
  "does this control explain itself" a machine-checkable question for the
  first time.
- Cost: 84–210ms per step, indistinguishable from `tap`.

Three things shaped the built verb:

1. **A settle is frames, and a tooltip's delay is a `Timer`.** The Studio's
   theme sets `waitDuration: 400ms` (`app/lib/src/ui/theme.dart:196`). A
   `hover` that settles and returns sees an idle tree at ~80ms and reports
   `settled: true` with no tooltip — the wait budget is never spent because
   nothing is animating. The tooltip only appeared after a separate
   `wait 1500`. So both verbs take a **`holdMs`** that burns *real* time, 600
   by default — the top of the range apps configure, Flutter's own default
   being zero.

   The hold is two phases and the order is the trick. The immediate reaction
   — a tint, an elevation — schedules a frame the instant the event lands, so
   a plain "stop as soon as the app reacts" poll stops on *that* and never
   waits for the delayed thing. A settle absorbs the immediate reaction
   first; only after it is a newly scheduled frame evidence of the second,
   delayed one. Missing that evidence costs latency and never correctness:
   the caller's settle runs after every hold. Measured after the build, one
   call, no follow-up `wait`: tooltip on screen and in `texts` at **1652ms**;
   a rail item with a tint and no tooltip at **855ms**; a no-op `unhover`
   at **180ms**.
2. **The pointer stays parked.** That is the correct mouse semantic — a real
   mouse does not un-hover because you pressed a key, and a `tap` after a
   `hover` finding the control still hovered is the point when the thing to
   tap only appears on hover. It also means a later `navigate` leaves
   whatever is now under that coordinate hovered. `unhover` is not optional
   garnish; it is the other half of the verb, and its step names what it
   released so the journal line reads `unhover "Save"`.
3. **Co-driving gets a second mouse.** `TestPointer` defaults a mouse to
   device 1 and the macOS embedder's real mouse is device 0. The built verb
   goes further and uses device 1000, because `MouseTracker` asserts an added
   event only ever follows a removed one: sharing the human's device would
   make `unhover` delete a state the engine still believes it owns, and the
   human moving their real mouse back over the window would fire that assert
   *inside their app*. The price is that the agent's hover and the human's
   coexist — two things can read as hovered at once — which is the cheaper of
   the two.

`human_actions.dart` needed no change: it records only down/up pairs, so the
human's own hovering stays out of the journal, which is right — a fling was
excluded for the same reason.

Built across `lib/src/drive/drive.dart` (engine), `guest_drive.dart` (wire),
`run_core.dart` (verb options, `holdMs`, wire allowlist), `mcp_server.dart`
(schema **and `actArguments`** — a guard test catches a property that is
advertised and not forwarded), the verb icon, `docs/capabilities.md` and
CLAUDE.md. Covered by `test/drive/hover_test.dart` — enter, exit, moving the
hover, a Material control's `onHover`, both tooltip directions with fake time
advanced by hand, and a refused target — plus the wire and journal in
`app/test/plugins/run_act_test.dart`.

## key — built

Two mechanisms, both non-obvious, both found by measurement:

**1. `flutter_test`'s key simulation cannot run in a live app.**
`simulateKeyDownEvent` always also sends the raw key message, and it sends it
through `TestDefaultBinaryMessengerBinding.instance`. In a process whose
binding is the real `WidgetsFlutterBinding` that throws
`'_debugInitializedType == null': is not true`. Measured, first attempt.

**2. `KeyEventManager.handleKeyData` alone dispatches nothing.** For a
non-synthesized event it *queues* into `_keyEventsSinceLastMessage` and waits
for the raw `flutter/keyevent` message that always follows on a real
platform. Measured: `metaLeft`+`keyK` through `handleKeyData` alone reached
no `Shortcuts` binding and changed nothing on screen.

What works is both halves, in the engine's order: the `ui.KeyData`, then
`channelBuffers.push(SystemChannels.keyEvent.name, …)` — the same door
`Drive.back` already knocks on — with the raw map built by
`KeyEventSimulator.getKeyData`, which is public and carries the per-platform
key tables. With that, `⌘K` opened the Studio's command palette and `escape`
closed it, and `HardwareKeyboard.instance.logicalKeysPressed` went
`{Meta Left, Key K}` → `{}` cleanly across the pair.

Four things shaped the built verb:

- **`keyEventManager` is deprecated** ("add a handler to `HardwareKeyboard`
  instead") and is nonetheless the only live path to the widget tree:
  `FocusManager` registers on `keyEventManager.keyMessageHandler`
  (`focus_manager.dart:2139`), so `HardwareKeyboard.handleKeyEvent` would
  update the modifier state and never reach `Shortcuts`/`Actions`. The verb
  ships with an `ignore:` and a comment; a Flutter release that removes the
  member takes the verb with it.
- **A key needs a focus, and it refuses when it did not have one.** Key
  events dispatch from the primary focus *upwards*. With nothing focused the
  primary focus is the root scope — or null — which sits **above** the app's
  `Shortcuts`, so every binding is missed. Measured on the Studio three
  times: `focus=Root Focus Scope` → ⌘K did nothing; after one `enterText`
  put focus in a field, `focus=FocusNode#4931e([PRIMARY FOCUS])` → the
  palette opened. A hidden or never-focused window makes this the *normal*
  state, not the edge case.

  The refusal is gated on **both** halves — nothing took the key *and*
  nothing holds focus — because either alone refuses wrongly. Plenty of
  keystrokes are legitimately unhandled (a letter typed at nothing, an
  Escape with no binding), and an app can handle a key through a
  `HardwareKeyboard` handler with nothing focused at all. `handled` comes
  back from `handleRawKeyMessage`, which returns `{'handled': bool}` — the
  same flag `flutter_test` reads. Measured after the build, on the real app:
  `cmd+k` refused with the focus sentence, then opened the palette after one
  `enterText`, and `esc` closed it.
- **The manager is called directly, not through its channel.**
  `handleRawKeyMessage` *is* the handler `ServicesBinding` puts on
  `SystemChannels.keyEvent`, so it is the same code either way — but a
  `channelBuffers.push` invokes it in the zone the listener registered in and
  answers through that zone, which under a test binding's `FakeAsync` never
  completes. The first version of the test **hung**, and this is why. Calling
  the manager keeps the reply in the caller's zone and keeps `handled`
  observable in a widget test.
- **The first keystroke of a run latches the process's transit mode.**
  `KeyEventManager` latches onto whichever kind of message it sees first and
  asserts on the other for the rest of the isolate's life. Sending the
  `KeyData` first latches `keyDataThenRawKeyData`, which is what every
  embedder Flutter currently ships does — so the human's own keyboard keeps
  working. Sending only the raw message would latch the legacy mode and crash
  on the engine's next real key.

**And a key does not type.** A character reaches a text field through the
platform's *text input*, never through a key event; the two merely accompany
each other on a real keyboard. `key('a')` into a focused field leaves it
empty, in a widget test and in a running app alike. That is not a gap in the
verb — `enterText` is the typing verb — but it is what "typing doesn't work"
looks like from outside, so it is asserted in a test and said in every
description.

The chord grammar is `+`-separated, last name fires, the rest are held and
released in reverse **in a `finally`** — a key left down is state the human
inherits. A chord whose keys are already held is refused rather than injected
on top, because this is a surface two people drive at once. Aliases (`cmd`,
`ctrl`, `alt`, `opt`, `shift`, `esc`, arrows) resolve to the **left**
modifier, which is what every `SingleActivator` is satisfied by. Covered by
`test/drive/key_test.dart`.

**A fifth mechanism, found in review: a key can exist and still not be
sendable here.** `knownPhysicalKeys` is every key on every keyboard, and it is
the right set for the `usbHidUsage` the `KeyData` half carries — but the raw
half is built out of Flutter's *per-platform* key tables, which are much
smaller, and `getKeyData` reaches into three of them with a bare
`assert(x != null); return x!;`. So `f24`, `browserBack` and `abort` all pass
the physical-key lookup and then throw an `AssertionError` from inside
`flutter_test` — which, not being a `TargetError`, escapes the guest's refusal
path entirely and comes back as a bare stack trace **with no screen attached**:
the worst answer available to someone who only mistyped a key name.

The fix asks the same function the send will ask, once per key, before
anything is pressed, and turns whatever it throws into the refusal the caller
deserved — rather than reimplementing three private lookups that would then
drift. Doing it for the whole chord up front is what stops a modifier being
left held by a trigger that turns out to be unsendable. Verified on the real
macOS app: `f24` and `browserBack` now refuse by name, naming the platform.

## scroll (wheel) — built

A `PointerScrollEvent` from a mouse device is a pointer *signal*: a different
path through the framework than a drag, and the one a desktop user actually
takes. Measured: one `scroll dy: 600` over the Lints table moved that table
and nothing else.

That last part is the interesting bit. Papercut 3 of the 2026-08-13 review
was `scrollTo` silently walking the wrong `Scrollable`; a wheel event has no
such ambiguity, because it is delivered by hit test to whatever is under the
pointer. `scroll` is not a nicer `drag` — it is the verb that makes "scroll
*this* pane" expressible.

Note `MouseTracker` ignores `PointerSignalEvent` for hover bookkeeping, so a
wheel that positions the pointer first (as this does) also produces the hover
— again, exactly like a real mouse, and `unhover` is what ends it.

The build added the one thing the spike had not thought about: **the sign is
the wheel's, not the finger's.** The delta is added to the scroll offset, so a
positive `dy` moves *down* the list, where `drag` wants a negative `dy` for the
same movement. Both conventions are the platform's; getting them backwards is
the one mistake this verb invites, so it is spelled out on `dy` itself in every
description. Measured after the build, live: one `scroll dy: 500` over the
Lints table at **370ms**, table moved, rail untouched.

Covered by `test/drive/scroll_test.dart`: two lists side by side prove the pane
under the pointer is the one that moves (a verb picking "the first Scrollable"
fails that), both signs, the parked hover, and a refused target.

## doubleTap and secondaryTap — built

Filed in the spike as "cheap, mechanically identical to `tap`". Half right.

**`doubleTap`'s gap is real time and cannot be skipped.**
`DoubleTapGestureRecognizer` *restarts* rather than fires when the second tap
lands inside `kDoubleTapMinTime` — 40ms, and it is there because a touch screen
reports one long touch intermittently, which is the case that rule exists to
tell apart. A naive tap-twice fires nothing at all. The default gap is 80ms:
above the minimum, well under `kDoubleTapTimeout` (300ms), which the whole
gesture must also fit inside. `gapMs` overrides it, and there is a test that
sets it to zero and asserts nothing fires, because that is exactly the mistake
the number prevents.

That gap is also why the tests for this verb run inside `runAsync`: a
`Future.delayed` in an ordinary widget test is fake time that nobody advances,
and the verb would hang. (Same class of problem as `key`'s channel round trip —
this engine keeps meeting it, and the shape of the answer is always "do not let
a verb wait on something the test zone will not deliver".) The one case that
does *not* need `runAsync` is the refusal: the target resolves before either
tap.

It is a **touch** rather than a mouse double-click, like `tap`: `onDoubleTap`
accepts either, and keeping the same pointer makes it exactly "tap twice" on a
phone as much as on a desktop.

**`secondaryTap` uses the same synthetic mouse as `hover`**, moving there and
clicking with `kSecondaryButton`, which is both what a mouse does and what a
context menu opening under the cursor depends on. It therefore leaves the
target hovered, like `scroll`. The button is released in a `finally` — a
pointer left down asserts on the next `hover` and would wedge every mouse verb
for the life of the run, so there is a test that right-clicks and then hovers
something else.

The spike could not measure `secondaryTap` because the Studio has no
`onSecondaryTap` in `app/lib`. It has one after all, one layer down: the diff
body is a `SelectionArea`, and `SelectableRegion` handles a right-click by
selecting the word under it and showing the toolbar. Measured live on the
Changes screen: **433ms**, and "Copy"/"Select All" arrive in `texts` — a
context menu is a widget like any other. `doubleTap` measured at **458ms**,
resetting the sidebar from 302px to its 232px default.

## resize — still the gap, and it is not a pointer verb

Recorded as the highest-value missing feature on 2026-08-13 and still true:
responsive breakage was the top finding of that whole review and testing it
meant dropping out of the tool to `osascript`. Two routes, and they are not
equivalent:

- **Native.** macOS AX exposes a settable `AXSize` on a window and
  `app/lib/src/run/native/ax_driver.dart` already speaks AX through its Swift
  helper (it does `foreground` that way). Real window, real platform
  constraints, macOS-only, and nothing for a phone.
- **Viewport override.** Set `renderView.configuration` to a tight logical
  size — the thing preview stages already do — and the app lays out narrow
  inside the same window. Works on every platform including mobile,
  letterboxes rather than resizes, and costs a wrapper the run guest does not
  currently have (`runGuest` wraps `main`, not the widget tree).

The second is the one that answers the actual question ("does this layout
survive 600px") everywhere; the first is the one that is honest about the
platform. Worth deciding before building either.

## Not investigated

Trackpad pinch/rotate (`panZoomStart/Update/End`, `PointerScaleEvent`),
`fling` with real momentum, clipboard read/write, and the semantics-action
surface (`increase`/`decrease`/`dismiss`/`copy`/`paste` on
`SemanticsController`) — the last of which would let the transcript audits
*act*, not just read.
