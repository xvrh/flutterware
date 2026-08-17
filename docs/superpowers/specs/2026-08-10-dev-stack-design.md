# The dev stack plugin — a delegated lifecycle, and how generic it really is

**Date:** 2026-08-10
**Status:** **`DevStack.background` is built** — see "What shipped" at the end.
The rest is design. "What is true today" is read off the code and from four
`fw capture` screenshots of the running shell; timings are measured and
reproducible. Everything under "Proposals" is direction for review.
**Supersedes:** the tasks-and-stack draft of the same date. The tasks plugin is
deferred — see §0 — and the document is now about the one plugin that survived.
**Anonymised:** the motivating case is a team's private monorepo, referred to
throughout as *the reference project*. Its stack CLI is called `stack.dart`
here; nothing about the design depends on either name.
**Reads against:** `2026-05-18-worktree-explorer-plugins-design.md` (the
`DockerStack` sketch this makes v1-shaped), `2026-07-25-overhaul-master-plan.md`
(decisions 4, 5, 6), `2026-08-10-worktree-explorer-view-design.md`.

---

## 0. What the task runner turned out to be worth, and why it is deferred

An earlier draft proposed a declarative task runner, absorbing the tools, CI
and test-command screens of the reference project's in-house dev app — 50 declared scripts, categories, typed arguments, a
secret store. It is **deferred indefinitely**, on evidence that came from
looking at what those 50 scripts now are:

- `format` is not something a person runs; it is a git hook.
- `distribute_app` runs in CI. Nobody triggers a store upload from a desktop
  panel.
- Translations moved into the repo and are handled by an agent skill.

The general observation behind those three, and the one worth keeping:

> **A panel that runs scripts is a panel built for a person who runs scripts.**
> That was the daily reality when the reference project's dev app was written.
> It is much less so now — an agent runs the script, and it wants a command and
> an exit code, not a form and a log pane.

`fw run <plugin> <action>` and MCP already give an agent every action a plugin
declares. A browsable grid of fifty scripts adds discovery for a human who has
largely stopped browsing.

**What survives, and where.** A handful of commands *attached to a thing that
has state* keeps its value — `logs`, `restart`, `recreate` on a stack that is
currently up. That is contextual, it is few, and it is bound to something you
are already looking at. So the task idea is not deferred so much as **absorbed
into §3's `commands:` list**, in the only form that was carrying its weight.

**Kept for the record, because it is reusable:** the UI finding from the
withdrawn draft. Previews already implements the sidebar-children → filterable
tree column → detail → bottom drawer layout, and anything in this app that ever
needs to browse hundreds of grouped items should reuse it rather than invent a
second one. Cards, specifically, are the wrong container — the equivalent card
in the reference project's dev app is 538 lines, which is what a card looks like
once it has grown a form, a log stream, a status and an env editor.

---

## 1. Why the stack is not three tasks

> **A task is a verb with an exit code. A stack is a noun with a state.**
> You poll a noun. You do not poll a verb.

Three consequences, each of which three side-by-side buttons cannot express:

1. **There are four states, not two.** `docker compose up --wait` takes tens of
   seconds. The control has to say `down` → `bringing up…` → `up` →
   `tearing down…`. A task has no state that persists between invocations, which
   is exactly what a stack is.
2. **Only one of up/down is ever right.** Two buttons of which one is always
   wrong is a UI you have to read before you click.
3. **`down` is a teardown step, not a button.** Closing a worktree that left a
   stack up is what `TeardownPhase.infra` exists for — its doc comment already
   uses "3 containers, 2 named volumes" as the example detail.

## 2. It delegates. It does not supervise.

- **A supervisor** owns the process, holds the pid, captures the logs, restarts
  it. That is what the reference project's dev app does, and it loses all of it
  on every GUI restart.
- **A delegated lifecycle** owns *nothing*. It polls a status command, renders
  one control, and hands every verb to the project's own CLI.

The project's own `tool/stack.dart` stays the authority — it allocates per-worktree
port blocks, writes `.env`, and knows things flutterware never will. flutterware
contributes a poll, one control, and a teardown step.

```dart
fw.use(DevStack.background(
  label: 'Dev stack',
  workingDirectory: 'packages/server',
  probe:  Probe(['dart', 'run', 'tool/stack.dart', 'doctor', '--json']),
  start:  ['dart', 'run', 'tool/stack.dart', 'up'],
  stop:   ['dart', 'run', 'tool/stack.dart', 'down'],
  stopIsDestructive: true,           // `down --volumes` wipes the DB
  poll: Duration(seconds: 10),       // the plugin owns the timescale — §5
  teardown: TeardownPhase.infra,
  commands: [
    Command('logs',     'Logs',     ['…', 'logs'],     streams: true),
    Command('restart',  'Restart',  ['…', 'restart'],  argument: 'service'),
    Command('recreate', 'Recreate', ['…', 'recreate'], argument: 'service'),
    Command('open',     'Open',     ['…', 'open'],     argument: 'surface'),
  ],
));
```

---

## 3. Is it generic? — evaluated against four real stacks

The ask was to check rather than assert. So: write the declaration for four
stacks nobody here uses, and see what breaks.

### It holds for daemon-backed stacks

**Supabase local.** `supabase status --output json` / `start` / `stop`.

```dart
DevStack.background(label: 'Supabase',
  probe: Probe(['supabase', 'status', '--output', 'json']),
  start: ['supabase', 'start'], stop: ['supabase', 'stop'],
  commands: [Command('reset', 'Reset database', ['supabase', 'db', 'reset'], danger: true)]);
```

**Plain docker compose, no wrapper.**

```dart
DevStack.background(label: 'Services', workingDirectory: 'docker',
  probe: Probe(['docker', 'compose', 'ps', '--format', 'json'], shape: ProbeShape.composePs),
  start: ['docker', 'compose', 'up', '-d', '--wait'],
  stop:  ['docker', 'compose', 'down', '--volumes'], stopIsDestructive: true);
```

