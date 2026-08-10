# The overhaul — master plan

**Date:** 2026-07-25
**Status:** Direction-setting. Decisions below are **locked**; milestone contents
past M2 are **stubs** that spikes S1/S2 will fill in.

Third document in the lineage:
`2026-05-15-wrapper-tool-architecture.md` → `2026-05-18-worktree-explorer-plugins-design.md`
→ this. It does not replace them; it re-frames them around a consumer they both
missed, and sequences the work in `_steps/_new_start.md`.

## The thesis

Both prior docs are human-GUI-centric — tabs, badges, panels, a switcher
dropdown. An AI agent consumes none of that, and "the AI can ask what is shown
in the app" is now a first-class requirement.

But the plugin model already produces the right artifact. A plugin reduces its
sources to a `Status`, a set of `actions`, and a panel drawn from a fixed
vocabulary. That is a **serializable manifest**. So:

> **The daemon owns a live manifest. The GUI, the CLI, the file projection, and
> (later) MCP are four renderers of it. No renderer is privileged.**

Everything below follows from taking that literally.

> **Revised 2026-07-26.** That framing was wrong about *what* is shared, because
> it was built on the wrong use case. "An agent reads what is shown in the app"
> turns out to be marginal. The real asks are **commands that produce
> artifacts** — "screenshot this catalog entry", "run this test", "give me the
> widget tree" — plus a separate ability to *drive* the running GUI. A doer does
> not need the GUI's state layer at all; it needs the manifest and the work.
> So:
>
> > **The manifest and the artifact pipelines are shared. The GUI and the CLI
> > are two *drivers* of the same pipelines, not two renderers of one state.**
>
> Consequences: no de-Fluttering of `Project` / `AsyncValue` / the services is
> needed (a refactor that was proposed and withdrawn); the plugin *config* in
> the manifest doubles as the CLI's contract; and the text projection
> (`PluginView`, `report.toText()`) stays as a convenience but must stop driving
> architecture.

## Locked decisions

1. **Manifest as the single source of truth.** GUI / CLI / file projection / MCP
   are renderers. A feature that cannot be expressed in the manifest is not a
   feature of the plugin model.

2. **The uniform contract is pure data for every plugin — native included.**
   `status`, `badge`, `actions`, `teardown`, `guard`, and a **text projection**
   are data. Only the *panel* forks (declarative tree vs. native widget). A
   native plugin renders a real Flutter widget for humans **and** emits a
   text/JSON view of what that widget is currently showing, for agents.

   This is the decision that makes "the AI can ask what is shown in the app"
   fall out for free. It costs ~nothing decided now and is unrecoverable
   decided later.

