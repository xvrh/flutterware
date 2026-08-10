# The splash plugin: from previewer to a viewer you can trust

> **Title corrected 2026-08-10.** It read *"to authoring tool"* until the
> authoring tool was built and deleted — see § Phases 2 and 3 are deleted. What
> shipped is a viewer that reads the generated files back and never writes.

**Date:** 2026-07-31
**Status:** Design. Supersedes nothing — the splash plugin shipped without a
spec.
**Follows:** `2026-07-29-config-reload-findings.md` (watching),
`2026-07-27-gui-cli-mcp-architecture.md` (one core, three surfaces).

## Where it stands

Three things exist, and they are not equally good.

**The cascade transcription is the asset.** `model/config.dart` and
`model/surface.dart` know that `android_12.color` falls back to the *top-level*
`color` and not to `color_android`; that `android_12.image` has no fallback at
all; that dark is an independent two-step chain that never falls through to
light. None of that is in the package's README, and every one of them is
load-bearing. This is the part nobody can reproduce by asking.

**The validator is sound in kind and wrong in one place.** See § 0.

**The previewer is the weak leg, and it is the one carrying the panel.** It does
not watch the file it previews, it draws every mobile surface at one canvas
size, it ignores safe areas, and it finds the real generated artifacts and then
renders them as the string `"12 files generated"`.

## The question this document answers

Not "should the plugin do more" but **which more**. The temptation is a form
over the config file. That is the one thing worth refusing: a form over ~50 keys
is a worse text editor than the user's text editor, and an agent writes that
YAML correctly today. Where we win is the two places neither an agent nor a text
editor can go — **seeing** (does the logo survive the device range, does it
collide with the home indicator, does it match what actually shipped) and
**pixels** (crop, pad and export art to canvases whose numbers nobody knows).

The division that falls out, and that the phases below follow:

> The agent writes keys. We do the seeing and the pixels.

Note the plugin already makes the agent better rather than competing with it:
`fw run splash describe` hands it the cascade, and `fw capture` can already
photograph the panel at an address. Phase 1d exists to make that photograph
legible.

---

## Phase 0 — Correctness

Small, and it goes first because it is a bug in the plugin's flagship claim.

### 0.1 Android 12 with no `android_12.image` shows the *launcher icon*

`model/validation.dart:275` says "every device from Android 12 on shows a bare
colour". It does not. When `android12ImagePath` is null the generator **removes**
`windowSplashScreenAnimatedIcon` from the launch theme
(`flutter_native_splash-2.4.8/lib/android.dart:519`), and Android's default for
that attribute is the application's launcher icon. The package says so itself,
in a comment at `android.dart:113`:

```dart
//create android 12 image if provided.  (otherwise uses launch icon)
```

Three changes fall out:

- **The message.** "Android 12+ will show your **launcher icon**, masked to a
  circle, not this image." That is more alarming than the current text and more
  actionable — it is the "why is my app icon on my splash screen" complaint
  everybody files.
- **The composition.** `composeSplash` should put the launcher icon into the
  android12 cell when `android_12.image` resolves nothing, flagged as
  `isLauncherFallback`, so the tile draws **what will really happen**. We already
  have a launcher-icon reader: `app/lib/src/icon/model/icons.dart`. Extract the
  discovery half (find `android/app/src/main/res/mipmap-*/ic_launcher.png`) into
  something the splash scan can call without pulling in the icon screen.
- **`fallsBackToLight`.** `resolveSplash` treats a missing dark android12 image
  as falling back to light. With the launcher icon as the real default this is
  not a light-mode fallback, it is the same icon in both. Narrow the test.

### 0.2 Soften the two canvas-size rules

`android12IconSize` returns 960 or 1152 and validation flags any deviation as a
warning. The size *is* what the package documents and the mask arithmetic is
real, but the tone is wrong for a near miss: a 1024×1024 icon is not broken, it
is 11% tighter in the circle than intended. Grade it — `Tone.warn` when the
logo's opaque bounds actually leave the 2/3 circle (Phase 3 gives us the bounds),
`Tone.info` when it is merely not the documented canvas.

**Cost:** half a day. **Tests:** extend `app/test/splash/splash_config_test.dart`
and `splash_composition_test.dart`.

---

## Phase 1 — The previewer becomes live and honest

### 1a. Notice when the file changes

`splash_core.dart:87` caches on first `track` and only `invalidate`s after
`generate`. Edit `flutter_native_splash.yaml` in your editor and the panel shows
the old picture forever. Everything below is worth less until this lands.

**Mechanism: poll a fingerprint, do not watch.** This is a deliberate departure
from `ConfigWatcher`, and the reasons are specific to this plugin:

- The set is not one file. It is the config file, *every referenced image*, and
  the generated artifacts — around fifteen paths across four directories. A
  designer re-exporting `logo.png` must move the preview, and a watch on the
  config alone would not see it.
- `package:watcher`'s `DirectoryWatcher` is **recursive**. `ConfigWatcher` gets
  away with it because `tool/` is small; pointing one at a package root would
  walk `build/`, `.dart_tool/`, `android/` and `ios/`.
- The responsiveness budget is different. `ConfigWatcher` feeds a compile-and-
  swap loop that wants sub-100ms. A preview is fine at 750ms.
- The scan already `stat`s every one of these paths. A fingerprint is free.

