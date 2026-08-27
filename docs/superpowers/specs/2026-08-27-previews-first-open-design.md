# A first open that says nothing is indistinguishable from one that hung

**Date:** 2026-08-27
**Status:** Design and findings. §4 and §5.1/§5.4 are built. What is left is
the measurement in §6 and the item in §5.5 that depends on nothing here.
**Reads against:** `2026-08-26-cold-start-seed-kernel-findings.md`, whose
measurements this both relies on and, in one place, contradicts.

Two reports, a day apart, that turn out to be the same report.

- Since the catalog became the landing page, opening previews arrives on a page
  of empty frames that says nothing for as long as the work takes.
- A consumer project took **~60s** to open on one machine, against a
  remembered ~20s.

They are one report because the second is only a question at all while the first
is true. A start that narrated its phases would have answered it in the panel,
in one glance, and this document would be half its length.

## 1. What a first open actually does

Two compilers, of the same program, at the same time, plus a build.

| lane | what it is for | who starts it |
|---|---|---|
| catalog daemon | the live guest on the stage | `CatalogSession.start()` |
| `flutter_tester` harness | the pictures on the catalog page | `thumbnails.wantAll` from the landing's first layout |

Neither waits for the other, because neither knows the other exists. Alongside
them the daemon runs the asset bundle and a `flutter build` of the host, both
already overlapped with its own compile and neither the problem.

