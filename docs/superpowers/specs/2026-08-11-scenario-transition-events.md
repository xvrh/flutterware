# Scenarios — what happened between two screens

**Date:** 2026-08-11
**Status:** **Built**, 2026-08-11, as described below.
Four questions were put to the owner and answered (§ Decided by the owner);
the spike then ran (`2026-08-11-scenario-events-spike-findings.md`) and
corrected three things in place: the print lane (no zone —
`LiveTest.onMessage`), where the logging listener lives (outside FakeAsync, or
the run hangs), and the plugin table (sqflite is **not** free). Every amended
paragraph is marked.

> **Superseded in part, 2026-08-21.** The reporting call is no longer
> scenario-only: it fans out to a mounted devbar as well, and the names moved
> with it — `ScenarioEvent` → `AppEvent`, `recordScenarioEvent` →
> `recordAppEvent`, `lib/src/scenarios/events.dart` →
> `lib/src/app_events/events.dart`. See
> `2026-08-21-app-events-unification.md`. Everything below about the *model*,
> the buffer, the caps and the lanes is unchanged and still current; only the
> names and the destination widened. This file uses the new names throughout.

As built: `lib/src/app_events/events.dart` (model, sink, buffer, caps),
`lib/scenarios.dart` (the import a fake uses), the three lanes in
`harness.dart`, drain-and-dedupe in `scenario.dart`,
`app/lib/src/scenarios/events_view.dart` (the tab), the two-line edge label in
`flow_view.dart` on an `EdgeTooltip` grown a subtitle.
Two things construction changed, both after looking at the panel:

- **The arrow counts non-`system` events only.** Counting everything put "4
  events" on every arrow of a flow with no reporting at all, and led the reader
  to a tab filtered down to nothing. `system` keeps its own chip and count.
- **A `ValueKey` target reads as `key 'shop.getStarted'`**, not
  `[<'shop.getStarted'>]` — three kinds of bracket around the only part
  anybody wrote. `describeTarget` is shared with the verbs' error messages, so
  both improved together.

**Lineage:** `2026-07-30-scenarios-design.md` (the plugin and the step triple),
`2026-08-10-scenarios-semantics-tab.md` (the fourth leg, and the shape a new
per-step capture follows), dev_studio's `AnalyticEvent` — one event per screen,
overridable by the project, drawn on the link row in the detail page. That is
the ancestor of everything below, generalized from one event to a stream and
from analytics to any channel.

## The gap

A step says what the screen looked like — pixels, widget tree, semantics,
texts. It says nothing about what the app *did* on the way there. A tap fires
an analytics event, a network call, three SQLite writes and a log line, and
the flow graph shows two pictures with an arrow between them. The arrow is
where the app's behaviour lives and it is currently empty.

## The model: keyed on the step, read as the edge

Every step has exactly one parent, so "the transition into step N" and "step
N's incoming edge" are the same object. Events are keyed on the **step**;
only the display speaks of transitions. No new entity on the wire, no second
address space, no edge identity to invent — `ScenarioRunStep.parent` already
says where the arrow starts.

Attribution is by arrival. The tester buffers events as they are recorded and
flushes the buffer when it captures: what is in the buffer at capture time is
what happened on the way here. Three consequences of that rule, each a
decision:

- **Before the first step** the buffer already has content — the app's boot:
  the database opening, the first fetch, the first `screen_view`. It lands on
  step 1, whose incoming edge is the one from nothing. Correct, and the most
  interesting transition in most apps.
- **After the last step**, nothing captures, so the buffer is dropped. Not a
  bucket, not a synthetic trailing node — see § Decided by the owner, 4.
  Written down here because dropping is a choice, and the day somebody asks
  "where did my logout call go", this paragraph is the answer. (The spike's
  trailing bucket held four events, all of them `TextInput` teardown — which
  is evidence for the call, not against it.)
- **An async continuation lands on the next transition.** Measured: a
  `path_provider` call made from a tap's `async` handler appeared on step 3,
  because step 2 had already captured. Honest — the buffer means exactly what
  it says — but a reader expects a tap's consequences under the tap, so the
  Events tab should say which two steps it sits between.
- **Split replays** re-run the body, so a shared prefix records its events
  again on every path. The capture path already recognises a repeated position
  and skips it (`_state.emitted`, `scenario.dart` `_capture`); the flush must
  follow the same key — a recognised position **discards** its buffer, because
  the first pass already recorded it. Without that, a two-branch scenario
  reports its prefix's events twice and a three-branch one three times.

### The step gains a verb

While the transition becomes visible, it should say what it *is*. A step
records no trace of the verb that produced it, so the flow can only ever read
`3 · Receipt`. Recording the verb and its target description at the top of
`_step` makes every surface able to say `tap "Pay" › 4 events › Receipt` — the
sentence the feature exists to write. Two nullable fields
(`verb`, `target`), set where the verb already has both in hand.

## Reporting: three lanes, and two of them cost the user nothing