**minikube.** `minikube status -o json` / `start` / `stop`. Identical shape.

Four fields and a command list cover all three. Nothing about the class is
docker-specific — it is *"a long-lived external thing whose lifecycle is
delegated to project commands and whose state is polled."*

### The second shape: foreground stacks

**Firebase emulator suite.** `firebase emulators:start` runs in the foreground
and you stop it with Ctrl-C. There is no `stop` command, no `status` command,
and `start` never returns. The declaration above cannot be written at all.

The same is true of `tilt up`, `devenv up`, `nix develop`, `ngrok http`,
`cloudflared tunnel run`. Sampling what people actually run for local backing
services, it splits close to evenly:

| Shape | Examples | Who owns the process |
|---|---|---|
| **Daemon-backed** — `start` returns, `status` answers, `stop` exists | docker compose, supabase, minikube, kind, colima, brew services, a project's own stack CLI | the project's CLI |
| **Foreground** — you Ctrl-C it; no status command | firebase emulators, tilt, devenv, ngrok, cloudflared | nobody, until we do |

So the API grows a second constructor, and the discriminator is *who owns the
process*:

```dart
// what the reference project declares
DevStack.background(
  probe: Probe(['dart', 'run', 'tool/stack.dart', 'doctor', '--json']),
  start: ['dart', 'run', 'tool/stack.dart', 'up'],
  stop:  ['dart', 'run', 'tool/stack.dart', 'down'],
);

// what a firebase project would declare
DevStack.foreground(
  start: ['firebase', 'emulators:start'],
  ready: Ready.port(4000, timeout: Duration(seconds: 90)),
  stop:  Stop.signals(),   // SIGINT → SIGTERM → SIGKILL, to the process group
);
```

`background` / `foreground` is the right pair of words even though what they
encode is process ownership, because it is the question a config author can
answer without knowing anything about flutterware: *does `X up` return, or do I
have to leave the terminal open?*

**Both produce the same five states, the same report, the same panel and the
same teardown step.** Only the source of the state differs:

| | `background` | `foreground` |
|---|---|---|
| owns the process | the project's CLI | flutterware, detached |
| liveness | the probe command | the pid is alive |
| readiness | the probe command | `Ready` — §3.2 |
| stop | the `stop` command | signal escalation to the group |
| extra `commands:` | spawn a new process | **identical** |

**Free third mode:** a `background` declaration that omits `start` and `stop` is
observe-only — a shared team server, a system postgres, anything you neither
start nor stop. It needs no constructor of its own; it falls out.

### 3.1 The process mechanics are solved, and measured

Foreground sounds like the supervisor that was rejected in §2. It is not, and
three measurements on this machine say why.

**Detached launch already exists and is not Flutter-specific.**
`app/lib/src/run/launch.dart` starts a detached child with output redirected to
a log file and a handle written to the run dir. The only Flutter in that
function is the contents of `command`.

**A detached tree shares one process group.** Probed with
`ProcessStartMode.detached` running a shell that backgrounds a child and then
`exec`s another:

```
  PID  PPID  PGID  COMMAND
15254     1 15253  sleep 300      ← the pid Dart reports
15255 15254 15253  sleep 300      ← its grandchild, same group
```

`PPID 1` confirms detachment, and both processes sit in group `15253`. Note the
pid Dart hands back is **not** the group leader — the pgid has to be read back
with `ps -o pgid= -p <pid>`.

**A group signal reaps the whole tree.** `kill -TERM -15421` took the group from
2 processes to 0. So `firebase`'s java children, `tilt`'s helpers and anything
else the tool spawned are signalled, not orphaned. `Process.killPid` cannot
address a group, so this is a `kill` invocation — about twenty lines including
the escalation ladder.

### 3.2 Where the pain actually is — two things, and one to cut

**1. Readiness has no general answer.** A background stack has a command you can
ask. A foreground one has nobody to ask, and "the pid is alive" is a lie —
`firebase emulators:start` is alive for twenty seconds before anything listens.
Three mechanisms, none universal:

- `Ready.port(n)` — best when there is one. Firebase opens five ports at
  different moments, so *which* port means ready is a per-project judgement.
- `Ready.logLine(RegExp(…))` — works for everything and is **brittle by
  construction**. A minor version bump changes `✔  All emulators ready!` and the
  panel sits at `bringing up…` forever.
- `Ready.processAlive()` — honest only for tools with nothing to wait for.

Mitigation, and it is a real one: **`timeout:` is required, not optional.** On
expiry the state becomes `up, never reported ready` rather than spinning — which
is actionable, whereas an indefinite spinner is not.

**2. Stop reliability is a property of the tool, and this codebase already
learned that.** `run_core.dart:1370` carries the lesson in a comment:

> "The app first, then its launcher. The other order leaves an orphaned app
> running on the phone with nothing able to reload it, which is the worst of
> both."

Run stops an app by asking it nicely over `ext.flutter.exit` **and then**
signalling the launcher, because the signal alone was not enough. A foreground
stack has no equivalent of `ext.flutter.exit` — there is nothing to ask nicely,
so you get only the half Run found insufficient. Group-signalling recovers most
of it, but whether a tool releases its ports and cleans its state on SIGTERM is
the tool's business. The failure mode when it does not is nasty and recurring:
orphans holding 8080/9099, and the next `start` failing `EADDRINUSE` with no
explanation.

Partial mitigation: an optional `orphans:` probe run before `start`, so the
error is "port 9099 is held by pid 4122, left by a previous run" rather than a
raw bind failure.

