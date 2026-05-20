# Worktree Explorer + Plugin Model — design

**Date:** 2026-05-18
**Status:** Exploration / direction-setting. **Not a committed spec.** No code exists
yet for anything in this document.

This document captures a brainstorming session about turning flutterware into a
**worktree explorer**: a GUI with one tab per git worktree of a project, where
each tab is populated by **plugins** that observe the worktree and surface
status, actions, and panels. It is a continuation of — not a replacement for —
`2026-05-15-wrapper-tool-architecture.md`.

## Relationship to the existing roadmap

This is **sub-project 1** ("Central place + GUI shell") of the wrapper-tool
architecture, with the plugin model as its extensibility surface. It does not
replace Mechanism A (wrap the launch) or Mechanism B (app connects back) — it
*consumes* them. The locked decisions in the wrapper-tool doc still hold:
per-project daemon, per-worktree config processes, SQLite-as-bus, Unix-socket
RPC, the three-layer distribution model.

The framing shift from that doc: the GUI/plugin surface is now a thing worth
building as its own sub-project, and the existing flutterware tools become its
first plugins (see "First-party tools as native plugins").

## The plugin model — a reactive aggregator

A plugin is registered in a worktree's `config.dart` and is a **reactive
aggregator**: it composes one or more **sources**, reduces them to a **status**,
exposes **actions**, and renders a **panel**. It may also contribute a
**switcher badge**, a **tab label**, **teardown steps**, **guards**, and
**launch policy**.

The same plugin model covers all of: observing polled state, observing
wrap-point sessions, observing back-channel data, acting on the worktree, and
participating in launch policy. There is one mental model, not several.

## The plugin API — `extends Plugin`

A plugin is a **class that extends `Plugin`**. The reactive-aggregator kit —
`poll`, `watch`, `sessions`, `channel`, `status`, `action`, `panel`,
`teardown`, `guard`, `label`, `switcherBadge`, `onLaunch`, `peers` — are
**protected methods of the `Plugin` base class**, called from a single
`build()` override. Constructor parameters carry per-instance configuration;
`worktree`, `context`, and the daemon handle are inherited getters available
inside `build()`.

```dart
class DockerStack extends Plugin {
  DockerStack({required this.compose, String? label}) : super('docker', label: label);
  final String compose;

  @override
  void build() {
    final stack = poll(every: 5.s,
        () => sh('docker compose -f $compose ps --format json'));
    status(() => stack.value.isEmpty
        ? Status.down('stack down') : Status.up('${stack.value.length} up'));
    action('Up', () => sh('docker compose -f $compose up -d'));
    teardown('Stop & remove stack', danger: true,
        checked: () => stack.value.isNotEmpty,
        () => sh('docker compose -f $compose down --volumes'));
  }
}
```

`build()` runs once per worktree (each worktree has its own config process); it
is separate from the constructor so the framework can wire `worktree` / daemon
access before it runs. Sources are ordinary locals in `build()`, referenced by
the `status` / `action` / `panel` closures — the reactive graph is just closure
capture.

**Why a class, not a closure or a data record.** Three shapes were compared: a
closure builder (`fw.plugin('id', (p) {...})`), this subclass form, and a
pure-data record (`Plugin(sources: [...], actions: [...])`). The data record
loses naturally-captured source references, needs separate context injection,
and grows an unwieldy constructor — rejected. The closure form is fine for a
one-off but gives a published plugin no nameable, documentable type. The
subclass form is the closure body with `this` instead of `p`, plus a real type
— idiomatic for Flutter authors (`extends StatelessWidget` muscle memory),
discoverable via autocomplete, and publishable on pub.

**Inline sugar.** `fw.plugin('id', (builder) {...})` remains for quick one-off
plugins in `config.dart`. It is *not* a parallel mechanism — it constructs an
anonymous `Plugin` subclass whose `build()` is the closure body.

**Registration.** `config.dart` is mostly `fw.use(...)`; a plugin class can be
instantiated more than once:

```dart
import 'package:flutterware/plugins.dart';
import 'package:flutterware_plugin_docker/docker.dart';

void main() => Flutterware.configure((fw) {
  fw.use(TestRunner());                                  // native, first-party
  fw.use(FeatureFlags());                                // native, first-party
  fw.use(DockerStack(compose: 'docker/dev.yml', label: 'dev'));
  fw.use(DockerStack(compose: 'docker/e2e.yml', label: 'e2e'));  // same class, twice
  fw.plugin('quick-thing', (b) { /* … */ });             // inline sugar
});
```

Native plugins use the **same base class** — there is no separate `NativePlugin`
type. A native plugin's `build()` calls `nativePanel()` instead of
`panel((ui) => …)`; see "Two plugin tiers". The code sketches throughout this
document use this `extends Plugin` form.

## Sources — four types, author picks per data point

A plugin author chooses the mechanism per data point. The four source types:

| Source | Mechanism | Good for |
|---|---|---|
| `poll(every:…)` | active subprocess polling | docker stack, `flutter devices`, port probes — state nothing reports |
| `watch(path, glob:…)` | filesystem watch | files that change rarely & unpredictably — Claude session JSONL, lockfiles |
| `sessions(match:…)` | the SDK wrap point (Mechanism A) | `flutter run` / server lifecycle — PID, uptime, device-id, exit code, for free |
| `channel(name)` | the back-channel (Mechanism B) | live in-app data — HTTP logs, SQL queries, custom metrics |

Rule of thumb: do not poll for something a stronger mechanism already knows.
"Is the server up?" is a `sessions` source (the wrap point knows the PID
exactly), not a port poll. "Is the docker stack up?" *must* be a `poll` — a
hand-run `docker compose up` touches no mechanism.

### Source algebra

Sources compose; a plugin's `status` is a pure function of a small reactive
graph.

- `Source.combine(a, b, (x, y) => …)` — derive a source from others.
- `source.map(…)`, `source.where(…)`, `source.changes` — transform / event stream.
- `poll(when: () => other.value, …)` — a poll that gates itself on another
  source (the health check cannot run unless the server session is live).

```dart
class DartServer extends Plugin {
  DartServer({required this.entrypoint}) : super('server');
  final String entrypoint;

  @override
  void build() {
    final run    = sessions(match: 'dart run $entrypoint');
    final health = poll(every: 3.s, when: () => run.live,
                        () => http.get('localhost:8080/healthz'));
    final ready  = Source.combine(run, health, (r, h) => r.live && h.ok);
    status(() => switch ((run.live, ready.value)) {
      (false, _)    => Status.down('stopped'),
      (true, false) => Status.warn('starting…'),
      (true, true)  => Status.up('healthy · ${run.uptime}'),
    });
  }
}
```

## Demand-driven execution

A source is active **iff something is observing its output**. Polling does not
run "just in case". Two subscription levels, because there are two display
surfaces:

- **Status subscription** — lightweight. Drives the worktree-switcher dropdown
  icons (one aggregate glyph per worktree). Carries only the reduced `Status`.
- **Panel subscription** — full. Active while a worktree tab is open/focused;
  drives the panel kit.

The GUI tells the daemon (over the existing Unix-socket RPC) what it is
displaying right now; the daemon starts/stops config processes and individual
sources to match. Closing the GUI stops everything. A source may set
`background: true` to opt out of demand-gating, for the rare genuinely-always-on
case (a cross-worktree alert, the idle reaper).

## The declarative panel kit

`panel((ui) => …)` returns a tree from a **fixed widget vocabulary** the GUI
interprets — `column`, `row`, `statusRow`, `keyValue`, `table`, `list`,
`logStream`, `section`, `badge`, `button`, `iconButton`, `textField`, `qr`,
`group`, `divider`, `dialog`, `checklist`, `checkRow`. No project code runs in
the GUI process.

The kit is **interactive**, not read-only: rows carry `onTap`, buttons carry
`confirm:` and `danger:`, a `textField` can live-filter a `logStream`. Panels
reference source values; a source update re-emits the tree and the GUI
re-renders.

Actions can declare a **form** the GUI collects before the callback fires
(`f.choice`, `f.toggle`, `f.textField`).

This declarative model is the panel mechanism for **all plugins running in the
headless config process**. Native plugins (below) are the exception.

## Two plugin tiers — declarative vs native

The discriminator is **where the plugin's code runs**, which is set by **who
compiled it**.

### Declarative plugins

