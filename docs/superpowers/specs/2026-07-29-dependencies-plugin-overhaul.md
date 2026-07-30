# The dependencies plugin — what is wrong with it, and what it should be

**Date:** 2026-07-29
**Status:** design. Everything under "What is already true" is verified against
the code, the pinned SDK (3.47.0-0.1.pre) and live API responses; the staging is
a proposal.
**Extends:** `2026-07-25-overhaul-master-plan.md` (decision 7 — port `admin_ui`
widgets lazily, as each panel is rewritten),
`2026-07-26-packages-and-laziness.md` (which named the workspace bug and left
it open).

## The question

The dependencies plugin was written as a proof of concept for the plugin model
and has not been touched since. What is actually broken, what is worth adding,
and in what order?

## What is already true

### The origin of a package is not reported, and cannot be

`DependenciesService._load` reads `pubspec.lock` from the *package* directory
(`model/service.dart:30`). This repo is a pub workspace: the only lockfile is at
the root, members have none. So `lockDependency` is null for every package of
`app` or `examples/example`, and `source` comes out null in the table and in the
`list` action's JSON (`plugins/native/dependencies_core.dart:236`).

Even where the lock *is* found, `PubspecLock.fromYaml` reads only `source`,
`version` and `dependency` (`model/pubspec_lock.dart:16`). The `description:`
block — which carries the git URL and ref, the relative path, the hosted server
— is parsed and discarded. `source: sdk` is not in the `DependencyType` enum at
all.

Net effect: a git dependency and a pub dependency are indistinguishable in the
UI, and both read as blank.

### The version column shows the wrong version

`_VersionCell` renders `dependency.pubspec.version` — the version declared in
the *resolved package's own pubspec*. For an SDK package that is `0.0.0`; for a
path dependency it is whatever the local file happens to say. The lockfile's
resolved version is never read, and the constraint *this* package declared is
never shown, which is the number a human actually reasons about.

### The graph is reconstructed, and is not scoped to the package

`Dependencies.computeDependants` walks every package in the workspace's
`package_config.json`, so the "why is this here" chain shown for
`examples/example` can route through packages only `app` pulls in.
`_computeReachable` re-derives the reachable set from pubspecs rather than from
the resolution that actually happened.

`dependencyPaths` (`model/service.dart:216`) assigns `_dependencyPaths` and then
never reads it as a cache, so full — exponential — path enumeration runs on
every access. It is called from a `Tooltip` inside every transitive row's build.

### No dependency is reachable from the command palette

`searchReport`'s walker matches `ViewItems` that carry an address and
[deliberately skips `ViewTable`](../../../lib/src/plugins/search.dart)
(`search.dart:196`). The plugin projects its packages as a `ViewTable`, so the
only search hit it has ever contributed is itself — despite
`dependencies_address.dart` already knowing how to build a per-dependency
address.

### Smaller, verified

- Typing in the search box re-filters from the full list, silently discarding
  the "Show all" toggle (`list.dart:246`).
- The table builds every row eagerly inside a fixed-height `SizedBox`
  (`list.dart:251`) — 170+ `DataRow`s — inside a horizontal `CustomScrollView`
  wrapping a `SliverFillRemaining`.
- `Dependency.dispose` releases `cloc` but not `size` (`service.dart:229`).
- `detail.dart` is on the legacy `AppColors` with hardcoded `Colors.black12`,
  `black54` and raw font sizes, while `list.dart` next door is on
  `context.colors` / `context.type`. The detail page is wrong in dark mode.
- The README/CHANGELOG tabs use a `FutureBuilder` with no error branch, so a
  missing or differently-named file renders as blank
  (`detail.dart:401`).
- `MyCustomScrollBehavior` (`detail.dart:20`) is dead.
- The upgrade screen is a red `Container` with the word "Upgrades", and it is
  addressable.
- The `pub_scores` snapshot (`all_packages.json`, 15 MB) is dated 2024-11-23, so
  every popularity, like and star figure is ~20 months stale and anything
  published since has no row. It is resolved through `Directory.current`
  (`service.dart:60`) — the launch cwd of the GUI binary.

## What the tooling actually gives us

Measured, not assumed.

### `dart pub deps --json` — 0.45s, and it carries the constraints

Run from `examples/example` against the pinned SDK:

| field | value |
|---|---|
| packages | 174 |
| `kind` | 144 transitive, 17 direct, 10 dev, **3 root** |
| `source` | 164 hosted, 5 sdk, 3 root, 2 git |

