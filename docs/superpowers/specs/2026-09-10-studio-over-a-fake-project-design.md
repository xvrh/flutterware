# The studio over a fake project — scenario tests of flutterware itself, and a web demo

**Date:** 2026-09-10
**Question:** two ideas that feel connected. (1) Scenario tests for the studio
itself — the same harness users get, pointed at our own GUI, to catch
regressions and iterate on UI. (2) A web demo of the studio, linked from the
README, over fake read-only data, so a reader sees what it looks like before
installing anything. Both seem to need an abstraction that can be faked. Is
there a place to put that hook, and does the abstraction make the code better
on its own — the only condition under which it is worth having?
**Answer:** yes to both, and they share one hook. Most of that hook already
exists: the shell has run over fake cores since the first shell test. The gap is
one level down — panels are typed on their concrete cores — and closing it is a
per-plugin interface extraction, not a generic provider layer. The web half
looked fatal (138 files importing `dart:io` in the shell's closure) and is not:
a real `flutter build web` of that closure fails on exactly one thing.
**Decision:** none yet. This is the investigation, written up for the decision.
The recommendation is at the end: scenarios first, as the go/no-go.
**Method:** read of the plugin layer, the two headline panels and their tests;
an import-closure walk over `app/lib`; one throwaway `flutter build web` of an
entry point importing the shell (deleted afterwards). No changes to this tree.

## What is already there

**The shell already runs over a fake project.** `ShellController`
(`app/lib/src/shell/shell_controller.dart`) takes every outside dependency as a
constructor argument: `coreRegistry`, `registry` (panels), `manifestLoader`,
`discovery`, `worktreeFacts`, `worktreeWatcher`, `watchEvents`.
`app/test/shell/shell_view_test.dart` pumps the entire studio over a
`_FakeCore` per plugin, a `_StubLoader` that hands back a manifest without
spawning anything, and a `WorktreeDiscovery` whose `runProcess` returns a
canned `git worktree list`. No process, no disk, no daemon. The rail, the
band, the badges, the teardown dialog and the ⌘K palette read nothing but
`PluginReport`, which is plain data — that was master-plan decision 2, and it
held.

So "the studio over fake data" is built today, down to the panel boundary.

**Below that boundary, the seams sit at the process edge.** Each core keeps
the real machine behind something a test can replace:

| plugin | seam | used by |
|---|---|---|
| scenarios | `ScenariosCore.debugInstallRunner(path, ScenarioRunner)` | `app/test/scenarios/panel_test.dart` — real core, real panel, fake runner that writes real files |
| scenarios | `ScenarioArtifacts` with `_io` and `_http` ends | the panel (io) and the exported page (http) |
| previews | `CatalogSession.connectToDaemon` | daemon client tests |
| previews | `PreviewThumbnails(PreviewRender)` — a function | thumbnail tests |
| previews | `InspectClient` over a fake guest | `app/test/previews/show_entry_test.dart` |
| export | `ViewerBundle.debugCompile` | export tests |
| shell | `WorktreeDiscovery.runProcess` | every shell test |

These are the right seams for core tests, and they stay. They are the wrong
seams for a web demo, because a core with a fake runner still walks the disk
to *list* scenarios, and a session with a fake daemon still owns an embedded
engine.

**The gap: a panel is typed on its concrete core.** `NativePlugin<C extends
PluginCore>` hands the panel `core` as `C`, and the panel calls it directly —
by design, since a run dialog streaming output for thirty seconds is not a
shape `Session.invoke` can express. Counted by grep over the two headline
panels:

| panel | distinct core members touched | core size |
|---|---|---|
| `scenarios_plugin.dart` | ~25 (`scanResultFor`, `panelRunFor`, `startRun`, `branchDelta`, `offeredDevicesFor`, `renderVideo`, …) | 4,521 lines |
| `previews_plugin.dart` | ~15 (`sessionFor`, `thumbnailsFor`, `entriesFor`, `canvasesFor`, `testRunnerFor`, …) | 3,423 lines |

A fake at this level means an interface per plugin: what the panel reads,
and the verbs it fires. That interface is the abstraction the question was
about.

## The web, measured

The shell's import closure, walked over relative and `package:flutterware_app`
imports from `app/lib/src/shell/shell_view.dart`:

| | files |
|---|---|
| closure of `shell_view.dart` | 399 |
| of which import `dart:io` | 138 |
| `dart:isolate` | 12 |
| `package:vm_service` | 10 |
| `package:watcher` | 2 |
| `package:hooks_runner` / `package:code_assets` | 3 (`assets/build_hooks.dart`, `previews/asset_bundle.dart`, `plugins/manifest_loader.dart`) |

For comparison, the closure of `main_export_web.dart` — the viewer that already
ships — is 105 files, and `scenarios/flow_view.dart` alone is 44.

Then the experiment: a throwaway `lib/main_web_probe.dart` importing
`shell_view.dart` and running an empty app, built with `fvm flutter build web`
on the pinned SDK. It fails in 29s on **exactly one thing**:

```
Error: Dart library 'dart:ffi' is not available on this platform.
  main.dart => package:flutterware_app => package:hooks_runner => dart:ffi
  main.dart => package:flutterware_app => package:code_assets => dart:ffi
```

Nothing else. dart2js ships `dart:io` and `dart:isolate` as libraries that
compile and throw `UnsupportedError` at run time, so 138 imports are not 138
problems. The app itself imports no `dart:ffi`; the embedder reaches native
code by other means. `package:vm_service` is pure Dart over a socket and
compiles.

So the web has two prices, and they are different in kind:

- **Compile:** fence the three files that reach `hooks_runner`/`code_assets`
  behind a conditional import. Small, and the `url_fragment.dart` shim in
  `app/lib/src/utils/` is the pattern already in the tree.
- **Run time:** whatever the demo *executes* must never touch `dart:io`. A
  recorded core guarantees that for the plugin's behaviour; what remains is the
  chrome's own touches, which are few because the shell was kept thin:
  `Platform.isMacOS` in two build methods (`shell_view.dart:448`,
  `catalog_view.dart:3024` — a `defaultTargetPlatform` check is the better
  spelling anyway), `Workspace.exists` (short-circuits on `discovered`),
  `AppContext.appToolDirectory` and `PackageRef.directory`, which construct a
  `Directory` eagerly.

One thing is **unverified**: whether `Directory(path)` can be *constructed* on
dart2js without throwing. If it cannot, those two fields become paths, which
they arguably should be — nothing reads them as a `Directory` at the shell
level.

## Where the guess was half right

The question assumed scenarios and previews are the hardest to fake. Half of
that is backwards.

**Scenarios are the easy half.** The fake data is a real run's export, and the
export is the published, version-gated format (`report.json` with its typed
reader; see `2026-08-11-scenario-web-export-design.md`). `main_export_web.dart`
already draws the flow view, the step page, the inspect dock and the beat view
in a browser from that file over `HttpScenarioArtifacts`; the panel's
`_ScenarioPage` draws the same `ScenarioFlowView`. A recorded scenarios core is
"a core over a `ScenarioWebReport` plus a listing", and every widget below it
exists.

The one wrinkle is the tell that this abstraction pays: the panel hard-wires
`IoScenarioArtifacts` at `scenarios_plugin.dart:372`, where the web viewer
installs the HTTP one. *Where a run's artifacts are read from* is a fact about
the run, not about the panel drawing it. It belongs on the core, and moving it
is the first line of code this work forces.

**Previews are the hard half.** The panel's centre is not data: it is
`CatalogSession`, which owns an `EmbeddedEngine` (a texture), a compiler
daemon client, a live session and an inspect client. A recorded core has to
replace each with its still form:

| live | recorded |
|---|---|
| `GuestTexture(textureId)` on the stage | a still picture — `catalog_view.dart:928` already branches on `engine.textureId == null`, so the picture becomes something the session provides rather than something the view builds |
| `PreviewThumbnails` rendering through `flutter_tester` | PNGs on disk / over HTTP, through the existing `PreviewRender` function |
| `InspectClient` walking the guest | a recorded tree and semantics, the `_FakeGuest` shape `show_entry_test.dart` already has |
| knobs and axes round-tripping to the guest | read-only; a change shows nothing, and the demo says so |
| the compile loop, `SwitchReport`, the startup strip | absent; the status bar reads "recorded" |

This is where the interface gets leaky, and it is the part to budget for. The
comparison's exported page already draws preview *shots* on the web
(`comparison/ui/previews_tab.dart` over `shot_store_http.dart`), which is
evidence the still form is enough for a reader.

## Does the abstraction make the code better?

Yes in three specific ways, and no in one.

**It turns a doc rule into a type.** `native_plugin.dart` says a panel may hold
no capability its core does not have, and must not itself spawn what an action
spawns. With a concrete core in hand nothing enforces that — `web_build_dialog`
calling `core.buildWeb` is fine today only because someone checked. An
interface of reads plus verbs makes the drift a compile error.

**It names what a panel actually depends on.** Twenty-five members of a
hundred-odd. The rest is the machine — build lanes, tester hosts, digests,
watchers — and drawing the line between the two is the refactor. It also
answers the question every panel bug has come with since 2026-08-13 (see the
config-reload findings: a panel tracking a core in `initState` only): what a
panel needs from a core is small enough to be written down.

**Whole panels become previewable in the studio's own catalog.**
`app/tool/catalog/demos/` shows pieces — the comparison stage, the verdict, the
device strip — because a whole panel needs a core, and the sessions that built
those demos each hand-rolled a stage set. A recorded core is the stage set,
made once and shared by three consumers.

**No, if it is done as a generic provider.** The data differs per plugin and
there is no common shape to abstract; a `Provider` with a `get(key)` would be a
map with a fancier name. And **no** if the seam is pushed to `FileSystem` /
`ProcessManager` injection across 138 files — `package:file` is a dependency
already, but threading it everywhere is a large diff whose only beneficiary is
the demo, and the process seams already exist for core tests.

## The design

### One fixture, three consumers

A **fixture** is a directory the real tool produced from `examples/example`:

```
app/demo/fixture/
  status.json            fw status --json — every plugin's PluginReport
  scenarios/
    listing.json         what the panel's list pane draws
    report.json          one run's export, artifacts beside it
    artifacts/…
  previews/
    entries.json         the scan
    thumbnails/…         previews screenshot, one per entry
    trees/…              inspect json per entry
```

Produced by a script (`app/tool/demo/record.dart`), not by hand, so the fixture
is only ever an output of the shipped formats and cannot silently drift from
the readers — every file has a typed reader with a version gate already. A
fixture that stops loading is a format change that needs a note, which is the
right time to find out.

The three consumers:

1. **Catalog demos of whole panels** — a `@Preview` per panel, staged at
   `Devices.window`, light and dark. The thing the studio UI pass kept
   wanting.
2. **Scenario tests of the studio** — `app/test/scenarios/*.dart`, run by the
   same harness users run.
3. **The web demo** — `app/lib/main_demo_web.dart`, the shell over the recorded
   registry, fetching the fixture over HTTP.

### Per plugin: an interface, a live core, a recorded core

```dart
abstract class ScenariosCore extends PluginCore {      // what the panel sees
  ScanResult? scanResultFor(String package);
  ScenarioPanelRun? panelRunFor(…);
  ScenarioArtifacts artifactsFor(…);                    // moved here from the panel
  Future<void> startRun(…);
  …
}
class LiveScenariosCore extends ScenariosCore { … }     // today's class, renamed
class RecordedScenariosCore extends ScenariosCore { … } // reads the fixture
```

`panelFor<ScenariosCore>(ScenariosPlugin.new)` in `native/registry.dart` does
not change. `defaultCoreRegistry()` maps the id to the live core; the demo's
registry maps it to the recorded one. Verbs on the recorded core do nothing
and say so — a run button in the demo shows "this is a recording" rather than
disappearing, because a demo whose controls vanish shows less of the product
than a demo whose controls explain themselves.

The other twelve plugins get one generic `RecordedCore` over their
`PluginReport` from `status.json` — enough for the rail, the badges and search
— and a panel that says "not in this demo". `MissingPlugin` is that shape
already; the demo registers a sibling with kinder words. Dependencies is the
candidate for a third real panel later, since its panel is nearly all table
over `PubDepsStore` output.

### Scenario tests of the studio

Declare `app` in the root manifest's `Scenarios(packages:)`. A test builds a
`ShellController` over the recorded registry, exactly as `shell_view_test.dart`
does, and pumps `ShellApp(shell)`:

```dart
scenario('Open a scenario run', (s) async {
  var shell = demoShell();                     // recorded registry, stub loader
  await shell.start('/demo');
  await s.pumpWidget(ShellApp(shell), shot: Shot('Overview'));
  await s.tap('Scenarios', shot: Shot('Scenarios'));
  await s.tap('Around the shop', shot: Shot('Flow'));
});
```

Two facts make this work without new machinery. `IoScenarioArtifacts` returns
`SynchronousFuture`s over sync file APIs precisely so that a widget test under
FakeAsync does not hang (found 2026-08-11), and neither headline core arms a
`Timer` at construction — the grep found none — so the walk settles. What the
harness draws with is its own font, not the platform's: the pictures are
deterministic, and they are not pixel-identical to a macOS window. For
regression that is the property wanted.

### The web demo

`main_demo_web.dart` = `main_dev.dart` with the recorded registry, an
`HttpScenarioArtifacts`-style fixture source, `setUrlStrategy(null)` as the
export entry point already does, and none of the dock-icon or window-title
calls. Built by the same `ViewerBundle` machinery, hosted where the viewer
already is (the GitHub Pages workflow from PR #306). The README link points at
it.

## Rejected

- **A generic fake data provider.** No shared shape to provide; see above.
- **`FileSystem` / `ProcessManager` injection through the cores.** Right for a
  library, wrong at 138 files for one consumer; the process seams exist and
  serve core tests better.
- **Faking at the runner level for the web.** A fake runner leaves a real core
  that lists scenarios by walking `test/` on disk. The demo needs the core not
  to *want* a disk.
- **Building the demo from the live export route** (the 0×0 iframe design from
  2026-08-11). It makes the user's app compile for web, and the studio is the
  app here — that is the 399-file closure, running for real, in a browser. The
  recorded route needs none of it.
- **Recording the fixture by hand.** A hand-written `report.json` is a second
  spelling of the format that nothing keeps honest.

## Unproven

- `Directory(path)` construction on dart2js — a throw there turns two fields
  into strings, which is a small change but a real one.
- That the previews interface comes out narrow. Fifteen members is the count
  of *calls*; `sessionFor` returns a `CatalogSession`, and how much of that
  object the view reads is the real width. Measure it by doing scenarios first.
- Whether a scenario of the shell settles cleanly with the shell's
  `_RebuildsWhen` filters and the facts controller stubbed. `shell_view_test`
  says yes under `flutter test`; the harness's `Settle` is stricter.

## The angle of attack: one small plugin, the whole slice

Before scenarios, a vertical slice through a plugin small enough that the
slice is mostly the *shared* work — the fixture, the stage set, the harness
on the studio, the web fence — and hardly any plugin work at all. Measured
over the simpler panels (distinct core members the panel touches / files in
the panel's import closure / of which `dart:io`):

| plugin | core members | closure | `dart:io` |
|---|---|---|---|
| launcher icon | 2 in the panel + 4 in the screen (`scanFor`, `failureFor`, `isScanning`, `reload`) | 47 | 8 |
| assets | 2 | 61 | 13 |
| splash | 3 | 63 | 11 |
| dependencies | 5 | 63 | 13 |
| lints | 12 | 48 | 11 |
| store | 6 | 65 | 25 + hooks_runner |
| translations | 19 | 105 | 44 |

**Launcher icon is the one.** Everything its screen reads is a pass-through of
one `ScanCache<(package, flavor), IconScan>`, and `ScanCache` takes its loader
in the constructor. So the recorded core is the *live* core with a canned
loader — `LauncherIconCore(host, scan: recorded)` — and no interface is
extracted at all. Of its 8 `dart:io` files, 5 are the shell's own
(`context.dart`, `package_ref.dart`, `workspace.dart`, `repo_layout.dart`,
`flutter_sdk.dart`) — the shims the web demo needs regardless — and the
plugin's own three are the scan (never run on web) and one leak in the screen:
`FileImage(File(file.absolutePath))` at `launcher_icon/screen.dart:177` and
`:251`. That leak becomes an `ImageProvider Function(IconFile)` the core
supplies, which is the only plugin-specific change. The fixture is real:
`examples/example` carries five Android source sets and three iOS icon sets,
put there as fixtures for this very viewer.

The same loader hook covers assets, splash, scene and translations, whose
listings also sit on `ScanCache`. It does **not** cover scenarios or previews
— their listings are their own — which is why those keep the interface plan
above.

The slice, and what each step proves:

1. `LauncherIconCore` takes an optional `scan` and `image`; `IconScan` and its
   five model types gain `fromJson` (they have `toJson` projections already,
   and the package uses `json_serializable`). *Proves nothing yet; ~50 lines.*
2. `app/tool/demo/record.dart` runs `scanIcons` on `examples/example` for
   every flavor and writes `app/demo/fixture/launcher_icon/*.json` with the
   PNGs beside. *Proves the fixture is an output of the real tool.*
3. The `_FakeCore` / `_StubLoader` / canned-`git` trio moves out of
   `shell_view_test.dart` into `app/lib/src/demo/` as the recorded project:
   a `ShellController` over `status.json` for every plugin and the recorded
   icon core for one. *Proves the stage set is shared, not per-test.*
4. `app/tool/catalog/demos/launcher_icon_panel.dart`: the whole panel, light
   and dark, at `Devices.window`. *Proves a whole panel previews.*
5. Declare `app` in the root manifest's `Scenarios`; write
   `app/test/scenarios/studio_test.dart` — open the shell, go to Launcher
   icon, switch flavor, three shots. *Proves the harness walks the studio
   under FakeAsync and settles.*
6. Fence the three `hooks_runner`/`code_assets` files, shim the two
   `Platform.isMacOS`, resolve the `Directory` question on `AppContext` and
   `PackageRef`, add `main_demo_web.dart`, build and open it. *Proves the
   shell renders in a browser at all.*

At the end of step 6 every shared question is answered on fact and the only
thing left to decide is the interface for the two big plugins — which is
then a decision about those two plugins, not about the idea.

### Two decisions the slice needed, settled on evidence

**Record the scan, not the projection.** The core already emits a JSON
inventory for `fw` (`IconInventoryResult`), so the cheap-looking move is to
record that and draw from it. It is lossy in exactly the places the screen
reads: the projection drops `IconFile.inherited` and `absolutePath`, re-roots
every path to the worktree, keeps `declaredSize` only on a mismatch, omits
empty roles, and reduces `AndroidWiring` to `minSdk` and its source — while
the screen reads `file.inherited`, `file.absolutePath`, every role, and the
wiring. Drawing from the projection means a second screen. So `IconScan` and
its model types (`IconFile`, `IconRoleScan`, `IconFinding`, `IconFlavor`,
`AndroidWiring`, `AdaptiveXml`; the enums by name, `IconRole` by id) gain
`fromJson`/`toJson` with `json_serializable`, which the package already runs.
The fixture is then the scan itself, with the referenced PNGs beside it and
`absolutePath` rewritten to a fixture-relative path the image provider
resolves. The 60-line `_inventory` projection stays as the agent surface;
folding it into `scan.toJson()` is a follow-up, not a prerequisite.

**Keep `Directory` on `AppContext` and `PackageRef`; pass the root, never
read it.** Measured with a `dart compile js` probe run under node:

| on dart2js | result |
|---|---|
| `Directory('/demo/app')` | constructs, `.path` reads |
| `Directory.current` | throws `Unsupported operation: _Namespace` |
| `.absolute.path` | throws `Unsupported operation: Platform._operatingSystem` |
| `.existsSync()` | throws `_Namespace` |
| `Platform.isMacOS` | throws |

So the two fields are fine as they are. What must hold on the web is that
nothing *reaches* the throwing members: `AppContext`'s `Directory.current`
default is not taken when the demo passes a root; `PackageRef.absolutePath`
is read only inside live scan loaders, which the recorded core replaces;
`Workspace.exists` short-circuits on `discovered`, which the recorded project
fills; `worktree_discovery.dart:103` takes `.absolute` only on the not-a-repo
branch, which a valid canned listing avoids. The two `Platform.isMacOS` reads
in build methods move to `defaultTargetPlatform`, which was the better
spelling anyway. No type changes, no diff outside the demo path.

## What was built (2026-09-10, same day)

The launcher-icon slice, all six steps, in one session. Every shared question
above is now answered on fact:

- **The recording.** `app/tool/demo/record.dart` scans `examples/example` as
  `.` and writes `app/demo/fixture/launcher_icon/`: five scans (main, beta,
  kiosk, partner, pro), 89 files copied flat, 295 KB, declared as two asset
  directories. `IconScan` and its six model types round-trip through JSON;
  a role is spelled by its id on the wire.
- **The doors.** `LauncherIconCore(scan:)` takes an `IconScanner`;
  `LauncherIconScreen(image:)` and `LauncherIconPlugin(image:)` take an
  `IconImage`. The live core over the recorded reader is the recorded core.
- **The stage set.** `app/lib/src/demo/recorded_project.dart`: a
  `ShellController` over canned git, an in-process manifest written with the
  same `FlutterwareConfig` classes a project uses, inert facts probes, empty
  watch streams, a quiet `RecordedCore` and a `NotRecordedPlugin` panel for
  the five plugins with nothing recorded. `test/demo/recorded_project_test.dart`
  opens it end to end.
- **Whole-panel catalog entries.** Three in `launcher_icon_panel.dart`,
  photographed through `previews screenshot` under `flutter_tester` with the
  recording read from assets — light, dark, and the kiosk flavor showing
  "4 not overridden" over main's art.
- **The studio scenario.** `app` declared in the root manifest's `Scenarios`
  (narrowed to `test/scenarios`); `studio_test.dart` opens the shell, walks to
  the panel, switches flavor and lands on a not-recorded plugin. Four shots,
  1.4s, green under the harness at `window`.
- **The web.** `lib/main_demo_web.dart` builds in 27s and runs: rail, tabs,
  overview, the launcher-icon panel with its pictures fetched from the asset
  bundle. What it took beyond the compile fence:

  | touch on the run-time path | fix |
  |---|---|
  | `hooks_runner`/`code_assets` import `dart:ffi` | `build_hooks.dart` is a conditional export over `_io` and `_stub`; the kernel-asset types route through it |
  | `Platform.isMacOS` in two build methods | `defaultTargetPlatform` |
  | `flutterwareDir()` reads `HOME` from the environment; `flutterwareRunDir()` creates it | both answer a nominal path on `UnsupportedError` |
  | `WorktreeWatcher` defaults `agentRoot` and `runDir` from the environment at construction | the recorded shell passes both |
  | `scanRunHandles` lists the run directory from the desk button's `initState` | returns nothing on `UnsupportedError`, beside the existing `FileSystemException` case |
  | `ConfigWatcher.watching` and `WorktreeWatcher.start` stat the disk | answer nothing on `UnsupportedError` |
  | `changesConfigKey` stats the config file after every load | null on `UnsupportedError` |
  | `findRepoRoot` and `discoverPackages` walk the disk | null / empty on `UnsupportedError` |

  Every one of these is also the right answer on a desktop whose filesystem
  refuses: the change makes a hostile disk a quiet screen rather than a red
  one. None touched a plugin.

- **A trap worth recording.** The file end of a recording hands back
  `SynchronousFuture`s, and a throw *after* awaiting one escapes the `async`
  function into the zone instead of failing its future — no caller can catch
  it. `recordedIconScanner` awaits through `Future.value(...)` so the resume
  is a microtask. The reverse trap (a real future never landing under
  FakeAsync) is why the file end is synchronous in the first place; the two
  together are the rule: a recording's readers resume on a microtask, never
  inline.

Not done: hosting the page and the README link. The viewer bundle's Pages
workflow is the template.

## What to do next

0. ~~The launcher-icon slice.~~ Built; see above.
1. **Scenarios next, as the go/no-go for the interface.** Extract `ScenariosCore`'s panel-facing
   interface, rename today's class `LiveScenariosCore`, move the artifacts
   source onto it, write `RecordedScenariosCore` over a fixture the record
   script produced. Deliverable: one whole-panel catalog demo, one studio
   scenario with shots, and the panel on the web behind the `dart:ffi` fence.
   Roughly two to three days. If the interface is unpleasant here, it will be
   worse for previews, and that is the moment to stop.
2. **Previews.** The still picture, recorded thumbnails and inspect, read-only
   knobs. Three to five days.
3. **The demo entry point, the record script as a documented command, the
   Pages deploy and the README link.** One to two days.

Related: `2026-08-11-scenario-web-export-design.md` (the viewer this rides
on), `2026-07-29-config-reload-findings.md` (why a panel's dependence on its
core is worth writing down), `2026-07-27-gui-cli-mcp-architecture.md`
(decision 2 — the report is data, only the panel forks).