### Lane 1 — the platform-channel spy (automatic)

The important discovery. Under the test binding **every platform channel
message passes through a messenger our own binding constructs.**
`_HarnessBinding` extends `AutomatedTestWidgetsFlutterBinding`, and
`TestDefaultBinaryMessengerBinding.createBinaryMessenger()` is a plain
`@override` returning a `TestDefaultBinaryMessenger` whose constructor is
public (`TestDefaultBinaryMessenger(delegate, {outboundHandlers})`) — verified
against the pinned SDK, 2026-08-11. So the harness returns a subclass that
overrides `send` (framework → platform) and `handlePlatformMessage`
(platform → framework), records, and delegates to `super`.

Not `allMessagesHandler`, the public single-slot hook on the same class: it is
one slot, a test may want it, and taking it from the user to implement a
viewer would be a poor trade. The subclass takes nothing away.

**Amended by the spike.** The rule is not "plugins are channels" — it is *how
each plugin's platform interface resolves*:

| | captured? | why |
|---|---|---|
| a plain `MethodChannel` invoke (what Firebase Analytics is on the wire) | **yes**, with its full argument map | nothing to resolve |
| path_provider, and any plugin whose platform interface defaults to a `MethodChannel` implementation | **yes**, measured | the default instance sends |
| **sqflite** | **no** | `openDatabase` throws `StateError` before any message: the factory is installed by the dart plugin registrant, which the harness never runs. And a project testing with `sqflite_common_ffi` is pure Dart — no channel either way |

So the honest claim is: *the spy sees whatever the app actually sends, and in a
widget test a good deal of plugin traffic is never sent at all.* One of the
owner's four sources arrives free, not two. The sink below is the primary lane;
the spy is a bonus that covers a real slice.

**Drop reply frames on system channels.** Measured: one `enterText` produced
nine consecutive identical 6-byte success envelopes. Keep a reply only when it
decodes to something — an error, a value.

The framework's own channels (`flutter/textinput`, `flutter/platform`,
`flutter/semantics`, `flutter/assets`) ride the same funnel and are noisy.
Captured, tagged `system`, **hidden by default** behind the channel filter
(owner, 2026-08-11). Captured rather than dropped because "did the app ask for
the keyboard" and "what `SystemUiOverlayStyle` did it set" are real questions
that no other leg answers; hidden because on an ordinary transition they are
the only thing you would see.

### Lane 2 — print and logging (automatic)

**Both amended by the spike; neither is what was planned.**

- `print` / `debugPrint`: **no zone.** `test_api`'s `Invoker` already forks a
  zone with its own print spec — which does not delegate upward, so a zone of
  ours captures nothing — and republishes every line on `LiveTest.onMessage`.
  `_runOne` never subscribed to that stream, so **a `print` inside a scenario
  currently goes nowhere at all**; subscribing is one line and fixes that
  standing bug as a side effect. `debugPrint` rides along, because this binding
  routes it to `debugPrintSynchronously`.
- `package:logging` records: a `Logger.root.onRecord` listener — `logging` is
  already a flutterware dependency, so an app using it shares the singleton.
  It must be installed and cancelled in `_runOne`, **outside FakeAsync**, not
  around the scenario body: `subscription.cancel()` returns a root-zone future,
  and awaiting one inside FakeAsync hangs the run until something else times
  out. That general rule — *a scenario body may not await a root-zone future* —
  belongs in the authoring docs.

Measured: the three lanes interleave in true order with no sequencing work,
because all three record synchronously.

### Lane 3 — the sink (the only custom API)

What the first two lanes cannot see is the in-process layer, and network is
its headline: `flutter_test` replaces `HttpOverrides` with a stub client, and
real suites fake *above* the socket anyway — an injected `http.Client`, a
repository fake, an analytics service the app wrote itself. Those report
themselves, through one global sink in the spirit of `scenarioRunListener`:

```dart
// package:flutterware/app_events.dart — imported by fakes, not only by tests
void recordAppEvent(AppEvent event);

AppEvent.request(method: 'POST', url: '/login', status: 401, body: …)
AppEvent.query(sql: …, args: …, rows: 12)
AppEvent.analytics('checkout_started', params: {…})
AppEvent.log('…', level: …)
AppEvent.custom(channel: 'websocket', title: …, data: …)
```

Typed constructors rather than a free-form channel string, because the GUI
wants columns — method and status on a request, row count on a query — and a
closed set is what gives each channel an icon and a one-line rendering.
`custom` keeps it open for the channel nobody anticipated.

**A no-op outside a run.** A fake that calls this is a fake that costs a bare
`flutter test` one null check, which is what makes it safe to leave in the
project's shared fakes forever.

**Where it is installed: `flutter_test_config.dart`.** The harness already
runs each folder's config to probe its profile (`harness.dart`,
`_probeProfiles`) — so "wire your fakes to the sink once for the whole suite"
has a home that already exists and already executes. That is the documented
recipe, and the `authoring` string the `list` action serves an agent should
grow a line about it.