**3. "An API to send commands" should be cut, because it contradicts the
launch.** Detached-so-it-outlives-the-GUI means stdin went to `/dev/null`; you
cannot hold a pipe to a process that survives you. `flutter run` escapes this
with `--machine`, a JSON protocol — which requires the *tool* to have one.
Firebase has none. Tilt exposes HTTP on :10350, ngrok on :4040 — both per-tool,
and both already reachable as ordinary `commands:` that spawn a new process.

So there is no stdin API in either variant, and `commands:` means the same thing
in both. That is not a limitation worked around; it is the answer both variants
already had.

### 3.3 Verdict — not a world of pain, but do not build it yet

The mechanics are measured and bounded: ~20 lines of signal handling over a
launcher that already exists, one new `Ready` concept, and no new panel, report
or state machine. It is perhaps 250 lines beyond the background variant.

**But nothing here needs it.** The reference project has no foreground stack, and building the
second variant now would be designing against a hypothetical — with the one part
that cannot be got right in the abstract (readiness) chosen without a real tool
to check it against.

**So: name the constructor now, build one of them.** Ship
`DevStack.background(...)` as a *named* constructor rather than the unnamed one,
so `.foreground(...)` lands later as an addition rather than a rename. That is
one keyword of insurance today against a breaking change later, and it puts the
boundary in the API where a config author meets it, rather than in a doc comment
they will not read.

## 4. Narrow first-party class, or the real plugin system?

The alternative on the table: skip the tailored class and build the declarative
tier — a rich API so a project writes this plugin itself.

### What the tier actually costs

Not a judgement — a reading of what `2026-05-18` and the master plan say it is:

- The per-worktree config process becomes **long-lived and source-hosting**.
  Today it is a short-lived manifest emitter (master-plan decision 5 is explicit
  that this changes only when the tier lands).
- `frontend_server` / resident-compiler config compilation, hot-swap, and a
  per-worktree config-process pool — every one of which master-plan decision 4
  rules out for v1 by name.
- The source algebra: `poll` / `watch` / `sessions` / `channel`, `combine`,
  `map`, `where`, self-gating polls.
- Demand-driven execution with two subscription levels, negotiated over the
  daemon RPC, so a source runs iff something is displaying it.
- The declarative panel kit — ~17 widget types, a GUI-side interpreter, forms,
  log streams — plus serialising the tree and re-emitting it on source updates.

That is a milestone, not a feature.

### The argument that decides it

With the task runner deferred, **the tier would have exactly one consumer.**
Building a general extension mechanism for a population of one is how you get an
abstraction shaped like its only example — which is the failure mode the tier
exists to avoid.

The inverse risk is real and should be named: shipping first-party classes for
project-specific needs is a slope, and flutterware must not grow a class per
customer. Three things keep this one off that slope:

1. **The subject is near-universal.** "Bring up the backing services my app
   talks to" is not one project's quirk; §3 wrote the declaration for three other
   stacks without touching the class.
2. **The config is the API.** Nothing here needs project *code* — a probe, two
   transitions, a command list and a teardown phase fully describe a delegated
   lifecycle. There is no branching a project would want to express.
3. **It is held to the declarative shape deliberately.** No logic in the class
   that a declarative author could not write. Which makes it the best available
   specification for the tier: **if v2's kit cannot reproduce this class
   exactly, the kit is not finished.**

### Recommendation

**Ship the class. Do not build the tier for this.** Build the tier when three
independent things want it — and treat this class as the first of those three
having been written down in advance, not as the reason to skip it.

The one thing to protect against: a narrow class *removes the pressure* to build
the tier. The mitigation is point 3 above, and it is worth an explicit test in
the repo — a comment or a doc that says which parts of this class are the v2
contract.

---

## 5. Naming

`DevStack` was flagged as more docker-flavoured than the thing is. Three
candidates:

| Name | For | Against |
|---|---|---|
| **`DevStack`** | Standard vocabulary — "the dev stack" is what people already call this. **`Dev` is a safety word**: it scopes the thing to local development, and a plugin that can `stop --volumes` should say in its own name that it is not pointed at anything real | "Stack" leans container-ish, though it is not actually docker-specific |
| `BackingServices` | Twelve-factor's own term, and exactly right — these are the services the app is backed by | Long, dull, and reads like a category rather than a thing |
| `Infra` | Matches `TeardownPhase.infra` in the existing contract, so the phase and the plugin share a word | Reads cloud-y; someone will eventually point it at a real environment, which is the failure the `Dev` prefix prevents |

**Recommendation: keep `DevStack`**, for the safety argument rather than the
familiarity one. If the container connotation is the sticking point, the closest
alternative that keeps the safety prefix is `DevServices`.

---

## 6. Polling — per worktree, at the plugin's declared interval

### The numbers

Measured on this machine, 2026-08-10:

```
docker version                     0.24s
docker compose ls --format json    0.32s
docker ps --format json            0.12s
```

A status probe is a few hundred milliseconds of subprocess. At `2026-05-18`'s
sketched `every: 5.s`, that is a subprocess running ~6 % of the time, forever.

### A withdrawn proposal: one probe for all worktrees

An earlier draft made the prober **workspace-scoped**, since
`stack list --json` reports every worktree's assignment in one call. That is
wrong, and worth recording because the efficiency is tempting enough to be
proposed again:

> **Config is per worktree and is allowed to diverge.** A shared prober bakes a
> cross-worktree assumption into a per-worktree declaration.

B is a different checkout at a different commit. Its `stack.dart` may take
different flags, emit a different shape, live elsewhere, or not exist. A prober
running A's command and handing the result to B's plugin reports B's stack
*through a config B does not have* — and it keeps working right up until someone
edits `stack.dart` on a branch, at which point the panel lies rather than fails.

The efficiency does not survive the mechanism either: `workingDirectory` is
worktree-relative, so A runs in `A/packages/server` and B in `B/packages/server`.
Different processes by construction; there was never a subprocess to save.