3. **Two projections, not one.** *Text* (structure: what entries exist, what
   state, what's selected) and *image* (pixels: the actual rendered frame).
   ui_catalog and the scenario runner need both; the embedder already produces
   the second.

4. **`tool/flutterware.dart` ships in v1 — as a static manifest emitter only.**
   Native plugins are compiled into the GUI binary, so v1 config cannot *add*
   code: it selects, configures, and orders plugins that are already linked in.

   ```
   dart run tool/flutterware.dart --emit-manifest  →  JSON on stdout  →  daemon
   ```

   Plain JIT `dart run`. **No** `frontend_server`, **no** resident compiler,
   **no** spawn-then-swap, **no** per-worktree config-process pool, **no**
   declarative panel interpreter. Re-run on file change.

5. **v1 sources run in the daemon**, on the native plugin's behalf. The config
   process is a short-lived manifest emitter, not a source host. It becomes
   long-lived and source-hosting only when the declarative tier lands. This is a
   deliberate deviation from `2026-05-18-worktree-explorer-plugins-design.md`.

6. **v1 is native-plugin-only.** Every panel is a plugin; every plugin is
   native. Decision 2 is what stops this from painting us into a corner.

7. **Design system: port the token layer from `cms/packages/admin_ui` first**
   (`lib/src/theme/` — palette, spacing, radii, typography, tokens, elevation)
   plus shell chrome. Port widgets **lazily**, as each panel is rewritten.
   `admin_ui` is ~44k lines; we want ~2k of it up front. Do not restyle screens
   that are about to be deleted.

8. **TUI: stop investing in `app/lib/src/tui/`**, evaluate
   [jtmcdole/termui](https://github.com/jtmcdole/termui) as the terminal
   renderer of the manifest. Do not delete the existing stack until termui is
   proven — deleting stays free, re-deriving five stages does not.

9. **Artifact pipelines live in `app/`, and purity is a property of the
   entrypoint's import closure — not of the package.** `package:flutterware` is
   published and every user's app inherits its dependencies, so heavy tooling
   deps must never land there. `flutterware_app` is `publish_to: none` and is
   already where the CLI lives: `app/bin/flutterware.dart` is a pure-Dart
   entrypoint inside a Flutter package, compiled with `dart compile exe`.
   `app/lib/src/embedder/` already shows the split — `compiler.dart` and
   `embedder_build.dart` are Flutter-free, `embedded_engine.dart` is not.

   **The guardrail is the compile itself**: if the CLI's closure ever acquires
   `package:flutter`, `dart compile exe` fails. That guardrail is currently
   **off** — the compile is broken on build hooks (`objective_c`, needs
   `dart build`), which promotes that fix from distribution debt to the thing
   keeping this architecture honest.

10. **Distribution (`fw` walker + bootstrapper) is last.** It gates adoption; it
   blocks no development. Saying so explicitly stops it from feeling like debt.

## Deliberately deferred

- The **declarative plugin tier** and the declarative panel kit → v2. This is
  what user-plugins (goal 7) needs; goal 7 is explicitly a stretch.
- `frontend_server`-based config compilation, hot-swap, per-worktree config
  process pool → arrives with the declarative tier.
- **MCP server** → a thin adapter once the CLI renderer exists. Not before.
- **Third-party native plugins** (extra pubspec entries compiled into the
  host-built GUI) → the door is open, unused.

## Where we actually are

| Layer | Goals (`_new_start.md`) | State |
|---|---|---|
| **Shell** — worktree switcher, plugin host, design rework | 1, 2, 3 | Designed (2026-05-18). No code. |
| **Panels** — ui_catalog, test_runner, others, user-plugins | 4, 5, 6, 7 | Old versions exist; to be replaced. |
| **Wrap / observe** — catch-all dart & flutter processes | 8 | **Half done.** `app/lib/src/wrap/` landed in #38: shims, install command, dart_define injection, session sink. Missing is the *consumer* side, not the interception. |
| **Distribution** — `fw` as Flutter version manager | 9 | Not started (walker + bootstrapper). |

Assets already built that this plan leans on:

- **Embedder steps 1 → 3b done**, including the Metal zero-copy path into shared
  `IOSurface`s (`app/lib/src/embedder/`, `#29 #31 #33`). This is the substrate
  for *both* ui_catalog and the scenario runner — not a ui_catalog trick.
- The SDK wrap point (`#38`).
- A full TUI widget stack (stages 1 → 4.5b) — see decision 8.

## The unification

Goals 4 and 5 are one problem with two entry points:

- **ui_catalog** — compile a scene fast → render → screenshot → let the AI see
  and inspect it.
- **test_runner** — compile a scenario → drive it → capture each step → let the
  AI see it and post-mortem it.

Both want: fast guest compile, real rendering, frame capture, widget-tree
inspection, hot reload. That is exactly what the embedder provides. Whether they
share one substrate is what **spike S1** decides.

## Milestones

### S — Spikes — **all complete**

- **S1 succeeded** → `2026-07-26-s1-scenario-in-embedder-findings.md`
- **S2 succeeded** → `2026-07-26-s2-design-tokens-findings.md`. The token layer
  is ported and live in `app/lib/src/ui/design/`; M1 can build against it now.
- **S3 succeeded** → `2026-07-26-s3-hot-switch-findings.md`. Run without a
  written brief, during session A. Answers the question S1 left open: a
  **newly reachable** library does enter a live isolate via `reloadSources`, so
  switching catalog entries is a hot reload, not a restart. Also establishes the
  compile economics the catalog and the scenario runner both budget against.

### M1 — The shell

**Chrome settled 2026-07-26** by prototype (`app/lib/main_shell_dev.dart`):

- The macOS titlebar is reclaimed — `titlebarAppearsTransparent`,
  `titleVisibility = .hidden`, `.fullSizeContentView`,
  `isMovableByWindowBackground`. The traffic lights stay **real**; band content
  insets 78pt past them. Verified: the band still drags the window, content
  drags do not, and band controls are clickable.
- **A tab per *open* worktree** in that band, each closable. Closing releases
  that worktree's panel subscription.
- **A switcher popover** (`+`) listing the full `git worktree list`, split
  OPEN / NOT OPEN, so unopened worktrees are reachable without spending a tab.
  This is what keeps the tab strip bounded.
- **Plugins in a vertical sidebar**, not horizontal. Rejected an all-horizontal
  layout on evidence: 8 plugins already fill the width, and status degrades from
  `3 failing` / `stack down` to bare dots — a horizontal strip cannot carry the
  status the plugin contract specifies, and user plugins would overflow it.

Then: plugin host; `Plugin` base class with the decision-2 uniform contract as
pure data; native panels only; `tool/flutterware.dart` manifest emitter; design
tokens (**done**, S2).

Port **two boring existing screens** as plugins — dependencies, themes, or the
icon editor. Boring is the point: they prove `PluginHost` cheaply, before the
flagships depend on it.

No daemon rewrite. Ships something usable daily.

### M1.5 — Monorepo packages + laziness

Prompted by two bugs M1 surfaced: the shell opened the repo root instead of the
project, and Dependencies reports "170 direct, 0 transitive" in a pub workspace.
Both come from assuming one directory is one package is one project.

Spec: `2026-07-26-packages-and-laziness.md`. Slice 1 is committed scope.

Two decisions from it worth carrying here:

- **Laziness is subscription**, not a demand protocol. Work starts on first
  listener; in the GUI, widget lifecycle supplies that for free. The rule that
  makes it hold: **`PluginReport` never triggers work** — it is a pure read of
  cached state, which is what lets the sidebar, tab glyphs, `fw` and an agent
  all call it for every plugin × package × worktree.
- **Packages are declared, not inferred**, with per-plugin typed entries
  (`UiCatalogPackage`, `ServerPackage`) so per-package config has somewhere to
  live. The framework requires only `path`, as the join key for validation and
  later tag filtering.

### M2 — The AI surface

The manifest's non-GUI renderers: `fw status --json`, the live file projection
under `.flutterware/`, screenshot-of-an-entry. Whatever "the AI asks what is
shown in the app" means concretely, it lands here.

**M2 is before the flagships on purpose.** ui_catalog and test_runner then get
built against a contract an agent is already reading. Built after, we retrofit
forever.

### M3 — ui_catalog on the embedder

Substrate settled by S1: guest + resident compiler + cached asset bundle +
capture path + ~130ms reload loop.

**The loop settled by S3** (`2026-07-26-s3-hot-switch-findings.md`):

- **One long-lived resident compiler per worktree.** The framework floor is 2.3s
  and is paid once, not per entry.
- **An accumulating generated entrypoint.** Each newly visited entry is *added*
  as an import under a **fresh prefix**, never rebound — rebinding an existing
  prefix to a different library is silently ignored by hot reload. Entries are
  then selected at runtime, so revisiting one costs no compile at all.
- **Measured cost:** cold once per worktree; 17ms–580ms for a first visit to a
  new entry; ~12ms for a revisit; reload is flat in subtree size (~117ms).
- Focus vs. browse is therefore a **UI** question, not a process question.

**The entry model settled by session A**
(`2026-07-26-ui-catalog-entry-model.md`): **the catalog map is gone.** Entries are
declared by annotation — `Demo extends Preview` from
`package:flutter/widget_previews.dart`, shipped in `package:flutterware` — so
existence comes from the declaration and hierarchy from the file path. Variants
are sibling entries with stable ids. Global axes (theme, locale, device) are
applied rather than expanded, and are runtime concepts owned by the project's own
wrapper, not by flutterware.

`transform()` maps our richer fields (`formFactor`, `id`, `figma`) down to
Flutter's, so one declaration serves both hosts: Flutter's previewer reads a
correct `Preview`, our guest reads the full instance. Evidence and measurements:
`2026-07-26-widget-previews-integration-findings.md`.

**Discovery, sharing and lifetime — settled 2026-07-26:**

- **Discovery is syntactic; resolution is the guest's job.** *Corrected
  2026-07-26 by measurement* — an earlier draft of this section claimed a
  resolved analyzer pass was "one file plus summaries, not a project analysis".
  That is false: over the reference project's 180-file demo tree, the **first** resolved unit
  costs **17.3s** (it needs the linked element model of the whole transitive
  closure), against 12.9s to compile the entire catalog. Subsequent units are
  ~26ms, and a **syntactic scan of all 180 files is 20ms**.

  Syntactic discovery sees a declaration, its name, its library path, an
  annotation, and a literal config reference — everything the tree and the
  generated entrypoint need. It cannot resolve an arbitrary expression to its
  declaring element. **That is exactly the difference between a map of widget
  expressions and a set of named declarations**, and it is an independent
  argument for the declaration model. The syntactic tree is provisional; a warm
  guest is ground truth, and a disagreement is a diagnostic. No resolved pass in
  between, so `package:analyzer` is needed only as a parser.
- **`@Preview` is discovered by the same syntactic scan**, not a separate
  pipeline. One scanner, two sources.
- **Watching is for humans; an explicit reload is for agents.** An agent needs a
  request/response barrier ("apply my edit, tell me when the frame is ready") or
  it races its own file write and captures the previous state.
- **One compiler, one dill, several guests.** The accumulating entrypoint makes
  entry selection a runtime choice, so the GUI and an agent share the expensive
  compiler while driving separate guests — no contention, and the human can watch
  what an agent is doing.
- **An agent is a client of the warm daemon, never its own compile.** Shelling
  out to a fresh compile costs 9–13s per screenshot and wastes S3 entirely. This
  strengthens decision 9: the CLI compiles nothing, so staying Flutter-free is
  structural rather than a discipline.
- **Process topology is per project; disk caches are global.** One auto-started
  daemon per repo root holding all its worktrees. Nothing heavy is shareable
  across projects. Auto-start needs lock-file + atomic-bind race handling
  (concurrent agents in several worktrees is the normal case) and a stated
  lifetime policy.

- **The daemon dies with its last client**, after a small grace period.
- **`@Preview` entries get their own tree root**, deduplicated against map
  entries that resolve to the same declaring library + symbol. **Preview support
  is a nice-to-have and may be deferred** for simplicity — but see the entry
  metadata note below, which is not deferrable.

### M4 — scenario runner (replaces test_runner) — *shape settled by S1*

> **Amended 2026-07-30 — the `LiveWidgetController` shape is superseded.** See
> `2026-07-30-scenarios-design.md`. S1's recommendation argued against
> dev_studio's vendored-fork architecture, not against entering through
> `testWidgets` — which the 2026-05 port had already shown needs no fork. The
> owner's requirements (FakeAsync instantaneity, flutter_test compatibility,
> user CI, artifact-driven inspection and auto-write) all point back to the
> test harness. M4 is now: the `flutter_test` harness under
> `AutomatedTestWidgetsFlutterBinding`, in a `flutter_tester` binary spawned
> directly by our daemon and fed by the catalog's resident compiler (spike S4
> pending). The paragraph below is kept for the record.