So: `SplashScan.fingerprint` — a hash over sorted `(path, mtime, size)` for the
config file, each referenced image, and the newest artifact. A timer polls it
while something is tracking; a change calls `invalidate` + `_load`. Fifteen
`stat`s at 750ms is arithmetic, not I/O pressure.

**Lifecycle.** Armed in `SplashCore.track`, released in `dispose` — which is
exactly what `PluginCore.dispose`'s doc comment asks for ("release watchers,
subscriptions and processes here") and which no plugin does yet. Explicitly
**not** armed from `computeAll`: `fw` and MCP call that and then exit, and the
budget there is parsing.

**And a manual Reload, always.** Not a consolation prize for when detection
fails — a permanent affordance, for the same reason `2026-07-29-config-reload-findings.md`
insisted on one: network filesystems, container mounts and unusual editors defeat
every detection scheme eventually, and the failure is *silent*. A stale preview
looks exactly like a correct one. `SplashCore.invalidate` already exists and does
precisely this, so the cost is a button in the header plus a `reload` action so
`fw` and an agent have the same escape hatch. It also gives the polling a safe
place to be conservative: if the timer is ever in doubt, the user is never stuck.

Show when the scan last ran, next to the button. A timestamp is what turns "I
think this is stale" into a fact, and it costs one field.

**New file:** `app/lib/src/splash/model/fingerprint.dart`. **Cost:** 1 day
including tests with an injected clock.

### 1b. The device range, and the two rules it makes computable

`splashPreviewSize` returns `(393, 852)` for android, android12 **and** ios, so
the iOS tile and the Android tile are the same picture. Meanwhile the entire risk
a splash carries is whether the logo survives the device range: a 1024px source
at `SplashFit.none` is 256dp — comfortable at 393dp, cramped on a 375dp SE, lost
on an iPad.

Two parts, and the second matters more than the first.

**A device axis.** `?device=iphone-se`, reusing `Devices.all` (`lib/src/devices.dart`)
and `resolveDevice` (`app/lib/src/catalog/devices.dart`) — the same vocabulary
the catalog already uses, so one axis name means one thing across the app.
Default per surface (a modern phone for android/ios, the existing 1280×800 for
web). Optionally a `device_frame` silhouette via the existing `deviceFrameFor`,
and an orientation axis.

**A computed sweep, which is the real deliverable.** Do not make the user click
through nineteen devices looking for the broken one. With a natural size and the
device table we can answer it in arithmetic, for every device, without rendering
anything:

- **Overflow** — `SplashFit.none` and `naturalWidth > device.width` (or height)
  means the image is clipped. Report the narrowest device it survives.
- **Safe-area collision** — branding at `bottom` with
  `brandingBottomPadding < device.insetBottom` sits under the iOS home
  indicator. Common, ships, and today the preview draws it as fine.
- **Status-bar collision** — a top-aligned image under `insetTop` when
  `fullscreen` is false.

Each becomes a `SplashProblem` naming the device, and clicking it sets the
device axis so the picture proves the sentence. This is the plugin's existing
philosophy — compute the answer, then show the picture that proves it — applied
to the one question the preview currently cannot answer at all.

**New file:** `app/lib/src/splash/model/fit_check.dart` (Flutter-free, so `fw`
gets it for nothing). Safe-area overlay in `ui/splash_render.dart`, gated on a
`showSafeAreas` flag so the capture path can turn it off. **Cost:** 2 days.

### 1c. Predicted next to actual

> **Half superseded, 2026-08-10.** The recomposition landed and is the best
> thing here. The *comparison* below — two pictures side by side, a mismatch
> raised as a problem — was built, shipped, caught nothing, and is deleted. See
> § The inversion for why the argument in this section is wrong, and read the
> table below knowing that its two rows are not peers.

`model/generated.dart` walks the real generated PNGs with paths, densities and
mtimes; the panel renders that as a count. Putting the generated image beside the
prediction is the single change that makes every other claim self-evidencing —
including the cascade transcription, which currently has only its own tests to
vouch for it.

**There is no runtime code in a splash.** `flutter_native_splash:create` is a
pure generator: it writes files and exits, and the OS inflates those files at
launch. The picture a device shows is therefore fully determined by a recipe
sitting in the repo, and every ingredient of it is readable.

On Android the recipe is a layer-list, `drawable/launch_background.xml`:

```xml
<layer-list>
    <item><bitmap android:gravity="fill"   android:src="@drawable/background" /></item>
    <item><bitmap android:gravity="center" android:src="@drawable/splash" /></item>
    <item android:bottom="{N}dp"><bitmap android:gravity="center" android:src="@drawable/branding" /></item>
</layer-list>
```

`styles.xml` points `windowBackground` at it, and — the part that makes this
cheap — **even the background colour is a PNG**: `_createBackground` renders the
colour to `background.png` rather than emitting a `<color>` drawable. So the
legacy Android splash is three bitmaps, one gravity attribute each, and one
padding number. Web is a literal `background-color`, a `background-size` and a
`<picture>` srcset — in `web/index.html`, not in the `web/splash/style.css` this
paragraph claimed until 2026-08-10; 2.4.x inlines it. iOS is the awkward one:
`LaunchScreen.storyboard` XML with constraints, plus `Contents.json`.

That gives us two pictures with genuinely different provenance:

| | reasons from | wrong if |
|---|---|---|
| **prediction** | the config → our transcription of the cascade | *our* transcription is wrong |
| **recomposition** | the generated files → the platform's compositing rules | we misread the platform |