**One probe per open worktree, from its own declaration, in its own checkout.**
The probe is therefore `doctor` — *this* worktree's stack — not `list`.

### The explorer column, consequently

It cannot be fed by a shared probe, and it cannot cover closed worktrees at all:
a closed worktree has no config process. The explorer design already answers
this — §1, *"Plugin-contributed cells layer on top, and in v1 only for open
worktrees."* So the column reads `up · 8200` for open checkouts and `—` for the
rest. Making it work for closed ones would need a **shell-owned** probe, and
there is nowhere honest to declare one.

### The plugin owns the timescale; the shell owns the gating

- **How fast does this change?** Only the plugin's subject knows. Declared:
  `poll: Duration(seconds: 10)`. Never guessed by the shell.
- **Should we poll right now?** Only the shell knows — window focus, panel
  visibility, which tabs are open.

So the shell applies a *multiplier*, not an interval:

| Shell state | Multiplier on the declared interval |
|---|---|
| Panel mounted and visible | ×1 |
| Worktree open, panel not showing | ×6 — enough to keep the sidebar's one word honest |
| Window unfocused | paused; one immediate probe on regaining focus |
| A start/stop just finished | one immediate probe, then ×0.2 until it settles |
| Nothing open | never |

`PluginCore.computeAll`'s budget already forbids spawning, so a cold `fw status`
reads nothing and says "not computed" — the ×0 case is the default.

---

## 7. One control, two actions

| | Shape | Verdict |
|---|---|---|
| (a) | Vary the declared action list by state — offer `start` when down, `stop` when up | **Rejected.** `fw actions` becomes a moving target, and an agent that listed actions a second ago gets a refusal it cannot tell from a typo |
| (b) | Declare both, always, idempotent; the **panel** renders one state-dependent control | **Recommended** |
| (c) | A `Lifecycle` concept in the contract with named transitions | **Deferred** — a concept for the declarative tier to earn on a second example |

(b) is master-plan decision 1 applied literally: the manifest is the source of
truth and renderers differ. It matches what a caller means — `fw run stack start`
means *ensure it is up*, and `stack up` is already idempotent. And it needs
**no contract change**, because a native panel is unrestricted Flutter.

`stop` carries `danger: true` and `confirm: true`.

### Five states, not four

The mockup surfaced one the prose had missed. A stack whose **prober** failed is
not a stack that is down: reporting `down` when Docker Desktop is asleep offers
a Bring-up button that cannot work. This is the distinction
`FactState.unavailable` already draws in the worktree explorer, and it should be
drawn here for the same reason.

| State | Status | Primary control |
|---|---|---|
| down | `○ down · slot 8200–8208 reserved` | **Bring up** |
| starting | `◐ bringing up… · the identity server can take 60s` | disabled |
| up | `● up · 4 containers · 12m` | **Tear down** (danger) |
| stopping | `◐ tearing down…` | disabled |
| unavailable | `✕ docker daemon not running` | **Retry**, + a way to fix the cause |

---

## 8. Where it goes on screen

Three complementary placements, settled against the captures:

1. **The sidebar row** — `Dev stack   up · 8200` in the same right-aligned slot
   Run uses for `4 devices…`. The one-word answer, at no navigational cost.
2. **The Overview screen** — the resting place. A worktree home currently holds
   a title, a path and two chips, and roughly 85 % of the window is empty.
   "Which port block does this checkout hold, is its stack up, since when" is a
   fact about *this worktree* in the strictest sense: it is allocated per
   worktree, by name.
3. **A panel** — the depth surface: per-service rows, the log stream,
   `recreate` / `prune`, the full `list` across worktrees.

The Overview block, in the shell's own label/value language:

```
explorer brainstorm
/Users/dev/worktrees/example/explorer-brainstorm-e5efdc
[ worktree ]  [ ⑂ claude/worktree-explorer-e5efdc ]

Dev stack   delegated to packages/server · tool/stack.dart
● up · slot 8200–8208 · 4 containers · 12m
  postgres 8200 · identity 8201 · sync 8202 · mail 8203

[ Tear down ]   wipes volumes — the next bring-up boots a fresh database
Logs   Restart ⌄   Recreate ⌄   Open ⌄   Doctor
```

`delegated to packages/server · tool/stack.dart` earns its line: it says who
is actually in charge, so nobody debugs flutterware when the stack misbehaves.

---

## 9. Teardown: the socket exists, nothing is plugged into it

The largest hidden cost, so: exactly what is built and what is not.

**Built.** `TeardownStep` (`phase`, `enabled`, `checked`, `detail`, `danger`),
`Guard` (`warn` / `block`), `PluginReport.teardown` and `.guards`,
`WorktreeSession.teardownSteps` assembling and sorting by phase,
`WorktreeSession.isBlocked`, and `ShellController.close()` refusing on a block.

**Not built.**

1. **No plugin emits a single step.** `grep 'teardown:' app/lib/src/plugins/native/`
   returns nothing. This would be the first.
2. **No checklist dialog.** `2026-05-18` specifies it in detail — grouped by
   plugin, `apps → infra → cleanup`, streaming stdout, pause on failure with
   Retry / Skip / Abort, removal gated on earlier steps not having quietly
   failed. None of it exists.
3. **No worktree-removal flow to hang it off.** `close()` closes a *tab*. The
   explorer puts "Remove worktree" in the row's `⋯` menu; that menu is unbuilt.
4. **Removing a *closed* worktree is an open question** in the explorer design:
   plugin guards need the worktree open, so removal either opens it first or
   runs with shell-owned guards only and says so.
5. **A freshness problem.** `TeardownStep`'s `enabled` / `checked` / `detail`
   are *values* here where `2026-05-18` had them as closures. Values are right —
   they serialise, so `fw` can print the checklist — but the dialog must force a
   refresh before opening, or it will offer to tear down a stack that died five
   minutes ago.