**The catch:** run from a member it still reports the whole workspace, and
`"root"` names the workspace root package, not the member. It does *not* scope
itself.

**Why it is still the answer:** each of the three `kind: root` entries carries
its own `directDependencies`, `devDependencies` and — the useful surprise —
`dependencyConstraints`. So scoping becomes an exact BFS from the member's own
root entry instead of the pubspec reconstruction we do today, and the declared
constraint arrives for free.

It gives `source` (`hosted` / `git` / `path` / `sdk` / `root`) but **not** the
URL, ref or relative path. Those still come from the workspace-root lockfile's
`description:`. The two together are the full picture; neither alone is.

### pub.dev's API carries most of a detail page

`pub_scores` exists to work around GitHub's throttling, which is the API that
actually needs a snapshot. pub.dev's own is not that API:

```
/api/packages/<name>        latest version, published dates, repository,
                            topics, the full version list
/api/packages/<name>/score  grantedPoints/maxPoints, likeCount,
                            downloadCount30Days, and tags:
                            publisher:dart.dev, license:bsd-3-clause,
                            platform:*, sdk:*, is:wasm-ready,
                            is:dart3-compatible
```

Verified against `http` on 2026-07-29. `downloadCount30Days` is a far better
number than the "popularity %" the table shows, and the `tags` list hands us
license, publisher, and platform support in one call.

**So: live pub.dev for pub metadata, `pub_scores` retained purely as the GitHub
source.** The snapshot stops being the freshness bottleneck for everything that
is not a star count.

## The table: port from `admin_ui`

`DataTable` is the wrong widget on desktop and is the direct cause of the
eager-row and scroll-sandwich problems above. `cms/packages/admin_ui` already
has the replacement — `CollectionTable`, built on `TableView` from
`two_dimensional_scrollables`: virtualized, pinned header, pinned leading
columns, fixed + flex widths, drag-resize, sortable headers with a per-column
menu, hover/zebra, and `loading`/`empty`/`error` body states.

Decision 7 of the master plan calls for exactly this — port widgets lazily as
each panel is rewritten.

### The couplings, checked

| | verdict |
|---|---|
| `FieldId` (the `sortKey` type) | `typedef FieldId = String`. The import is simply deleted. |
| theme tokens | Already shared — the token layer was ported from `admin_ui`. Only `iris`/`irisSoft`/`irisSoft2` differ, named `accent`/`accentSoft`/`accentSoft2` here. |
| support widgets | `tappable`, `popover`, `popover_menu`, `menu`, `empty_state` — 586 lines, importing only Flutter, `url_launcher` (already a dep) and the tokens. |
| new pub dependency | `two_dimensional_scrollables`, and nothing else. |
| `table_cells.dart` | **Skip.** CMS domain — thumbnails, relation chips, locale rollups. |

**Decision: fork, do not vendor.** It is renamed to flutterware conventions and
adapted — inline editing (`editBuilder`, the `TapRegion`/`Shortcuts`/`Actions`
editor cell) and row selection (the synthetic checkbox column and its
select-all) are **dropped**, since the plugin is read-only by decision below.
That also drops `checkbox.dart` from the port. Selection is ~40 lines to
reinstate if a bulk feature ever appears; git history keeps it.

`column_layout.dart` (persisted column order, hidden set, widths) comes across —
the new list has eight columns and will not fit them all.

Landing site is `app/lib/src/ui/`, flat alongside `breadcrumb.dart`,
`command_palette.dart` and `side_menu.dart`, so the detail page can reuse `Menu`
and `EmptyState` too.

Expect mechanical churn from the lint gap: `analysis_options.yaml` here enables
`omit_local_variable_types` and `avoid_final_parameters`, and the source file
uses `final` locals throughout.

## Scope

Decided in discussion, 2026-07-29:

- **Read-only.** No pubspec mutation, no upgrade actions, no `pub get`. The
  plugin reports; the human runs the command.
- **Correctness and the detail page first.** Usage analysis and `pub outdated`
  are deferred, but the detail page is laid out so they drop into existing slots
  without a re-layout.
- **No OSV.** Advisories are a later stage; pub.dev's `advisoriesUpdated` is
  noted as the cheap first step when it comes.

## Staging

**Stage 0 — correctness.** Pure model and tests, nothing visible changes.

- `model/pub_deps.dart` — parse `dart pub deps --json`.
- `PackageOrigin` (sealed): `Hosted(server, name)` · `Git(url, ref,
  resolvedRef, subPath)` · `Path(relative)` · `Sdk(name)` · `WorkspaceMember`.
  Kind from `pub deps`, details from the lockfile.