They must agree. **When they disagree, one of us has a bug** — and since the whole
plugin rests on a hand-transcription of somebody else's `cli_commands.dart`, that
disagreement is the only external check on it we will ever have. Stronger than
any unit test we can write, because it tests against the real generator's real
output. This is the argument for doing it rather than deferring it.

- **1c-a — the artifact browser.** Grouped by surface/theme/density, real
  `Image.file`, mtime, and the generated layer beside the predicted layer for the
  cell. Proves placement and scaling. **1.5d.**
- **1c-b — recomposition.** Parse `launch_background.xml` + `styles.xml` (+ the
  `-v31` variant) and `web/splash/style.css`; composite from the artifacts into
  the same `SplashComposition` the renderer already takes, tagged
  `SplashSource.generated`. A mismatch against the prediction is itself a
  `SplashProblem`. **1.5d**, cheaper than it looks precisely because of the
  all-bitmaps layer-list above.
- **iOS storyboard parsing is out of scope**, and honestly so: constraints are a
  layout engine, not a recipe. iOS keeps the artifact browser and the prediction.

**Two limits worth stating in the UI, not just here.** This is still a model —
the truly real answer is a photograph of a device. And the Android 12 path is
the part recomposition cannot fully reach: the launcher-icon default is resolved
by the OS from the manifest, adaptive-icon masking is the OS's, and OEMs vary.
Legacy Android and web it can nail exactly.

The tile also gains a truthful staleness state: `splashIsStale` already knows,
and "what you are looking at is not what ships" belongs on the picture rather
than in a list at the bottom.

**New files:** `app/lib/src/splash/ui/artifacts_view.dart`,
`app/lib/src/splash/model/recompose.dart`. **Cost:** 3 days total.

### 1d. Single-cell mode

When the address carries **both** `surface` and `theme`, render that cell large
instead of highlighting it inside a grid of eight. One rule, and it makes every
`fw capture 'flutterware.splash/app?surface=android12&theme=dark'` legible
instead of a thumbnail with a blue outline. Pair it with `CaptureMode.isCapturing`
to drop the header and problems list when photographed, as the catalog already
does.

**Cost:** half a day. Touches `splash/screen.dart` only.

---

## Phase 2 — Fixes, not an editor

> **Deleted 2026-08-10.** Built, shipped, and reverted — see § Phases 2 and 3
> are deleted. Read this section as a record of what was tried, not as a plan.

The principle: **write only what we must, surgically, and never round-trip the
file.** The moment we own the config we are in the tarpit of comment
preservation, key ordering and merge conflicts. Every write below is one or two
keys.

### 2a. The writer

New dependency: **`yaml_edit`** (Dart team, pub.dev) — surgical edits that
preserve comments, ordering and formatting. Add to `app/pubspec.yaml`.

`app/lib/src/splash/model/writer.dart` — a `SplashWriter` built from a
`SplashConfig`, because the config already knows which of the three targets it
came from:

```dart
Future<void> set(String dottedKey, Object? value)  // null removes
```

It resolves `android_12.image` into the nested path, and knows that all three
kinds (`flutter_native_splash.yaml`, `pubspec.yaml`, a flavor file) nest under a
top-level `flutter_native_splash:` key. One place that writes, so the CLI, the
GUI and an agent cannot disagree about where a key goes.

### 2b. Every problem carries its fix

`SplashProblem` gains an optional `SplashFix`: a human sentence plus a list of
`(key, value)` writes. Rendered as a button in the Problems list *and* on the
tile the problem belongs to.

Candidates that are exactly one or two keys:

| problem | fix | shipped |
|---|---|---|
| no `android_12` image, legacy image present | point `android_12.image` at a studio-generated 1152 icon | Phase 3 |
| dark background, no dark image | write the dark twin of the key that won | yes |
| branding under the home indicator | set `branding_bottom_padding_<platform>` to the device inset | yes |
| unknown key (typo) | rename to the nearest known key, when edit distance ≤ 2 and there is no tie | yes |
| a placement value not in its vocabulary | the nearest legal value, replacing only the bad token of a compound | yes (added) |
| a three-digit colour | write it out in full | yes (added) |
| no dark configuration at all | — | no: the colour is a decision, not a derivation |
| not in `dev_dependencies` | — | no: `dart pub add dev:flutter_native_splash` gets the constraint right |

**Exposed as an action, not just a button:** `fix`, taking a problem id, so `fw`
and an agent apply the identical write. A GUI-only capability here would violate
the one-core rule and would mean the agent and the panel disagree about what
"fix it" means.

### 2c. Edit the value you are looking at

The tile captions already carry provenance — `#101418 · from color_dark_android`
(`ui/variant_tile.dart:133`). Make the swatch and the path clickable: a colour
picker or a file picker that writes back through `SplashWriter`.

**The write target is the key that won**, not the most specific key for the cell.
If you are looking at a value defined at `color_dark` and you change it, you mean
`color_dark` — the caption already told you that is where it lives, so there is
no surprise. Offer "only for Android" as a secondary that writes
`color_dark_android`. Getting this backwards is the obvious mistake and it
produces a config that grows a platform-specific override every time somebody
nudges a colour.

**Cost:** 3 days for the whole phase, writer and tests included.

---

## Phase 3 — The image studio

> **Deleted 2026-08-10**, with phase 2. See § Phases 2 and 3 are deleted.

The strongest case for editing, and the reason is a loop that currently costs
five minutes and a round-trip to a real device:

> open Figma → know the 2/3 mask rule → export at exactly 1152×1152 → guess the
> padding → run `create` → build → look at a phone → it is cropped → repeat

Every number in that loop is already in this codebase and known to almost nobody
using the package.

### 3a. Target specs, derived not typed

`app/lib/src/splash/model/studio.dart`, Flutter-free:

| target | canvas | usable area |
|---|---|---|
| `android_12.image` | 1152² (960² with an icon background) | centred circle at 2/3 → **768** (640) diameter |
| `android_12.branding` | 800 × 320 | full |
| `image` | 4× the logical width you want | full |
| `background_image` | derived from the device table's aspect extremes | full |

The `image` row is the one that needs a question rather than a number: the studio
asks "how wide on screen?" in dp and multiplies by `sourceDensity`. That is the
right question and it is the one nobody thinks to ask.

### 3b. The crop surface

Source image, scale and offset, with the mask circle and the safe rect drawn
live over it, and the eight tiles updating from an **in-memory composition** — no
file is written until Apply. That live-tile feedback is the whole point: it is
the thing that replaces the trip to a device.

**Input path: `file_selector` first, drag-and-drop second.** `file_selector` is
already a dependency and the icon tool already uses it (`icon/screen.dart:44`).
Real desktop drag-and-drop needs a new dependency (`super_drag_and_drop` or
`desktop_drop`); ship the click path first, add the drop target once the studio
itself is proven. Ninety percent of the value, zero new deps, and the risky part
is decoupled.

### 3c. Output

- PNGs written under `assets/splash/` by convention, path configurable through
  the plugin's declaration in `tool/flutterware.dart`.
- **The source is copied in beside them.** Re-cropping means re-dropping;
  keeping the original next to the derived files means nobody has to find it
  again. Deliberately **no sidecar** recording crop parameters — inventing a file
  format is how we end up owning something.
- The keys that reference them, through `SplashWriter`.

Encoding uses `package:image` inside `Isolate.run`, exactly as
`icon/model/icons.dart:171` already does.

**Cost:** 5 days. This is the phase with real UI in it.

---

## What we deliberately do not build

- **A form over the config.** ~50 keys, a cascade that means the form must either
  show all of them or lie about which one is winning, and a text editor that is
  already better at it. Refused on principle, not on cost.
- **Round-tripping the YAML.** Surgical writes only.
- **A replacement for `flutter_native_splash:create`.** We spawn the project's
  own pinned version (`splash_core.dart:519`) for the reason recorded there: a
  version we linked against would produce output the project's CI would not.
- **A splash-to-first-frame animation simulator.** The white-flash-on-handoff
  complaint is real, but it is a runtime property of the app, not of this config
  — it belongs to the run cockpit if it belongs anywhere.

## Decisions

1. **Poll a fingerprint; do not watch — and keep a manual Reload regardless.**
   Fifteen paths across four directories, `DirectoryWatcher` is recursive, and
   the scan already `stat`s all of them. Detection fails silently on exotic
   filesystems, and a stale preview is indistinguishable from a correct one, so
   the button is permanent rather than a fallback.
2. **The device range is a computed sweep first and an axis second.** Do not
   make the user click nineteen devices to find the broken one.
3. **The write target is the key that won.** The caption already says where the
   value lives.
4. **Every fix is an action before it is a button.** One core, three surfaces.
5. **The studio keeps the source and invents no file format.**
6. **Click-to-pick before drag-and-drop.** No new dependency on the critical
   path.

## Open questions

1. ~~**Where the studio's output goes when a project already has an asset
   convention.**~~ **Answered while building 3:** beside the file the key already
   points at, then beside any image the config references, then `output` on the
   plugin declaration, then `assets/splash/`. Detecting beats declaring — a
   project with a convention has already said what it is.
2. **Does the fit sweep belong in `validation.dart` or beside it?** It is the
   first rule that depends on the device table rather than on the generator's
   source, which is a different kind of claim and may deserve a different
   heading in the UI.
3. **Launcher-icon discovery** currently lives in the icon tool, which is
   pre-overhaul code slated for rework. Extract now and accept the churn, or read
   the mipmaps directly in the splash scan and de-duplicate later?
4. ~~**What a prediction-vs-recomposition mismatch does to the badge.**~~
   **Answered 2026-08-10 by deleting the comparison** — see § The inversion. The
   question assumed the two pictures were peers. They are not: one is a readback
   and one is a guess, so the panel shows the readback and says when it could
   not get one.

## Sequencing

| phase | lands | cost | status |
|---|---|---|---|
| 0 | the Android 12 message is true; launcher icon drawn | 0.5d | **done** |
| 1a | the preview tracks the file; manual Reload + last-scanned | 1d | **done** |
| 1b | device axis + overflow and safe-area rules | 2d | **done** |
| 1c-a | artifact browser, roles, per-density dp | 1.5d | **done** |
| 1c-b | recomposition from `launch_background.xml` / `styles.xml` | 1.5d | **done, Android only** |
| 1d | single-cell mode for `fw capture` | 0.5d | **done** |
| 2 | `SplashWriter`, fixes on problems, click-to-edit | 3d | **built, then deleted 2026-08-10** |
| 3 | the image studio | 5d | **built, then deleted 2026-08-10** |

Amendments made while building, each recorded at the code:

- **1b drops the third rule** the plan named (a top-aligned image under the
  status bar). `android_gravity: top` is rare and when somebody writes it the
  image being under the status bar is usually the intent — it would have fired
  on intent rather than on a mistake. The two that shipped fire on defaults
  nobody chose.
- **Fit problems collapse to the worst device**, not one per device.
- **A chosen `?device=` applies per platform.** Redrawing the Android row at an
  iPhone SE's 375×667 would be a picture of a phone that does not exist.
- **1c-a stops before "generated beside predicted".** The Android artifact is a
  bare layer and the prediction is composed; putting them side by side and
  calling it a comparison would make somebody trust the wrong one. That
  comparison is what 1c-b is *for*, so it waits for the recomposition.
- **`background.png` is now recognised as an artifact.** It was skipped, which
  meant the browser showed a splash with no background in it.
- **1c-b ships Android only, and web moved out of it.** Legacy Android and
  Android 12 are recomposed from `launch_background.xml` and `values-v31/styles.xml`.
  Web was its own small piece of work and **landed 2026-08-10** — out of
  `web/index.html`, not `style.css`, which does not exist; iOS stays out for the
  reason already given.
- **Open question 4 is answered: a drift note is `Tone.info` and carries no
  device or key.** It indicts our reading of `cli_commands.dart`, not the
  project — a config that is perfect must not grow an amber dot because our
  transcription slipped. The message says so in as many words.
- **Drift is not reported while the config is stale.** The two are then
  *supposed* to differ, and saying so would be reporting staleness twice under a
  more alarming name.
- **1d hides only the timestamp under capture, not the safe areas.** The plan
  said the overlay would go; that was wrong on `CaptureMode`'s own terms, which
  are "hide what varies without meaning", not "hide chrome". The safe areas are
  part of what the panel *is*, so a screenshot without them would not be a
  picture of the product. A wall clock is the textbook case and it goes.
- **1d is where predicted-vs-generated finally lands**, because 1c-b gave it
  something to compare. Both pictures go through the same `SplashRender` over the
  same `SplashComposition` type, so a difference is a difference in the
  compositions rather than in two drawing paths.
- **The address is written by the plugin, not the screen.** `SplashScreen` takes
  callbacks; only `_SplashPanel` touches `AddressScope`. That is what keeps the
  screen mountable in a test with no address at all.
- **Two of the six planned fixes turned out to have no defensible value, and one
  turned out to be for a problem that cannot happen.** "No dark configuration at
  all" would have written `color_dark` — but from what? Copying the light colour
  makes dark resources real and identical to light: more files, the same picture,
  and a config that now looks like somebody thought about it. Adding
  `flutter_native_splash` to `dev_dependencies` needs a version constraint, and
  one transcribed into this repo goes stale the week after; `dart pub add
  dev:flutter_native_splash` gets it from pub. Both problems keep their
  diagnosis and get no button. **The bar a fix has to clear is that the value is
  derivable and not a judgement** — otherwise the buttons stop being trustworthy
  and people stop pressing all of them.
- **The dark-image rule could never fire for Android 12, and the code had a
  branch for it.** `android12Image(dark)` falls back to `android_12.image`, so a
  dark cell whose light twin has an image is never missing one. Writing the fix
  is what surfaced it; the branch is gone.
- **The branding safe-area sweep was a false positive on Android 12**, shipped in
  1b. `_applyStylesXml` for the v31 templates takes no padding — the system
  places `windowSplashScreenBrandingImage` itself — so `branding_bottom_padding`
  does not reach that surface and there was no edit that would answer the
  warning. Trying to attach a fix to it is what found it. Exempted, like the
  fixed 240dp icon slot already was.
- **The branding padding fix writes the platform-suffixed key**, not the global
  one the plan named. The number comes from that platform's hardware — 34dp on a
  notched iPhone, less on an Android gesture bar — so a global value set from the
  worst iPhone would over-pad every Android device to answer an iOS problem.
- **A suggestion is withheld on a tie, and the guard earns its keep in the
  vocabularies rather than in the key names.** `scaleAspectFil` is one edit from
  `scaleAspectFit` and one from `scaleAspectFill`; the two legal values are only
  two edits apart to begin with. The key namespace turned out to be sparse enough
  that no real tie could be constructed in it.
- **2c needed a second door: a `set` action.** A fix is a remedy the plugin
  worked out; click-to-edit is a value somebody chose, and routing it through
  `fix` would have meant inventing a fix per keystroke. `set` validates the key
  against the generator's own vocabulary *before* writing — an unknown key is not
  a cosmetic problem, it makes `create` exit, and a tool that wrote one would
  have taken a building project and stopped it.
- **The fix button has no confirmation dialog.** The label *is* the edit —
  `Rename to "color_dark"` — and the tooltip names the file and the keys. A modal
  would add a step and say strictly less. What makes that defensible is the size:
  one or two keys, spliced into a version-controlled file.
- **Missing levels are created in one write, not as a chain of empty maps.**
  `yaml_edit` splices an empty map in flow style, so creating `android_12:` and
  then filling it leaves `android_12: {image: …}` in an otherwise block-styled
  file.
- **3 is an action first and a crop surface second**, which the plan did not
  say and which turned out to be the larger half. `fw run splash prepare
  --source=assets/logo.png --target=android12Icon` does the whole thing with no
  UI at all — the canvas, the fit, the file, the key. An agent cannot do the
  2/3-mask arithmetic either, and the numbers are the value here rather than the
  dragging.
