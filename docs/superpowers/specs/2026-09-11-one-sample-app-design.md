# One sample app: brewline absorbs the shop, example becomes a fixture

*2026-09-11. Analysis and proposal; nothing here is built yet.*

## The situation

The repository carries two coffee shops called Brewline.

`examples/example` (package `flutterware_example`, 401 tracked files) is a
workspace member with a path dependency on flutterware. It is where the shop
was written, and it is also flutterware's engineering fixture: nine plugins
are bound to it from the repo's own `tool/flutterware.dart`, and the app's
tests, integration tests, CI steps and probe scripts read its files directly.
An inventory on 2026-09-11 found:

- **CI:** 14 steps across four jobs run inside it or over it (previews audit
  on Linux and Windows, `fw` self-install checks, the studio demo recording
  check, the web demo build and browser walk, the Pages deploy).
- **Tests that read it off disk:** 22 files under `app/test/`, 7 under
  `app/integration_test/`, 3 under `test/`, plus the recorded fixture
  `app/demo/fixture/` (255 files) and the generated wrappers in `web_demo/`.
- **Tests that only use its name as a label:** 20 more files.
- **What it contains beyond the shop:** engine probes (`fox_probe`,
  `model_probe`, `phone_rig_probe`, `gpu_smoke`, `compute_probe`,
  `vector_smoke`, `asset_smoke`), 13 scene files plus the editor-generated
  `scene_args.dart`, four `.glb` models with their generator scripts and a
  build hook, the asset inspector's deliberately wrong assets, five launcher
  icon sets and six Android flavors, a half-declared splash, a devbar with
  every plugin and a command plugin, a dev stack with its own server, render
  bundles, an http replay fixture, a `UICatalog`, the run cockpit's knob
  fixture (`main.dart` is the counter app with `fwMarker`), and spikes
  (`network_spike`, `drive_spike`).

