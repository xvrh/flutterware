# Spike — capturing what happens between two steps

**Date:** 2026-08-11
**Question:** the design doc's step 1 — *is the free capture as good as it
reads?* Does the channel spy see real plugin traffic, does it disturb a passing
suite, how loud is `system` really, and does buffer-then-flush attribute events
to the right transition.
**Answer:** the mechanism works, costs nothing, and **one of the design's two
headline claims is wrong**: sqflite is not free. Two of its three planned
mechanisms were replaced by better ones found here.
**Method:** the real `examples/example` package, a real `flutter_tester`, the
real runner. A scenario exercising print / `debugPrint` / `package:logging` /
a hand-rolled analytics `MethodChannel` / `path_provider` / sqflite, run four
times with the harness hardcoded. All spike code reverted; the tree is green
(`app/test/scenarios/runner_test.dart`, 6/6).
**Design:** `2026-08-11-scenario-transition-events.md`, amended by this.

## What the transition actually looks like

The design's central mechanic — buffer as recorded, flush on capture — works,
and reads the way it was supposed to. One tap, verbatim:

```
=== step 2 (auto) ← 6 events
  out flutter/accessibility  <34 bytes>
  out flutter/platform  MethodCall(SystemSound.play, SystemSoundType.click)
  print [app] save tapped
  print [app] debugPrint from save
  log WARNING spike: saving
  out com.example.analytics  logEvent({name: checkout_started,
                                       parameters: {cart: 3, currency: EUR}})
```

Three independent lanes — platform channel, `print`, `package:logging` —
interleaved in true order with no sequencing work of any kind. All three
record synchronously, which is why. **Ordering is not an open question.**

## Finding 1 — the spy must wrap, not raid

`createBinaryMessenger()` is overridable and `TestDefaultBinaryMessenger`'s
constructor is public, as the design said. But the binding's own override
installs `outboundHandlers: {'flutter/keyboard': …}`, and those are private.
The first attempt took the configured messenger's `delegate` and rebuilt around
it — dropping the keyboard handler. `getKeyboardState` then went to the engine,
was never answered, and **every run hung until the 4-minute test timeout**,
including the whole existing e2e suite.

The fix is one word: the configured messenger becomes the **delegate**, not the
donor.

```dart
_SpyMessenger(TestDefaultBinaryMessenger inner) : super(inner);
```

Unhandled channels then fall through to it and its handlers are intact. Mock
handlers a user's test registers land on the outer messenger and are still
found first. With that, the existing suite passes in 13s, unchanged.

Not `allMessagesHandler` (the public single-slot hook on the same class): it is
one slot, a user's test may want it, and the subclass takes nothing away.

## Finding 2 — prints need no zone, and are currently being dropped

The design proposed a `ZoneSpecification(print:)` around the scenario body.
Installed at the **harness** level it captured nothing, and the reason is
structural: `test_api`'s `Invoker` already forks a zone with its own print
spec, which does not delegate upward. It republishes each line on
`LiveTest.onMessage`.

`_runOne` never subscribed to that stream. So today, **a `print` inside a
scenario goes nowhere** — not to the terminal, not to the panel. That is a
standing bug this spike found by accident, and the fix is one line:

```dart
var messages = live.onMessage.listen((m) => _spy('print ${m.text}'));
```

It catches `debugPrint` too (this binding routes it to
`debugPrintSynchronously`), it is ordered correctly against channel traffic,
and it needs no zone anywhere. **Delete the print-zone lane from the design.**

## Finding 3 — never await a root-zone future inside a scenario body

The logging listener was first installed around `body(s)`, cancelled with
`await subscription.cancel()`. Every run hung — including scenarios that log
nothing, which is what made it hard to see.

`StreamSubscription.cancel()` returns a future owned by the **root zone**.
Awaiting one from inside FakeAsync parks the continuation on the real microtask
queue, which the fake clock never drains while the body is blocked. Confirmed
by bisection: listener with `await cancel()` hangs; identical listener with the
cancel unawaited passes in 9s.

