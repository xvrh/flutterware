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

9. **Distribution (`fw` walker + bootstrapper) is last.** It gates adoption; it
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

### S — Spikes — **both complete**

- **S1 succeeded** → `2026-07-26-s1-scenario-in-embedder-findings.md`
- **S2 succeeded** → `2026-07-26-s2-design-tokens-findings.md`. The token layer
  is ported and live in `app/lib/src/ui/design/`; M1 can build against it now.

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

### M3 — ui_catalog on the embedder — *stub, S2 + the plugin spike fill this in*

Substrate settled by S1: guest + resident compiler + cached asset bundle +
capture path + ~130ms reload loop.

### M4 — scenario runner (replaces test_runner) — *shape settled by S1*

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
5. Manifest schema — the text projection's shape is the part with no prior art.
6. Whether termui can host the manifest renderer, or whether the CLI stays
   plain structured output (decision 8).
7. What of the current app survives M1 beyond the two ported screens.