Run in the **headless per-worktree config process**. Their code is never in the
GUI binary, so they physically cannot draw Flutter widgets (Flutter widgets need
`dart:ui` / the engine; a headless Dart process cannot import
`package:flutter`). They get the declarative kit. This is every third-party /
community plugin and the project's own `config.dart` plugins (docker, git,
claude, …).

### Native plugins

Compiled **into the GUI binary itself**. They are real Flutter code, so they
render real widgets with no restriction. First-party only for v1.

A native plugin is **two artifacts linked by a string id**:

1. **A pure-Dart `Plugin` subclass** — no Flutter import, lives in
   `package:flutterware` so `config.dart` can reference it. Declares everything
   *uniform* (sources, status, badge, actions, teardown, guard) and calls
   `nativePanel()` to mark its panel `native`.
2. **The widget** — real Flutter, lives in `flutterware_app`, registered in a
   GUI-side map keyed by the same id.

```dart
// package:flutterware/plugins/test_runner.dart  —  pure Dart, NO flutter import
class TestRunner extends Plugin {
  TestRunner() : super('flutterware.test_runner', label: 'Tests');

  @override
  void build() {
    final res = watch(worktree.dbPath,
        query: 'SELECT pass, fail FROM test_runs ORDER BY ts DESC LIMIT 1',
        (row) => TestSummary.from(row));
    status(() => res.value.fail > 0
        ? Status.error('${res.value.fail} failing')
        : Status.good('${res.value.pass} passing'));
    switcherBadge(() => res.value.fail > 0 ? Badge.dot(Tone.error) : Badge.none);
    action('Run all', () => sh('flutter test'));
    teardown('Clear screenshot cache', checked: () => false,
        order: Phase.cleanup, () => sh('rm -rf .flutterware/screenshots'));
    nativePanel();   // panel kind = native; GUI supplies the widget for this id
  }
}

// app/lib/src/plugins/native_registry.dart  —  real Flutter
final nativePanels = <String, Widget Function(PluginHost)>{
  'flutterware.test_runner':   (h) => TestRunnerScreen(host: h),
  'flutterware.feature_flags': (h) => FeatureFlagsScreen(host: h),
  'flutterware.dependencies':  (h) => DependenciesScreen(host: h),
};
```

The headless config process runs `config.dart`, and emits a **manifest** — for
every plugin: id, status, badge, actions, teardown, and a panel that is either
`declarative(tree)` or `native(id)`. For native plugins it never touches a
widget; it just reports the id.

The explorer renders every plugin **identically except the panel mount**:

```dart
Widget panelFor(PluginInstance plugin, PluginHost host) => switch (plugin.panel) {
  DeclarativePanel(:final tree) => DeclarativePanelView(tree),  // interpret the kit
  NativePanel(:final id)        => nativePanels[id]!(host),     // mount the real widget
};
```

A native widget gets a `PluginHost` handle — worktree identity, a daemon
connection, the SQLite handle, the plugin's own source values. From there it is
unrestricted Flutter. (`app/lib/src/test_runner/runtime.dart` already owns a
daemon connection today — that pattern *is* `PluginHost`.)

The uniform contract: **every plugin is identical for status / badge / actions /
teardown / guard.** The explorer shell, the switcher, and the teardown dialog
treat all plugins alike. The *only* fork is the panel — a clean two-case union.

### Future extension (out of scope for v1)

The GUI is host-built from the pinned `flutterware` package (per the
distribution model). So native plugins need not stay first-party forever: a
project could list extra native-plugin packages in its pubspec and the host GUI
build would compile them in — real third-party Flutter plugins, no dynamic
loading. The door is open and free; v1 ships first-party native only.

## Teardown steps

A plugin contributes **teardown steps** by calling `teardown(...)` in `build()`.
When a worktree is removed, the GUI assembles every plugin's steps into a
**checklist dialog**; the user checks/unchecks; selected steps run in order;
then the worktree is removed.

```dart
// inside build()
teardown('Stop & remove dev stack',
  detail:  () => '${stack.value.length} containers · 2 named volumes',
  enabled: () => stack.value.isNotEmpty,   // greyed + uncheckable if nothing to do
  checked: () => stack.value.isNotEmpty,   // default tick state
  danger:  true,                           // destroys data — red row
  order:   Phase.infra,                    // apps → infra → cleanup → (built-in remove)
  () => sh('docker compose -f docker/dev.yml down --volumes'));
```