Two consequences, one narrow and one general:

- Install and cancel the logging listener in `_runOne`, **outside** FakeAsync,
  around `live.run()`. Once per run rather than once per split replay, and no
  fake-clock interaction at all.
- The general rule is worth carrying into the authoring docs: **a scenario body
  may not await a future that belongs to the root zone.** It does not fail, it
  hangs, and the harness reports nothing until a timeout fires somewhere else.

## Finding 4 — sqflite is not free, and the doc must say so

The design listed sqflite as captured with no user API. It is not.
`openDatabase` throws `StateError` **before any channel message exists**:

```
[app] sqflite threw: StateError   // databaseFactory not initialized
```

`sqflite`'s factory is installed by `SqflitePlugin.registerWith()`, which the
generated dart plugin registrant calls — and the harness compiles its own
entrypoint, so no registrant ever runs. Worse for the claim: real projects test
sqflite with `sqflite_common_ffi`, which is **pure Dart and never touches a
channel either**. Both lanes are invisible to the spy.

`path_provider`, in the same run, *was* captured:

```
out plugins.flutter.io/path_provider  getApplicationDocumentsDirectory(null)
```

The discriminator is not "is it a plugin" but **how its platform interface
resolves**: a default `MethodChannel` implementation (path_provider) sends and
is seen; an instance gated on registration (sqflite) throws before sending.

So the honest statement, replacing the design's table: *the spy sees whatever
the app actually sends, and in a widget test a good deal of plugin traffic is
never sent at all.* The sink (lane 3) is the primary lane; the spy is a bonus
that happens to cover a real slice. Analytics is the good case — a plain
`MethodChannel` invoke was captured with its full argument map, which is what
Firebase Analytics is on the wire.

## Finding 5 — `system` is exactly as loud as feared, and `ret` is worse

One `s.enterText` produced **24 events**, all but one on `flutter/textinput`,
including nine identical 6-byte reply envelopes. Boot cost 18. The scenario's
own interesting events numbered six.

- Hidden-by-default for `system` (owner's call) is confirmed, not a guess.
- Additionally: **drop reply frames for system channels.** `ret … <6 bytes>` is
  an empty success envelope; nine of them in a row is noise with no reading.
  Keep replies where the payload decodes to something (an error, a value).

## Finding 6 — cost is nothing

**55 events, 1.0ms of decode, over a 480ms four-step scenario — 0.2%.** The
capture path (PNG encode) remains the entire cost of a run, exactly as the
2026-07-30 measurements said. No budget concern, and the caps in the design are
about response size and memory, not speed.

## Finding 7 — two attribution behaviours worth documenting

- **Async continuations land on the next transition.** `path_provider` was
  called from the tap's handler, but the handler is `async` and the step had
  already captured, so it appears on step 3 rather than step 2. Honest — the
  buffer says "between capture 2 and capture 3" and means it — but a reader
  will expect a tap's consequences under the tap. Say so in the tab.
- **The trailing bucket is real but was junk.** Four events arrived after the
  last step: `TextInput.clearClient`, `TextInput.hide` and their replies —
  pure teardown. Supports the owner's call to drop them, on this evidence.

## Verdict

Build it. The mechanism is sound, cheap, correctly ordered, and the two hangs
it produced are both understood and both one-line fixes. Revise the design doc
for findings 2, 3 and 4 before starting.

## Amendments owed to `2026-08-11-scenario-transition-events.md`

1. Lane 2 loses the print zone → `LiveTest.onMessage`, and gains the note that
   prints are dropped today.
2. Lane 2's logging listener moves out of the body into `_runOne`, with the
   root-zone rule recorded.
3. The plugin table loses sqflite and gains the platform-interface
   discriminator; "two of the four sources arrive free" becomes one.
4. § Order of work loses step 1 (this spike) and gains "drop system `ret`
   frames" in the capture step.
