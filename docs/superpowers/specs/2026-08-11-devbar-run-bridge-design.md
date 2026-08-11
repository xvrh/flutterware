# Devbar over the run bridge — the app's own plugins, on every surface

**Date:** 2026-08-11
**Status:** Designed with the owner in conversation, 2026-08-11. **Not spiked.**
Two experiments gate the build (§ Experiments). The SQLite/PowerSync time
machine is deliberately *not* in this design — it is the second consumer of the
bridge and gets its own session (§ Deferred: WIRE·LINE).

**Lineage:** `2026-07-31-app-launcher-cockpit-brainstorm.md` §D5/§D6 — this
design **supersedes D5**. D5 proposed mounting the whole inspection runtime
through `Devbar`; the run guest was built instead and did that job with no app
code at all, so `Devbar` keeps a smaller and better-defined one. §D6 (devbar
plugins over the server protocol on a VM-service transport) survives intact and
is the core of this document. Also: `2026-07-30-server-inspection-design.md`
(the channel protocol being reused), `2026-08-11-run-drive-design.md` (the
guest this hangs off), `2026-07-31-run-cockpit-panel-design.md` (the tab strip
that was built as the extension point for exactly this).

## The goal

Turn a feature flag on. Watch the network. Fire a local notification with a
specific title and a specific deep link. Read what permissions the app actually
holds. All of it from the GUI, `fw`, or MCP — against the app that is running
right now, on a real device, without a rebuild.

Devbar has been able to do all of this *inside* the app for a long time. What
it has never had is a way out of the app.

## What already exists, measured 2026-08-11

| what a plugin needs | what is in the tree today | gap |
|---|---|---|
| commands with typed parameters | `PluginAction`, `ActionParameter`, `ActionOption`, `optionsFrom` (`lib/src/plugins/action.dart`) — already rendered by the GUI, `fw --help` and the MCP schemas | route them into the app |
| a read-write knob | devbar `variables` (persisted store + editor UI), `KnobDescriptor` | a wire, and an owner for the value |
| an append-only feed | `lib/src/server/` (1374 lines): bounded ring per channel, replay-on-attach with a `replay-done` marker, `{ch,t,id,m,p}` envelope, zone correlation, lazy detail fetch by event id; plus the attacher side — timeline, waterfall, JSON viewer, SQL normalizer, secret masking (`server_plugin.dart`, 1878 lines) | split the transport out (§D6) |
| a state snapshot | — | trivial |
| a place in the cockpit | the `Screen`/`Steps`/`Logs` tab strip, whose doc comment says in as many words that the strip is the extension point and must accept tabs this build does not know about (`app/lib/src/plugins/native/run_plugin.dart:542`) | nothing |
| a way in to the app process | the run guest, generated per launch around the app's `main` (`app/lib/src/run/guest_entrypoint.dart`), already registering `ext.flutterware.*` | one more extension |

**The finding that sets the scope: this is three extractions and one transport,
not a new subsystem.** Every hard part — replay so a panel opened late still
shows history, correlation ids, bodies fetched only when someone looks, a
handler that runs *where the data is* — was already solved for host Dart
servers and is sitting behind a unix socket.

Two things that do **not** exist and are commonly assumed to:

- **There is no push channel.** `app/lib/src/run/connection.dart:72` subscribes
  to `kService` and nothing else. Everything the cockpit knows today it asked
  for.
- **There is no network capture.** `log_network` is not an interceptor:
  `DevbarHttpClient(inner)` is a `BaseClient` the app author must hand-wire,
  and it sees `package:http` only — no `dart:io` `HttpClient`, no dio, no
  websockets. Getting network into the cockpit is a capture problem first and a
  transport problem second.

## Decision 1 — two modes, declared per plugin (owner, 2026-08-11)

A devbar plugin declares one of:

- **widget mode** — it renders its own Flutter tab in the in-app overlay, as
  today, and is **invisible to the host**. This is the escape hatch: anything
  the descriptor vocabulary cannot express stays possible, at the cost of
  working only where the app's own widgets run.
- **descriptor mode** — it declares data and commands; the host renders them,
  and so does the overlay, from the same descriptor. One plugin, one
  declaration, two renderers.

The mode is per plugin, not per surface. A plugin that wants both writes two
plugins, and that is the honest cost of wanting a bespoke in-app view *and* a
remote one.

**Every built-in becomes descriptor mode** — variables, logger, network,
analytics. If a built-in cannot be expressed in the vocabulary, the vocabulary
is wrong and gets fixed; that is the point of converting them first.

