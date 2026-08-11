# Scenarios as a web page — spike findings and design

**Date:** 2026-08-11
**Question:** dev_studio could publish its scenario runner as a compiled web
app. Can we? And if so, what does the CLI + GUI export look like — the shape
Previews already has (`fw run previews build-web`, "Build a web page…").
**Answer:** yes, both ways. The *live* route dev_studio took is proven to work
here — measured below, not argued — but it costs a debug-mode bundle, loses
widget-creation locations, and demands that the user's app compile for web. The
*snapshot* route needs none of that and is what ships first.
**Decision (owner, 2026-08-11):** snapshot first, live later behind the same
command as `--live`. The export **re-runs the scenarios**; `--offline` is a
flag and a checkbox rather than the default.
**Status:** the snapshot route is **built** — `fw run scenarios export`, the
"Export a web page…" command on the package row, and the viewer that serves
both. Verified end to end against `examples/example`: 5 scenarios, 36 steps,
142 artifacts, 16.8s including the run. See "What was built" below.
**Lineage:** dev_studio `/Users/xavier/projects/dev_studio`, `lib/core/web_compiler.dart`
and `lib/main_scenario_web.dart`.
**Method:** a throwaway `flutter create` package outside the workspace, on the
pinned SDK (3.47.0-0.1.pre), built with `flutter build web` and run in a real
browser. No changes to this tree.

## What dev_studio did

Three moves, and only the first is clever.

**Two Flutter web apps on one page.** The viewer at the root, the app and its
scenarios in `client/`, loaded in a **0×0 hidden iframe**
(`lib/main_scenario_web.dart:44`). This is forced, not stylistic:
`AutomatedTestWidgetsFlutterBinding` is a singleton that owns the frame
pipeline, so a viewer cannot share an isolate with it. The client is never
seen — only the frames it captures and posts out.

**postMessage as a `StreamChannel<String>`.**
`lib/client/src/scenario_runner/runtime/setup_web.dart` picks its transport at
startup: a WebSocket when `scenario-server-url` is defined, `window.parent`
otherwise. Their runner was already a protocol client, so the web port swapped
a transport and touched nothing else.

**`buildWebBundle` is two `flutter build web` calls.** Viewer → `out/`, client
→ `out/client/`, plus a hand-written `index.html` carrying build metadata in a
`<body build-info="…">` attribute.

Ours is not a protocol client. `lib/src/scenarios/harness.dart` is welded to
`dart:developer` service extensions and `dart:io` file writes, and
`lib/src/scenarios/scenario.dart:964` writes shots itself. That difference is
the entire cost of the live route.

## The spike

A web build of `AutomatedTestWidgetsFlutterBinding` + the `Declarer` / `Suite` /
`LiveTest` walk the harness does + our exact capture path (`layer.toImage` →
`toByteData(png)` inside `tester.runAsync`).

**It works.**

| | |
|---|---|
| the `flutter_test` + `test_api` closure under dart2js | compiles, no stubs, no fork |
| build | 11–13s |
| scenario (pumpWidget, pumpAndSettle, tap, 2 captures) | 413ms |
| `layer.toImage` | 89ms cold, **3ms** warm |
| PNG encode | 11–19ms |
| a 390×844 step | 7.6 KB PNG, 1.3 MB raw |

The captured PNG was rendered back into the page and read by eye: real layout,
real fonts, the text where it belongs. `flutter_test` ships `_binding_web.dart`
/ `_goldens_web.dart` conditional halves, and the web engine implements
`Scene.toImage` and `toImageSync`
(`bin/cache/flutter_web_sdk/lib/_engine/engine/layer/layer_scene_builder.dart:23`),
which is why none of this needed help.

### Three prices, all measured

**Asserts are mandatory, so the client is a `--debug` build.** `debugLayer` is
assert-gated — in a `--release` build it is null and capture dies with `Null
check operator used on a null value`. That is not a capture-path detail to
route around: `flutter_test`'s own `captureImage` reads `debugLayer` too, and
the inspector's tree needs debug fields throughout. The tool passes
`--enable-asserts` only for `BuildMode.debug`
(`packages/flutter_tools/lib/src/web/compiler_config.dart:102`). Cost: **8.0 MB
`main.dart.js`, 1.29 MB gzipped**, dart2js `-O1`.

**No `--track-widget-creation` on web.** The tool never passes it for a web
target. The per-step tree keeps its structure and loses its source locations,
so the click-a-node→insert-`tap()` path cannot work on the page. A GUI feature,
not a page feature — but say so rather than shipping a tree with dead links.

**The user's app must compile for web.** One `dart:io` import anywhere in the
graph ends it. This is the adoption cliff, and it belongs to their project, not
to ours.

Also seen, and left as a note: the web binding finishes a test with a
`SemanticsHandle` still active and reports it. Ours wants a handle anyway for
`captureSemanticsTree`.

Offline artifacts are possible: `--no-web-resources-cdn` bundles CanvasKit
instead of pointing at gstatic (`flutter_command.dart:1496`).

## The design

### The viewer is ours, and it is the same in both routes

The unifying fact. The snapshot page and the live page differ only in where the
steps come from — a `report.json` fetched over HTTP, or a channel to a client
iframe. Everything above that seam is the panel we already have.

