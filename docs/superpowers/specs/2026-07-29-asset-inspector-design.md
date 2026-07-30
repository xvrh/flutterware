# The asset inspector — and why it is not a file browser

**Date:** 2026-07-29
**Status:** design. "What is already true" is verified against the code in this
worktree; everything else is a proposal.
**Extends:** `2026-07-27-gui-cli-mcp-architecture.md` (decisions 1–6 hold),
`2026-07-26-packages-and-laziness.md` (the parsing budget).

## The question

A small new plugin: show every asset a package registers, with previews —
images, SVG, Lottie, fonts — plus search, filtering and metadata. Where is the
value beyond what an IDE's file tree already gives, and what do `fw` and MCP get
out of a feature this visual?

## The short answer

**The inspector shows what the engine will resolve, not what the folder
contains.** That single reframing is what makes it worth building, makes it
correct by construction, and gives the CLI something to do.

| | verdict | why |
|---|---|---|
| A browser over `assets/` | **no** | the IDE has one, and it knows nothing about pubspec |
| A view of resolved asset keys | **yes** | the gap between disk, pubspec and manifest is where every real asset bug lives |
| A second asset resolver | **no** | one exists, and it is verified frame-for-frame against `flutter build bundle` |
| GUI-only | **no** | `audit` is a CI gate, and the exact key string is what an agent gets wrong |

### The thesis

Three sets that everyone assumes are one:

1. files on disk under the asset roots,
2. entries declared in pubspec — the package's own, **and every dependency's**,
3. keys that reach `AssetManifest.bin`, which is what `Image.asset` looks up.

Every asset bug is a gap between two of them. The sharpest example, and the one
nothing warns about today: **a directory declaration is not recursive.**
Declaring `assets/` includes the files directly inside it and *not*
`assets/icons/`. The files are on disk, they are in a declared tree, they are in
version control — and they are not in the bundle. The app throws at runtime,
pointing at a path that visibly exists.

An inspector built on the resolver the guest engine already uses can show all
three sets and the diff between them. It is also honest by construction: if it
disagrees with the running app, the guest is wrong too.

## What is already true (verified)

### 1. The resolver exists, and it is not a sketch

[`AssetBundleBuilder`](app/lib/src/catalog/asset_bundle.dart) assembles the
asset directory the embedder guest reads, without invoking
`flutter build bundle`. To do that it re-implements Flutter's resolution in
plain Dart — `dart:io`, `yaml`, `package_config`, no Flutter:

| | where |
|---|---|
| root package unprefixed, every other package keyed `packages/<name>/…` | [`_collect`](app/lib/src/catalog/asset_bundle.dart:63) walks the package config |
| `assets:` in string form and map form (`- path: …`) | [`_readPubspec:96`](app/lib/src/catalog/asset_bundle.dart:96) |
| directory declarations, non-recursively, files only | [`_addAsset:109`](app/lib/src/catalog/asset_bundle.dart:109) |
| `2.0x/`-style density variants, and *not* mistaking a variant for an asset | [`_register:131`](app/lib/src/catalog/asset_bundle.dart:131), [`_parseScale:289`](app/lib/src/catalog/asset_bundle.dart:289) |
| `fonts:` families with weight/style, package-prefixed | [`_addFonts:157`](app/lib/src/catalog/asset_bundle.dart:157) |
| `uses-material-design` pulling in `MaterialIcons-Regular.otf` | [`:90`](app/lib/src/catalog/asset_bundle.dart:90), [`_writeManifests:190`](app/lib/src/catalog/asset_bundle.dart:190) |

`tool/catalog/bundle_probe.dart` renders the same scene against this bundle and
against the tool's own and compares frames byte for byte. **The correctness of
the resolution is already someone's job**, and the inspector inherits it for
free.

What it does *not* handle, and the inspector therefore starts without: `flavors:`
on an asset entry, `transformers:`, and `.lottie` archives. All three are
listed under "Backlog" rather than silently absent.

### 2. The existing asset report is legacy, and wrong

`createAssetReport` in `app/lib/src/overview/model/assets.dart` counts files and
bytes for the old single-project app.