A **rewrite** on `LiveWidgetController`, not a port of dev_studio. Take
dev_studio's GUI / protocol / authoring ergonomics (~8,200 lines, reusable);
rewrite its ~1,400-line `WidgetTester`-coupled runtime, which today depends on a
vendored 701-line fork of Flutter's `widget_tester.dart`. Details and open gaps
(`enterText`, plugins, post-mortem) in the S1 findings.

### M5 — Process catch-all (goal 8 consumer side), user plugins (goal 7), `fw` (goal 9)

## Spike briefs

Written before the spikes run, so they stay spikes.

### S1 — Run a `flutter_test` scenario inside the embedder guest

**Question.** Can a scenario run under `LiveTestWidgetsFlutterBinding` against
the embedded engine, rendering real frames into the shared `IOSurface`, instead
of headless `flutter test`?

**Why it matters.** If yes, we get for free: watch a scenario run live in the
app, pause / step, inspect the widget tree at any step, hot-reload the scenario,
and screenshots that are real GPU frames. ui_catalog and test_runner collapse
onto one substrate, and M3/M4 look very different from "port dev_studio".

**Success.** A two-step scenario drives a `runApp` UI in the guest; both steps
are visible live in a flutterware window; a frame is captured per step.

**Kill criteria.** Abandon if the binding cannot be made to drive a
non-`flutter test` embedder host without forking `flutter_test`, or if it costs
more than ~2 days. Fallback is the plain path: port dev_studio's runner as-is
and drive it from the GUI over a socket, as `_new_start.md` originally said.