- **The live tile is one tile, not eight**, and it is drawn from a **real encoded
  PNG** written to a temp file on a 140ms debounce and loaded back through the
  ordinary `SplashRender`. Six of the eight cells do not read the key being made,
  so a live matrix would be six unchanged pictures around the one that matters.
  Drawing the crop with a second widget path would have been cheaper and would
  have meant the preview and the export were two implementations that agree until
  they do not — the exact failure this plugin exists to catch. What is on screen
  is the file that will be written.
- **The default fit targets the usable *square*, not the inscribed circle.** For
  the Android 12 icon that means a square source touches the mask and loses its
  corners — which is what the package's own "1152 file, 768 image" advice
  produces, and what a logo with transparent corners wants. Fitting to the circle
  would shrink every icon by 30% to protect corners that are usually empty. The
  overhang is *reported* instead, because only the person looking at it knows
  which kind of artwork they have.
- **Open question 1 is answered, and the answer has three steps.** Beside the
  file the key already points at; failing that, beside any image the config
  references, since a project with an `assets/branding/logo.png` has already told
  us where its splash art lives; failing that, `assets/splash/`, which is the only
  guess in the whole resolution. The launcher icon is excluded by name — the scan
  keeps it among the referenced images, and following it would put generated
  assets inside `android/app/src/main/res/mipmap-…`.
- **The source is copied only when it came from outside the package.** The plan
  said keep it beside the derived files; that is right for the drag-and-drop case
  where the original is on somebody's desktop and gone next week, and clutter for
  a file already in the project and already findable.
- **`decodeImage` does not return null on rubbish.** It walks its decoders asking
  each whether the bytes are its format, and the PSD probe reads a 32-bit header
  field without checking the buffer is that long — three stray bytes come out as
  `RangeError (length): Not in inclusive range 0..2`. That is what a user picking
  a corrupt file would have been shown. Found by the test that fed it garbage.
- **The crop surface was a lie about its own shape until a throwaway golden
  caught it.** Its parent `Expanded` hands down a *tight* width, a
  `Container(width: box)` under a tight constraint is stretched to fill it, and a
  1152² canvas came out landscape — with the mask circle centred in the stretched
  box while the source was positioned as if the box were the width the arithmetic
  assumed. Nothing in the widget tests could see it. Same lesson as the two
  layout defects in 1b: **render it and look.**
- **The picker is faked at the platform interface**, not through a test-only
  parameter on the dialog. A seam in the production API that only the tests use
  is a second way to open a file.

### Found by actually opening the panel (2026-08-01)

Running `create` on `examples/example` for the first time turned up four bugs
that no test could have caught, because every one of them was the model and the
test agreeing on something false.

- **`launch_background.xml` is not evidence of generation.** `flutter create`
  writes one into every project. Reading it as generator output gave a "What
  shipped" with no colour and no layers, which the renderer drew as a **black
  rectangle** — the first thing anybody opening the panel on a fresh app saw.
  The marker is `background.png`, which `_createBackground` always leaves
  behind. `findSplashArtifacts` already refused to count the stock
  `LaunchImage.imageset` on iOS *for exactly this reason*; the same trap, one
  platform over, went unnoticed.
- **The flagship warning said the opposite of what happens.** "A dark colour
  makes dark resources real, so this will show an empty background — set
  `image_dark`" is alarming, plausible and wrong. Every platform resolves a
  missing dark resource to the light one: Android's dark `launch_background.xml`
  is written with `showImage: imagePath != null` (the *light* path) and resolves
  `@drawable/splash` to the non-night folder; iOS's `Contents.json` has no dark
  appearance at all without a dark image; web says `darkImagePath ??= imagePath`
  in as many words. What ships is the light logo on the dark colour, which is
  usually the intent. Now an `info`, and the fix that wrote `image_dark` to the
  file it already fell back to — a no-op sold as a repair — is gone.
- **A dark cell with no dark config drew black under a caption saying the OS
  shows the light splash.** The picture contradicted its own caption on the most
  common config there is. `resolveSplash` now returns the light resolution
  labelled dark, so the tile shows what the device shows.
- **Web branding really does break, and the wrong rule hid it.** `index.html`
  gets a `<source media="(prefers-color-scheme: dark)">` pointing at
  `branding-dark-*` whenever the *light* branding is set, and
  `_createWebImages(imagePath: null)` deletes exactly those files. That is a real
  warning with a real fix, and the old `else if` fired first and talked about
  images.

Two smaller ones from the same session: `windowSplashScreenBrandingImage` was
never read back, so an Android 12 branding showed in the prediction and not in
what shipped; and `drawable-xxxhdpi-v31` was treated as "not a density", so the
readback named `drawable-hdpi-v31` — the lowest — as the file that shipped.

**Drift detection caught none of it**, and that is the lesson worth keeping. It
compares the prediction against the recomposition, and both were derived from the
same wrong belief about dark fallback. A cross-check only finds what its two
halves disagree about; it cannot find a mistake they share. The thing that found
these was opening the panel on a real project.

### The inversion (2026-08-10)

An evaluation pass after phase 3 asked whether the plugin had earned its size:
~9,200 lines of production code and 5,000 of test, which makes splash the third
largest feature in the app, ahead of scenarios and sixteen times the launcher
icon plugin that was *deliberately* scoped down to a viewer eight days earlier
for reasons that apply here word for word.