**Corrected 2026-07-29**, during M1: this section first said nothing outside
`app/lib/src/overview/` imports that directory. It does — `project.dart` imports
the service by relative path, which the grep behind the claim did not match. The
screens are legacy rather than dead: reachable from `main_dev.dart`, not from
`main.dart`, and slated for deletion (see `Project`'s own doc comment). Deleting
the model therefore meant deleting its call site in the metrics card too.

It is also wrong in a way worth recording so it is not copied:
[`_variants`](app/lib/src/overview/model/assets.dart:29) is
`['dark', '2.0x', '3.0x', '4.0x', '2x', '3x', '4x']`, and `dark/` is not a
variant directory — Flutter's asset resolution is density-based and has no theme
tier. The short forms in that list *are* fine:
`flutter_tools`' own regex is `RegExp(r'/?(\d+(\.\d*)?)x$')`
(`asset.dart:111`, `:935` in 3.47.0-0.1.pre) and its comment offers `plants/3x`
as an example match, so `3x` and `2.0x` are equally real. Deleted when the
plugin's report supersedes it.

**Corrected 2026-07-29**, during M0: an earlier draft of this section claimed
`2x` was not a density directory. It is. The claim was checked against the SDK
only after a fixture test failed on it, which is the order that should have been
used in the first place.

### 3. Most metadata lands on the Flutter-free side of the line

This decides how much reaches `fw` and MCP rather than the panel only.

| | Flutter needed? | note |
|---|---|---|
| size, mtime, declaration, variants, font family/weight/style | **no** | the resolver already has it |
| raster width/height/alpha | **no** | `image` is pure Dart and already an app dependency (`app/pubspec.yaml:56`) |
| Lottie dimensions, fps, in/out point, duration, layer names and types | **no** | `w`, `h`, `fr`, `ip`, `op`, `layers[]` are plain JSON. `dart:convert` reads them; the `lottie` package is not involved |
| SVG intrinsic size and viewBox | **no**, but | XML attributes. Needs an XML parse, which no current app dependency provides directly |
| duplicate detection | **no** | `crypto` is already an app dependency (`app/pubspec.yaml:38`) |
| rendering anything | **yes** | and only the panel does it |
| authoritative "this Lottie/SVG feature is not supported by the renderer" | **yes** | the renderer package is the only thing that can say |

So `fw describe --asset=…` returns real facts about a Lottie file — duration,
frame count, layers — with no dependency added at all. That was not obvious
going in.

### 4. What the contract requires of the core

From `PluginCore`: `report` is a pure read that must never start work;
`computeAll`'s budget is **parsing** — read files, parse, cache, no compiling or
spawning; `search` is a pure read called on every keystroke. The default
`search` already walks the report, so the plugin is searchable the day it
reports.

### 5. `examples/example` declares no assets at all

Its pubspec's `flutter:` section is entirely commented-out boilerplate. There is
nothing to develop against, so fixtures are M0 work, not a nicety.

## Decisions

**D1 — The inspector's subject is resolution, not the filesystem.** Every view
is keyed by asset key, and the filesystem appears as an answer to "where does
this key come from", plus one explicit "on disk, resolving to nothing" section.

**D2 — One resolver, two consumers.** Extract resolution out of
`AssetBundleBuilder` into `app/lib/src/assets/model/asset_catalog.dart`; the
builder keeps manifest writing and symlinking and consumes the catalog. Same
shape as the UI catalog's scan/screenshot split, and `bundle_probe.dart` is the
regression check for the extraction itself.

**D3 — Dependency assets are included, grouped under the bundle that pulls them
in.** A dependency's assets belong to whichever declared package depends on it;
two apps in one workspace have different dependency sets, so nothing floats at
top level unattached to a bundle. The tree is: `PluginChild` per declared
package → its own assets → `from packages/…`, one group per owning package,
collapsed by default.

This is also what promotes the weight report from a nice extra to a reason to
open the plugin: **bundle weight attributed per dependency** is a number that
otherwise requires unzipping a release build.

**D4 — No per-package config.** `Assets({List<AssetsPackage> packages})` in
`lib/src/plugins/first_party.dart`, with an `each` helper, mirroring
`DependenciesPackage`. The pubspec is the declaration; the config only names
which packages get a child. Options are added when something needs one.

**D5 — Metadata lives in the core wherever it can.** Per §3. The panel adds
rendering and nothing else, so every fact it shows is a fact `fw` can print.
Metadata is read lazily per asset and cached — **never in bulk during
`computeAll`**, which stays at parse-and-stat.

**D6 — Previews render GUI-side, with the guest as the stated destination.**
The GUI decodes with its own `flutter_svg`/`lottie`/`image`, not the user's
versions. Accepted for now because it is a fraction of the work and unblocks the
whole panel; the fidelity gap is real and named: "this SVG renders wrong in my
app" is a question only the user's own dependency versions can answer.

What keeps the door open is the address (below). A preview is already identified
by an address with its axes resolved, which is exactly the capture spec
`HeadlessCatalog` consumes — so moving rendering into the guest later changes
who draws the pixels, not what a preview *is*, and `preview` becomes an
`Artifact` on all three surfaces at that point.

**D7 — `lottie` becomes an `app` dependency.** Deliberate, and the first
"flutterware ships a renderer for a third-party format" decision. Privileged
here because the maintainer of the package is the maintainer of this repo; that
does *not* generalise to Rive, Spline or the next one, and each gets its own
argument.

**D8 — The projection truncates hard; the panel does not.** A real app's
dependency assets run to thousands of keys. `fw status` and MCP list the root
package's own assets and *count* the rest, via `ViewItems.truncated`.

## The address

```
fw:///<worktree>/flutterware.assets/<package>/<asset key…>?density=3.0x&frame=42&bg=checker
```

Identity is the segments; **density, Lottie frame and preview background are
applied axes**, which is the distinction `Address` already draws for theme. A
paused Lottie frame on a dark background is the same asset seen differently, so
it is one address, and a citable one.

Encoding mirrors [`ui_catalog_address.dart`](app/lib/src/plugins/native/ui_catalog_address.dart)
exactly: the package path is **one** segment (so `examples/example` arrives
percent-encoded as `examples%2Fexample`), and the asset key is split on `/` so
that `packages/foo/logo.png` stays readable as three segments. `catalogSegments`
and `catalogPlace` are inverses with a test that says so; `assetSegments` and
`assetPlace` get the same treatment, in the same one file, for the same reason —
drift here navigates silently to the wrong asset.

## What the panel shows

Master/detail, in the shape of [`dependencies/list.dart`](app/lib/src/dependencies/list.dart).

**List:** fuzzy filter on key, filter chips for kind and for "problems only",
the package grouping from D3. Sortable by size, because that is what the weight
question needs.

**Detail:** the preview, then metadata, then *where this key came from* — the
pubspec line that declared it, the file on disk, the variants found beside it.

Preview chrome that earns its place: checkerboard / light / dark background,
nearest-neighbour zoom so actual pixels are visible, and a density switcher that
writes `?density=` rather than holding local state.

**Fonts get their own section rather than rows.** A family with four files is
one thing to look at, not four; the specimen is the family × weight × style
matrix rendered through `FontLoader` from bytes.

## Actions

Four, all falling out of the core with no GUI in them.

| action | for | returns |
|---|---|---|
| `list` | an agent asking what exists | `AssetListResult` |
| `describe --asset=` | an agent about to write `Image.asset('…')` | `AssetDescription` |
| `audit` | CI | `AssetAuditResult` — findings, exit 0; see the M3 note |
| `preview --asset= --out=` | MCP image block, GUI thumbnail | `Artifact(png)` — **not built**, see below |

**`preview` is the one action still open, and the question is where it
rasterises.** A raster needs no rendering at all — the artifact is the file on
disk, and the density axis names which variant — so that half is a path
reference and a few lines. The other half needs a Flutter engine, and there are
three shapes:

1. **Their code, their bundle** — generate an entrypoint in the user's project
   and render it in the guest. Highest fidelity, and the same work as moving the
   panel's rendering into the guest (D6's destination), so doing it once serves
   both. It fails on a project that does not depend on `flutter_svg` or
   `lottie`, which has to be detected and explained rather than left to the
   compiler.