**Estimate.** Checklist dialog ~400 lines of shell, removal flow ~200, the
plugin itself ~350 core + ~250 panel. The dialog is shell work every future
plugin benefits from, not a cost of this one — but it is what stands between
here and "`stop` is integrated into the dispose system".

---

## Decisions this asks for

1. **The task runner is deferred indefinitely**, on the evidence in §0. Its
   surviving value is the `commands:` list on a stack.
2. `DevStack` as a **delegated** lifecycle plugin — flutterware owns no process;
   the project's CLI stays the authority. (§2)
3. **Ship the class; do not build the declarative tier for it.** One consumer is
   not a population. Hold the class to the declarative shape so it specifies the
   tier instead of deferring it. (§4)
4. **Ship `DevStack.background(...)` only, but name it now.** The foreground
   variant is measured, bounded (~250 lines) and not a supervisor — but nothing
   here needs one, and readiness is the part that cannot be designed without a
   real tool to check it against. Naming the constructor today makes
   `.foreground(...)` an addition rather than a rename. (§3.3)
5. `start` and `stop` stay declared and idempotent; only the **panel** renders
   one control. Five states, not four. (§7)
6. The prober is **per worktree**; the plugin declares the interval and the
   shell only multiplies it by visibility. (§6)
7. The teardown checklist dialog and a worktree-removal flow are accepted as
   **shell work that precedes** integration. (§9)
8. **Open:** the name. `DevStack` recommended, on the safety argument. (§5)

---

## What shipped (2026-08-10)

`DevStack.background(...)` is implemented, registered, and exercised end to end
against a real subprocess. 22 tests, `flutter analyze` clean, the app suite at
1970 passing.

| | |
|---|---|
| `lib/src/plugins/first_party.dart` | `DevStack.background`, `Probe.exitCode` / `Probe.json`, `StackCommand` |
| `app/lib/src/plugins/native/dev_stack_core.dart` | probe, cache, poll, transitions, actions, teardown step |
| `app/lib/src/plugins/native/dev_stack_results.dart` | `StackState`, `StackReading`, `StackService`, `DevStackRunResult` |
| `app/lib/src/dev_stack/stack_block.dart` | the state line and controls — **one widget, two homes** |
| `app/lib/src/plugins/native/dev_stack_plugin.dart` | the panel: the block plus the last command's output |
| `app/lib/src/shell/worktree_home.dart` | the block on the worktree home |

Verified against a stand-in stack: `fw run dev_stack status` reported `down`,
`start` returned `{"ok":true,…,"reading":{"state":"up"}}`, and the shell drew
`up · 4 containers · slot 8200-8208 · just now` on the worktree home with `up`
in the sidebar's status slot. The stand-in was then removed from
`tool/flutterware.dart` rather than committed: a fake stack in the real config
would poll a pointless subprocess for every flutterware developer.

### Decided while building, not before

**Efficiency on the worktree home — reference counting, not a `track()`.** The
other cores start work that runs until the worktree closes, which is right for a
file watch. This spawns a subprocess per interval, so `watch()` / `unwatch()` are
counted and the timer only runs while a surface is mounted. Two surfaces watch —
the home and the panel — and a navigation can mount one before releasing the
other, which is what the count is for. A worktree open in a background tab polls
nothing.

**What makes the home screen still cheap.** `computeAll` reads a cache file
(`stack-<hash>.json` in the run dir) and spawns nothing, so `fw status` and a
cold sidebar say something true immediately — a reading with an age, the same
bargain `RunCore` strikes with `devices.json`. The home screen's cost is one
subprocess per `poll` **while it is on screen**, and a project that declares no
stack sees exactly what it saw before.

**No badge when the stack is up.** The first build put a green dot on the tab
for `up`; seeing it on screen made the mistake obvious. A tab lit green every day
is a tab you stop reading — the failure the explorer design names about
`needsYou`. Down is not a badge either: a checkout you are not working in
*should* have its stack down. Only `unavailable` badges, because it is the one
state you cannot infer and cannot ignore.

**`_transition` is `async` so its refusal arrives through the future.** A method
whose type says `Future` and which throws synchronously is one a caller can only
guard by wrapping the call site *and* awaiting it. Caught by a test written
against the CLI's view rather than the panel's.

**The exit-code probe strips ANSI.** A health check writes for a terminal,
so its summary line arrives wrapped in colour codes that would otherwise land
verbatim in a 96-pixel sidebar slot.

### Not built, and deliberately

- **`DevStack.foreground`** — named in the API and documented, per §3.3.
- ~~The teardown checklist dialog.~~ **Built** — see below.
- **The explorer column.** Open-worktrees-only per §6, and gated on
  `WorktreeFacts` growing a fifth provider.

---

## The teardown checklist (2026-08-11)

Built, on the three decisions taken when the inventory was reviewed: the
supporting emitters land in the same pass, the dialog attaches to a **new
removal flow** rather than to tab-close, and removing a closed worktree **opens
it first**. 22 tests, analyze clean, the app suite at 1992.

| | |
|---|---|
| `lib/src/plugins/teardown.dart` | `TeardownStep.arguments`, and `id` documented as an action id |
| `app/lib/src/teardown/plan.dart` | assembly — shell guards + plugin guards + steps, phase-ordered |
| `app/lib/src/teardown/runner.dart` | runs the selection, then the removal, gated on it |
| `app/lib/src/teardown/remove_worktree.dart` | `git worktree remove`, `git branch -d` |
| `app/lib/src/teardown/dialog.dart` | checklist -> run, with Retry / Skip / Stop |
| `app/lib/src/plugins/native/run_core.dart` | one teardown step per running app |
| `app/lib/src/worktrees/explorer_row.dart`, `shell_view.dart` | the row menu and the flow behind it |
| `app/tool/catalog/demos/teardown_dialog.dart` | five previews, four of which open themselves |