- `PubspecLock` keeps `description`, and is found by walking up to the workspace
  root rather than assumed beside the package.
- Per-member scoping: BFS from the member's own `kind: root` entry; classify
  direct/dev/transitive relative to *it*; build dependants only inside that
  subgraph.
- Version becomes three things — declared constraint, resolved version, and
  (later) latest.
- Bug sweep: cache `dependencyPaths` and switch to bounded shortest-path BFS;
  fix the search filter; dispose `size`; delete `MyCustomScrollBehavior`.
- Projection emits `ViewItems` with `dependencySegments(...)` addresses, so
  every dependency becomes a palette hit.
- `DependencyEntry` gains origin detail and constraint. **This changes the
  `list` action's JSON shape** — worth doing before anything depends on it.

Tests run off a captured `pub deps --json` fixture plus a synthetic workspace;
nothing shells out. The regression to pin: `examples/example` reporting
170 direct / 0 transitive instead of 14.

### Two things Stage 0 settled that the design had not

**The projection lists every declared dependency, uncapped.** It used to carry
12 rows and count the rest, which is the right rule for a projection that is
read rather than scrolled. But once the rows carry addresses, truncating also
decides what is *findable*, and "the first twelve dependencies are searchable"
is not a rule anyone can hold in their head. What a package declares is bounded
— tens, not hundreds — and it is the list this plugin exists to show.
Transitives remain a count: they are the unbounded half, and you go looking for
what you asked for. So the searchable set is **declared dependencies**, not
every resolved package.

**Packages are sorted by name at construction.** Reachability is computed by
traversal, and traversal order was leaking into the table and the projection.
The first symptom was a search test failing because `auto_size_text` happened to
fall outside the first twelve rows.

**Stage A — table port.** Independent of Stage 0; can land in parallel. Port,
adapt, compile standalone. `flutter analyze` under `strict-casts` is the gate.