The two halves turned out to have very different value density. Reading the
generated files back, writing the config through `yaml_edit`, and the staleness
poll — roughly 1,200 lines — are the parts that do what the plugin is for.
Everything that predicts what the generator will do is a transcription of a
third-party package, and § "Found by actually opening the panel" is what a
transcription's failures look like.

So two changes, and no rewrite:

- **`compareSplash` is deleted.** It existed to catch exactly the class of bug
  the section above describes, and caught none of them, for a reason that is
  structural rather than incidental. Its one real signal — the config has moved
  since `create` ran — is `splashIsStale`, which fires on its own. Open question
  4 above is answered by removing the thing that raised it.
- **The generated files are the picture; the prediction is the fallback.**
  `SplashConfigScan.pictureFor` returns a `SplashPicture` carrying its own
  provenance, every tile says which it got, and `describe` grew a `generated`
  flag so an agent is told the same thing a person is. The side-by-side is gone:
  two pictures with no comparison between them made the reader arbitrate, which
  is the panel's job, and it was the source of every "why is this one black" in
  first contact.

Two consequences fell out. `recomposeSplash` now resolves `-night` per file the
way Android does, so a dark cell with no dark resources is the light splash
*read back from disk* rather than a prediction — which is the same fix as the
third bullet above, one layer down, and the layer where it is a fact rather than
a claim. And the header offers `Run flutter_native_splash:create` (confirmed
first — it rewrites 44 files) wherever the panel is showing a guess, because a
reader who has just been told the picture is a prediction wants the one action
that makes it real.

### Web recomposition, and the rule it caught (2026-08-10)

Done the same day, and it moves two more of the eight cells onto ground truth —
six of eight now.

**There is no `style.css`.** The spec above says there is, and so did the code
comment, and so did the `describe` text. 2.4.x inlines everything into
`web/index.html`: a `<style id="splash-screen-style">` and a
`<script id="splash-screen-script">` appended to `<head>`, up to two `<picture>`
elements at the top of `<body>`, and `_updateHtml` removes the old
`<link href="splash/style.css">` on sight. One file holds the colour, the dark
media query, both srcsets and the placement classes; `web/splash/img/` holds the
pixels. Parsed with `package:html` — the generator's own parser, so a hand-edit
reads back as a hand-edit.