**Do not** build a plugin, a panel, or a protocol. Hardcode everything.

### S2 — `admin_ui` tokens onto one existing screen

**Question.** Is the design lift mechanical?

**Success.** `admin_ui`'s theme subtree lands in the app, one existing screen
(dependencies list) renders through it and looks like the target, and the diff
is boring.

**Kill criteria.** If the tokens drag in `admin_ui`'s app state, CMS field
model, or shell assumptions, stop and extract a smaller token set by hand.

## Where to pick up

The work has outgrown one session. Three, in this order:

**A — UI catalog (next).** Its own session, goals first: what an entry is, how
AI-friendliness actually works, what the hot-reload loop feels like. Read
`2026-07-26-s1-scenario-in-embedder-findings.md` first — the guest, the ~130ms
reload loop, and the plugin/platform-channel trap are all established there.
It inherits exactly one constraint from this session: **the catalog pipeline
must stay Flutter-free** (decision 9), so the CLI can drive it later without a
rewrite. macOS-first is accepted; `FlutterEmbedder.framework` is `darwin-x64`
only and Linux has no path yet.

There is already a UI catalog, and deciding what happens to it is part of A's
scope rather than something to discover mid-build:

- `lib/src/ui_catalog/` (~15 files, published in `package:flutterware`) — the
  runtime users embed in their app: `UICatalog`, parameters editor, device
  panel, treeview, Figma hooks. Exported from `lib/ui_catalog.dart`, so its API
  is a **public commitment** to existing users.