The second lane is new. Before the catalog page landed (#261, 2026-08-25) the
tester lane came up on a hover, which is a person asking for one picture; now it
comes up on arrival, which is the same cold compile paid by everybody on every
first open. Its own comment has always known the number: *"which on a cold
catalog is thirteen seconds"*.

**This is the first thing to measure and the last thing to guess at.** Two
compilers of one program either overlap usefully — different work, spare cores —
or they contend and each takes longer than it would alone. Nothing here has
measured which, and the answer decides section 6.

## 2. Why the screen is empty

There is a loading state for exactly this wait, and it is good: a title, and a
message carrying the entry's name and a climbing seconds count, because *"a
count that is climbing is the only thing on screen that distinguishes slow from
hung"*.

It is unreachable.

`_buildCanvas` answers the no-selection case **before** it looks at the phase
(`catalog_view.dart:535`), and the loading state lives inside the phase switch
below it (`catalog_view.dart:561`). Landing on the catalog means nothing is
selected, so the branch that would say what is happening is the branch that is
never taken. The state was written when the panel opened on a demo; the landing
moved the door and nobody moved the sign.

What is left narrating a 20–60s wait: a `BusyDot` and a status bar at the foot
of the pane.

The tiles themselves are empty on purpose, and the purpose stands — *"a page of
a hundred and fifty spinners is a page that looks broken, where a page of empty
frames filling in one by one reads as what it is"* (`preview_sheet.dart:468`).
The complaint is not that the tiles are quiet. It is that nothing anywhere is
loud.

## 3. What the daemon already knows and nobody reads

`DaemonReady.timings` (`protocol.dart:232`) carries the whole breakdown — scan,
quarantine, asset bundle, host build, cold compile, seed kernel — and its doc
comment says why: *"Reported rather than logged so the GUI and `fw` can show it
without scraping a log."* It has **no consumers**. The GUI decodes it and drops
it.

And there is no progress message at all. `DaemonResponse` has `ready`,
`catalog-changed`, `assets-changed`, `compiled`, `failed` — the daemon binds its
socket, then prepares in silence, and the client waits. So the panel cannot
narrate live today even if it wanted to: the channel does not exist. The
post-mortem does.

## 4. The design: one voice, two lanes — built 2026-08-27

Built as designed, with three departures worth writing down. `CatalogStartup`
is called `StartupProgress` and lives in `app/lib/src/ui/startup_progress.dart`
with `StartupStrip` over it. The daemon's phase names are turned into sentences
by `daemonPhaseLabel` (`app/lib/src/previews/daemon_phase.dart`) rather than on
the wire, so an unrecognised phase from a newer daemon is *shown* rather than
swallowed — the daemon and the GUI that spawns it move independently, and that
is the ordinary case here rather than an edge one. And the model reads its clock
through `package:clock`, which is what makes the one number it exists to show
testable at all: a `Stopwatch` reads a clock a widget test cannot move, so every
rule about the readout would have passed vacuously.

**One thing was wrong on the first run and is the rule now.** Every lane closes
before the next opens — the harness reports ready, and the render pass it
unblocked opens a frame later — so a clock that reset between them showed a
first open of forty seconds as `0s`. A gap shorter than `appearsAfter` is not
the end of a wait; it is a handover, and the clock and the strip's visibility
both survive it.

**The scenarios panel mounts it too**, and gained the half it never had. It
already narrated a wait while its canvas was empty, with a `Stopwatch`, a floor
and a ticker of its own — all three now come from the shared model — but it
*stopped* the moment the first step landed. So a long scenario filled in step by
step with nothing on screen saying more was coming, and a run still going looked
exactly like one that had finished. The strip says so, above the flow, and
retires when the run does.

**Two surfaces, and the rule between them is what there is to sit above.** With
an empty canvas the centred `LoadingState` is the surface — a band alone over
empty space reads as nothing happening — and mounting both put the same sentence
on screen twice, once as a band and once under a spinner four hundred pixels
below it. The strip is gated on the flow having steps.

### 4.1 `DaemonProgress`

A sixth response. The daemon already wraps every phase in `_timed(name, …)`
(`compiler_daemon.dart`); emitting phase-started and phase-finished to connected
sessions is the same call site saying out loud what it already writes down. A
client that attached to a running daemon gets `reused: true` and no phases,
which is correct — it paid for none of them.

Deliberately **not** a log stream. `DaemonLog` exists and tails the daemon's file
forward at 25ms, and reusing it would work; it is rejected because a phase is a
fact the daemon has and a log line is a sentence somebody has to parse back into
one. The wire carries the fact.

### 4.2 `CatalogStartup` — the merge

One `ChangeNotifier` that both lanes report into, because the person waiting is
waiting for one thing. It answers three questions and no others:

- **what is happening**, in the daemon's or the harness's own words
- **how long it has been happening**, in seconds, climbing
- **how much of it is left**, where a count exists — which is the render pass
  and nothing else. A compile has no denominator and must not be given a fake
  one.

The tester lane needs no new channel: `TesterHost.onLog` already narrates
*"compiling the harness"* before and *"compiled the harness in Nms"* after,
written precisely because *"the panel shows the last line the host said, and a
silent one reads as a hung one"*.

**This is the piece scenarios takes.** A scenario run comes up through the same
`TesterHost` and waits the same wait for the same reason. `CatalogStartup` lives
in `app/lib/src/ui/` as a lane-agnostic model with a widget over it, and the
previews landing and the scenarios panel each mount one.

### 4.3 The strip

Pinned under the top bar, above the sheet — not over it. Covering the page while
the page fills in is the one arrangement that makes the filling invisible.

It carries the phase, the seconds, and a bar: determinate for the render pass,
indeterminate for a compile. It **retires itself** when the last tile lands,
because a progress surface that outlives its progress is a permanent bar of
chrome.

### 4.4 Skeleton tiles

A shimmer on a pending tile, and the no-spinner rule survives intact: a shimmer
is a surface treatment, not a control, so a hundred and fifty of them read as
one page loading where a hundred and fifty spinners read as a hundred and fifty
problems.

The store already tells the two waits apart —
`ThumbnailPending(compiling: bool)`, whose comment is *"a cold harness compiles
the whole catalog and takes tens of seconds, where a warm one is a message and a
frame. A caption that said 'rendering' for both would be a lie for one of
them."* Compiling shimmers; queued is a flat tone, because it is seconds away.

**One ticker, and this is the trap to write down before anybody opens the
file.** A hundred and fifty `AnimationController`s is a hundred and fifty
tickers, on the frames where the thing being waited for is a compiler that wants
every core. One controller at the sheet, read through an `InheritedNotifier`,
stopped the moment nothing is pending.

### 4.5 The tile being rendered now

`_pump` knows which entry it is on and tells nobody. Marking it is the single
most reassuring thing a filling grid can do: the page visibly walks down itself,
and the rendering order stops being a claim in a doc comment.

### 4.6 Why was that slow

A popover off the status bar's `cold NNNNms`, rendering `timings` as it arrives
— plus **which seed was found and how many packages it held**, which is the one
fact section 5 shows is worth a line of its own.

This is the surface whose absence produced this document.

## 5. The compile side

### 5.1 The seed never upgraded — measured, and fixed

**Built 2026-08-27.** The measurements below are what it was and what it is.


`SeedStore.find` sorts the matching seeds largest-first and the store keeps
three (`seed_kernel.dart:105`), so a machine is built to hold, and prefer, the
biggest seed it has. Nothing ever writes a second one. Both lanes guard the
write on *"is there a seed at all"*:

- `compiler_daemon.dart:880` — `if (_seed == null)`
- `tester_host.dart:268` — `if (existing == null)`

**First writer wins, permanently, per (engine, flags).** A machine whose first
seed came from a small project serves that seed to every large one afterwards,
for ever, and the large one never leaves a better seed behind for the next
checkout.

The development machine was holding exactly one seed — 20 packages, 51.9MB,
written by the sample project's lane. Measured on this repo's catalog, three
cold starts an arm, output dill and warm kernel deleted before each:

| this repo's catalog, cold compile | ms |
|---|---|
| the 20-package seed a sample project left | **3578 / 3591 / 3665** |
| the 65-package seed it now leaves for itself | **1674 / 1598 / 1628** |
| no seed at all (2026-08-26 findings) | 6031 |

**~3.6s → ~1.6s, a 55% cut**, landing on the 1671ms the seed findings measured
for a properly sized seed. This was the *undershooting is worse than
overshooting* result arriving through the write side rather than the read side.

**The fix is the condition, not the machinery.** Ask on every start whether this
program would leave a better seed than the one it was given, rather than only
when it was given none.

*What the condition is not.* A **strict superset** was built first and is wrong,
and only a measurement showed it: this catalog reaches **62** packages against
the seed's 20 — and **3 of those 20 it never reaches**, because a sample app
uses localisations and an http client that a widget gallery does not. The rule
declined the exact case it was written for. Two programs sharing one workspace
normally overlap without either containing the other; nesting is the exception.

So the rule is the one `SeedStore.find` already reads by — **more packages
wins** — because a write rule stricter than the read rule leaves seeds nothing
will ever produce. Three properties make that safe, and all three are tested:

- Nothing is displaced. A seed is named by its manifest hash, so a grown one
  lands *beside* the one it grew from and the smaller project still finds its
  own while the resolution validates it. `keep: 3` is still the budget.
- Growth is monotone, so two projects cannot take turns: whoever reaches more
  writes, and the one reaching less is handed the bigger seed and has nothing to
  write.
- The decision is taken from a cheap estimate — a walk of `compiler.sources`
  with no file reads — and confirmed against the exact artifact
  (`SeedStore.holds`) before anything is compiled. An estimate that came out a
  package high costs one lookup, not an excursion on every start.

*What it costs, measured on the same runs.* The start that grows the seed pays
**810ms** once, for 2630 shared libraries across 65 packages — the ~800ms the
seed findings predicted. Every start after it pays **11ms** to decide there is
nothing to do. And the reach is stable at the fixed point: the start after the
growth reports reaching 65 against a seed of 65 and writes nothing.

### 5.2 What is **not** evidence about the slow machine

The 60s was on another machine. Everything measured on the development machine
is therefore about the development machine, and is recorded here so nobody
mistakes it for the diagnosis:

- 13.6 GB of 15.3 GB swap in use.
- **19 orphaned `flutter_tester` processes**, `ppid` 1, the oldest up **1 day
  23 hours**, on assets directories belonging to worktrees whose GUI was long
  gone. Duplicates *per assets directory* are the tell: one host holds one
  guest, so three live testers on one `previews_assets` is two orphans.
  Corrected from a first reading of the same `ps` output: the 9 testers under
  one live Studio are **not** a leak — they are one guest each for previews on
  two packages, scenarios, and a feature branch's own harness. And every
  `frontend_server` on the machine had a live parent; none had leaked. Owner
  death is the mechanism, not in-process duplication.
- `~/.flutterware` at 49 GB; one worktree's `app/build/catalog` at 1.7 GB across
  14 address directories created in a single evening.

The **mechanisms** are code, so they hold on any machine: a `TesterHost` leaks
its guest, and an address change orphans ~280MB of `out/` and `assets/`. The
**quantities** are local and prove nothing about the slow start.

### 5.3 What to ask the slow machine

The daemon writes its phases to `~/.flutterware/run/<key>.log`, and the seed
store is one directory listing. Two commands, no instrumentation, and they
answer whether that 60s was the seed, the two lanes, or the machine:

```sh
grep -hE '^\[(catalog|compiler)\]' ~/.flutterware/run/*.log | tail -40
```

```sh
ls -la ~/.flutterware/kernels/*/ && sysctl vm.swapusage && pgrep -fl flutter_tester | wc -l
```

What each answer means:

- `warm kernel: none` **and** `seed kernel: none` — a genuinely unseeded cold
  compile, which on a consumer resolution measured 14830–14984ms in the
  2026-08-26 findings. Two lanes doing that concurrently is a 60s start with no
  regression required beyond #261.
- `seed kernel: <path> (N packages)` where N is small — section 5.1, on that
  machine. Since 2026-08-27 the daemon says this itself, on every start:
  *"the seed this start used holds N packages; this program reaches M, of which
  K are not in it"*. M far above N is the stunted seed, and the next start
  after the upgrade fixes it and says `reseeded`.
- Neither, and a healthy swap figure — then the two lanes contend, and section 6
  is the whole answer.

Note that the upgrade itself costs one cold start on every machine and is not a
bug: `kernelKey` moved in #272, so the first daemon after it inherits no warm
kernel. Once.

### 5.4 The leaks — built 2026-08-27

**`TesterHost.dispose` already killed its guest, and always did.** What it
cannot cover is the owner dying before it gets there — every crash, every
`kill -9`, every window closed the quick way — and no in-process hook ever
will. So the cure is a handle and a sweep: a guest announces itself in
`guest-<pid>.json` on spawn, withdraws on exit, and the next process to bring a
harness up kills whatever is left whose owner is not coming back.

Two rules decide *whose* guest a handle names, and both are about not killing a
live one:

- **The owner is gone**, by `isProcessCurrent` rather than `isProcessAlive`: a
  handle outlives a pid's recycling, and believing the new occupant would shield
  an orphan for ever.
- **The owner is this process, from before it restarted.** A hot restart
  replaces the isolate and keeps the process, so `dispose` never runs and the
  new incarnation spawns beside the old guests. An in-memory set of this
  incarnation's own pids is what stops that rule reaching a guest still in use.

One race was closed with it. A cold start is tens of seconds of awaits, so a
`dispose` — a config reload swapping the plugin graph — could land after
teardown had killed a guest that did not exist yet; the spawn then completed
into a host nobody would tear down again. `_spawnGuest` now checks after the
spawn, which is the only step that leaves something behind.

`ResourceCleanerService` is deleted. It was written for exactly this job, was
initialised on every GUI start, and **nothing ever registered a pid with it** —
so it swept an always-empty directory, at a relative path, with no owner or
start-time check. Two mechanisms for one job is how the second one rots.

**Abandoned build directories** go on the same trigger, from the daemon that
made them. A directory is named by the address, and an address hashes the whole
config, so every change to what the daemon is given orphans one whole — the
Impeller flags did it to every project on every machine at once. Measured on one
worktree: **3.6 GB across 30 directories**, all but one dead.

The gate that took a correction: **a socket is tested by existence, never by a
knock.** `_answers` gives up after a second, and a second is a duration a live
daemon can miss under load — three integration files running at once and 3.6 GB
being deleted was enough, and the daemon whose `out/` went with it died on its
next write with a broken pipe. For a socket *file* a false negative costs a
relink; here it costs a running daemon. `sweepRunDir` unlinks the sockets of
daemons that are really gone, so nothing is lost: a directory is reclaimed one
start later rather than this one.

Verified end to end: three provably dead directories backdated past the age
gate, a real daemon started, `dropped 3 abandoned build directories` in its log
and the three gone.

**What this does not do is clean up the orphans already out there.** They
predate the handles, so nothing records them; they have to be killed by hand
once.

### 5.5 A picture that outlived its rasterizer

`ThumbnailKeys` names a picture by its import closure, the pixel inputs, the SDK
root, and `{format, longest}`. **Not the rasterizer.** #270 moved both lanes to
Impeller, so every cached thumbnail and every cached comparison shot is still
served from the Skia era, from a store that is content-addressed and shared
across worktrees.

That PR's *"a project gets one noisy comparison and then quiet ones"* assumes the
base side re-renders. It does not: it is served from the cache, under a key that
did not move. Putting the rasterizer in `extra` is correct and costs one
re-render of every catalog on every machine — which is why it is called out
separately here rather than folded into the work above.

## 6. What must be measured before it is decided

**Should the guest lane wait?** While the catalog page is up and nothing is
selected, warming the guest is work for a click nobody has made, competing with
the lane that draws what the person is actually looking at. Deferring it might
halve a first open, or might only move 12.5s to the first click. The comment at
`catalog_view.dart:519` argues for warming and was right when opening the panel
meant opening a demo; the landing changed the premise, not the argument.

Measure: first open to last tile, with the guest lane deferred and not, on this
repo's 159 entries and on a consumer resolution.

**And there is now a second argument for deferring, which is memory.** Measured
2026-08-27: an idle `frontend_server` is **~21 MB**, and one actively compiling
peaks at **~1.2 GB** — seeded or not, identically, because the seed saves the
*work* of building the shared half and not the memory of holding it. So the
footprint of this system is not its resident state, it is the number of compiles
running at the same instant.

A first open is two of them. Three worktrees opened together is six, ~7 GB, and
**nothing anywhere bounds that number** — not per worktree, not per machine. On
this 64 GB machine it disappears; on a 16 GB laptop it is a swap storm, and the
report this document opens with came from a machine nobody has measured.

What is bounded, and stays bounded: the seed store trims itself to
`SeedStore.keep` on every `find` — verified, 5 seeds and 527 MB back down to 3
and 229 MB — and `find` rejects a seed holding a package this resolution does
not have, so seeds do not ratchet across unrelated projects. Two programs in one
workspace converge instead: measured, a program reaching 62 packages served by a
74-package seed writes nothing, because everything it reaches is already in
there.

## 7. Order

Sections 5.1 and 5.4 are small, independent of the UI, and are the only items
with a measured saving attached. They go first for that reason and no other.

1. ~~**The seed condition** (5.1)~~ — **built 2026-08-27**, 3.6s → 1.6s.
2. ~~**The leaks** (5.4)~~ — **built 2026-08-27**.
3. ~~**`DaemonProgress` + the merged model + the strip** (4.1–4.3)~~ — **built
   2026-08-27**, scenarios included.
4. ~~**Skeleton tiles and the rendering mark** (4.4–4.5)~~ — **built
   2026-08-27**.
5. ~~**Why was that slow** (4.6)~~ — **built 2026-08-27**, and it reports two
   facts §4.6 did not ask for: whether the compiler started from a warm kernel,
   and whether this client attached to a daemon somebody else had already paid
   for. Without the second, the table is a list of another session's phases
   presented as this one's.
6. **The two-lane measurement** (6), and whatever it decides.
7. **The rasterizer in the key** (5.5), on its own, because it invalidates every
   store.

## 8. Not proposed

- **A spinner per tile.** Settled, and settled correctly.
- **A modal compilation dialog.** The catalog page is the thing being waited
  for; covering it to report on itself is the arrangement in 4.3 that makes the
  filling invisible.
- **A fake denominator on the compile.** A bar that fills at a rate nobody
  measured is a bar that lies, and the seconds counter already does the one job
  — slow from hung — that the bar would be pretending to do.
- **Tailing the daemon log for progress** (4.1).
- **Anything from the 2026-08-26 findings' rejected list**: `package:kernel`
  path rewriting, and seeds built from the whole resolution. Both measured dead
  ends.