The readback covers: background colour from the `body` rule and the
`@media (prefers-color-scheme: dark)` block layered on top (no block means dark
is the light colour, the same fact `drawable-night`'s absence carries); the
background image, which the template always stretches; the image and branding
from the densest `Nx` file, at `pixels ÷ multiplier` CSS px; and the placement
from the `<img class>`.

**And it immediately found a rule that was wrong.** The `web-branding-dark`
warning — "the generator deletes `branding-dark-*` when `branding_dark` is
unset" — was written in this same overhaul, a week after the flagship warning it
replaced, from the same source, and is wrong in the same direction:
`_createWebSplash` says `brandingDarkImagePath ??= brandingImagePath` one line
above the call that writes those files, and has in every version back to 2.4.2.
The files are on disk in `examples/example` right now. Web branding falls back
exactly like the image; the rule, its fix, and the special case it had grown in
`resolveSplash` are all deleted.

That is two transcription rules written from the same file, one week apart, both
confidently wrong, both about the same fallback. It is not an argument for
reading more carefully next time. It is the argument for § The inversion.

**iOS is the one surface left**, and permanently: a storyboard is constraints,
which is a layout engine rather than a recipe. The tile says so.

### Phases 2 and 3 are deleted (2026-08-10)

Reverted the same day they were reviewed, on Xavier's call after opening the
panel: *"everything is too complex."* The tile was spending four caption lines
on an editing affordance, and the plugin had become the third-largest feature in
the app for a splash screen.

Gone: the studio (model, isolate renderer, 715-line dialog, `prepare`), the
fixes (`SplashFix`, `writer.dart`, `fix`, `set`), click-to-edit
(`edit_target.dart`, the value dialog, the tappable captions), and their tests
— about 3,500 lines. Also gone: the two rules that narrated what `create` would
write for dark, since the readback now draws it and the tile caption says it.

Kept, and this is the whole plugin now: read the config, read the generated
files back, draw eight cells with their provenance, and list the problems that
are facts about *your files*. `describe`, `artifacts`, `reload`, `generate`.

**The panel itself writes nothing** — decided 2026-08-10, after a
`Run flutter_native_splash:create` button lasted a day. Two reasons, and the
second is the one that settles it:

- It discarded everything that would have made it trustworthy. `generate`
  returns `ok`, `exitCode` and the generator's own stdout and stderr, kept whole
  *because they name the file it choked on* — and the button awaited the call
  and dropped all three. A failed run looked like a quiet re-scan.
- Running the generator belongs to whoever edited the config. In the loop this
  plugin is for — an agent edits the YAML, runs the generator, captures the
  panel with `fw capture <address> -o shot.png`, and a person looks at the
  picture — the human never presses it. The agent calls the action and gets the
  exit code and the output back as data, which is a better surface than any
  dialog.

`generate` stays as an action for exactly that caller. `Reload` stays in the
toolbar because it only re-reads.

**The reasoning is not that the editor did not work** — it did; the fix buttons
edited a real config and kept its comments. It is that every button was computed
from a transcription of a third-party generator, and two of those transcriptions
shipped backwards inside eight days. A wrong picture is a wrong picture. A wrong
fix button is a wrong edit to somebody's project.

Same conclusion as [[project_launcher_icon_viewer_scope]] reached for icons on
2026-07-31, arrived at here the expensive way. What survives is what that
decision would have predicted: a viewer, plus the one action that runs the real
generator.

The numbers the studio knew — 1152 square with only the inner 768 circle
showing, a splash image drawn at a quarter of its pixel size — are still in
`validation.dart`'s Android 12 rules and in `surface.dart`. They are worth a
sentence in the panel; they were not worth a cropping UI.

**All of it is committed**, phase 3 included. The order matters more than the
dates: phase 1 is the "seeing" half and is what the plugin already claims to be;
phase 2 is small once the writer exists; and **phase 3 depends on phase 1 in a
way that is not merely organisational** — the studio's entire value is the live
tiles updating as you drag, so building it first would mean building it against
a preview that cannot show a device range, cannot show safe areas, and does not
notice the file changed.

1c-b is placed where it is deliberately. It verifies `config.dart`, which
everything after it trusts — finding out that the cascade transcription is wrong
is much cheaper before phase 2 starts writing keys based on it than after.

### The review pass after the rebase (2026-08-10)

A read of the whole plugin against master, once the shape had stopped moving.
Nothing found was a crash; all of it was the same kind of thing — an idea that
had moved and left a copy behind.

**Two surfaces still answered the old way.** The inversion changed `describe`
and the panel to read the generated files, and missed the two places that reach
the same scan by another route:

- `fw status`'s matrix table was still built from `compositionFor`, the config
  prediction. On a generated project it printed `assets/logo.png` where
  `describe`, over the same scan in the same process, printed what the drawables
  say. It now uses `pictureFor` like everything else, and carries a `From`
  column — a picture and its provenance are one fact, and a table that showed
  one without the other was how this drifted in the first place.
- The `artifacts` action read `scan.main` and had no `flavor` parameter, so a
  flavored project always got whichever config sorted first — while the panel,
  which follows the address, was showing a different flavor's files at that same
  moment. It takes `flavor` now, and reports which one it answered for.

**`pictureFor` was doing disk I/O from `build()`.** Recomposition parses
`web/index.html` and a stack of drawable XML; the panel calls it nine times per
build. Measured against `examples/example`: **5.8ms of synchronous I/O per
rebuild**, on the UI isolate. Everything else on `SplashConfigScan` is computed
once by `_scanConfig` and kept — this was the single exception, and it was the
expensive one. It is now a map built at scan time, which also makes
`packageRoot` unnecessary on the scan.

**Deleted:** `SplashArtifactsView` (197 lines) — the inspector already lists each
cell's files beside the picture they belong to, and the header's pill and every
cell's origin line already say when nothing has been generated. `blocksGeneration`
on `SplashConfigScan`, uncalled. `SplashToolbarButton`, and its `primary` flag
that no caller ever set — a leftover from the generate button. `SplashScreenBox`
was a pass-through to a private widget, justified by a side-by-side view that had
been deleted with `compareSplash`; the wrapper is gone and the widget is public.
The problem row, written twice identically, is now `SplashProblemRow`.

### Feedback is a shared control, not a splash problem (2026-08-10)

Xavier on the Reload button: *"no push feedback... I have very little confidence
in that."* Correct, and it was worse than it looked — the button also called
`core.invoke('reload')`, which `NativePlugin` explicitly forbids (*"a panel calls
its core directly, and no panel invokes an action"*), and threw the result away.

The instinct is a spinner. A spinner is wrong here: the reload takes about 40ms,
so a spinner shown for its natural duration is one dropped frame. **What is
missing is an acknowledgement, and an acknowledgement has to outlast the work.**

`app/lib/src/ui/action_button.dart` — `FwActionButton` — holds each state for a
minimum rather than for its natural length: running for at least 320ms even if
the future is already complete, a tick for 1.4s, and a failure that stays up
until the next press carrying the error's own words. The floor is started
alongside the work and both are awaited, so work that takes longer is not
delayed by it.

It is in `ui/` and not in `splash/` because the defect was never splash's. The
dependencies panel had the same Reload behind a one-item popup menu; it uses the
button now, and `refreshOrThrow` rather than `refresh`, because `refresh`
resolves to a `Snapshot` carrying its own error and would have shown a tick for a
failed resolve.

The splash panel's Reload now calls `SplashCore.reload`, a real method that
returns whether anything moved and throws when the re-read fails. The `reload`
*action* wraps it and reports a failure as a result instead, because finding out
that a config is broken is exactly what somebody calls `reload` to do.

The states are transient and timing-dependent, so no screenshot and no widget
test shows them — they are a preview (`tool/catalog/demos/action_button.dart`),
where they can be pressed.

## Tests

Existing coverage is good (1626 lines across `app/test/splash/` and
`app/test/plugins/`) and every phase extends it rather than replacing it.

- **0** — `splash_config_test.dart`, `splash_composition_test.dart`: the
  launcher-icon composition and the narrowed `fallsBackToLight`.
- **1a** — new `splash_fingerprint_test.dart`: an injected clock and a temp
  directory; a touched image fires, a rewritten-identical file does not.
- **1b** — new `splash_fit_test.dart`: pure arithmetic over `Devices.all`, no
  widgets.
- **1c** — `splash_screen_test.dart`: artifacts present, absent, stale.
- **2** — new `splash_writer_test.dart`: comments and key order survive a write,
  across all three config kinds.
- **3** — new `splash_studio_test.dart`: target specs and export geometry, pure
  Dart.