2. **Our code, their bundle** — a fixed flutterware-owned entrypoint compiled
   against `flutterware_app`'s package config, with the bundle assembled from
   their project. Always available, caches well, fidelity identical to the panel
   today. Does not answer "why does this SVG look wrong in *my* app".
3. **Rasters only** — name the file, refuse the rest with the path and a reason.

What is ruled out: adding `flutter_svg` and `lottie` to the published
`flutterware` package so a generated entrypoint always compiles. Two packages in
every consumer's dependency graph for a devtool feature is the wrong trade.

Results are `PluginResult` classes with `json_serializable`, per
[`dependencies_results.dart`](app/lib/src/plugins/native/dependencies_results.dart) —
`PluginAction.returns` is read statically to build `docs/capabilities.md`, so
the class *is* the published shape.

`describe` returning the correct call site (`Image.asset('assets/logo.png')`,
`SvgPicture.asset(…)`, package prefix included) is the highest-value line in the
whole plugin for an agent: guessing that string is a thing models do wrong
constantly, and there is no cheap way to learn it today.

**`audit`'s findings**, in the order they are worth having:

1. declared but not on disk;
2. on disk under a declared tree but not resolvable — the non-recursive
   subdirectory case above;
3. density variant gaps: a `3.0x` with no `2.0x`, or variants with no base;
4. duplicate content under two keys (SHA-1, `crypto`);
5. total bundle weight, and per-dependency attribution, against an optional
   budget;