And because the viewer is *ours*, it compiles from `app/` — which already has a
`web/` directory — and its bundle is **data-free**. Build it once, cache it
keyed by app version + SDK revision, and every later export is a file copy
rather than a 60s compile. No generated package, no synthetic pubspec, no
`pub get`; `app` is `resolution: workspace` and cannot be path-depended on from
outside anyway.

The consequence worth stating plainly: **the snapshot export asks nothing of
the user's project.** Not web support, not a web-clean import graph, not even a
`web/` directory. It works for every project that can run scenarios at all.

### What has to move

The viewer's import closure is already almost web-clean — `flow_view`,
`step_page`, `events_view`, `framed_shot`, `step_status`, and everything they
pull from `inspect/`, `ui/`, `previews/`, `utils/graphite.dart` carry no
`dart:io`. Two offenders:

- `app/lib/src/plugins/native/scenarios_results.dart:317` — five `File` getters
  and `readEvents()` reading the events file off disk. The model has to stop
  knowing about disks: a loader supplied by the host, `File` on the desktop and
  `http.get` on the page.
- `app/lib/src/utils/raw_image_provider.dart` — one import.

That is the whole refactor for route A. It is a seam, not a rewrite.

### The output

```
build/scenarios/web/
  index.html            the cached viewer bundle
  main.dart.js
  report.json           the run, verbatim from the harness
  shots/…               PNGs, trees, semantics, events — as written today
```

Fetched relative to the base href, which means the page needs a server —
exactly as the Previews page does, and `app/lib/src/previews/web_server.dart`
already is one.

### The surface

Mirrors Previews, deliberately:

- **CLI** — `fw run scenarios export [--output build/scenarios/web]
  [--base-href /x/] [--serve]`, alongside `run` and `shots`.
- **GUI** — a "Build a web page…" action in the scenarios panel, the
  `web_build_dialog.dart` shape, with serve-and-open afterwards.

### The seam for `--live`

Route B adds a second bundle in `client/` built from the user's package (a
generated entrypoint, exactly as `WebAppGenerator` does for Previews), the 0×0
iframe, and a postMessage channel. What it needs from us first:
`harness.dart` split into a transport-neutral core plus two adapters — the
`dart:developer` + disk one it is today, and a channel + in-memory one — and
`Platform.environment` in `profile.dart` / `scenario.dart` behind conditional
imports.

Design the viewer's data source as an interface **now**, so B drops in without
touching a widget.

## What was built

| | |
|---|---|
| `app/lib/main_scenarios_web.dart` | the page's entry point — data-free |
| `app/lib/src/scenarios/web_viewer.dart` | the page: scenario list, flow, step, inspect dock |
| `app/lib/src/scenarios/web_report.dart` | the envelope, shared by exporter and page |
| `app/lib/src/scenarios/artifacts.dart` + `_io` / `_http` | the seam, and its two ends |
| `app/lib/src/scenarios/web_export.dart` | build, copy, rewrite, write |
| `app/lib/src/scenarios/web_export_dialog.dart` | the GUI, on the catalog's dialog shape |
| `ScenariosCore.exportWeb` + `webExportActionId` | the CLI action, and what the dialog calls |

The viewer compiles to **2.9 MB** of release JS, and the page renders the run
with real device frames, real transition arrows, the elements tree and the
semantics tree, all fetched over HTTP.

Two decisions changed on contact:

**The file source reads synchronously.** `ScenarioArtifacts` is an
asynchronous interface because the other end is a network, but
`FileScenarioArtifacts` returns `SynchronousFuture`s over the sync file APIs.
Going through the thread pool put a frame between opening a step and seeing
its tree — and in a widget test, a hang, because a real `readAsString` never
completes under `FakeAsync`.

**The base href is patched, not compiled in.** `flutter build web --base-href`
only edits one attribute of `index.html`, so the export rewrites it after
copying. That is what lets one cached bundle serve every mount point.

**Motion is not exported** (owner, 2026-08-11: "this would be too big"). The
recorded transitions `2026-07-31-motion-design.md` added are the bulkiest thing
a run produces — every frame of every transition, against five small files for
the step itself — and a page is a thing people download. The export **strips**
the frame fields rather than merely not copying them: the panel records by
default, so a report reaching the exporter may well carry them, and a step that
kept them with no frames beside it would put a play button on the page that
fetches nothing and never moves. `ScenariosCore`'s "panel-only, deliberately"
note about recording now holds for one more surface, and for a different
reason: the page *can* watch a movie, it just should not have to download one.

And one bug worth remembering, because it reported success: the collector
walked the report *envelope* instead of the run inside it, copied nothing, and
returned a perfectly healthy-looking result whose only tell was
`"artifacts": 0`. `app/test/scenarios/web_export_test.dart` asserts the count.

## Unproven

- Route B against a **real** app. The spike compiled a toy; the unknown there
  is the user's package, not the harness. `examples/example` is the gate.
- `--offline` end to end. The flag is wired and reaches
  `--no-web-resources-cdn`; nobody has read the resulting page with the network
  off.
- The GUI dialog by hand. Its core path is the same `exportWeb` the CLI runs,
  and the command it echoes is tested against the action's declared flags, but
  nobody has clicked the button.
- Whether `--extra-front-end-options=--track-widget-creation` can force
  creation locations into a web build. Untested; assume not.