**Why the overlay renders from the descriptor too.** A plugin written twice
drifts within a month, and the drift is invisible until someone compares the
two surfaces on a bug. One renderer also makes the whole vocabulary
developable in previews, against fixture descriptors, with no app running.

## Decision 2 — Devbar is the mount, and under a run it is headless

(owner, 2026-08-11: "it's the entry point that decides that, by registering the
plugins in the devbar")

The app's entrypoint keeps writing `Devbar(child: MyApp(), plugins: [...])`.
That is where plugins are constructed, so that is where they are declared;
there is no manifest, no generated import list, and no auto-detection — which
the owner explicitly did not want.

`Devbar` therefore has two jobs that were previously one: **plugin host**
(always) and **in-app overlay** (only when nothing else is looking).

**Consequence, and it is not cosmetic: under a connected run the overlay must
not be in the widget tree at all.** Today `Devbar.build` inserts a `Stack`, a
`Directionality`, an `OverlayDialog`, a `ToastsOverlay`, `DevbarAppWrapper`'s
`FittedBox` and a `bug_report` floating button over the app.

**Amended by E2, 2026-08-11.** This section first argued the case on pixels —
that the chrome would show up in every screenshot. Measured, that is only half
right: with the panel shut and no plugin contributing a button,
`overlayVisible: false` paints *byte-identical* pixels, because the `FittedBox`
is a no-op at scale 1. The load-bearing reason is the other half of an `act`
reply — the **widget tree**, which `Target` resolution walks and `nth` counts
in. Extra layers between the root and the app change what a tap can land on.
The pixels follow the moment the panel opens or a plugin adds a button, but the
tree is wrong from the first frame.

So: when the run guest is installed, `Devbar` builds `child` directly and holds
plugins only. Not a flag on the button — a separate build path, so there is
nothing to leak.

**Late attach.** The guest registers extensions before `runApp`; `Devbar`
registers itself in `Devbar.instances` on first build. The bridge is therefore
a registry the `DevbarState` joins on mount and leaves on dispose, and it must
survive:

- **no devbar yet** — the cockpit tab exists and says "no devbar mounted",
  rather than the tab being absent and reappearing;
- **hot restart** — the old state disposes, a new one mounts, and channel
  history is invalidated (a restart is a new epoch, not more of the same run);
- **more than one** — `examples/example/lib/multi_devbar_variables.dart` is
  exactly that case today. **Built as a suffix, not an index prefix**
  (amended): the first claimant of an id keeps it and later ones become
  `flags#2`, `flags#3`. An index prefix would have made the ordinary
  one-devbar app read `0/flags`, so every agent and every URL would pay for a
  case almost no app has.

## Decision 3 — the descriptor vocabulary is `PluginAction`, plus feed and state

Do not invent a second grammar. A descriptor-mode plugin declares:

1. **Actions** — literally `PluginAction` / `ActionParameter` / `ActionOption`
   from `lib/src/plugins/action.dart`, the same objects a host-side flutterware
   plugin declares. `danger`, `confirm`, `returns` and `optionsFrom` all keep
   their meaning. The owner's own example — *show a local notification with
   this text and this link* — is one `PluginAction` with two string parameters
   and nothing else.
2. **Feed** — a named channel of append-only events, which is `lib/src/server/`
   unchanged: bounded ring, replay-on-attach, correlation, lazy detail by event
   id. Network and SQL are feeds. So is a structured log.
3. **State** — a snapshot map, re-read on demand. Device info, package info,
   permission grants. The cheapest of the three and the one that covers most
   of the "custom plugin" wish list.
4. **Knobs** — `KnobDescriptor` from `lib/src/ui_catalog/knob.dart`, unchanged
   except for two optional fields (`step`, `description`) the devbar's
   variables need and a catalog demo never did. Not a new type: it already
   carries kind, current value, default, `min`/`max` and options, it is already
   Flutter-free and published, and its doc comment already says it is "the
   shape a panel renders *whatever* produced it". Feature flags are knobs; so
   is a base URL.

   **Corrects this document's earlier claim, and the 07-31 brainstorm's.** The
   brainstorm said `KnobDescriptor` was in the plugin contract; it is in the
   catalog's. A first pass at step 3 searched `lib/src/plugins/`, concluded it
   did not exist, and was about to specify a parallel type with a duplicate
   kind enum.

Actions are the load-bearing choice. Because the shape is already what the GUI,
`fw` and MCP render, a plugin that declares one gets all three surfaces on the
day it is written, and nobody learns a second vocabulary to use them.

**And it costs nothing to reuse them, which was not obvious and was checked.**
`lib/plugins.dart` is pure Dart by rule — its own doc comment forbids importing
`package:flutter` — and nothing under `lib/src/plugins/` imports `dart:io`
either; `action.dart` has zero imports of any kind. So the same objects a
host-side plugin declares under a plain `dart run` compile into a Flutter app,
web included. Had the contract dragged in `dart:io` this decision would have
needed a parallel type, and the "one vocabulary" argument would have collapsed
with it.

## Decision 4 — flags: the app owns the list, the host owns the wish

(owner, 2026-08-11: "only devbar can report the available flags… what could
exist is the GUI/CLI pre-pushing the value before, so it's available
immediately")

A flag does not exist until the widget declaring it builds —
`_FlagToVariableState` registers it from the tree. Nothing static can be
promised, and pretending otherwise would mean a GUI list that lies.

So there are two lists, and the cockpit shows their union:

- **Registered** — what the running app has actually declared, reported up as
  it happens. Authoritative, live, and grows as you navigate.
- **Wished** — a host-side map of values pushed for flags that may not exist
  yet. Pushed at launch and at any time after; applied by the app the instant a
  matching flag registers.

**A pushed value lands in `overrides`, never in `store`.** The existing
precedence is `storeValue ?? overrideValue ?? flagValue ?? defaultValue`, and
`overrides` is already session-scoped. If the host wrote to `store`, the
override would outlive the host's intent and survive into runs nobody
configured — a flag stuck on with no owner. The host is the thing that
persists; the app is the thing that obeys for the length of a run.

**The host remembers every flag it has ever seen for a project.** From the
second run onward the cockpit list is complete: flags not yet registered this
run show greyed, and pushing a value to one is how you set a flag before you
have navigated to the screen that declares it. That closes the discovery gap
the owner correctly refused to close with static declaration.

The wish map is persisted per project + package, sticky across launches, shown
in the cockpit as an explicit *override active* state with a clear-all. Sticky
because a launch-time flag is useless otherwise; loud because a forgotten
override is the worst debugging hour there is.

## Decision 5 — transport: ring in the app, pull, with a nudge

(owner, 2026-08-11: "we'll decide by experimenting" — so this is the hypothesis
the experiment tests, not a settled call.)

Split `lib/src/server/inspector.dart` into a transport-free core (ring,
channels, handlers, zone correlation, replay handshake) and two transports:

| transport | for |
|---|---|
| unix socket + handle file | a Dart server on the host — today, unchanged |
| `registerExtension` + `postEvent` | a Flutter app, on any device |

The proposed hybrid: **the ring lives in the app and the host pulls** — attach,
replay, fetch details lazily — plus a *tiny* `postEvent` nudge carrying nothing
but "channel `sql` has N new". No payload on the event stream, so a bulk sync
cannot flood it; no polling, so the cockpit is not late. The protocol does not
change if payload streaming is added later.

This requires the first `Extension`-stream subscription in
`app/lib/src/run/connection.dart`, which is the one genuinely new piece of
plumbing in the whole design.

### Built, 2026-08-11 — and three things the build settled

`lib/src/server/vm_transport.dart` (guest) and
`app/lib/src/run/channel_client.dart` (host). The hybrid stands; the nudge
carries only `{"peer": …}`, not even a count.

1. **The nudge is coalesced per peer, and that is what makes it safe.** At most
   one nudge is outstanding between drains, so the nudge rate is bounded by how
   often the host *pulls*, never by how fast events arrive: a burst of 500
   events posts one nudge. This matters more than it first looked, because —

2. **The `Extension` stream is not ours.** Flutter posts `Flutter.Frame` on it
   for every frame it renders
   (`scheduler/binding.dart:_profileFramePostEvent`, checked in the pinned
   SDK). Subscribing eagerly in `RunConnection.connect` would have dragged
   sixty events a second across the wire for every connected run, wanted or
   not. `listenExtensions()` is therefore lazy and idempotent, called by the
   first attacher.

3. **Draining synchronously would have cost every command an extra round
   trip**, and only the real wire showed it. `InspectorCore` answers a request
   from an `async` method, so even a handler that returns a value immediately
   enqueues its frame one microtask later — a VM-service probe against a real
   Dart process returned `EXPLAIN -> {"frames":[]}`, then a nudge, then the
   answer. `exchange` now yields once before draining, and a synchronous
   handler answers in the reply to the call that carried the question. A
   genuinely async handler still misses that window and still answers on a
   later pull, which is the case the nudge exists for.

Two smaller decisions, recorded because they are load-bearing later: the queue
per peer is **bounded** (2000 frames) and the frames it throws away are
**counted and reported**, so a host that fell behind learns its view has a hole
and can re-attach — the events are still in the core's ring, so re-attaching
genuinely recovers them. And a peer is identified by a **host-chosen id**, so
the GUI and an MCP call attach independently, each with its own queue and its
own replay.

**Not in the plan, done anyway:** the attacher side was forked the moment a
second host existed, so `lib/src/server/attach_session.dart` now holds the
correlation, the replay boundary and the event list, and both
`ServerAttachClient` (socket) and `RunChannelClient` (VM service) are thin
transports over it. `ServerEvent` and `ServerRequestException` became typedef
aliases of the session's types; no published name changed.

## The cockpit surface

The tab strip gains tabs from the app: `Screen | Steps | Logs | Network |
Flags | …`. The address already carries a tab *name* and falls back to the
screen on an unknown one, which is what makes this additive.

Rendering per descriptor kind: feed → the server plugin's timeline + waterfall
+ JSON viewer, unchanged; state → a key/value inspector; knobs → the variables
editor, re-pointed; actions → the parameter form the GUI already draws for
plugin actions.

## `fw` and MCP

Nothing bespoke. A descriptor-mode plugin's actions surface as
`run/<runKey>/<plugin>/<action>` under `flutterware_actions` and
`flutterware_invoke`, feeds as a read action with a cursor, state as a read
action, knobs as get/set. `docs/capabilities.md` is generated, so it picks
them up.

## Adoption

Wrapping in `Devbar` is app code, and that is fine: constructing a plugin is
app code by definition. The zero-touch property belongs to inspect and drive
and is not weakened — an app with no `Devbar` keeps everything the run cockpit
does today and simply has no plugin tabs.

Release safety is the existing gate: `kReleaseMode` / `dart.vm.product` plus an
explicit off switch, matching the server library.

## Not in v1

- Payload streaming over the event stream (the nudge is enough; see §5).
- Network capture beyond what an app opts into. Making `HttpOverrides` global
  from the guest would catch `dart:io` and therefore dio and `package:http`'s
  `IOClient` too — a real prize, and a behavioural change to every request the
  app makes. It is its own decision with its own blast radius.
- Widget-mode plugins on the host. By construction.
- Anything SQLite.

## Order of work

1. ~~**Split the inspector**~~ — **done 2026-08-11.** `frames.dart` (wire) and
   `inspector_core.dart` (ring, channels, handlers, details, handshake) are
   `dart:io`-free and compile to JavaScript; `protocol.dart` keeps the
   rendezvous half and re-exports the wire half so no importer changed;
   `inspector.dart` is now only the socket. A guard test walks the core's
   transitive imports and fails on `dart:io`.
2. ~~**VM-service transport**~~ — **done 2026-08-11.** See § Built above.
   Proven twice: eleven tests through a real `VmService` client against a real
   transport, and a throwaway `sql` channel on a real VM service in a spawned
   Dart process — attach, replay, an in-app handler answering, one coalesced
   nudge, a live event on the pull.
3. ~~**Descriptor model**~~ — **done 2026-08-11.** `lib/channels.dart` is the
   published library: `PanelDescriptor` / `FeedDescriptor` / `StateDescriptor`
   / `FieldDescriptor` are new, `PluginAction` and `KnobDescriptor` are reused
   verbatim. `Panels`/`Panel` serve them onto an `InspectorCore`. Twelve unit
   tests plus six driving a panel end-to-end from `RunPanels` over the
   transport, and a real VM-service probe: list, set a knob, read a state, run
   an action, take a refusal, receive a feed event.

   **A panel is built, not implemented.** Every `feed`/`state`/`knob`/`action`
   call takes the declaration *and* the code that serves it, and the descriptor
   is derived from what was registered — so a panel that describes something it
   cannot answer is not expressible, and there is no four-method interface to
   implement. Three rules fell out of writing it:

   - A knob always reports `declaration.withValue(read())`, never its declared
     value. A flag registered by a widget that has since rebuilt would
     otherwise report what it was at declaration time.
   - Setting a knob answers with **what the app kept**. An app may clamp or
     refuse, and a cockpit echoing the request would show a value nothing
     holds.
   - Emitting on an undeclared feed throws, listing the feeds that exist.
     Silently ringing an event on a channel nothing renders costs an afternoon.

   Feed channels are qualified (`<panel>/<feed>`) so two plugins can both have
   a `requests`. Reserved methods are prefixed (`fw:state`, `fw:knobs`,
   `fw:knob`) so an action may be called `state`; action ids are used verbatim
   as methods, and two actions claiming one id — including a panel action and a
   feed's item action — is an error at declaration.

   **Mode is implicit, deliberately** (Decision 1): a plugin with a panel is
   descriptor mode, one without is widget mode. An enum would be a second place
   to say the same thing, and a place for the two to disagree. Revisit in step
   4 if `DevbarPlugin` turns out to need it spelled.
4. ~~**`Devbar` split**~~ — **done 2026-08-11.** `Devbar` gained `headless`
   (defaulting to `GuestChannels.installed`), which builds `child` directly and
   holds plugins only. `DevbarPanelSource` is the descriptor-mode declaration —
   implementing it *is* the mode, no enum. `DevbarBridge` mounts each
   descriptor-mode plugin as a panel after the plugins load, unmounts on
   dispose, and disambiguates a second devbar's ids as `flags#2` so the
   ordinary one-devbar app keeps the id the plugin declared. Eleven widget
   tests: mount, unmount, hot restart, two devbars, a knob written over the
   wire reaching the plugin, a feed emitted after mounting, and the gate.

   **E2 ran, and corrected this design.** A headless devbar is byte-identical
   to no devbar — the gate passes. But `overlayVisible: false` is *also*
   byte-identical with the panel shut and no plugin adding a button, which this
   document assumed it would not be: the `FittedBox` is a no-op at scale 1. The
   real justification is the other half of an `act` reply — the **widget
   tree**. An extra `Stack`, a `FittedBox` and an overlay `Navigator` between
   the root and the app change what `Target` resolution walks and what `nth`
   counts, and the pixels diverge too the moment the panel opens or any plugin
   contributes a button. Both facts are pinned in
   `test/devbar/headless_test.dart`.

   **A pre-existing bug fell out.** Passing `flags:` without also installing
   `VariablesPlugin` threw `Bad state: No element` from
   `plugin<VariablesPlugin>()` — every app with flags had to install that
   plugin or crash on first build. Flags now register when the plugin is there
   and simply stay uneditable when it is not.

   **One deliberate hold:** `app/lib/src/devbar.dart` pins `headless: false`.
   Auto-headless would fire the moment this GUI is launched through the run
   plugin — the normal inner loop — and would remove a working surface before
   step 5 gives it a replacement. Drop that line with step 5.
5. ~~**Descriptor renderers**~~ — **done 2026-08-11.** `lib/src/channels/ui/`:
   `PanelView` (tab strip over one body per feed, per state, plus Controls),
   `FeedView` (master/detail with a per-row waterfall), `StateView`,
   `ControlsView` / `KnobControl` / `ActionControl`. Eight previews in
   `app/tool/catalog/demos/panel_view.dart`, six regression tests in
   `test/channels/panel_view_test.dart`.

   **Views, not Screens.** Each takes the descriptor, the events and the
   snapshots as plain data and hands every interaction back as a callback — no
   channel, no fetching. That is what lets a preview exercise an action
   mid-flight and a feed with nothing in it, neither of which is reachable by
   launching an app and waiting for a lucky moment.

   **One renderer, no token move (owner, 2026-08-11:** *"we don't move the
   token, that doesn't make sense — inline them so it looks mostly right on
   both sides"*). `PanelStyle` takes **colours from the ambient `Theme`** — both
   hosts have one, and it is what makes the same widget look native in the
   cockpit and in somebody else's app — and **inlines the rhythm** from
   `app/lib/src/ui/design/`: the `FwSpacing` scale, `defaultRadii`, the
   `FwTypography` sizes and `InspectTabStrip`'s 34px, copied on purpose. The
   monospace stack is verbatim from `server_plugin.dart:1859`. Moving `FwTokens`
   into the published package would have made the GUI's design system published
   API for every flutterware user; a copy that drifts by a pixel is the cheaper
   mistake.

   **Fidelity: follow the shape, write fresh** (owner). Master/detail, tab
   strip, same beat as the panels beside it — but written against
   `FeedDescriptor` rather than extracted from `_RequestList`/`_Waterfall`,
   which are welded to `ServerEvent`. Extraction waits for Network (step 8) to
   supply a second real consumer to prove the generalisation against.

   **Three bugs the previews caught before anything shipped**, none of which a
   compile or a unit test would have found:

   - `Switch`, `TextField` and `DropdownButtonFormField` threw with no
     `Material` ancestor, and a bare `Text` rendered in Flutter's
     yellow-underlined fallback. Every exported view now carries a
     `PanelSurface` — the same reasoning `InspectTabStrip` gives for having its
     own.
   - A feed that declared no `primary` field had **no flexible cell**, so a
     90-character SQL string overflowed the row by 583px. The first field is
     now primary when nobody says which is.
   - The waterfall's duration label wrapped at `1.18s`, making rows with slow
     requests taller than their neighbours.

   **The previews tooling works; the invocation form matters.** A first pass
   here reported that the headless screenshot "could not run in this repo" —
   that was wrong, and it was wrong in a way worth recording. `fw run previews
   screenshot` refuses with *"DaemonConfig.appPackageRoot must be flutterware's
   own app/ directory"* when `fw` is started as `dart run flutterware_app:fw`,
   and works when started as `cd app && dart run bin/fw.dart` — which is what
   `bin/fw.dart`'s own doc comment says to do.

   The cause is `Session.findAppToolDirectory()`
   (`app/lib/src/session/session.dart`). It takes `APP_TOOL_PATH` when the
   launcher recorded one, and otherwise derives the package root from
   `Platform.script`. Under a `package:name` invocation `Platform.script` is
   **not** the source file — measured on `a911609e`:

   | invocation | `Platform.script` | `findAppToolDirectory()` |
   |---|---|---|
   | `dart run flutterware_app:<bin>` | `.dart_tool/pub/bin/flutterware_app/<bin>.dart-<sdk>.snapshot` | **null** |
   | `dart run bin/<bin>.dart` from `app/` | `app/bin/<bin>.dart` | `…/app` |
   | either, with `APP_TOOL_PATH` set | — | `…/app` |

   **This reaches the MCP server, which is the documented agent path.**
   `tool/mcp_server.sh` (added by #97, which fixed the *bootstrap* race — the
   reason the server fails to connect in a fresh worktree — not this) ends in
   `exec fvm dart run flutterware_app:mcp`: the null row. So an agent driving
   flutterware through MCP cannot screenshot or check previews, and the error
   it gets names `appPackageRoot` rather than the invocation.

   **Both fixed (owner, 2026-08-11: "do both").** `tool/mcp_server.sh` now
   `exec env APP_TOOL_PATH="$PWD/app" …`, and `findAppToolDirectory` gained a
   third strategy: resolve `package:flutterware_app/` with
   `Isolate.resolvePackageUriSync`. Verified — the command that opened this
   whole thread, `dart run flutterware_app:fw run previews screenshot` from the
   repo root, now writes the PNG.

   **A third bug surfaced while testing the fix, and it was the deeper one.**
   The derivation accepted *any* directory with a `pubspec.yaml` two levels
   above the script. This repo is a workspace whose **root is also a package**,
   so under `flutter test` it happily returned `flutterware` — the wrong
   package — which is why the original failure named
   `<repo>/tool/catalog/compiler_daemon.dart` rather than reporting nothing at
   all. A candidate root is now accepted only if its pubspec says
   `name: flutterware_app`. Pinned by a test that exercises the *rule*, since
   under `flutter test` neither derivation answers and the live resolution
   cannot be exercised there at all.

6. ~~**Flags end to end**~~ — **done 2026-08-11**, bar one piece named below.
   `VariablesPlugin` is descriptor mode as well as widget mode: every devbar
   variable mirrors as a knob, the set follows widgets mounting and unmounting,
   and a value moving in-app announces so the host re-reads. `FlagMemory`
   (`app/lib/src/run/flag_memory.dart`) is the host's half; `PanelsTab` is the
   cockpit's **App** tab, a new `RunViewKind.panels`. `AppDevbar`'s pinned
   `headless: false` is gone — the GUI driven through the run plugin now
   reports its own variables instead of drawing an overlay.

   Decisions the build made:

   - **A picker crosses as its label**, matching `KnobDescriptor`'s existing
     rule, and an unknown label is *refused* rather than clearing the value —
     a stale panel must not be able to blank a setting.
   - **The wish map needed no protocol.** It is a `preset` action on the flags
     panel, writing to `VariablesPlugin.overrides` (session-scoped), never the
     app's persisted store. So a host wish dies with the process and what
     survives is the cockpit's file — an app that persisted it would keep a
     flag on for somebody who never asked.
   - **Memory is keyed by worktree + package**, not by entrypoint or device:
     `main.dart` and `main_dev.dart` are two builds of one app, and a flag
     turned on for the simulator was meant for the app.
   - **What is remembered is the shape, not the value.** Keeping run-time
     values would make a second, invisible wish nobody set.
   - Wishes are pushed **before** the first list, so the cockpit opens showing
     what was asked for rather than flickering through defaults.

   **Not yet surfaced:** the cockpit *stores* every knob a project has ever
   shown (`FlagMemory.seen`) but does not yet render the ones absent from the
   current run. So "the list is complete from the second run onward" is true of
   the file and not yet of the screen. Rendering it needs a way for a knob to
   say *declared elsewhere, not here* — `KnobDescriptor` has no such state, and
   inventing one silently would make a flag that is not live look live. Writes
   to such a knob already have somewhere to go: `preset` is exactly that path.
7. ~~**A command plugin**~~ — **done 2026-08-11**, built and driven.
   `examples/example/lib/shop_devbar.dart` is Brewline with a push
   plugin on it: `PushService` (`lib/src/notifications/`) is the app's own
   notification machinery — permission, an inbox, a deep-link table, a banner
   — and `NotificationsPlugin` (`lib/src/devbar/notifications_panel.dart`)
   implements none of it and only drives it. Eleven tests, every one of them
   through `InspectorCore.handleFrame` rather than through the plugin, because
   the claim is that an *outside* caller reaches the feature.

   **A simulated delivery, not a real OS notification (owner, 2026-08-11).**
   The action injects the payload the platform would have delivered. That is
   not a shortcut: a real banner is drawn by the OS, so it is absent from the
   screenshot and from the widget tree, and an agent could neither see the
   result nor tap it. In the tree, `send` → `observe` → `tap` is one loop. The
   native path costs a dependency and three platforms' setup to buy strictly
   less proof.

   **Brewline, as a new entry point (owner).** The shop is the one thing in
   this repo that looks like a product, so "push an order-ready notification,
   tap it, land on the cart" is a story rather than a fixture. `ShopApp` gained
   two ordinary parameters — `navigatorKey` and `overlay` — and the scenarios
   keep mounting it untouched.

   **Four things this second consumer found, none of which step 6 could have.**

   - **`itemAction` was undeliverable.** The handler is invoked with
     `event: <ring event id>` and nothing else, but `Panel.emit` returned
     `void` — so a plugin had no way to tie that id to its own object.
     `emit` and `InspectorCore.addEvent` now return the event id.
   - **Feeds never rendered in the cockpit.** `PanelsTab` passed no `events`
     to `PanelView` and no `onItemAction`, so a panel with a feed showed an
     empty tab. Step 6 was knobs-only, so nothing noticed. It now buckets the
     attachment's held events by feed channel — no new subscription, because
     the attachment already carries every channel with its replay — and
     coalesces the repaint to one per drain.
   - **An agent could not reach a panel at all.** The GUI surface was built in
     step 6 and the `fw`/MCP one was not, so "the same `PluginAction` reaches a
     form, a flag and a tool schema" was true of host plugins and false of app
     panels. `RunCore` gained `panels`, `panelInvoke`, `panelKnob` and
     `panelState`, each attaching for the length of one call — a cached
     attachment would mean a queue nobody drains between calls, and attaching
     is what buys the ring's replay to a stateless caller.
   - **`lib/channels.dart` pulled Flutter into the pure entry points.** It
     exported the renderers beside the wire types, so the moment `run_core.dart`
     imported a `PanelDescriptor`, `bin/fw.dart` and `bin/mcp.dart` failed
     `entry_point_purity_test`. Split: `channels.dart` is Flutter-free and
     `channels_ui.dart` holds the views. Worth stating as a rule — **the
     vocabulary is for everything that talks to a panel, and most of that is
     not a Flutter program.**

   **One declaration, two hosts, demonstrated rather than asserted.** The
   plugin's overlay tab renders `PanelView` over its *own* descriptor and
   routes every callback to the same methods the wire handlers call. So an app
   on a phone with no flutterware attached gets the screen the cockpit shows,
   and there is only one of it. That is the first evidence for what Decision 1
   deferred: the overlay drawing descriptor-mode plugins may belong in the
   framework rather than in each plugin, since this one does it in thirty
   lines that say nothing about push notifications.

   **Driven, 2026-08-11.** Brewline launched on macOS through `run/launch` and
   the whole loop ran against the real app. What it showed:

   - **Headless fired on its own.** The first `observe` is Brewline with no
     devbar chrome anywhere — 35 nodes — because `GuestChannels.installed` is
     true under a run. Nobody passed a flag.
   - **`run/panels` reported the panel exactly as declared**, and the `link`
     parameter's options came back as the real screens — `/menu`, `/cart`,
     `/order` and one per drink, labels and all, because the plugin builds them
     from Brewline's own `drinks` list rather than from a list it typed out.
   - **The refusal crossed verbatim.** `send` before granting answered
     *"notifications are not determined — this app will not show one until
     permission is granted"*: the app's own sentence, from `PushRefused`, with
     nothing wrapped around it. An unknown link refuses the same way and names
     all eight it knows.
   - **`send` → `observe` → `tap` is one loop, as designed.** After the knob
     granted permission, the banner is in the screenshot *and* in `texts` (35
     nodes → 53), `tap "Your order is ready"` navigated to the cart, and the
     banner dismissed itself. This is the payoff of simulating delivery: a real
     OS banner is in neither.
   - **The item action works end to end.** `open` with the feed's event id
     resolved to `push-1`, followed `/cart` and pushed the route with no widget
     involved — which is exactly the path a push tapped from a lock screen
     takes.
   - **The cockpit renders the feed.** Run → App on this run shows `Inbox 2`
     with both rows, `—` where a body is null, a detail pane reading
     `Event 13 · push-2`, and `Open` as a button that navigated Brewline to the
     matcha screen. `Registration` reads the state; `Controls` renders the
     picker badged `overridden` and `send` as a form. Typing a title there and
     pressing the button delivered, printed `{id: push-3, link: null,
     delivered: true}` beside it, and moved the Inbox badge 2 → 3 live.

   **And the drive found two bugs that eleven tests had not**, both in the
   sample, both invisible until something was *cleared*:

   - **The feed went silent for the rest of the run.** `_flush` compared a
     high-water count against `service.inbox.length`; `clear` empties the
     inbox, so the mark sat above the length forever and nothing was ever
     emitted again. It is a set of emitted ids now.
   - **An id came back attached to a different notification.** `clear` reset
     `_nextId`, so a second `push-1` appeared — and `open` on the *first* row,
     the one reading `/cart`, navigated to `/menu`. `clear` no longer resets
     the counter: an id outlives the inbox, since it is in the feed, in the
     journal, and in whatever a host wrote down.

   One test pins both, and reintroducing either bug alone fails it — which is
   the point: **they are one fix, not two.** A set of emitted ids does nothing
   if the ids repeat, and unique ids do nothing if the flush counts positions.
   Both were re-driven green after a hot restart, and `open` on a cleared
   message now refuses by name instead of quietly following a newer one.

   The general lesson is worth more than the fix: **a plugin mirroring app
   state onto a feed must key on identity, not on position**, because the state
   it mirrors can shrink and the feed it writes to cannot.

   Not covered by the drive: the overlay tab. Brewline runs headless under
   flutterware, which is the point, so the in-app half is proven by tests only.
8. **Network**, if step 7 leaves the feed path proven.
8. **Network**, if step 7 leaves the feed path proven.

Subject throughout: `examples/example` (owner, 2026-08-11). flutterware's own
`AppDevbar` (`app/lib/src/devbar.dart`) stays as the compile-time canary but is
not the test bed — driving the GUI whose own devbar reports into the GUI is a
hall of mirrors.

## Experiments that gate the build

**E1 — the nudge, under load.** Does `postEvent` + pull keep up, and what does
it cost? Drive a channel at 1, 100 and 5000 events/second from a real app and
measure cockpit latency and dropped nudges. Settles Decision 5 in whichever
direction the numbers point.

**E2 — the headless mount.** With `Devbar` mounted in run mode, is the
screenshot from `flutterware_act {verb: observe}` byte-identical to the same
app without `Devbar`? If not, the overlay is still perturbing the tree and
Decision 2's separate build path is incomplete. This is a cheap check and it
has to be green before any plugin work lands.

## Open, deliberately

- **Whether widget mode survives.** If converting the four built-ins to
  descriptors turns up nothing the vocabulary cannot hold, widget mode is an
  escape hatch nobody needs and a second code path forever. Revisit after
  step 5.
- **Whether the wish map should be per-device.** A flag pushed for the
  simulator arriving on someone's phone is either convenient or astonishing,
  and there is no evidence yet for which.

## Deferred: WIRE·LINE, the SQLite time machine

Its own session, built on this bridge. Recording the three findings from the
2026-08-11 prototype review so they are not re-derived:

1. **It reads PowerSync's own schema** — `ps_data__<table>`, `ps_crud`,
   `ps_oplog` — so replicated tables need no interception at all. That is why
   the design comes out as clean as it does.
2. **Successful sync destroys the evidence.** `ps_crud` is an upload queue and
   drains on ack; `ps_oplog` is the server's compacted view. The prototype's
   own status line reads `upload complete · queue drained`. Scrubbing back to
   seq 1 therefore cannot be a read of those tables at time T — something must
   have been tailing and persisting them since seq 1. **That capture sidecar is
   the feature**; the viewer is its client. Open: attaching at seq 100 means
   history starts at 100 — acceptable, or must it reconstruct?
3. **Capture is in-app, and that is not a preference.** On physical hardware
   the database is inside the app sandbox and the host cannot read the file;
   the run cockpit took physical devices day one. Simulator-only host-side file
   access would be a second implementation of the same feature.

Also open for that session: local-only (non-replicated) tables get nothing from
this mechanism, and `sqlite_async` is the seam that would have to cover them.