6. oversized rasters — a 4096px icon is a real finding even though the
   displayed size is not statically knowable.

## Milestones

**M0 — resolver and fixtures. Landed 2026-07-29.**
[`AssetCatalog`](app/lib/src/assets/model/asset_catalog.dart) per D2, with
`AssetBundleBuilder` reduced to manifest encoding and symlinking. The extraction
was checked by capturing `AssetManifest.bin`, `FontManifest.json` and the
payload tree from the old code and diffing after: **byte-identical**, which is a
stronger check than `bundle_probe` and does not need an embedder.

Beyond a straight move, the resolver now records what it could not resolve
(`AssetProblem`) instead of returning silently — M1's report and M3's `audit`
both need it, and the silent `return` was why nothing could report it.

Fixtures in `examples/example`, documented in `examples/example/assets/README.md`
and deliberately including the broken cases. Two notes worth keeping:

- `assets/images/icons/star.png` proves the non-recursive rule *and* trips
  nothing else — `flutter analyze` does not flag it. The declared-and-missing
  file is flagged (`asset_does_not_exist`, ignored in the example's own
  `analysis_options.yaml`), but the equally deliberate missing **font** file
  produces no diagnostic at all. That asymmetry is itself a reason the plugin
  is worth having.
- `packages/flutterware/assets/figma_logo.png` shows up in the bundle without
  anything being added: `examples/example` depends on `flutterware`, which
  declares `assets/`. D3's case, for free.

**M1 — core, no GUI. Landed 2026-07-29.** `AssetsCore`, `assets_address.dart`
with its round-trip test, `Assets` in `first_party.dart`, registered in
`defaultCoreRegistry()` and declared in both project configs. `fw status`
describes a real project's assets, and `flutterware_status` reaches the same
data through MCP without a line of surface-specific code.

`search` is overridden per the plan: the default walks the report, which would
make exactly the first 15 assets of each package findable, and a palette that
only reaches the alphabetical head of a list is worse than one that reaches
nothing — it looks like it works.

The scan runs through `Isolate.run`. A scan is thousands of `stat`s on a real
project and `PluginReport` is read on every keystroke, so `AssetScan` computes
every total once, off the main isolate, and the report only formats.

**Running it found a second divergence from `flutter_tools`, and this one was a
real bug.** `AssetCatalog` walked *every package in the package config*. A
config resolves imports, and in a pub workspace it resolves them for every
member at once — so `app`'s bundle was reported as containing
`flutterware_example`'s nine assets, and dev-dependencies' assets counted too.
`flutter_tools` filters the config down to transitive dependencies and says why
in the same words (`asset.dart:423`). Fixed by walking `dependencies:` from the
root. It affected the **embedder's bundle**, not just the report;
`bundle_probe` never caught it because extra assets do not change a rendered
frame.

`overview/model/assets.dart` is deleted. It was not as dead as this document
claimed — `project.dart` imports the overview service by relative path — so its
two call sites in the legacy metrics card went with it.

**M2 — panel. Landed 2026-07-29.** `lottie` added; previews render GUI-side per
D6. The split the house UI convention asks for holds: `list.dart`, `detail.dart`
and `preview.dart` take data and hand back callbacks, `screen.dart` reads the
address and the scan and does the file I/O, and `assets_plugin.dart` is a
`buildPanel` and nothing else. Three catalog entries in
`app/tool/catalog/demos/asset_inspector.dart` draw the views with synthesised
data — which is why `AssetFile` gained an optional `length`, so an asset that
never existed can still be listed.

Four things only came out of building it:

- **Preview scaling is not one rule.** A raster uses `BoxFit.scaleDown`, so at
  1× the pixels on screen are the pixels in the file; a vector fills the pane,
  because it has no resolution to invent. Zoom is the control that says by how
  much you are lying.
- **Only `.json` is a Lottie candidate.** Handing a `.txt` to an animation
  parser costs an isolate and shows nothing while it finds out.
- **A font is sniffed before it is loaded.** `FontLoader` does not reliably
  refuse: given a PNG it may register a family with no glyphs, which draws as a
  blank panel that reads as a working preview of an empty font.
