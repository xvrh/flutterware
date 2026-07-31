# The app launcher cockpit — direction and steps

**Date:** 2026-07-31
**Status:** Brainstorm. "What is already true" is verified in code and against
the pinned SDK in this session; "Direction" is proposal, and the numbered
decisions are the ones that want an owner's word before code.

**Settled in discussion, 2026-07-31** — folded in below rather than left open:

- **The plugin is `flutterware.run`.** "Launcher" collides with the
  launcher-icon editor; "cockpit" is what the feature *is*, not what a sidebar
  row should say.
- **Physical iOS and Android from day one.** They are the main target, not a
  later port. This is the input that changes the most (see "Physical devices
  are the target").
- **Scenarios stay a separate project.** The verbs will probably rhyme, but how
  the two share code is not clear yet and forcing it now would be inventing a
  seam for an imagined consumer. Revisit when both exist.
- **New requirement: an agent must be able to remember how to get somewhere in
  the app.** Reaching a screen is a prerequisite for almost every other ask, and
  it is its own problem. See D10.
**Extends:** `2026-07-25-overhaul-master-plan.md` (this is M5's goal-8 consumer
side), `2026-07-27-gui-cli-mcp-architecture.md` (decisions 1–6 hold),
`2026-07-30-server-inspection-design.md` (the pattern this reuses wholesale).
**Adjacent:** `2026-07-30-scenarios-design.md` — the cockpit and the scenario
runner drive an app for opposite reasons, and share one vocabulary or diverge
forever. See "The convergence".

## The ask

1. List connected devices, and say whether each is free or held by another
   worktree.
2. List and name an app's entry points.
3. Entry points carry **knobs** filled before launch (inject the local server's
   IP, pick a flavor…) — a way to declare them, a way to inject them.
4. While the app runs: inspect the current screen, screenshot it, see network
   requests — from GUI **and** MCP.
5. Devbar plugins report into the cockpit — an in-app SQLite inspector browsed
   from the desktop, and readable by an agent.
6. Switching entry point on the same device in the same worktree should be a
   hot restart, not a rebuild. *(Usefulness explicitly up for discussion.)*
7. Everything reachable from GUI / CLI / MCP, so a human and an agent work on
   the same running app.
8. MCP exposes actions an agent can perform: tap this, scroll that.
9. An agent can **remember the steps that reach a given point in the app**, and
   get back there without rediscovering them. *(Added 2026-07-31; see D10.)*

## The short answer

**The cockpit is the server-inspection design pointed at a Flutter app, plus a
launch half that plugin never needed.** Almost none of it is new machinery:

| the ask | what already exists |
|---|---|
| devices | the flutter daemon's `device` domain (verified below) |
| free / held | the `~/.flutterware/run` handle + connect-probe rule |
| entry points | the catalog's syntactic scan + `tool/flutterware.dart` declaration |
| knobs | `KnobDescriptor` (pure Dart, published) and devbar `variables` |
| inspect a screen | `lib/src/inspect/` — tree, hit-test, logs, errors, images |
| screenshot | `ext.flutter.inspector.screenshot`, free in any debug build |
| network / SQL | `lib/src/server/` — ring, channels, correlation, the panels |
| launch + control | `flutter run --machine` client, and hot reload over VM service |
| GUI/CLI/MCP parity | `PluginCore` + `Session.invoke` + the parity test |

The new parts are: a **rendezvous that works on a device** (a phone cannot
write a handle file into the developer's home directory), a **drive** verb set,
and a plugin to hang it on.

## What is already true (verified this session)

### 1. The flutter daemon's `device` domain is the device source

`packages/flutter_tools/lib/src/commands/daemon.dart:1012-1035` registers
`getDevices`, `discoverDevices`, `enable`/`disable`, `forward`/`unforward`,
`logReader.start`/`stop`, `startApp`/`stopApp`, `takeScreenshot`,
`startDartDevelopmentService`, **`startVMServiceDiscoveryForAttach`**, and
fires `device.added` / `device.removed` from every polling discoverer.

The last handler is the interesting one: it is how `flutter attach` finds an
app nobody told it about, which is exactly ask 7's "however it was launched".

`flutter devices --machine` on this machine returns per-device `capabilities`.
Two of them decide design:

```json
{"name":"macOS","id":"macos","targetPlatform":"darwin",
 "capabilities":{"hotReload":true,"hotRestart":true,"screenshot":false,…}}
```

**`screenshot` is false for macOS and Chrome** — and, checked because physical
devices are the target, **false for every iOS 17+ device**:
`ios/devices.dart:1321-1328` returns false for a "core device" because
`idevicescreenshot` stopped working with iOS 17 / Xcode 15 (flutter#128598).
Android returns true (`android_device.dart:887`).

So device-level screenshots are not a capability the cockpit can build on — on
the single most important target they do not exist. The cockpit screenshots
*in the app* (fact 4), which is portable, subtree-scoped, and the same picture
the catalog and the scenario runner produce.

### 2. `flutter run` registers reload and restart as VM-service methods — any
### client may call them

Not recalled: `app/lib/src/utils/hot_reload.dart:10-28` documents it with the
SDK reference (`kReloadSourcesServiceName`, `kHotRestartServiceName`, aliased
`Flutter Tools`), and the class already does it for the GUI's own process.
Names are namespaced per client (`s0.reloadSources`) and arrive in
`ServiceRegistered` events, so they are listened for, never guessed.

**This is what makes a supervisor process optional.** A launch can be a
*detached* `flutter run`, and every later client — a `fw` invocation that did
not start it, the GUI, an MCP call — reaches the same app over the VM service
and can reload it, restart it, inspect it and drive it. Nothing has to stay
resident to hold the connection.

`app/lib/src/utils/daemon/` is a working `--machine` protocol client
(`AppStartEvent`, `AppDebugPortEvent`, `AppStartedEvent`, `AppRestartCommand`,
`AppStopCommand`) and `app/lib/src/utils/flutter_run_process.dart` drives it.
Both are legacy-test-runner code, unreachable from the shell, and both are
directly reusable — a rare case where the deletion pass should stop and take
inventory first.

### 3. The rendezvous pattern is established, and its one assumption breaks here

`app/lib/src/catalog/live_session.dart` and `lib/src/server/inspector.dart`
both: write a JSON handle into `~/.flutterware/run`, bind a socket, let
attachers decide liveness *by connecting*, and delete handles that will not
connect. `sweepRunDir` already has a per-prefix rule set.

That works for a desktop app and fails for every other device: **an iPhone
cannot write into the developer's `$HOME`.** The transport that does exist for
every Flutter target is the VM service — and the repo already streams over it
(`developer.postEvent` in `guest_logs.dart:95`, `guest_watch.dart:45`) and
answers commands over it (`registerExtension` in five `lib/src/inspect/` files).

So: **the host writes the handle, not the app.** Whoever launches records
`{device, worktree, entrypoint, knobs, vmServiceUri, pid}`; liveness is decided
by connecting to the *VM service* instead of a unix socket, which keeps the
existing rule intact for a case it was not written for.

### 4. The inspection runtime exists and is published — it is just not mounted
### in real apps

`lib/src/inspect/` (~2.7k lines): `ext.flutterware.tree`, `hitTest`, `logs`,
`errors`, `watch`, `imagesSettled`. Node ids are **structural** — derived from
the tree's shape rather than minted per object group — precisely so "a tree read
by one `fw` invocation can be asked about by the next"
(`guest_inspect.dart:26-28`). That property is what makes an agent loop possible
at all, and it was designed for the catalog guest.

Its only mount point today is the catalog's generated entrypoint. Mounting it in
a user's own app is the gap, and the user's app already has a place where
flutterware code is wrapped around it: `Devbar`.

Free in any debug build, no guest code required (verified in the SDK by the
07-29 inspection design, fact 1): `ext.flutter.inspector.screenshot` (base64
PNG, `debugPaint` option), `getRootWidgetTree`, `getLayoutExplorerNode`,
`setFlexFit`, and `ext.flutter.accessibilityEvaluations` — contrast, tap-target
size and unlabeled-tap-target checks we do not have to write.

### 5. The channel protocol for ask 5 is written, with the wrong transport bolted on

`lib/src/server/` is: a bounded ring per channel, replay-on-attach with a
`replay-done` marker, an `{ch, t, id, m, p}` envelope where **new feature = new
channel name**, zone-based request correlation, lazily fetched bodies, and
command handlers that run *inside* the inspected process against its own live
resources. The attacher side reduces (`ServerInfo.fromEvents`), normalizes SQL,
masks secrets at display time, and renders a timeline + waterfall + JSON viewer.

A devbar plugin reporting SQLite queries wants every one of those. The only
thing that does not carry over is `bind(unix socket) + write handle file`.

### 6. Launch-time injection already has a mechanism

`app/lib/src/wrap/dart_define.dart` + `run_command.dart` inject
`--dart-define=FW_MARKER=<token>` into an intercepted run. Knobs are the same
move with a declared list instead of one constant.

And runtime injection has one too: the devbar `variables` plugin
(`lib/src/devbar/plugins/variables/`) is a persisted key/value store with an
editor UI, which is *already* how you change a server IP without relaunching.

### 7. `catalog/devices.dart` is not about physical devices

It is the form-factor vocabulary (`DeviceKind`, `DevicePlatform`,
`CatalogDevice`) used to size catalog captures, deliberately Flutter-free. The
cockpit's device list is a different thing with an unfortunately identical name;
the two will need distinguishing (`CatalogDevice` vs `TargetDevice`, say) or
they will be confused forever.

## Physical devices are the target

Taking iOS and Android hardware from day one is not a wider port of the same
design — it removes options the desktop case leaves open.

**What it settles for free.** The VM service becomes the *only* channel worth
designing for. A phone cannot connect to a unix socket in the developer's home
directory, and a LAN socket back to the host is a firewall/roaming problem
nobody wants; the VM service is already there, already carries
`postEvent`/`registerExtension`, and already works over USB. D6's transport
question stops being a judgement call.

**What it costs, in rough order of how much it hurts.**

1. **The connection is a forwarded port, and the forward has an owner.**
   Android forwards through `adb` (`android_device.dart:1307-1420`); iOS
   forwards through the tool's own tunnel. Both are set up by the `flutter run`
   process. So "detached" in D1 means *detached but alive* — kill the child and
   the VM service becomes unreachable even though the app is still on screen.
   That is a supervision requirement the desktop case does not have, and it is
   the first thing S-L1 must measure.
2. **Reinstall is the dominant cost.** A `--target` change on an iPhone is a
   rebuild *and* a reinstall — minutes, not the tens of seconds a Mac pays.
   This raises the value of both D4's runtime knobs and D8's dispatcher
   sharply, and it is worth measuring early precisely because it reorders the
   plan.
3. **Attach-without-launch goes through mDNS.** `mdns_discovery.dart` is the
   mechanism (`queryForAttach`, with `useDeviceIPAsHost` for wirelessly
   connected devices), and `ios/devices.dart:1315` routes iOS attach through
   it. It is discovery over a network interface, so it inherits that
   interface's failure modes.
4. **Failure surfaces multiply**: locked device, lost pairing, expired
   provisioning profile, cable pulled mid-session, wireless device that roamed.
   Every one of these is a *normal* outcome on hardware, and each must read as
   "this device went away" rather than a stack trace. Budget UI for it.
5. **One phone, several worktrees.** The occupancy ledger (D2) stops being a
   nicety: a laptop has one test iPhone and three worktrees, which is exactly
   the case that motivated the ask.

## Direction

### D1. One plugin, two rendezvous, one session model

A `RunningApp` is `{device, worktree, package, entrypoint, knobs, vmServiceUri,
startedAt, pid?}`. It arrives two ways and is otherwise identical:

- **We launched it** — detached `flutter run --machine`, `app.debugPort` hands
  us the URI, we write the handle.
- **Something else launched it** — the IDE's run button, a terminal, an agent.
  Discovery via the daemon's `startVMServiceDiscoveryForAttach`, and on desktop
  additionally via the app's own handle write (a desktop app *can* write one).

> **Measured 2026-07-31 (S-L2): the second rendezvous is Android-only.** An
> Android app started from the phone itself is found in 5.9s, and attach
> restores reload/restart; the same test on iOS never discovers the app. The
> model holds, but its iOS branch currently has one arm — **we launched it** —
> so plan for a device where "adopt a running app" is simply not offered.

Control after that is VM-service-only: reload, restart, inspect, drive. The
`--machine` stream is still worth keeping — it carries build progress and
device logs — but it goes to a **log file beside the handle**
(the `wrap/session_sink.dart` shape), so a client that arrives later reads it
rather than needing to have been present.

**Consequence worth stating:** this deliberately does *not* build the per-repo
supervisor daemon the wrapper doc parked. Ask 1's "free or held" and ask 7's
"any surface" are both answered by handles + VM service. The daemon becomes
necessary the day we want PTY streaming, orphan sweeps and heartbeats — that is
a decision to postpone until something demands it, not to take here.

**On hardware, "detached" means detached but alive** (physical-devices cost 1):
the child owns the port forward, so it is a process nobody is *waiting on* and
everybody depends on. The minimum honest version is that the launcher writes
the handle, the child reparents, its stdout goes to a log file, and any client
notices it died by failing to connect and sweeping the handle. If that turns
out to be too lossy — a phone session dying silently while three surfaces think
it is up — the supervisor moves from postponed to next, and S-L1 is what tells
us which.

### D2. Devices: the daemon is a source, the run dir is the ledger

- **Inventory** — a `flutter daemon` child gives `getDevices` plus
  added/removed events. It is slow to start (seconds) and pointless to start per
  `fw` invocation, so whoever has one live writes `devices.json` into the run
  dir with a timestamp, and a cold CLI **reads the cache and says how old it
  is**. The architecture doc's rule applies verbatim: a run is a fact that
  happened; it gets old, it does not become wrong. `--refresh` is meaningful
  here (unlike the rejected one) because there is a file to refresh.
- **Occupancy** — scan `app-*.json` handles, connect-probe, delete the dead.
  A device is free, or held by `<worktree>` running `<entrypoint>` since
  `<time>`. Cross-worktree visibility falls out; nothing coordinates.
- **Contention is reported, not enforced.** Launching onto a held device is
  allowed (it is sometimes what you want) but the GUI says who has it, and the
  CLI/MCP answer carries the same field. Silent stealing is how a tool gets
  uninstalled — the `reveal` rule, one level up.

### D3. Entry points: declared wins, discovered fills in

```dart
fw.use(Run(packages: [
  RunPackage(app,
    entrypoints: [
      Entrypoint('lib/main.dart', name: 'App'),
      Entrypoint('lib/main_staging.dart', name: 'Staging', knobs: [...]),
    ]),
]));
```

Nothing declared → a syntactic scan of `lib/*.dart` for a `main()`, the same
scanner shape and the same ~20ms/180-file budget as the catalog. The scan is
provisional and the declaration is authority — the rule discovery already has.

Names matter more than they look: an agent picks an entry point from a list, so
`Staging` beats `main_staging.dart`, and the manifest is the only place a
human-written name can live.

### D4. Two kinds of knob, and the honest rule between them

| | mechanism | changing it costs |
|---|---|---|
| **launch knob** | `--dart-define` (and env for non-Flutter bits) | a rebuild |
| **runtime knob** | devbar `variables`, pushed over the channel | nothing |

**Prefer a runtime knob; make it a launch knob only when it must be baked in.**
This is not tidiness — a dart-define change triggers a full rebuild, so a
cockpit whose knobs are all launch knobs is a cockpit where every experiment
costs a build.

Reuse `KnobDescriptor` (published, pure Dart, already carries kinds, defaults
and options and already renders in `fw --help`, the docs and MCP schemas). One
addition earns its keep: `optionsFrom` pointed at live facts —
**the base URLs published by the server plugin's live handles**
(decision 17 of the server design mirrors `baseUrl` into the handle) and the
host's LAN addresses. "Inject the local server IP" then stops being typing and
becomes picking a value the tool already knows, on either surface.

### D5. Inspect: mount the existing runtime through `Devbar`

`Devbar` is already the widget users wrap their app in, already loads plugins,
already defers the first frame while they load. Give it the guest runtime:
tree, hit-test, logs, errors, images-settled, plus the channel of D6.

Adoption is then `Devbar(child: MyApp(), plugins: [...])`, which many users
already have, and the fallback for those who do not is a one-liner
(`Flutterware.attach()` before `runApp`). Gated exactly like the server library
(`kReleaseMode` / `dart.vm.product`, plus an explicit off switch), so a release
build carries nothing.

The pre-M4 review already queued "extract the generated-`main()` bootstrap"
into one published `installGuestRuntime(...)` because a second generator would
fork those ~60 order-sensitive lines. **The cockpit is the third consumer**, and
it is the one that makes the extraction non-optional.

The agent-facing shape is the **step triple** the scenario design fixed: PNG +
tree JSON + extracted texts, each an `Artifact` with an address. One node
vocabulary across catalog, scenarios and cockpit means an agent learns it once.

### D6. Devbar plugins report over the server protocol, on a VM-service transport

Split `lib/src/server/inspector.dart` into a transport-free **core** (ring,
channels, handlers, zone correlation, replay handshake) and two transports:

| transport | for |
|---|---|
| unix socket + handle file | a Dart server on the host (today) |
| `postEvent` + `registerExtension` | a Flutter app, on any device |

A devbar plugin then declares a channel and gets, for free: replay so the panel
shows what happened before it opened, correlation ids, lazy body fetch, and
command handlers that run inside the app against its own live database. An
SQLite inspector is the drift/`sqlite3` snippet already written for servers,
pointed at the app's connection — and `explain`/`requery` work for the same
reason they work there: **the handler runs where the data is.**

The network view is the same move on `lib/src/devbar/plugins/log_network/`,
which already intercepts `HttpClient`.

The GUI panel is largely the server plugin's, which is an argument for doing
this split rather than a new protocol: one timeline, one waterfall, one JSON
viewer, one SQL normalizer, one masking rule.

### D7. Act: one verb set, defined once, two backends

`tap`, `longPress`, `drag`/`scroll`, `enterText`, `back`, `settle` — addressed
by **structural node id** (from the tree the agent just read), with `key=` and
`text=` as secondary finders for a human writing by hand.

Live, this is `LiveWidgetController` over `WidgetsBinding` — what
`flutter_driver` does, without taking `package:flutter_driver` into a user's
app (master-plan decision 9 forbids the dependency, and its finder model is
worse for an agent than node ids we already mint).

Two things this must get right, both learned elsewhere:

- **A settle barrier.** After an action, wait for frames to stop and images to
  resolve (`ext.flutterware.imagesSettled` exists) before returning the new
  tree/shot. Without it an agent reads the pre-tap screen — the same race
  "watching is for humans, an explicit reload is for agents" names in the
  catalog.
- **`enterText` is the known gap.** S1 flagged it as the largest hole in the
  `LiveWidgetController` route: it is `WidgetTester`-only because it needs a
  test text input. In a live app the workaround is to reach the focused
  `EditableText` and push an editing value directly. Spike it; do not assume it.

**The verbs belong in the published package, defined once**, because the
scenario runner drives the same conceptual app through a test binding. Two verb
sets is the retrofit `Address` exists to prevent.

### D8. Hot-switching the entry point — the answer is "proven, and second"

S3 settled the mechanism: a newly reachable library enters a live isolate via
`reloadSources`, so a **generated dispatcher entrypoint** that imports every
declared entry point under a fresh prefix and mounts the selected one turns an
entry-point switch into a hot reload (~100ms) instead of a rebuild (tens of
seconds on desktop, minutes on a device). The fresh-prefix rule applies
verbatim; rebinding a prefix is silently ignored.

What is genuinely different from the catalog, and what the discussion should be
about:

- **A real `main()` has side effects** — binding init, DI, Firebase, plugin
  registration. Mounting entry point B without unwinding A leaves A's singletons
  alive. Hot *restart* is the honest reset, and it is ~1s over the VM service
  with no reinstall, which already captures most of the win.
- **The selection cannot survive a restart on a device.** The dispatcher would
  start unselected and wait for the host to push a selection, which means it
  must degrade sanely when nobody is attached (fall back to the default entry
  point) — otherwise `flutter run` from a plain terminal shows a blank app.
- **It puts generated code in the user's project** and makes the run target not
  be their `main.dart`, which is a real cost in confusion the catalog does not
  pay (nobody runs the catalog entrypoint by hand).

So: **v1 launches the declared target directly and uses hot restart for what it
can.** The dispatcher is a later slice, taken when someone actually feels the
rebuild — and the first thing to measure is how much of the pain is entry-point
switching versus knob changes, since a dart-define change forces a rebuild too
and D4's runtime knobs may be the cheaper cure.

**Revised for hardware.** On an iPhone the alternative to a hot switch is a
rebuild *and* a reinstall, which is minutes rather than the tens of seconds a
Mac pays — so the dispatcher's value goes up by roughly the amount the target
changed. It stays second, because a dispatcher whose selection cannot survive a
restart on a device is a design problem and not a coding one, and because the
same reinstall cost makes runtime knobs the higher-leverage half of the same
pain. But measure the reinstall early: if the number is bad enough, this moves.

**Measured 2026-07-31, and the platforms are expensive at opposite ends:** a
cold launch is 48.4s on a wired iPhone (11.8s of it *installing*) and 98.4s on
Android (82.8s of it a cold *Gradle build*) — hello-world apps, so real ones are
worse. A hot restart on the same hardware is 0.76–1.5s. The dispatcher is
therefore a *scheduled* slice rather than a maybe; what keeps it out of v1 is the
unsolved "selection cannot survive a restart on a device" problem, not doubt
about the payoff.

### D10. Getting back to a screen — the reliability ladder

*New requirement from the 2026-07-31 discussion: an agent has to remember the
steps that reach a given point in the app.* This is not a sub-feature of D7. A
verb sequence is how you *record* the journey; it is a poor way to *reproduce*
one, because taps resolve against a tree that changes every time the UI does.

Three mechanisms, in decreasing order of reliability, and the design should
prefer the highest one available:

1. **Address the screen directly.** If the app has a router, "get to the order
   detail for order 42" is a URL, not eleven taps — deterministic, legible to a
   human, stable across redesigns, and it survives a hot restart. flutterware
   already ships `router_outlet`, and go_router / Navigator 2.0 apps have the
   same property. This wants two primitives in the runtime: report the current
   location, and navigate to one. Cheap, and it retires most journeys outright.
2. **A named journey, replayed with resilient finders.** For what a URL cannot
   express — a wizard mid-flow, a state only reachable by doing things — a
   stored sequence of verbs, addressed by name, replayed with a settle barrier
   between steps. Finders are the whole game here: keys and semantic labels
   survive refactors, structural node ids do not (they are stable across
   *processes*, which is a different property from stable across *edits*). So a
   journey records the most durable finder available and reports honestly when
   a step no longer resolves.
3. **A raw verb script.** The escape hatch, and the thing a recording produces
   before anyone names it.

**A journey is a human feature first, and that changes its shape** (owner,
2026-07-31): *"open the app, use journey 'go to patient info profile as a
clinician'"* — the journey logs in, navigates, and hands the app over. Five
consequences, none of them cosmetic:

- **A journey is a launch option**, not only a post-launch action. It sits
  beside device / entry point / knobs in the launch UI and on the command line,
  and it starts from a **cold app** — so a journey declares that it begins at
  launch, rather than assuming whatever state the last one left.
- **A journey takes parameters, and they are knobs.** "As a clinician", "patient
  42" — `KnobDescriptor` again, the same type the entry points use, so it renders
  in the panel, in `fw --help` and in the MCP schema without new machinery.
- **Journeys compose.** "Log in" is a journey; "patient profile" starts from
  logged in. Without composition, login gets re-recorded into forty journeys and
  changes forty times when the login screen moves.
- **A journey ends by handing over, and asserts nothing.** Its success criterion
  is "the app is now here" and then a human keeps tapping. That is the cleanest
  line between a journey and a scenario, and it is why the two can stay separate
  projects without the distinction feeling arbitrary.
- **Credentials do not go in the repo.** A login journey references a variable
  (devbar variables, or an untracked local file) rather than inlining a
  password, or the first thing a team commits is a test account.

**Recording is two different features wearing one word.** They should not be
planned as one:

| | mechanism | cost |
|---|---|---|
| **Record what was dispatched** — an agent's calls, or a human clicking in the cockpit's panel | log the verbs going through `Session.invoke` while recording is on | ~free, *if* the panel dispatches actions instead of calling the core (enforcement #1 of architecture decision 6 — the panel-with-logic-in-`onPressed` rule) |
| **Record real touches on the device** — a human using the actual phone | observe pointers in the runtime and resolve each to a durable finder | a real feature: raw pointer events, hit-testing, and the hard part — choosing a finder that will still resolve after a refactor |

The first falls out of the architecture we already have. The second is the one
the owner expects to matter less, and it is also the expensive one — so it is
deferred on both counts, which is a comfortable place to be.

Two properties that make this useful to an agent rather than to us:

- **Journeys live in the repo, not in a cache.** They are shared between the
  human and the agent, they are reviewable in a PR, and they are the artifact
  that says "this is how you get to checkout". A run-dir cache would be
  private to whoever recorded it.
- **They are listed with names and descriptions** through an ordinary
  `PluginAction`, so an agent discovers "checkout-with-saved-card" the same way
  it discovers anything else, and `run <journey>` is one call rather than a
  reconstruction from a transcript.

This is also, quietly, the thing most likely to converge with scenarios later —
a journey is a scenario prefix that nobody asserted on. Worth noticing and not
worth designing for yet.

### D9. Surfaces: actions first, promotion later

Everything above is `PluginAction`s on a `RunCore` (`flutterware.run`), so
`fw`, MCP and the panel get it through `Session.invoke` with the parity test
walking it — `devices`, `entrypoints`, `apps`, `launch`, `stop`, `restart`,
`reload`, `tree`, `screenshot`, `tap`, `scroll`, `text`, `navigate`,
`journeys`, `replay`, `logs`, `requests`, `sql`.

The MCP surface stays the three fixed tools. But the architecture doc reserved
promotion "where a good name beats a discovery round-trip", and the drive loop
(screenshot → tree → tap → screenshot) is the first thing plausibly worth it:
it is high-traffic, latency-sensitive, and an agent that must call
`flutterware_actions` to remember how to tap is paying a round trip per gesture.
**Decide it with a real client in front of us**, after the actions work.

## The relationship to scenarios (kept loose, deliberately)

Scenarios stay a separate project (settled 2026-07-31). The overlap is real but
it is a *vocabulary* overlap, not a code one: both name a tap, both produce a
screenshot + tree + texts, both address a moment in an app. Nothing yet says
whether a `LiveWidgetController` verb and a `WidgetTester` verb should be one
type with two backends or two types that read alike, and inventing that seam
now would be designing for a consumer that does not exist.

The cheap discipline that keeps the option open, and costs nothing:

- **Name the verbs the same.** `tap` / `drag` / `enterText` / `settle`, same
  parameter names, same finder spelling.
- **Emit the same artifact triple**, in the `lib/src/inspect/` node format both
  already speak.

If they converge later, the convergence is a serializer — the cockpit records a
real session, the runner replays it deterministically on FakeAsync in CI, which
is also scenarios' own auto-write roadmap item approached from the other end.
If they never converge, nothing was spent.

## Open questions, for the owner

1. **How much of D6 to do up front.** Splitting `Inspector` from its transport
   is a refactor of shipped, tested code. Doing it before the first devbar
   channel exists risks designing for one imagined consumer; doing it after
   risks two protocols. (Recommendation: split when the *second* transport is
   actually being written, i.e. inside the D6 slice, not before it.)
2. ~~**Whether `flutter daemon` runs resident.**~~ **Answered by building it.**
   A shared daemon per SDK per process, leased: the GUI panel holds one while
   it is open, `fw` takes one for the length of a `--refresh` and gives it
   back. Measured on this machine with an Android, two iPhones, Chrome and
   macOS attached: `fw … devices --refresh` **7.9s** end to end against
   **4.6s** for the cached read and 4.6s for `fw status` — so the daemon itself
   is ~3s and the rest is `dart run`. Cheap enough that the cache exists for
   convenience rather than necessity, and no supervisor is implied.
3. **Where journeys are stored, and in what.** D10 says "in the repo"; whether
   that is JSON under `.flutterware/`, a committed Dart file, or something the
   scenario runner would recognise is open — and is the one D10 decision that is
   awkward to change later, because agents will have written the files.
4. **Wireless devices.** `useDeviceIPAsHost` exists and works, but a device on
   wifi can roam, sleep and change address. Worth deciding whether v1 supports
   only cabled devices and says so, rather than half-supporting wireless.
5. **Web.** DWDS is a different VM-service story and may never earn the work.
   Not in scope unless someone asks.

## Spikes, before anything is designed further

Small, hostile, throwaway — the repo's spike discipline. All four can share a
scratch harness.

**S-L1 — Detached launch and third-party control, on real hardware.** The one
that decides D1, and it runs on **a physical iPhone and a physical Android
first** — simulators would prove the easy case and hide every interesting
failure. Launch `flutter run --machine` detached; from a *different* process,
connect to the reported VM service, list the registered services, call
`reloadSources` and `hotRestart`, and verify the change reaches the screen.
Then the hardware questions: does the forward survive the launching shell
exiting; what happens when the cable is pulled and replugged; what does a
locked device do; and **how long is a rebuild-and-reinstall** (the number that
reorders D8). **Kill criterion:** if a detached child's VM service is not
reachable by a later, unrelated process, D1 collapses and the supervisor daemon
moves from "postponed" to "prerequisite" — which is a plan change, not a bug.

> **Ran 2026-07-31, partially — see `2026-07-31-sl1-detached-launch-findings.md`.**
> D1 holds on macOS and the iOS simulator: a detached run reparents to init and
> an unrelated process reloads (54–75ms), restarts (218–232ms), reads the tree
> and screenshots it. The finding that changes this document: **capabilities
> split into an app-owned tier (tree, shot, logs, verbs, channels) that survives
> the launcher dying and a tool-owned tier (reload, restart) that does not** — so
> the cockpit reports capability, not just liveness, and `flutter attach` is how
> reload is *acquired* rather than merely how an app is found. The hardware leg
> **Completed on hardware** — wireless iPhone, wired iPhone, wired Android.
> Control works on all five targets (tree 41–125ms, screenshot 72–172ms, reload
> 283ms–1.57s, hot restart 0.76–1.5s), and the **two-tier split is universal**:
> tree/screenshot/verbs live in the app and survive the launcher; reload and
> restart are registered by the tool and die with it. So the cockpit reports
> **capability**, not just liveness, and `flutter attach` is how reload is
> *acquired* rather than merely how an app is found.
>
> **One configuration kills the app with its launcher** — iPhone 16, cabled,
> reproduced twice and confirmed absent from the device's process list. A 2×2
> run after swapping the cable **rules out the transport**: the iPhone 11
> survives wired *and* wireless, and the iPhone 16 survives wirelessly. One cell
> dies, reproducibly, for reasons not established (screen state is the
> uncontrolled variable worth checking next). So the rule for iOS is *do not
> assume the app outlives its launcher* — keep the child alive and detect its
> death as **robustness**, not as a known platform rule.
>
> Cold launch: **40.7s** wired iPhone 11, **48.4s** wired iPhone 16 (23.0s
> warm), **98.4s** Android cold but **9.6s** warm — the Gradle build is a
> one-time cost. Against 0.76–1.5s for a hot restart.
>
> **Wireless is worse, by an amount this spike could not measure.** All three
> wireless runs waited on a human dismissing an OS dialog — device trust, then
> macOS local-network permission, **which re-fired even after being granted**.
> What is clean is the per-interaction cost: reload **289ms wired vs 1571ms
> wireless**, tree 41ms vs 69ms. That is enough to prefer cables; the install
> figures are not.
>
> The prompt itself is a design input: **a launch can block forever on an OS
> dialog**, so "waiting for permission" is a state the cockpit must model rather
> than a progress bar it spins. And if the re-prompting turns out to be an
> artifact of launching from a CLI — a bare `dart` process is a weak subject for
> macOS's per-application attribution, while the GUI is a real bundle — then
> `fw` and the GUI have a genuine capability gap on wireless devices. Worth
> checking before promising parity there.

**S-L2 — Attach to a run we did not start.** IDE run button on a physical
device, then find it: `startVMServiceDiscoveryForAttach` / mDNS headless,
timing, and what it needs to know in advance. Cabled and wireless, since
`useDeviceIPAsHost` splits the two. **Kill criterion:** if discovery needs the
device id and several seconds every time, ask 7's "however it was launched"
degrades to "we launched it, or you tell us where it is" — survivable, but it
should be known before the UI promises otherwise.

> **Ran 2026-07-31 — `2026-07-31-sl2-attach-findings.md`. Split result.**
> **Android:** an app started from the phone's own launcher, with every host
> forward removed, is found in **5.9s** knowing only the device id; attach
> creates its forwards and **restores reload/restart**. Ask 7 holds, and
> `attach` is the ~6s repair path for a session whose launcher died.
> **iOS: not found.** The app runs (confirmed in the device process list) but
> two attempts, ~5 minutes of waiting, produced no `app.debugPort` and no
> mDNS advertisement — the plausible reason being that iOS enables the VM
> service only via arguments `flutter run` passes, while Android's debug engine
> always does. Cause not isolated. Combined with S-L1's wired-iOS result (the
> app dies with its launcher), **an iOS session is owned by whoever started it,
> start to finish** — so on the primary target the cockpit must be the launcher,
> or the IDE must have been.

**S-L3 — Drive a real app.** Mount `GuestInspector` + a `LiveWidgetController`
extension in a toy app under `Devbar`; read the tree, tap a node by structural
id, settle, read it again. Then the hard one: `enterText` into a `TextField`.
**Kill criterion:** if tapping by node id cannot be made reliable (hit-test
through transforms, scrollables, platform views), the verb set needs a different
addressing scheme and D7 must be redesigned before the plugin exists.

**S-L4 — A devbar channel over the VM service.** One toy SQLite plugin
publishing `sql` events through `postEvent` and answering `explain` through
`registerExtension`, read by a throwaway client. Measures the event rate the VM
service will take before it becomes the bottleneck. **Kill criterion:** if
`postEvent` throughput or payload limits make a busy `http` channel unusable,
D6 needs a side channel (a socket for desktop, a device-side buffer + pull for
the rest).

## A first slice, if the spikes hold

Order chosen so each slice is useful alone and the risky parts come early.

1. ~~**Devices and occupancy.**~~ **Built 2026-07-31.** Daemon inventory +
   `devices.json` cache with an age, `app-*.json` handles, probe-and-sweep,
   `devices` / `apps` actions, a panel, and the sweeper taught about both new
   file kinds. `fw status` reads five real devices and says which are held, by
   which worktree, running which entry point.

   Three things the build settled that the design had not:

   - **The two-tier split is in the data model, not a comment.** `RunProbe` has
     `app` (the VM service answered) and `launcher` (the `flutter run` is
     alive) as separate facts, and `canReload` is their conjunction while
     `canInspect` is the first alone. The sweep rule falls out of it: a handle
     is deleted only when *neither* is there, so a cold Android build — live
     launcher, no VM service for ninety seconds — keeps its device.
   - **A shared daemon has to be leased, not owned.** The first working version
     printed a correct device list and then hung for ten minutes, because the
     `flutter daemon` child keeps the Dart VM alive and nothing stopped it. The
     GUI wants one daemon across every open worktree; `fw` wants it gone when
     the command ends. Reference counting is the only rule that serves both.
   - **A wire type we do not version must never throw.** `MessageLevel` was
     `{info, warning, error}`; the tool actually sends `trace`, `status`,
     `warning`, `error` — `info` does not exist. The first `status` line threw
     out of `Event.decode`, out of the stdout subscription, and took the whole
     protocol down. The enum is now the real set *and* `tryReadEvent` swallows
     what it cannot decode, because losing one event is a bug and losing the
     connection is an outage.
2. **Launch and lifecycle.** Declared + discovered entry points, launch knobs as
   dart-defines, detached child, log file, `stop` / `restart` / `reload`, the
   panel's device × entry-point grid, and honest reporting when hardware goes
   away mid-session.
3. **Inspect.** `installGuestRuntime` extracted and mounted via `Devbar`; tree,
   screenshot, logs, errors as the artifact triple with addresses; MCP loop
   working with no GUI running (the server plugin's exit criterion, reused).
4. **Act, and reach.** The verb set, the settle barrier, node-id addressing —
   and D10's rung 1 in the same slice, because "navigate to this location" is
   both the most reliable way to reach a screen and much less work than the
   journey machinery above it.
5. **Journeys.** Record, name, store in the repo, list, replay with resilient
   finders and a truthful failure when a step stops resolving.
6. **Channels.** Transport split, network and SQLite panels over the server
   plugin's UI, runtime knobs pushed live.
7. **Then decide** on the dispatcher (D8), armed with S-L1's reinstall number
   and real usage to argue from.
