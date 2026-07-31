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

## The build list, for when slice 3 starts

1. ~~`Entrypoint.description`~~ **built** — through `declaredEntrypoints`,
   `EntrypointRef` and `RunEntrypointEntry`, and shown in the picker.
2. ~~`run_address.dart`~~ **built** — `<runHandleKey>/<tab>`, round-trip tested.
   Artifacts are *not* under it: the screenshot action writes a file and
   returns its path, which left the artifact question open (below).
3. ~~Panel: subject chips + tab strip + run header~~ **built**.
4. ~~The New run page as a subject~~ **built**.
5. ~~The desk widget in the panel's empty state~~ **built**. Still to promote to
   shell chrome with the worktree-jump.
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

### What the build changed about the design

- **The rail lists runs, not devices.** A `PluginChild.id` becomes the first
  address segment, so the children have to be things the panel can be pointed
  at. Devices moved to the desk and the status line.
- **The tabs are `Screen`, `Tree`, `Logs`** rather than the `Screen`/`Logs` the
  design named. The tree earns its own pane: it is the only artifact that
  carries source locations, which is what makes it actionable.
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