- **A real bug, caught by the screen test and invisible to the demos.** The
  screen's file read called `setState` from `didChangeDependencies` — inside the
  build phase, so it threw, and `unawaited` swallowed the error. Every selection
  would have shown a permanent spinner. Views that take plain data cannot catch
  this; only mounting the screen over a real address can.

The widget tests use `runAsync` and bounded pumps rather than `pumpAndSettle`,
for two reasons worth knowing before writing the next one: the loading state is
a `CircularProgressIndicator`, which never settles, and both the scan
(`Isolate.run`) and the screen's `File.readAsBytes` are real async work that a
`testWidgets` fake zone will never complete.

**M3 — actions. `list`, `describe` and `audit` landed 2026-07-29; `preview`
deliberately not.**

`preview` is deferred by decision rather than by running out of time: the raster
case is a path reference and the interesting cases are not, so it waits for the
fork below to be settled. Everything in `describe` that a preview would have
shown in pixels is there in words.

**`describe` reads the file, and the CLI gets everything the panel has.** §3's
claim held up: `image`'s `startDecode` reads a raster's dimensions from its
header without touching the pixels, and a Lottie's frame rate, duration, layer
list and markers are plain JSON. So `fw run assets describe
--asset=assets/animations/pulse.json` reports 200×200, 30fps, 60 frames, 2000ms,
two named layers and two markers with **no `lottie` package involved**. A `.json`
that parses is reported as `kind: animation` rather than `data` — the extension
was a guess and opening the file is the answer.

`describe`'s `code` field is the line the whole action exists for:
`Image.asset('assets/logo.png')`, `TextStyle(fontFamily: 'Roboto')`, the
`packages/` prefix included where there is one. A key that does not resolve is
refused with the near misses, because the mistake is almost always a directory
or a missing prefix.

**`audit` finds all six findings** and every one has a fixture:
`declared-missing`, `unreachable-file`, `density-gap`, `duplicate`, `oversized`
(`--maxEdge`, default 2048) and `over-budget` (`--budget`, silent when omitted).
Scoped to each package's own assets, since a dependency's density ladder is not
the reader's to fix — weight excepted, which counts everything because what a
dependency contributes is the thing worth knowing.

**Corrected:** this document said `audit` should "exit 1 on findings". It does
not, because the catalog's own `audit` does not: `fw` exits 1 only when an
action *throws*, and throwing would print an error instead of the findings. A CI
gate is `--json` and a check on `findings`. Inventing a second convention for
the second audit would have been the wrong way to win the argument.

**One thing outside the plugin needed fixing.** `shapeSources` in
`generate_capabilities.dart` was a hand-maintained list of files scanned for
`PluginAction(returns:)`, so three actions with published result classes
rendered as "Shape not published: … writes its own `toJson`" — which reads as a
decision rather than an omission, and no test could catch it because the
freshness check re-derives from the same list. It globs `*_core.dart` now.
Sorted, so the generated file does not shuffle with the filesystem. It also
turned up 11 shapes the hand list had been missing all along.

The Lottie layer inspector and orphan analysis come after M3: both want the
panel to exist first.

## Backlog, roughly by value ÷ effort

- **Orphan and usage analysis** — grep Dart sources for each key. Finds dead
  weight and typo'd references. Heuristic (defeated by `flutter_gen` and by
  interpolated paths) and must say so on the row, not in a footnote.
- **Font sanity** — declared `weight:` against the OS/2 table in the file.
  Declaring `700` on a Regular file is common and produces no error anywhere.
- **The Lottie inspector** — layer tree, markers, frame scrubber writing
  `?frame=`, per-layer solo/hide, and warnings for After Effects features the
  Dart renderer does not implement. The differentiated one: "why does my
  animation look wrong" has no tooling at all today.
- **SVG compatibility warnings** — the same idea one layer down: surface what
  the parser silently dropped.
- **`flavors:` and `transformers:`** — modern pubspec asset syntax the resolver
  ignores today. "This asset is excluded from the flavor you are running" is a
  genuinely mystifying bug to hit.
- **`.lottie` archives** — needs `archive`. Until then: recognised, not
  inspected, and labelled as such.
- **Copy-as-code** on any row.

## Open questions

1. **The XML parse for SVG intrinsic size** (§3) — add a dependency, lift it
   from `flutter_svg`'s transitive `xml`, or read the attributes with a regex
   and accept the ugliness. Small, but it decides whether SVG dimensions are a
   core fact or a panel-only one.
2. **Where the weight budget in `audit` finding 5 is declared.** D4 says no
   per-package config, and a budget is exactly the kind of thing that wants
   one. Deferred until someone asks for the gate, at which point it is the first
   real argument for config.
