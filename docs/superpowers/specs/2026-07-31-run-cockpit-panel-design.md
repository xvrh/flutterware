# The run cockpit's panel: two surfaces

**Date:** 2026-07-31
**Status:** Settled with the owner. Build it at the *start* of slice 3, not
before — the container is decided, the content it holds is not built yet.
**Mockups:** https://claude.ai/code/artifact/7123dacc-a659-4b86-8526-1220f60a427c
(flutterware's own palette, both themes)
**Follows:** `2026-07-31-app-launcher-cockpit-brainstorm.md`, slices 1 and 2.

## Why redesign at all

The shipped panel is a list of devices with a run squeezed into each row. That
fitted slice 1, strained in slice 2, and has nowhere to put slice 3: a
screenshot, a widget tree and a log stream do not go in a table row.

**There is no reference implementation for this panel.** dev_studio is the
reference for scenarios, but its "devices" are simulated frames inside a
scenario run, not machines on a desk. So this was designed fresh — said out
loud rather than quietly invented, per the standing rule about announced GUI
shapes.

What *does* exist is the **server panel**, and it is this problem solved once
already: subject chips → tab strip → master/detail. A run is a subject in the
same sense a server is. The run panel follows it.

## The two surfaces

The first pass had one popover doing two unrelated jobs. They separate cleanly:

### 1. Starting a run is a page

A device picker, an entry point picker, that entry point's knobs, and Start.
One column, in that order.

- **Pickers, not lists.** Four to ten entry points as a list is a wall; as a
  picker it is a line.
- **The page opens filled in with the last run.** Running the same thing again
  is then opening it and pressing Start — the common case, served with no extra
  controls. (An earlier draft had a "recents" row; it was half of why the page
  was hard to read.)
- **Knobs carry their offered values.** `from: KnobSource.servers` fills the
  list with the base URLs of servers announcing themselves right now,
  `hostAddresses` with this machine's LAN addresses.
  <br>**Superseded 2026-08-10.** Shipped as `DartDefine`/`DefineSource` (the
  rename's rationale is on `DartDefine` itself), and `servers` has been deleted:
  offered values are a `List<String>`, so two servers arrived as two bare URLs
  with no way to tell them apart, and the scan was never scoped to the worktree.
  `hostAddresses` remains, and each address now carries the interface it was
  found on.
- **Warn before the click on a wireless device.** Every wireless launch in S-L1
  stalled on an OS dialog while the tool said only `Installing and launching…`.

**This needs one config addition:** `Entrypoint(..., description: '…')`.
`Kiosk` and `Onboarding` are unguessable from their file names, and the picker
is where that costs you. An agent choosing an entry point reads the same field,
so it pays twice.

### 2. The desk lives in the shell's chrome

A device control beside the worktree tabs: what is on this machine, what is
free, and who has the rest.

**The argument for chrome is not that devices are machine-global.** That
settles nothing — a second flutterware window has its own chrome either way.
It is that **a busy device should take you to the worktree holding it**, and
switching worktrees is something only the shell can do. The panel structurally
cannot offer it.

It stays one widget, rendered in the panel's empty state too, so nobody who
never looks up there loses the list.

Starting devices belongs here: the daemon's `emulator` domain offers
`getEmulators`, `launch` (with `coldBoot`) and `create`.

## Three kinds of device

The list has been treating these as one thing. The differences are exactly what
a row has to say.

| kind | comes and goes | contended | can be started | a row says |
|---|---|---|---|---|
| **physical** — iPhone, Pixel | unplugged, asleep, roaming | yes, across worktrees *and* repos | no | free · busy, and by whom |
| **virtual** — emulator, simulator | you start and stop it | yes, once booted | yes — `emulator.launch` | offline · free · busy |
| **host** — this Mac, Chrome | always there | not really: the run owns a window, not a slot | n/a | not running · running *X* |

**The shipped code gets `host` wrong.** `RunCore._deviceStatus` labels this Mac
`free` or `busy` as though it were a phone somebody could take from you. It
cannot be taken, and stopping the run closes the window — so the honest words
are about the run, not about the slot. (The data already distinguishes them:
`RunDeviceEntry.physical` is false for macOS and Chrome. Only the labels lie.)

## A run's page

Runs are the panel's subjects. The **tab strip is the extension point**:
`Screen` and `Logs` arrive with slice 3; `Network` and `Data` are devbar
plugins reporting into the cockpit (ask 5), so the strip has to accept tabs it
does not know at build time.

The header shows **capability, not liveness** — the S-L1 finding made visible.
An app whose `flutter run` died keeps its tree and its screenshots and loses
hot reload; a row saying only "running" hides exactly what the buttons are
about to.

| state | header says | reload/restart | screen · logs · verbs |
|---|---|---|---|
| building | the launcher's progress line | off | off |
| waiting for permission | "waiting for a permission dialog on this Mac" | off | off |
| running | reloadable | on | on |
| launcher gone | no launcher — attach to reload | off, Attach offered | on |
| another worktree's | the worktree's name | off | on, read-only |

## Addresses: the key, and that is all

A run already has an id — the handle is keyed by
`sha1(worktree | device | entrypoint)`, twelve hex characters (`runHandleKey`),
and it is **stable across relaunch**. Stop Staging on the iPhone, start it
again, same address: `fw://…/flutterware.run/<key>/screen`.

An earlier draft called this expensive to get wrong. It is not, and the reason
is worth keeping: **a run is ephemeral, so nothing durable points at one.**
What agents write down for the long term are journeys, and those are
deliberately last.

The one piece that *is* worth deciding inside slice 3: **whether a screenshot
hangs under its run or stands on its own.** A picture can outlive the run that
took it, and a run's address cannot reach it once the run is gone. That is a
question about artifacts, not about runs.

## Still open

- **Does a foreign worktree's run get a full page or only a row?** Showing
  another worktree's screenshots is useful and slightly surprising. Instinct:
  yes, read-only — the alternative is a tool that knows and will not say.
- **Does the screen pop out?** A phone screenshot at device scale is tall, and
  a mirror wants to stay up while you work elsewhere. Whether that is a real
  window or a pinned pane is a slice-3 decision.

## Revised after seeing it built (2026-07-31)

The mockup drew the run list **twice** — as rail sub-items under `Run`, and as
the chip row above the tab strip — and building it made the duplication
obvious. The chips go. The rail is the list.

That was queried with "we can teach anything to the rail or any place we want,
we should not be driven by artificial constraints", against an earlier answer
here that treated `PluginChild` as fixed. It is not: it is our own API, and
`NativePlugin.childCommands` already proves the shell takes per-row affordances
from a plugin. So:

- **Runs live only in the rail.** Failures go into `report.children` too —
  putting them in the chips alone was the wrong half.
- **`+ New run` becomes an affordance on the plugin's own rail row**, which is
  the scenarios pattern (`+` in a section header, big button in the empty
  state) applied one level up. It needs a plugin-level command hook beside the
  existing child-level one — a small, general addition, not a special case.
- **Reload and restart need feedback.** They are wired and measured (275ms /
  727ms) but the panel says nothing on success and nothing while pending, so a
  working button is indistinguishable from a dead one.
- **The tab strip and the tree are `InspectDock` and `ElementsView`**
  (`app/lib/src/inspect/`), already shared by ui_catalog and scenarios. The
  cockpit's `RunInspector` emits the same `InspectNode`, so this is a swap that
  deletes `_ViewTabs`, `_TreeTab`, `_TreeRow` and `_sourceLabel` — including
  the per-row source paths, which `ElementsView` correctly keeps in the detail
  pane, shortened against a display root.

## The build list, for when slice 3 starts

1. ~~`Entrypoint.description`~~ **built** — through `declaredEntrypoints`,
   `EntrypointRef` and `RunEntrypointEntry`, and shown in the picker.
2. ~~`run_address.dart`~~ **built** — `<runHandleKey>/<tab>`, round-trip tested.
   Artifacts are *not* under it: the screenshot action writes a file and
   returns its path, which left the artifact question open (below).
3. ~~Panel: subject chips + tab strip + run header~~ **built**.
4. ~~The New run page as a subject~~ **built**.
5. ~~The desk widget in the panel's empty state~~ **built**, and ~~promoted to
   shell chrome with the worktree-jump~~ **built 2026-08-11** — `DeskButton` in
   the band (`app/lib/src/shell/device_desk.dart`), reading `devices.json` and
   the ledger directly rather than a `RunCore`, because the chrome outlives any
   one worktree session. A busy device's row jumps straight to the run's page
   in the worktree that holds it; booting emulators stays in the panel's desk,
   with the daemon.

   **"The panel's empty state" was the mistake, corrected 2026-08-25.** The
   panel desk was drawn only while the worktree had no runs — and it is the
   only surface in the GUI that can boot anything, because the chrome copy has
   no `RunCore`. An unbooted emulator is not a device, so it is not in the
   launch form's picker either: one running app and every machine that was not
   already up became unreachable, reported as *the buttons are absent*. The
   desk is now drawn whenever the launch form is, and has gained the two
   controls it never had — a **Refresh** (the list could say `27m ago` and
   nothing could take a new one) and **Run here** on a free device, which fills
   the form's Device field rather than navigating. The chrome copy stays
   read-only and now carries a row into the panel, so the two surfaces over the
   same machines are visibly one thing.
6. ~~Fix the `host` labels~~ **built**, and the fix went deeper than labels: the
   distinction is now `DaemonDevice.kind` (`physical`/`virtual`/`host`) and it
   is reported by the `devices` action, because `physical: false` covered both
   this Mac and a booted simulator and a caller could not tell them apart.
7. ~~`emulator.getEmulators` / `emulator.launch`~~ **built** — as the
   `emulators` and `bootEmulator` actions and a boot control in the desk.
   Booting the iOS simulator through it took 6.1s.

   One thing the daemon forced: **`booted` has to be nullable.** There is
   exactly one iOS entry, `apple_ios_simulator`, and it is a door to the
   Simulator rather than a machine — the Simulator may already be running
   `iPhone 16e` under a name that links back to nothing. Reporting `false`
   there claimed an offline simulator while `devices` listed a booted one two
   lines away. Android answers the question properly, through `emulatorId`.

### One action, not three

`tree`, `screenshot` and `logs` shipped as three actions and were merged into
one `inspect` with flags, plus a standalone `screenshot`. **The catalog had
already decided this**, and its reason is written into `ui_catalog_core.dart`:
a `--screenshot` is "a PNG of the same frame everything else is reported from",
and `--annotate` draws boxes from "genuinely the same tree as the one reported
rather than a second reading that happened to agree, which was the point of
having it".

That reasoning is *stronger* here, not weaker. The catalog inspects a frame it
just rendered; the cockpit inspects a **live app** that animates, fires timers
and takes in data between calls. Three actions meant three processes, three
connections and three moments. The tree and the picture now come off one
`getRootWidgetTree` call in one object group — which is the only footing on
which annotating a screenshot with node ids can ever be built.

One thing done differently from the catalog: **`inspect` answers even when the
app is not up.** The cockpit's logs come from the launcher's file rather than
from the app, so they are readable during a cold build and after a crash —
exactly when nothing else is. So `up` is a field, not an error, and a call
during a build returns the progress line and the logs instead of refusing.
Verified against a cold Chrome build.

### A failed launch has to leave something behind

The first launch onto real hardware failed, and the cockpit said nothing —
the chip appeared, vanished, and the panel was back at the form. Three separate
faults, each of which alone was enough to lose the reason:

1. **The log kept only its last plain line.** An iOS signing failure ends `App
   failed to start`; the cause — `No Account for Team "B7V224LKE4"` — is twenty
   lines above it, with the four Xcode steps that fix it. `LaunchLog` now keeps
   the plain block since the last structured event and reports all of it.
   Delimited by events rather than by matching words, because **`flutter run
   --machine` emits nothing structured at all for a build failure**: no
   `daemon.logMessage`, no error on `app.stop`. Measured, not assumed.
2. **`awaitLaunch` returned at `app.stop`,** which the tool emits *before* it
   explains itself — and while the launcher was still alive, so
   `failure(launcherAlive: true)` answered null. A failed launch came back as a
   bare `stopped` with no error at all. It now waits for the launcher to exit
   (bounded at 3s) so the log is whole, and a stop before `app.started` is a
   `failed`, not a `stopped`.
3. **The handle is deleted on failure and that is correct** — a launcher that
   never came up is not holding the phone, and leaving it would tell the next
   person a device is busy. But the chip went with it. `RunFailure` is what
   stays: in memory, keyed by the run key, so the address you were watching
   turns into the reason rather than bouncing you to the form. The log is the
   durable record and the failure points at it.

### Flavors are entry point config

`flutter run --flavor` selects a build variant — a Gradle product flavor on
Android, an Xcode scheme on Apple platforms. It matters more than a knob does:
**a project with flavors cannot be built without one at all.** Where a missing
`--dart-define` gives you the fallback value, a missing `--flavor` fails before
anything compiles.

So it is declared on the entry point (`Entrypoint(..., flavor: 'dev')`), which
is how the pairing already works in practice — `main_dev.dart` goes with `dev`.
It is reported by `entrypoints`, overridable per launch, and offered in the New
run page as a field that is always present, because whether *this* project has
flavors is not something the cockpit knows.

**It is part of a run's identity, not a decoration.** `dev` and `prod` install
as different bundle ids and sit on one phone together, so `runHandleKey` takes
it; without that, two live runs would share one handle and one log — the
collision that already published a dead VM service address once. A null flavor
hashes exactly as before, so nothing written earlier is orphaned.

Not built: **offering the flavors a project actually has.** The tool knows them
— its own error names the schemes it found — so reading `productFlavors` from
gradle and the `xcshareddata/xcschemes` directory would let the picker list them
and let a wrong one be caught before a build. Worth doing; it needs two parsers
and neither is guessable, so it waits for a real flavoured project to test
against.

### What the build changed about the design

- **The rail lists runs, not devices.** A `PluginChild.id` becomes the first
  address segment, so the children have to be things the panel can be pointed
  at. Devices moved to the desk and the status line.
- ~~**The tabs are `Screen`, `Tree`, `Logs`** rather than the `Screen`/`Logs`
  the design named. The tree earns its own pane.~~ **Wrong, and reverted**
  (2026-07-31). The mockup's run page has `Screen` and `Logs`, and the *Screen
  tab is a split*: a narrow phone pane on the left with `Screenshot` / `Pop
  out`, the widget tree filling the rest on the right, with the driving verbs
  under it. Splitting the tree into a third tab separated the picture from the
  tree it describes — the two things you look at together — and this entry
  wrote the deviation up as an improvement instead of flagging it. The rule it
  broke is the standing one: **diff against the announced shape before styling,
  and a deviation needs the owner's word.**
- **A run's log opens at its newest line**, and the app's output is separable
  from the build's. That split had to be measured rather than designed — see
  `2026-07-31-sl3-inspect-surface-findings.md`.

### A bug the rebuild surfaced

Worth recording because it was invisible until runs became subjects. The handle
key is stable across relaunch *by design*, so two runs of the same entry point
on the same device share one `app-<key>.log`. The shell redirect only truncates
that file once the child is running — and `awaitLaunch` starts polling the
moment `Process.start` returns. In that window it read the **previous** run's
`app.debugPort` and published the new run at a dead VM service address.
`refreshFromLog` then returned early because the handle already had both fields,
which made the wrong value permanent. Fixed at both ends: the log is emptied
before the spawn, and the log now always wins over the handle.

## Revised after living with it (2026-08-11): the rail is scoped, the ledger is not

The open question above — "does a foreign worktree's run get a full page or
only a row?" — got answered in practice by a third option nobody chose: every
worktree's runs were rows in *every* rail, distinguishable only by a status
suffix, and the panel's fallback picked the newest handle on the machine — so
opening Run in one worktree could land you on another checkout's app.

The line now runs where the design originally drew it:

- **Occupancy is machine-global.** `RunCore.handles`, the desk (both copies),
  the `devices` and `apps` actions, and the probe-and-sweep loop still read the
  whole ledger — a device held by another checkout is exactly the case they
  answer.
- **Subjects are worktree-scoped.** `report.children`, the rail badge, the
  panel's fallback selection, `isStarting` (it gates `busyWith`, and a capture
  must not wait out another checkout's cold build) and `.failed` records — which
  now carry the launching worktree — use `ownHandles`/`ownFailures`.
- **The read-only foreign page survives, behind an explicit address only.**
  An address that names another worktree's run key still resolves — a tool that
  knows should say — but nothing lists it here; the desk's worktree-jump takes
  you to the owning worktree instead, where the run is drivable.