`examples/brewline` (package `brewline`, 113 files) is the demo a stranger
clones. It is not a workspace member; its pubspec names the hosted
`flutterware: ^0.6.0`, and `tool/publish_example.dart` projects its tracked
files to github.com/flutterware/flutterware_example. It carries the same
shop screens (`shop_screens.dart`, `mini_markdown.dart`, `store_frame.dart`
and the four asset JSONs are byte-identical to example's), five previews, two
scenarios, a manifest declaring eight plugins, and an onboarding README.

Everything that has diverged between the two copies is a wart in one or the
other: example's `ShopApp` takes `home`/`cart`/`themeMode`/`locale` so a
preview mounts a screen inside the real app, brewline rebuilds a
`MaterialApp` in its preview wrapper instead; example's `ShopStrings` has an
`assetPackage` hook so the studio's web page can compile the shop into
another app, brewline loads assets flat; example's `Order placed` has a name
knob and a `Drink badges` sheet, brewline has neither; example's scenario
types `Xavier`, brewline's types `Ada`.

## What "drop one" can and cannot mean

The three constraints are: brewline is exportable to its standalone repo;
brewline compiles to the web under the studio demo; brewline's recording is
the fixture for scenarios of flutterware itself. Add the one the request
states first: brewline is a clean project representative of a real one.

That last constraint decides the shape. The probes, the deliberately wrong
assets, the six flavors with a partial override, the half-declared splash,
the icon config that is configured and never generated: those exist because
a test needs the wrong case, and a real project has none of them. They
cannot move into brewline without making it the debug harness the
publication plan refused to ship. And they cannot be deleted: the previews
audit, the icon scanner tests, the asset inspector tests, the dependency
classification tests and the 3D export lane all read them.

So the unification is not "move example into brewline". It is:

1. **The shop lives in brewline only.** Every shop-shaped thing in example
   moves to brewline or is deleted. Brewline becomes the recorded project,
   the web demo's subject and the source of the README's pictures.
2. **Example stops pretending to be an example.** It keeps the probes and
   the wrong cases, loses the shop, and is renamed to say what it is.

One app with a story, one harness without one. The harness is not a second
coffee shop because it has no shop in it.

## Brewline after the move

**Package and workspace.** Brewline joins the workspace (`resolution:
workspace` in its pubspec, `examples/brewline` in the root list) while its
pubspec keeps `flutterware: ^0.6.0`. Verified 2026-09-11: pub resolves a
member's hosted constraint to the workspace's own `flutterware` when the
version satisfies it, so `flutter pub get` at the root resolves brewline
against the checkout with no override file. Two consequences worth having:

- The CI override step and the CLAUDE.md paragraph about
  `pubspec_overrides.yaml` go away, as do the two `.gitignore` lines for
  brewline's lock and override.
- When flutterware bumps to 0.7.0, brewline's `^0.6.0` stops resolving and
  the root `pub get` fails. That is the demo being forced to name the
  version it demonstrates, the same discipline the two package pubspecs
  already keep by hand.

`tool/publish_example.dart` gains its first and only transformation: it drops
the `resolution: workspace` line on the way out, because a clone has no
workspace root. Its rule stays "what git tracks, and nothing else"; this is a
line removed from one file, not a curated list. A new CI step proves the
export: dry-run the publish into `build/flutterware_example`, write the
override there (the clone is against a checkout, not pub.dev), then `pub
get`, `analyze` and `test` in the clone. Nothing checks this today.

**Previews.** `demo/shop.dart` takes example's version: the wrapper mounts a
screen in the real `ShopApp` (`home:`, `cart:`, `themeMode:`), the group is
`Brewline`, `Order placed` keeps the `name` knob defaulting to `Ada`, `Drink
badges` stays as the component sheet. `demo/brand.dart` moves over with
`assets/brand/`: the icon sheet and the one-variant entry are the source art
of the launcher icon, which is the pitch. The generator
`app/tool/demo/brand_icons.dart` becomes `examples/brewline/tool/brand_icons.dart`;
it depends only on `image` and `path`, which become brewline dev
dependencies. Brewline's manifest keeps its two-device canvas.

**Launcher icon and splash.** Brewline gets a generated icon set on Android,
iOS, macOS and web from its own brand art, and one flavor: `kiosk`, the
in-store build, with its own icon. A single flavor is what most real apps
have, it keeps the recorded launcher icon panel interesting, and it keeps
the studio's own scenario, which walks to `kiosk`, meaningful. The five-set,
six-flavor fixture stays in the harness for the scanner tests. Brewline also
gets a complete `flutter_native_splash.yaml` with three small assets and the
generated outputs tracked, the way a real project tracks them. The
half-declared dark section stays in the harness.

**Scenarios.** Rule: a scenario moves to brewline if it is about the shop and
needs nothing beyond flutterware; it stays in the harness, rewritten off the
shop, if it exists to pin runner mechanics. By that rule:

| moves to brewline | stays in the harness (rewritten off the shop) |
|---|---|
| `mobile/shop_test.dart` (already there) | `api/profile_test.dart` (http replay) |
| `desktop/shop_window_test.dart` | `events_test.dart` (transition events) |
| `mobile/keyboard_test.dart`, `keyboard_types_test.dart` | `async_boot_test.dart`, `counter_test.dart` |
| `mobile/beans_test.dart` (`scrollTo`) | `database_test.dart` (native assets guard) |
| `mid_flight_test.dart` | `vector_graphics_test.dart` (asset transformer) |
| `attachment_test.dart`, with the receipt as text rather than `pdf` | |
| `mobile/brewline_reel_test.dart`, in the last step | |

Brewline gains the per-folder profile story (`mobile/` and `desktop/` with
`profiles.dart`), which is worth showing. The recording stays curated: the
two mobile scenarios and the desktop one, as today; `record.dart` already
selects.

**Devbar.** `shop_devbar.dart` with the push-notification command plugin
moves to brewline as a second entry point ("Brewline (devbar)"). It is the
sample for driving a running app from outside and needs only flutterware.
The storage panel (`shared_preferences`, `flutter_secure_storage`), the
sqlite ledger and `devbar_example.dart` stay in the harness: each adds a
native plugin to a demo whose promise is "clone and run one command".

**Web.** The wrapped entries are `demo/brand.dart` and `demo/shop.dart`;
`web_entries.dart` already fences their import closure off `dart:io`. The
shop's product code stays free of it. `ShopStrings` takes the bundle-prefix
hook from example, spelled as a parameter of `load` rather than a static,
and `web_demo/demo/main.dart` passes `packages/brewline/`.

**Not moving now.** The 2D scenes (store banner, store hero, showcase), the
3D phone and the renderers. A store listing drawn from a scene is a real
product story, but the scene editor is not ready to be a stranger's first
impression, and it brings 1,300 lines of generated and renderer code. Revisit
when scenes are published work. `renders.dart` (server-side render bundles),
the dev stack and server inspection stay in the harness too.

## The harness after the move

`examples/example` loses `lib/shop/`, `lib/src/store_copy.dart`,
`lib/store_frame.dart`, `lib/store_hero.dart`, `lib/shot_image.dart`,
`lib/shop_devbar.dart`, `lib/src/notifications/`, `demo/shop.dart`,
`demo/brand.dart`, `assets/brand/`, `assets/i18n/`, `assets/store/`, the
shop scenarios, `test/shop/`, the store shots and translations declarations,
and the dead spikes (`network_spike.dart`, `simple_test.dart`,
`widget_test.dart`; `drive_spike.dart` unless the run drive design still
needs its service extension as a comparison point).

It is then renamed to say what it is. Proposed: path `fixtures/probe_app`,
package `flutterware_probes`. `examples/` is what a stranger browses on
GitHub, and a stranger should find one thing there. The rename is
mechanical: about 120 path strings in tests, CI and manifests, the captured
`pub_deps.json` fixture regenerated, `.pubignore` gains `fixtures/`,
`bump_flutter.dart`'s list updated. Historical specs under `docs/` keep the
old name; they describe what was.

The harness README becomes one paragraph: this is flutterware's fixture,
several things in it are wrong on purpose, the sample is
`examples/brewline`. Its `main.dart` stays the counter with the `fwMarker`
knob.

## Sequencing

Five pull requests, each green on its own, in this order so the churn
happens once and the demo is never broken in between. (Four were planned;
the rename was split out of the third because 107 files move with it and a
reviewer should see the deletions on their own first.)

1. **Brewline joins the workspace; the export is tested.** Workspace member,
   publish script strips one line, CI clone-and-test step, override
   plumbing deleted. Small; unblocks everything else.
2. **Brewline becomes the recorded project.** Shop seams, brand art and icon
   generation, one flavor, splash, the moved scenarios and the devbar entry
   point land in brewline; `record.dart`, `web_entries.dart`,
   `build_web.dart`, `recorded_project.dart`, `web_demo/`, the studio
   scenario and the README screenshot tooling point at it; the fixture is
   re-recorded. The largest of the four.
3. **Example becomes the harness.** Shop remnants deleted, harness
   scenarios rewritten off the shop, the reel and the store panorama moved
   to brewline, root manifest split between the two packages.
4. **The rename.** `examples/example` → `fixtures/probe_app`, package
   `flutterware_example` → `flutterware_probes`. The native projects keep
   their product name: nothing reads a pubspec name from them, and a
   pbxproj edit buys nothing.
5. **Polish.** Whatever the recording made visible on the web page gets
   fixed; the publication plan and the fake-project spec are updated to
   describe the new layout; the spikes (`network_spike`, `drive_spike`) go
   if nothing still needs them.

## Decisions (2026-09-11)

- **Harness path and package name:** `fixtures/probe_app`,
  `flutterware_probes`.
- **The receipt attachment:** `pdf` was cleared to come along, and turned out
  not to be needed — the scenario attaches JSON and text, so brewline gains
  no dependency for it.
- **No flavor after all.** A Gradle flavor makes a bare `flutter run` on
  Android refuse until it is given `--flavor`, and the flutter tool applies a
  pubspec `default-flavor` on every platform, where it demands an Xcode
  scheme (measured 2026-08-31). Either way a demo whose promise is "clone and
  run" fails its first run. Brewline ships one adaptive icon set, drawn from
  `demo/brand.dart`, and the icon sheet has one row until a flavor earns a
  second. The studio's own scenario walks the panel's roles instead of a
  flavor chip.
- **The strings' bundle prefix** stays a static (`ShopStrings.assetPackage`)
  rather than a parameter of `load`: the web demo compiles brewline's preview
  file unchanged, and that file constructs the app, so the host has nowhere
  to pass a parameter through. One line in the host, documented on the
  static.
- **Recording source.** From `examples/brewline` in the checkout, not from
  the clone under `build/`: paths are re-rooted to `/recording` either way,
  and the CI recording check re-records from the source tree.