- `app/lib/src/ui_catalog/service/` — the GUI half, which today reaches the
  running app over a **UDP-discovered socket server**, not the embedder.

So A's first question is whether the embedder *replaces* that transport or sits
beside it, and what the published runtime API owes existing users. The plugin id
`flutterware.ui_catalog` and the `UiCatalogPackage(entrypoint:)` config shape
already exist; the id currently resolves to `MissingPlugin`.

**Session A, 2026-07-26 — settled so far.** The transport question is separable
from the compile loop, and it is smaller than it looked: `app/lib/src/ui_catalog/
service/` is effectively dead — `api.dart` is five empty stubs, and the service
discovers a `ui_book.dart` entrypoint name that real consumers do not use. It is
deletable, not a transport to preserve.

- The inner loop → S3 (`2026-07-26-s3-hot-switch-findings.md`).
- The entry model → `2026-07-26-ui-catalog-entry-model.md`.
- Why `@Preview`, and at which layer →
  `2026-07-26-widget-previews-integration-findings.md`.
- **The existing catalog app is kept, not replaced.** It is the published API,
  it is what compiles to web for per-PR catalog links, it is the real-device
  path (each demo file already has its own `main()`), and it is the fallback
  where the embedder has no port. The flutterware GUI is an *additional*
  renderer.