### What made the contract executable

`TeardownStep` was pure data with no callback, so nothing said how a step
*runs*. It now says: **the step's id is an action id on the plugin that emitted
it.** That is the only executable meaning a serialisable contract can carry, it
costs nothing, and it buys the property everything else here already has — the
checklist runs exactly what `fw run <plugin> <action>` runs, so a teardown can
never reach a capability the CLI cannot.

`arguments` came with it, and earns its place on the run plugin: one step per
running app rather than one "stop 3 apps" row, so each names its device and says
how long it has been up, and one can be left running while the others go.

### The bug the preview caught

`report` is a computed getter — every plugin builds **fresh** `TeardownStep`
objects on each call. The first runner found a step's owner by scanning the
reports again and comparing with `identical`, which can never match, so every
plugin step would have failed with a refusal naming the wrong plugin. The unit
tests missed it because they run with `session: null`.

The fix is `PlannedStep`, which records the plugin id **at assembly time**. It
also closes a subtler version of the same hole: the report is genuinely rebuilt
between drawing the checklist and running it, because the stack polls while the
dialog is open.

### Judgements worth re-reading

- **Only the primary checkout blocks.** Uncommitted work warns; unpushed
  commits warn; a working agent warns. See "The block that had to go" below.
- **`--force` is passed exactly when the user was warned about uncommitted
  work**, and never otherwise. Both halves come from
  `TeardownPlan.uncommittedFiles`, so the dialog cannot promise a deletion that
  git then refuses. A checkout the plan believed clean is still unforced, which
  is what catches a file written while the dialog was open.
- **No answer to a failure is taken as abort.** A caller with no way to ask must
  not fall through to deleting the directory.
- **The checkout goes last and only if nothing failed.** A half-torn-down stack
  is recoverable; a deleted worktree is not.
- **A clean run closes the dialog; a failed one stays up.** The output is the
  only account of what happened.

### Still open

- `TeardownPhase.cleanup` has no emitter. The run-dir files were considered and
  dropped: `sweepRunDir` ages them out in a day, so a checkbox for them is a
  checkbox for something that already happens.
- `fw` cannot print or run a plan yet. `TeardownPlan` is pure Dart precisely so
  it can, but nothing calls it from the CLI.

### The block that had to go (2026-08-11)

The first version made uncommitted files a **blocking** guard, reasoning that
nothing should be able to destroy work no reflog can return. Reviewed and
reversed: it is now a warning, and the removal is forced past it.

The argument that settled it is about what the screen is *for*. The worktrees
anybody needs to remove are the abandoned ones, and an abandoned checkout has
junk in it almost by definition — so a block on dirty files refused precisely
the case the explorer exists to clean up, while the stale worktrees piled up.

Worse, the block and the no-`--force` rule reinforced each other into a dead
end: even with the guard downgraded, `git worktree remove` would have refused on
its own, so the dialog would have promised a deletion and then failed. The two
had to change together, which is why they now read from one number.

A refusal you route around by opening a terminal is not a safeguard. It is
friction that teaches people the dialog is not worth opening — and a cleanup
tool nobody opens protects nothing at all. What is left is a warning that names
the count, a removal row that repeats it in red directly above the button, and a
decision that belongs to the person looking at their own checkout.

---

## The example project declares one (2026-08-11)

The stand-in was pulled out of `tool/flutterware.dart` when the plugin shipped,
on the reasoning quoted above: *a fake stack in the real config would poll a
pointless subprocess for every flutterware developer*. That was right about the
fake and wrong about the config. It left the plugin as the only one here with no
worked example — the catalog previews script a subprocess, the tests script a
subprocess, and nothing anywhere showed what a project actually **writes**.

So the example project now declares a real one, and the reasoning survives
intact: the subprocess is no longer pointless, because the stack is real.

### The subject: the toy server, in the background

`examples/example/bin/example_server.dart` already existed for the
server-inspection panel, and it is exactly the shape `DevStack.background`
describes — a long-lived thing the app talks to locally, which somebody has to
remember to start. `examples/example/tool/stack.dart` is the project's own CLI
over it: `up`, `down`, `status --json`, `logs`, `hit <path>`. Nothing in it
knows flutterware exists.

That pairing is worth more than a demo of one plugin. Bring the stack up, press
**Send a request**, and the traffic lands in the Server panel — two plugins on
one subject, which is what the shell is for.

**The port is the authority, not the state file.** `status` decides by asking
`/health`, so a server started in a terminal and one started by the button read
identically — the property §2 claims for the whole design, now demonstrated
rather than asserted. The state file adds only what the port cannot say: which
pid to signal, and whether a refused connection means *not running* or *not
listening yet*.

**A JSON probe, for the state an exit code cannot reach.** Port 8080 occupied by
something that is not this server is `unavailable`, not `down` — the difference
between an honest error and a Bring-up button guaranteed to fail. Verified by
pointing `python3 -m http.server` at the port.

**A clock, not a liveness check.** There is no platform-independent way to ask
whether a pid is alive: Dart can send a signal but not the null signal, and
`kill -0` is not a thing on Windows. So a launched-but-silent server is
`starting` for 20 seconds and `down` after. `down` waits on the port instead,
because it is the one caller that knows it just sent a signal.

### Three things this found in the shipped code

**A JSON probe was parsing stdout *and* stderr.** `dart` announces
`Running build hooks...` on stderr, which made every probe unparseable — and
this is not a Dart quirk: docker writes deprecation warnings there, a wrapper's
`set -x` writes every line it runs. `Probe.json` asks the command for JSON *on
stdout*, so that is now what it reads; the failure message still quotes the
combined output, which is what keeps `Cannot connect to the Docker daemon.`
arriving intact. A probe that reads both is one that works for a fortnight and
then fails because a tool started mentioning something.