- `enabled` / `checked` / `detail` are **closures over source state**, evaluated
  when the dialog opens — the checklist reflects reality, not registration time.
- A plugin may register more than one step.
- `order` is a `Phase` enum (`apps`, `infra`, `cleanup`); the built-in "Remove
  the git worktree" step always runs last and is locked-checked.
- Steps stream stdout/stderr into the dialog. On a step failure the flow pauses
  with Retry / Skip & continue / Abort. Worktree-removal is gated: if an earlier
  step failed and the user did not explicitly continue, removal aborts so the
  checkout is never lost with infra half-up.

The dialog is the declarative kit (`ui.dialog` + `ui.checklist` + `ui.checkRow`),
grouped by plugin.

## Guards

Distinct from teardown steps. A teardown step is *checkable* ("do this
cleanup?"). A **guard** runs *before the dialog renders* and can:

- `g.block(reason)` — hard stop; "Tear down" is disabled with the reason shown.
- `g.warn(reason)` — proceed allowed, an acknowledgement line is added.

```dart
// inside build()
guard((g) {
  if (st.value.dirty > 0)
    g.block('${st.value.dirty} uncommitted change(s) — commit or stash first');
  if (st.value.ahead > 0)
    g.warn('${st.value.ahead} commit(s) not pushed to ${st.value.upstream}');
});
```

Git motivates `block` (don't destroy uncommitted work); Claude motivates `warn`
(Claude is mid-task, but you may know better).

## Tab label & switcher badge

Raw worktree slugs (`nostalgic-maxwell-db14b2`) are meaningless. Any plugin can
contribute a **tab label** via `label(value, priority:)`. The explorer
resolves per worktree by priority:

```
claude session title  (high)    → "Worktree explorer plugin design"
  ↓ falls back to
git branch             (normal)  → "claude/nostalgic-maxwell-db14b2"
  ↓ falls back to
worktree slug          (built-in)→ "nostalgic-maxwell-db14b2"
```

The tab shows the winner; hover shows the full stack. Same precedence feeds the
switcher dropdown.

Any plugin can contribute a **switcher badge** via `switcherBadge(...)` — a
tiny per-worktree glyph (`Badge.dot`, `Badge.count`, `Badge.none`, tones, an
optional `pulsing` flag). The switcher becomes a dashboard:

```
● Worktree explorer plugin design   feature/explorer   ↑3  ⬤claude-waiting
```

One glance: the branch, 3 unpushed commits, Claude parked waiting for you.

## Launch policy — the unification

A plugin that knows something can also **inject it at launch time**, collapsing
the old `fw.command(...)` verb into the plugin model. A plugin declares
`onLaunch(match:, handler)`; the handler can rewrite argv/env, add
`--dart-define`s, or `block` the launch.

```dart
class Postgres extends Plugin {
  Postgres({required this.container, this.exposeAs = 'DB_PORT'}) : super('postgres');
  final String container;
  final String exposeAs;

  @override
  void build() {
    final db = poll(every: 5.s, () => inspectContainer(container));
    status(() => db.value.running ? Status.up('5432→${db.value.hostPort}')
                                  : Status.down());
    onLaunch(match: 'flutter run', (launch) {
      if (!db.value.running) launch.block(reason: 'dev-db is down — start it first');
      launch.dartDefine(exposeAs, '${db.value.hostPort}');
    });
  }
}
```

One plugin owns a concern end-to-end: observe it, act on it, and wire it into
every launch. This ties the plugin model harder to sub-project 0 (the wrap
point) — accepted.

## Cross-worktree sources — `peers`

A plugin can subscribe to **the same plugin's output in sibling worktrees** via
`peers('<source-key>')`. The per-project single-DB design makes this nearly
free. It unlocks cross-worktree plugins — the motivating case is port-conflict
detection (two worktrees both binding `:8080`).

```dart
class Ports extends Plugin {
  Ports() : super('ports');

  @override
  void build() {
    final mine      = poll(every: 6.s, () => listeningPorts(worktree.pids));
    final peerPorts = peers('ports.mine');
    status(() {
      final clash = mine.value.where((port) => peerPorts.any((w) => w.has(port)));
      return clash.isEmpty ? Status.up('${mine.value.length} ports')
                           : Status.warn('port ${clash.first} also used by '
                                         '${peerPorts.owner(clash.first)}');
    });
    onLaunch(match: 'flutter run', (l) => l.env['PORT'] =
        '${worktree.allocatePort()}');
  }
}
```

## First-party tools as native plugins (the keystone)

flutterware already ships per-project tools: the test runner / visualizer, the
dependency manager, feature flags, the UI catalog, the launcher-icon editor,
Devbar. In this model **each of those is a native plugin** — `fw.use(TestRunner())`,
`fw.use(FeatureFlags())`, `fw.use(UiCatalog())`. The worktree explorer is the shell;
today's screens become native panels. This is what makes the "re-purpose" not a
throwaway: it is an extension architecture wrapped around the existing app.

## Plugin ideas catalogue

Captured for later; not all are v1.

**Git** — branch / ahead-behind / dirty count; switcher badge; tab label; fetch
/ pull / push actions; teardown step "delete merged branch"; guard blocking
teardown on uncommitted work.

**Claude** — `watch` source over the worktree's Claude Code session JSONL;
status = working / waiting / idle; tab label from the session title (high
priority); pulsing switcher dot when Claude is *waiting on you*; actions open
transcript / resume in terminal; teardown step "archive session"; guard warning
when Claude is still working. `ClaudeSession` encapsulates the unstable
knowledge of `~/.claude/projects/<encoded-cwd>/*.jsonl`.

**Docker / Postgres** — poll-based stack status; up/down actions; teardown steps
that tear down containers & volumes; `onLaunch` injecting the live DB port.

**Server / devices** — `sessions`-based; lifecycle, uptime, device-id; start /
stop actions.

**Ports** — cross-worktree conflict detection via `peers`.

**PR** — GitHub PR state for the branch; switcher badge for review-required /
checks-failing; tab label from the PR title.

**Merge-preview** — proactive throwaway merge into `main`; switcher goes red the
moment `main` moves under you.

**Visual-diff** — diffs this worktree's screenshots against `main`'s; the
existing screenshot infra in `test_runner/runtime/widget_tester_screenshot.dart`
is the plumbing.

**Analyzer / Test / Format / Pub-outdated** — quality plugins; counts + switcher
badges + issue-list panels.

**Tunnel** — one-button `cloudflared` tunnel to the dev server; panel shows the
public URL + a `ui.qr` node.

Crazier, captured but unprioritised: **Handoff** (package a worktree's live
state to share with a teammate), **Cost** (Claude token spend per worktree,
budget badge), **Standup** (cross-worktree git+PR+Claude summary as markdown),
**Idle reaper** (`background:` plugin flagging abandoned worktrees), **Replay**
(time-slider over the SQLite bus timeline), **Soundboard** (`background:` OS
notification when any worktree's Claude flips to waiting / tests go red).

## config.dart lifecycle

Each worktree's `config.dart` is compiled and run by the daemon as the
per-worktree config process; edits reflect in the GUI within ~0.5–0.8s.

- **Compile** — a *non-resident* `frontend_server` (via
  `package:frontend_server_client`), spawned per change and seeded with
  `--initialize-from-dill` from a cached `.dill`, so it recompiles only changed
  libraries then exits. No resident compiler is held in memory (it would cost
  ~50–150 MB per open worktree).
- **Run** — the config process runs JIT against the produced `.dill`. On change,
  **spawn-then-swap**: the new process warms its sources before the old one is
  killed, so panels and policy queries never go dark.
- **No hot reload.** `reloadSources()` was considered and rejected: with the
  compile path above the restart loop is already sub-second, and hot reload
  would re-impose a resident compiler plus reassemble/diff complexity and
  stale-state risk to save ~0.3s. Same conclusion as the wrapper-tool doc's
  "compile-on-invalidation (not hot reload)", updated mechanism.
- **Trigger** — a `package:watcher` *directory* watch over the **import closure
  of `config.dart`** (the source set `frontend_server` reports from each
  compile, refreshed on every successful recompile). Debounced ~150–250 ms;
  directory-watching handles atomic rename-saves. `pubspec.yaml` /
  `pubspec.lock` route to a slower `pub get` + cold-restart path. A compile
  error keeps the last-good config serving and surfaces file+line in the GUI. A
  manual "Reload config" affordance + a `config.reload` RPC covers filesystems
  that do not deliver native watch events.

## Transport

Consistent with the locked design:

- **RPC** (Unix socket, GUI→daemon) — subscription control: "I am now displaying
  worktree X's status / worktree Y's panel"; teardown-plan requests; action
  invocations.
- **SQLite bus** (daemon→GUI, via `watch()`) — data flow. Source values,
  statuses, panel trees, PTY chunks, channel messages are rows; the switcher
  reads cheap status rows, the open tab reads panel rows.

## Incremental story

- `poll` / `watch` sources need nothing beyond the daemon + explorer shell — a
  poll-only plugin (docker, git, claude) works from day one.
- `sessions` plugins light up when sub-project 0 (the SDK wrap point) lands.
- `channel` plugins light up when sub-project 2 (the back-channel) lands.
- Native first-party plugins land as the existing screens are adapted to
  `PluginHost`.

The explorer ships useful early and gains capability as the lower layers arrive.

## Decisions reached in this session

- Worktree explorer = sub-project 1, built on the per-project daemon.
- Plugin = reactive aggregator: sources → status → actions + panel.
- **API shape: a plugin is a class that `extends Plugin`** with a single
  `build()` override; the kit (`poll`, `status`, `action`, …) are protected
  methods. Chosen over a closure builder and a pure-data record: it is the only
  shape giving a nameable, documentable, publishable type while keeping the
  reactive graph as plain closure capture. `fw.plugin('id', (b) {...})` remains
  as inline sugar — an anonymous `Plugin` subclass, not a parallel mechanism.
- Native plugins use the **same `Plugin` base class** — no separate
  `NativePlugin` type; a native plugin's `build()` calls `nativePanel()`.
- Four source types: `poll`, `watch`, `sessions`, `channel`; author picks per
  data point. Sources compose (combine / map / `when:`).
- Demand-driven execution; two subscription levels (status vs panel);
  `background: true` opt-out.
- config.dart lifecycle: non-resident `frontend_server` + `--initialize-from-dill`,
  JIT spawn-then-swap on change, **no hot reload**; watch set = the
  compiler-reported import closure of `config.dart`.
- Declarative, interactive panel kit for all headless-config-process plugins.
- Two plugin tiers: **declarative** (headless config process) and **native**
  (compiled into the GUI). A native plugin is a pure-Dart `Plugin` subclass + a
  registered GUI widget, linked by a string id. Uniform contract for everything
  except the panel.
- Plugins are publishable classes (`fw.use(...)`), instantiable more than once.
- Teardown steps (checklist dialog, `Phase` ordering, failure-gated removal).
- Guards, distinct from teardown steps: `block` (hard) vs `warn` (soft).
- Tab label + switcher badge contributed by plugins; priority-resolved label.
- `fw.command` is collapsed into `onLaunch` — plugins own launch policy.
- `peers` — cross-worktree sources.
- The existing flutterware tools become the first native plugins (the keystone).

## Open questions

- The exact `PluginHost` API surface handed to native widgets.
- DB schema for plugin sources / statuses / panel trees / manifests.
- Worktree discovery & tab lifecycle in the explorer shell (`git worktree list`
  + watching for new/removed worktrees).
- Whether `watch` stays a distinct source type or folds into `poll` with a
  filesystem trigger. (Leaning: keep distinct — file-watch vs interval are
  genuinely different.)
- How a native plugin's headless `Plugin` subclass and its GUI widget share the
  daemon connection without double-subscribing.
- Manifest format and how the GUI revalidates it on `config.dart` recompile.
- Label/badge precedence when two plugins claim `LabelPriority.high`
  (claude title vs PR title).

## Next step

This document is the spec for the worktree-explorer + plugin model. The agreed
next thing to build remains **sub-project 0 — the SDK wrap point** (it is the
dependency for `sessions` sources and `onLaunch`). Sub-project 1 — the explorer
shell, the daemon, the declarative kit, the first poll/watch plugins — can be
specced and built in parallel against the parts that need no wrap point.