- **Invariant, amended:** the whole catalog stays enumerable and renderable from
  a plain `flutter test` with no running daemon. With the map gone, Dart has no
  runtime reflection over annotations and no dynamic import — so *invocation*,
  not discovery, forces generated code. The cost is small because the per-PR web
  build already needs the same full entrypoint: one generator, three consumers
  (lazy daemon, web build, test). The generated file is **committed** and guarded
  by a regeneration-produces-no-diff check, reusing the
  `dart tool/prepare_submit.dart` pattern.

**Session A, 2026-07-27 — the loop runs in the GUI.** The catalog renders a
live embedder guest in the flutterware app and switches entries by hot reload
(compile 5-10ms, reload 85-107ms, `+0 libs` on revisit); see
`2026-07-27-gui-slice-findings.md`. The compile half runs in a **plain-Dart
daemon**, not in the app — `FrontendServerClient` spawns the compiler through
`Platform.resolvedExecutable`, so compiling inside the GUI relaunches the GUI,
recursively. This document's "the catalog pipeline must stay Flutter-free"
constraint turns out to be load-bearing rather than stylistic.

Still open for A: discovery without compiling, the watch-vs-explicit-reload
split, and how the GUI and an agent share the warm process.

Deletable once A lands: `app/lib/main_shell_dev.dart` (the throwaway chrome
prototype).

**B — The CLI.** Separate, because its blockers are distribution-shaped and
independent of catalog goals: `dart compile exe` → `dart build` for build
hooks, then the walker and bootstrapper. Do **not** fold this into A — but note
that the compile fix is what re-arms the purity guardrail A depends on.

**C — Remaining plugins**, once A settles the shape: tests (the dev_studio
rewrite), launcher icon, and whatever else earns a row.

Also outstanding, unowned: 5 pre-existing test failures in
`app/test/passthrough/` and `app/test/wrap/`, which predate this work and will
eventually mask a real regression.

## Open questions

1. ~~**dev_studio: fork the code, or fork the design and rewrite on the
   embedder?**~~ **Answered by S1 (2026-07-26): fork the design, rewrite the
   runtime.** See `2026-07-26-s1-scenario-in-embedder-findings.md`.
2. ~~**Plugins / platform channels in the embedder guest.**~~ **Investigated by
   S1: not a blocker.** Fake at the platform interface, as with `flutter test`.
   Follow-up work item, not a question: give `host.c` a **platform task
   runner**, so an unfaked call throws `MissingPluginException` instead of
   hanging forever.
3. **Text entry in scenarios** — `enterText` is `WidgetTester`-only and needs a
   test binding. Largest API gap in the `LiveWidgetController` route. *(new,
   raised by S1)*
4. Where the per-worktree "close and release" boundary sits for native plugins
   whose sources run in the daemon (decision 5). Sharpened by the M1 chrome
   prototype: the switcher shows badges for **unopened** worktrees
   (`2 failing`, `PR open`), so "not open" cannot mean "not observed". That is
   the 2026-05-18 doc's two-level split — status subscription vs panel
   subscription — and closing a tab must release only the latter. Still to
   decide: are unopened badges computed eagerly, lazily when the popover opens,
   or not at all?

   **Costed for the catalog (2026-07-26).** The state splits into three tiers
   with different release policies: the **syntactic scan result** is cheap
   (478ms cold for 778 files, ~1ms incremental) and should be *kept* on close —
   it is what powers badges for unopened worktrees; the **resident compiler** is
   hundreds of MB and should be released after a grace period; the **guest
   engine** should be released immediately. The two-level split holds, now with
   measured costs behind it.
5. Manifest schema — the text projection's shape is the part with no prior art.
   **Partly answered for the catalog (2026-07-26):** an entry's address is its
   path + symbol (pinned by `Demo(id:)`), with global axes (theme, locale,
   device) carried as an applied assignment rather than expanded into the tree.
   "Screenshot an entry" is under-specified without the resolved axis
   assignment, which every artifact must therefore record. See
   `2026-07-26-ui-catalog-entry-model.md`.
6. Whether termui can host the manifest renderer, or whether the CLI stays
   plain structured output (decision 8).
7. What of the current app survives M1 beyond the two ported screens.