**A command with an argument was reachable from `fw`, from an agent, and from
nowhere in the GUI.** `DevStackBlock` leaves those out of its row of links on
purpose — a link is one click and there is nothing to click *with* — and its
comment sent them to "the panel that asks for it". The panel embeds the block
and asked nothing. Declaring `hit <path>` in the example is what surfaced it;
reading the code had not, because the comment described the intent and the
intent sounded right. The panel now renders one row per argument-taking command,
with the argument's declared name as the hint. The home screen still does not:
a field to fill in is not an answer to *is my stack up*.

**`dart` on PATH is not the project's `dart`.** The config emits
`Platform.resolvedExecutable`, because a config already runs under the SDK the
project is pinned to. The `dart` on this machine's PATH is two versions behind
and refuses the file outright — an absolute path in the manifest is ugly in the
panel and correct everywhere. Measured while there: `dart tool/stack.dart` is
245ms against `dart run`'s 696ms, and `run` is what emits the stderr line above.

### Declared twice, deliberately

`examples/example/tool/flutterware.dart` declares it for someone who opens that
directory as their project; the repo root declares the same stack with
`workingDirectory: 'examples/example'`, which is what that field is for and what
makes it visible in `main_dev` — the shell a flutterware developer actually
runs. One script, two configs, neither aware of the other.

---

## The interface was redrawn (2026-08-11)

Everything above is about what the plugin *is*. How it reads on screen is
`2026-08-11-dev-stack-ui-study.md`, written after looking at the shipped thing
and not liking it: a run-on state line, a destructive button as the loudest
control on the worktree overview, and a 100px sidebar slot being sent a
sentence. Ten findings, six rules, three directions, and what landed.

Two decisions there reach back into this document:

- **The status message is now a word.** `_statusFor` no longer appends the
  probe's detail — see §"P6" there. `up 3/4` is the only compound one, and it is
  derived from the services rather than written beside them.
- **A transition is clocked on the core** (`busySince`), not in the widget, so
  two surfaces watching one bring-up agree about how long it has been.

---

## The example probe was wrong (2026-08-14)

Reported by a consumer with a plain compose stack: the copy-paste declaration in
`DevStack`'s own doc comment used
`Probe.exitCode(['docker', 'compose', 'ps', '--quiet'])`, which **exits 0 with
empty output when nothing is running**. It succeeded at listing zero containers.
So the panel was green, the state was `up`, and the Bring-up button never
appeared — the block draws `Tear down` in its place for a stack it believes is
already running, which is exactly right for the state it was handed. Nothing in
the app was wrong;
`_read` maps zero to `up` exactly as designed and as tested. The defect was
entirely in the sentence people copy.

**Fixed in two places, because the trap is bigger than the example.** The
headline now declares the check that actually fails when the project is
stopped — `sh -c 'test -n "$(docker compose ps --quiet --status running)"'` —
and `Probe.exitCode` states the requirement on the *command* rather than only
the reading of it: the exit code must be about what the check found, not about
whether the tool ran. `docker ps`, `kubectl get pods` and `ls` fail the same way
and are named. The doc also now says that the command is spawned directly, which
nothing had said before: `$(…)` and pipes exist only if `sh -c` is in the list.

**A general lesson about the two shapes.** §"the honest floor" is right that
`Probe.exitCode` costs a project nothing *when it already has a health check*.
What the example did was reach for a command that was merely *about* the stack.
The floor is only honest for checks that already answer yes/no; everything else
is a script, and a script that is being written anyway should print JSON.

### `Probe.dockerCompose()` — asked for, not built

The same report suggested a first-party compose probe, on the grounds that every
consumer with a compose stack otherwise writes the same wrapper script. The
argument is real and the counter-arguments are the ones this document has
already taken:

- **It re-opens `ProbeShape.composePs`**, which §3's own draft proposed and the
  shipped design dropped for two shapes — "the honest floor and the useful
  ceiling". A third shape has to be a third thing the app parses, forever.
- **It encodes another project's CLI.** `--status`, `--format json` and what
  `ps` lists by default have all moved across compose versions. A first-party
  probe keyed to those flags is a heuristic about somebody else's release
  schedule, and it goes stale silently — the panel keeps drawing a state.
- **Nothing about `DevStack` is docker-specific** (§3), and the first member
  named after one tool is the one that decides the class is a docker plugin
  with escape hatches.

One report is not a population, which is decision 3's test. **Deferred, with the
evidence recorded here**: if a second and third consumer arrive writing the same
wrapper, the thing to build is not `Probe.dockerCompose()` but a way for a
project to *declare* the mapping from a lister's output to a state — which does
not name a vendor and does not go stale when compose changes a flag.

---

## What runs it, and how often (2026-08-17)

Two changes from a first integration report, plus one bug the second one exposed.

### `StackRun` — the four declaration sites stop naming an interpreter

`Probe`, `start`, `stop` and `StackCommand` each took a `List<String>` spawned
directly, which asks the config file to name an executable. `DefineSource.script`
refuses to do that, in writing, two hundred lines earlier in the same file:
*"a command would have to name an executable and no config file can know which
one."* Both halves of one package, opposite policies.

The evidence that this is not a style question is in this repository. Both
configs opened by computing `Platform.resolvedExecutable` into a `dart` variable
and prepending it to six commands, under ten lines of comment explaining why.
The consumer who reported it reached instead for `['fvm', 'dart', 'run', …]` — a
committed file naming a version manager, and worse than the workaround here in a
specific way: `fvm` has to be *found*. It lives at `~/.pub-cache/bin/fvm` on this
machine, which is in none of `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin` — so a GUI
started from the Dock rather than a terminal cannot spawn it, and the panel
reports `unavailable` every poll on a healthy stack.