Landed as `app/lib/src/ui/`: `table.dart` (`FwTable` / `FwTableColumn` /
`FwTableSort` — the `Fw` prefix avoids colliding with Flutter's own `Table`),
`column_layout.dart`, plus `menu.dart`, `popover.dart`, `popover_menu.dart`,
`tappable.dart` and `empty_state.dart`. Nothing imports `FwTable` yet; Stage B
does.

Dropped in the fork, as agreed: inline cell editing, row selection (and with it
`checkbox.dart`), and `MenuItem`'s `url_launcher` `Link` mode. `FieldId` was
`typedef FieldId = String`, so the CMS coupling really was one deleted import.

Density was retuned for a dev tool rather than a CMS: rows 52 → 44, header
44 → 40, cell padding 14 → `FwSpacing.lg`.

The lint gap turned out to be smaller than feared. `strict-casts` found nothing;
`omit_local_variable_types` meant converting `final` locals to `var`
throughout, which is mechanical.

**Stage B — rebuild the list on it.** Columns: package · type · origin ·
declared constraint · resolved · pub · github. (Latest and downloads wait for
Stage 4's live pub.dev data.)

The screen became a bounded `Column` instead of a `ListView`: a table cannot
virtualize inside a scrollable that offers it unbounded height, which is why the
old one wrapped a `DataTable` in a `SizedBox` of `rowCount * rowHeight`.

The "Show all" checkbox became three filter chips with counts. It could only
ever say "transitive or not", and the model now distinguishes dev — a
distinction it could not make before it read the real resolution.

Filtering and sorting live in a top-level `visibleDependencies`, outside the
widget, because they are the only real logic on the screen and the table is a
pure view that renders whatever order it is handed.

**Testing a screen whose service shells out.** A widget test drives fake time,
so a subprocess never completes inside one — the `runProcess` seam answers `pub
deps` from the fixture instead. The subtler trap: the load must be driven
**before** `pumpWidget`. A load started by the widget's own subscription begins
under fake time, and nothing in `tester.runAsync` can then drive it to
completion; awaiting it deadlocks with no output at all. Loading first leaves
the `AsyncValue` initialised, so mounting subscribes to a cached value and
starts nothing.

That screen test immediately earned its place by catching a `RenderFlex`
overflow of 107px at a 700pt window — the toolbar's fixed 300pt search box plus
a `Spacer`. The search box now yields width first and the filters scroll.

**Stage 3 — detail page.** Header with the real origin (git URL + ref, or
relative path), stat tiles, a Versions section, a Why section rendering chains
as a collapsible tree rather than a `→`-joined tooltip string, Usage, a
Compatibility block built from the pub.dev `score` tags, and Readme/Changelog
with the current version's entry highlighted and an actual error state. On
`context.colors` / `context.type` throughout.

Landed. `model/pub_dev_api.dart` fetches both endpoints, merges them, and caches
under `~/.flutterware/cache/pub.dev` — the same home-directory convention the
bootstrapper uses. **It never throws for a network problem**: a detail page that
failed because pub.dev was unreachable would be worse than one missing a
download count, since everything else on it comes from disk and is still true.
Expiry is a refresh policy, not a correctness boundary, so an expired entry is
still served when the network fails.

`PackageImports` grew from `Map<String, List<File>>` to records carrying the
URI, the sub-library, the scope (lib / test / tool / other) and whether it was
an export. That makes the Usage section able to say "test-only — could be a dev
dependency", which is the first genuinely diagnostic thing this plugin says.

Two rules the Usage copy follows deliberately: a package with no imports is
reported as *"no Dart file imports it"* and explicitly **not** as unused —
build tooling, lint sets and native-only plugins are never imported — and
"never imported" is not "test-only", so an absent package does not read as a
misplaced dependency.

The licence document section is titled **"License text"**, because the
Compatibility section already has a row called "License" carrying the SPDX id,
and two headings reading the same on one page is a question about which is
which. A screen test caught that as an ambiguous finder.

## Stage 1 — usage analysis

**This section was rewritten on 2026-07-29 after review.** The first draft argued
for a `fw run dependencies check` gate with four severities and derived
exemptions. Most of that argument was wrong, and the measurement that killed it
is recorded below. What survives is smaller and does not overlap anything that
already exists.

### What already covers this, measured

`depend_on_referenced_packages` is in `package:lints/core.yaml`, which
`recommended.yaml` includes, which this repo's `analysis_options.yaml` includes.
It is on, here and in most projects.

It is also **location-aware**, which the first draft assumed it was not. Probe —
a package with `collection` in `dev_dependencies`, imported from both `lib/` and
`test/`:

```
info - lib/a.dart:2:8 - The imported package 'collection' isn't a dependency
       of the importing package. - depend_on_referenced_packages
```

The `test/` import is silent; the `lib/` one is not. So the analyzer already
catches:

- importing a package you never declared, and
- **importing a `dev_dependency` from `lib/`** — which the first draft claimed
  was a gap in rimbaud's test worth building a plugin around. It is a gap in
  that test, but it is not a gap in the toolchain, so it is not a reason for
  anything here.

That also explains the prototype's "zero undeclared imports across three
members" result. It was not luck and it was not evidence of a healthy repo — it
is the lint doing its job on every save.

**Consequence: there is no error tier.** Both candidates for it are already
enforced upstream, closer to the code, with an editor squiggle instead of a CI
log.

### What is actually left

Two questions, neither of which any lint answers:

1. **Declared and never referenced.** No analyzer rule reports this; it cannot,
   because the answer needs every file in the package at once.
2. **In `dependencies:` but referenced only from test scope.**

rimbaud's `test/dependendies_usage_test.dart` already answers both, in ~150
lines, as a CI gate, with a checked-in allow list — including the good trick of
asserting an allow-listed package is *still* a violation, so a stale exemption
fails the build.

So the honest position: **a `check` action would be a third implementation of a
gate that already exists twice.** It is not built.

### Are the derived exemptions brittle? Yes

The first draft claimed deriving exemptions from facts on disk beats a
hand-written list. Testing it found the counter-example immediately: "ships a
`build.yaml`" excuses `vector_math` and `github`, which ship one to configure
builders for their *own* build. The discriminating key is a top-level
`builders:` section. One refinement in, and the rule is already carrying a
special case.

That is the shape of the whole idea. A derivation reads a fact that the
dependency's author controls and that changes without warning when they publish;
an allow-list entry changes only in a reviewed diff. **For a gate, the list is
the more robust mechanism**, and the ad-hoc list is also what lets a project
adopt the gate on day one — which is what the first draft's severity gradient
was reinventing.

Derivations keep exactly one defensible use: **ranking and explaining in the
UI**, where being wrong costs a misleading sort order rather than a red build.
They must never decide a gate.

### So Stage 1 is a display, not a checker

The plugin's edge is not verdicts — it is the resolution graph, which neither a
lint nor a per-package test has. Three things follow from it, and none of them
is a yes/no:

- **Where a package is used.** The files, the scopes, and *which library* of a
  multi-library package. This is navigation, and it is what you actually want
  open when deciding whether to remove something. Landed in Stage 3's Usage
  section; extend it to link into the files.
- **What removing it would cost.** `github` is not one line in a pubspec — it is
  N transitive packages, M MB and K LOC that leave with it. That needs the
  scoped subgraph from Stage 0 and it is the one number no existing tool can
  produce. This subsumes what was Stage 5.
- **Why a transitive package is here.** Neither the lint nor the test sees
  transitives at all. Stage 3's Why section already answers it; the ranking
  above makes it actionable.

Unused declarations still appear — as a column and a chip, sourced from the same
`PackageImports`, with the exemption reasons shown as explanation. Advisory, in
a window someone deliberately opened. No exit code.

### When it runs

Only where someone is looking: on the detail page for the package you opened,
and as a column when the list opens. Both already gather imports.

Not in `fw status`. A status line is read by a human glancing and by an agent
deciding what to do next, and putting a soft advisory there — one whose
exemptions are admittedly brittle — trains both to ignore it. The gate belongs
in the analyzer, where it already is.

Separately: `fw help status` claims "nothing here compiles, spawns a daemon or
touches the network", and this plugin already spawns `dart pub deps` there. That
sentence needs amending regardless of any of the above.

### Measured on this workspace

Prototyped over the three members, 2026-07-29 (and then deleted):

| Member | Declared | Files | Gather |
| --- | --- | --- | --- |
| `flutterware` | 17 + 10 dev | 261 | 400 ms |
| `flutterware_app` | 58 + 5 dev | 337 | 178 ms |
| `flutterware_example` | 14 + 4 dev | 21 | 15 ms |

- `flutterware_app` declares nine packages nothing imports: `file_picker`,
  `flutter_web_plugins`, `github`, `io`, `meta`, `os_detect`, `process`,
  `vector_math`, `win32`. `flutter_web_plugins` is imported by the *generated*
  web plugin registrant — the kind of case that makes any automatic exemption
  rule a guess.
- The root package declares `analyzer`, `dart_style` and `process_runner` in
  `dev_dependencies` and nothing in *that* package imports them; `app` does.
  Declaring in the wrong member is a workspace-only mistake, and only per-member
  scoping sees it.
- `examples/example` declares `auto_size_text` and never mentions it again.

**A trap the prototype hit, which the model must encode.** A member's own files
are not "everything under its directory": `app/` and `examples/example` sit
inside the root package's directory, and walking it whole credited the root
package with 42 undeclared imports that were its siblings'. The file set is the
member's directory minus every nested directory containing a `pubspec.yaml`.
Same class of bug as Stage 0's, one level down.

### Two model fixes, landed

Both were bugs in what Stage 3 shipped — the Usage section reporting no usage
where there was usage — and are independent of everything above.

**Conditional imports count.** `import 'x.dart' if (dart.library.io) 'y.dart'`
carries its alternative URIs in `directive.configurations`, and `PackageImports`
read only the default. A dependency reached solely on one platform read as
unreferenced. Every branch is now recorded, each carrying the environment that
selects it (`PackageImport.condition`), and the detail page prints it — without
it, two rows for the same file look like a duplicate rather than two platforms.

In analyzer 13 a `Configuration`'s `name` is a `DottedName` whose components are
`tokens`, not the `components` of older versions; `toSource()` is the stable
spelling.

**Asset references count as use.** `packages/<name>/…` paths under `flutter:
assets:` and `flutter: fonts:` are read from the member's own pubspec, so a font
or icon package — depended on and shipped without one line of Dart naming it —
is no longer reported as unreferenced. It also cannot be test-only: an asset
ships with the app however its Dart libraries are imported.

The parser is deliberately tolerant, and the test written for that immediately
caught a real throw: `flutter['assets'] as List?` raises on the scalar somebody
eventually writes there, and this walks user-authored YAML of a shape Flutter
keeps extending (a bare path, or a map with `path:` and `flavors:` since 3.19).
A shape it does not recognise is one missing reference, not an exception on the
way into the panel.

Third, smaller: the detail screen test never drove `packageImports`, so every
Usage assertion in it was being made against "Scanning…". Same load-before-pump
rule as the rest of that file.

**Later.** `pub outdated`; a real upgrade screen; advisories and licenses.

## Notes

`flutter_test` and `flutter` resolve as `source: sdk` with version `0.0.0`, so
they must render as "Flutter SDK" anywhere a version is shown.