### What is not in the model

No `duration` field (owner, 2026-08-11). Under FakeAsync a faked request
completes in zero fake microseconds, so every duration this could show would
be either a lie or a zero. A reporter that has a real measurement puts it in
`data`, where it reads as the reporter's claim rather than the harness's.

No read-back: the sink is write-only, and `expect(s.events, …)` is not part of
this (owner, 2026-08-11). Scenarios do not become analytics contract tests
here. Worth noting the door: making the sink readable is additive, so a later
change can open it without moving anything designed above.

## Wire and artifacts

Follow the semantics leg exactly:

- The harness writes `<base>.events.json` beside `.tree.json` and
  `.semantics.json`, and adds `'events': path` to the step record. Absent —
  not empty — when a transition recorded nothing, so an old artifact and a
  quiet transition stay distinguishable.
- `ScenarioRunStep` gains `events` (nullable path), `eventCount`, and a
  per-channel count map for the badge. Plus `verb`/`target` from above.
- **The schema is free.** `ResultShape` derives the wire shape from the result
  classes, so `docs/capabilities.md`, `fw run scenarios run --help`, and the
  MCP tool description all describe the new fields the moment they exist. This
  is most of the GUI/CLI/MCP parity requirement, and it is already paid for.

### What goes inline

Mirror the PNG policy the design already settled — *"not every step inline:
fifty pictures per call is context an agent pays for and did not ask for"*:

- **Every step**: a digest — the per-channel counts and the capped list of
  one-line titles. `POST /login → 401` is the part an agent reasons about;
  the payload is what it fetches when it cares.
- **The failing step**: the full event list inline, for the same reason the
  frame before a failure is inline. This is the artifact that answers "why did
  it break", and it is the one call an agent should not have to make twice.

### Caps, stated rather than discovered

An app that logs in a build method will otherwise produce a run measured in
tens of megabytes. Three bounds, each with a visible truncation marker:
events per transition, bytes per event payload, total bytes per run. A run
that truncated says so on the step — silence here would read as "the app did
nothing", which is the one wrong answer.

## GUI

- **Step page** — a fourth `InspectDockTab`, id `events`, label **Events**,
  beside Elements / Semantics / Texts. The list is ordered as recorded; the
  header says what the transition was (`tap "Pay"`); channels are filter
  chips with `system` off; a row expands to its payload. Snapshot-shaped, like
  every other tab in that dock.
- **Flow canvas** — a badge on the arrow: the count, and per-channel dots.
  Clicking opens the target step's Events tab. The edge is now a drawn thing
  with a label on it (the branch label was just restored there through
  graphite's `edgeTooltip`), and `EdgeTooltip` is text-only — so this needs
  either a small extension of the vendored painter or an overlay positioned
  from the same points. Decide when building; the overlay is likelier, since a
  badge wants hit-testing.
- **Not in v1**: a run-level timeline (every event of the scenario in one list
  with step separators). It is where "find the request that 404'd" is really
  answered, and it should exist — after the per-step view proves the capture.
- **Known cosmetic limit**: the edge label wraps mid-token in the 90px gutter
  (`tap key 's / hop.getSt / arted'`). Widening `cellPadding` would spread
  every flow to fix a label, and 90 is dev_studio's; left alone, and legible
  at any zoom because the wrap is in layout, not rendering.

## Order of work

1. ~~Spike.~~ **Done, 2026-08-11** —
   `2026-08-11-scenario-events-spike-findings.md`. Verdict: build it. Cost is
   0.2% of a run; the two hangs it found are both understood and fixed above.
2. ~~Guest side~~ **done**: the sink, the buffer, the flush-and-dedupe on the position key,
   `.events.json`, the step's `verb`/`target`. Plus the two spike fixes that
   stand on their own: subscribe to `LiveTest.onMessage`, and drop system
   reply frames.
3. ~~Results model~~ **done**: digest + the failing-step inline rule (app side,
   build_runner).
4. ~~The Events tab.~~ **done**
5. ~~The flow badge.~~ **done** — as an edge label, not a badge: `EdgeTooltip` grew a subtitle, which is cheaper than an overlay and needs no hit test, since the node under it already opens the step.
6. The run timeline, later, on its own evidence.

## Decided by the owner, 2026-08-11

1. **Events are not assertable.** Write-only sink; no `expect` surface.
2. **Framework channels captured, hidden by default.**
3. **No durations** — not important enough to carry a field that FakeAsync
   makes meaningless.
4. **No trailing bucket** for events after the last step. They are dropped.

## Open, deliberately

- The badge's rendering on the canvas (extend `EdgeTooltip` vs. overlay) —
  falls out of building it.
- ~~Whether `system` events are too expensive to capture at all.~~ Closed by
  the spike: 55 events cost 1.0ms of a 480ms run. Noisy, not expensive.
- ~~The sqflite channel claim.~~ Closed by the spike: it never reaches a
  channel. Corrected above.