So all four take a `StackRun`, which is either a `.command` naming an executable
the machine is expected to have, or a `.script` naming a Dart file in the project
and letting flutterware supply the SDK it is running under.

**A script's path is relative to `workingDirectory`, and it runs there.** This
diverges from `DefineSource.script`, which is worktree-root-relative, and the
divergence is deliberate: this plugin *has* a declared working directory, and the
natural reading of `tool/local_env.dart` is the one you get having cd'd into the
directory every other command of the stack already runs in.

**Spawned as `dart <path>`, not `dart run <path>`.** Measured here, from a
package with native-asset build hooks: 0.33s for `dart run` of
`void main(){print('hi');}` against 0.28s direct, and the gap is the hooks —
`dart run` re-resolves the graph and executes every hook in it, every time, while
the direct form runs none. So the gap grows with the project instead of staying
constant. The example project's config had already found this and written
`dart tool/stack.dart` by hand.

**Corrected 2026-08-17, and the correction matters more than the original
number.** This section first quoted **4.4s** for a `dart run` of a trivial
script in the reporting consumer's 16-package workspace, and attributed it to
the build hooks. It was not the hooks. Re-measured idle by the same consumer,
spawning the SDK binary the way `StackRun.script` now does:

| | trivial script | their real probe |
|---|---|---|
| `dart run <path>` | 0.33s | 0.70s |
| `dart <path>` | 0.30s | 0.58s |
| `fvm dart --version`, doing nothing | **4.3–7.7s** | |

The 4.4s was a version manager on a loaded machine. `dart <path>` buys ~0.12s
on a real probe, which is worth having and is not the headline. **The headline
is the other half of the same decision**: because a `StackRun.script` names a
Dart file rather than an executable, flutterware resolves the SDK itself and
spawns it directly, and never goes through `fvm` at all. That took their probe
from ~5s to 0.58s — an 8× win, and the reason a config file cannot be the thing
that names an interpreter.

The price is real and worth stating: build hooks do not run, so a script whose
imports need native assets built will not find them, and a stale
`package_config.json` is an error where `run` would have fixed it. Both are loud.
A script that genuinely needs hooks is a `.command`.

**Not adopted: `dart run --resident`.** It exists on the pinned SDK (undocumented
in `--help`) and is a real win on compile — 0.59s to 0.25s on a script with
dependencies — and, importantly, the resident compiler does its own incremental
staleness tracking, so it does not cost the caller the invalidation logic that
pre-compiling a binary would. But it **does not skip build hooks**: measured with
hooks present, `--resident` still prints them and still pays them — so it buys
back less of the `dart run` overhead than the direct form does, for more
machinery. It also spawns a long-lived compiler daemon on a port, which a plugin
whose whole posture is *it owns nothing* should not do implicitly. (This
paragraph used to rest its case on the 4.4s figure corrected above; the
correction removes an argument it did not need — `--resident` still pays the
hooks, and still leaves a daemon behind.)

### The interval a slow probe earns

`poll:` is now a floor rather than a promise: the effective interval is at least
four times the last probe's duration, so a probe never occupies more than a
quarter of it. A fast probe never reaches the multiplier, so the common case is
unchanged and free.

Only the last probe knows what a probe costs. The reporting consumer's honest
number for a 4.6s probe was 30s, which they had to write into `poll:` and then
justify in a comment — a fact about the tool's cost model, in a file where every
other line is a fact about the project. The declaration should say the timescale
the *subject* changes on, which is what the field's doc comment already claims it
is for.

Implemented as a one-shot timer re-armed after each probe rather than a
`Timer.periodic`, because the interval is not known until the probe it follows
has been timed — and because with a periodic timer the gap *between* probes
shrinks by however long each one took, which is backwards for a slow probe.

### Two probes could race, and a hung one was forever

`refresh()` guarded on `_busy` — a user-started transition — but not on whether a
probe was already out. At the shipped default a 4.6s probe on a 10s interval
never showed it; anything slower than its interval left two subprocesses both
writing `_reading`, and the panel showed whichever finished last.

A second caller now joins the probe in flight rather than starting one. Joining
rather than skipping is what keeps the `status` action honest: asked to go and
look while a poll is out, it returns *that* look rather than the cache it was
trying to refresh.

That guard makes a timeout necessary rather than merely tidy. Before it, a probe
that never returned leaked a process per interval; with it, the guard would hand
every later caller the same dead future and the panel would sit on one reading
for the rest of the session. So a probe that outlives three intervals (floored at
30s, because a project declaring a two-minute interval is describing something
slow) is adopted as `unavailable` naming the command.

**Done since, from the same report:** `stderr` is separated from `stdout` on
`DevStackRunResult` — both tailed, with the merged `output` kept because it is
what the panel draws and what a terminal wants — and commands have a timeout,
`DevStack.commandTimeout` defaulting to ten minutes with a per-`StackCommand`
override.

The timeout turned out to matter more than "the same hang the probe got
protected from" suggested. A transition in flight is what refuses the next one,
so a command that never returned did not fail by itself: it held `_busy` for the
rest of the session and every later `start`, `stop` and command was refused
against it. `logs --follow` declared as an ordinary command is exactly that, and
the reporting consumer had added `--no-follow --tail` to their own CLI to avoid
it — which a project whose `logs` is someone else's binary cannot do. **The
timeout bounds the wait, not the process**: nothing is killed, because a
`docker compose up` interrupted half way leaves a stack in a state nobody chose
and this plugin owns nothing. What ends is flutterware's claim.

**Still not done:** a streaming command kind, so `logs --follow` is *declarable*
rather than merely survivable (§the `logs` gap) — the timeout stops it wedging
the panel, but the output still only arrives when the wait gives up; and options
on `StackCommand.argument`, which `ActionParameter` already models. The variadic
case the same report raises — `recreate <svc> [<svc>…]` — is a third shape again
and not expressible at all.
