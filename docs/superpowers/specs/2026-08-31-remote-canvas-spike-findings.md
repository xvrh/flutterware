# Remote canvas — the scene rendered where user code lives, measured

**Date:** 2026-08-31
**Status:** findings from a working spike, all numbers observed live. The
question, set by the owner: can the *whole* canvas render through the preview
system — in a process compiled against the user's package — **without compile
in the loop**, at the canvas toy's speed and simplicity? The fear it answers:
an editor-process canvas can never inherit the app's theme, and a rasterized
external node kills live/animated widgets.
**Artifacts:** `examples/example/demo/scene_host.dart` (the guest half, behind
the *Scene host* entry point) and `app/lib/canvas_toy/remote.dart` plus an
`ExternalNode` kind in the toy (the editor half). Both stay disposable.
**Leans on:** `2026-08-31-canvas-toy-findings.md` (the editor surface),
`2026-08-31-widget-registration-findings.md` (whose registry this spike
hand-writes).

## The reframe that makes it work

*"Compile in the loop"* conflates two different changes. An **edit** — drag a
node, retune a size — is a *data* change: the scene model is a value, and it
travels as JSON. Only a **code** change (the user edits a widget's source)
needs a compiler, and that path already exists as hot reload. Dart-as-file is
the *persistence* format, not the edit-time transport. So:

> The scene renderer runs in a guest compiled against the user's package,
> once per session. The editor streams the model to it as data over a
> VM-service extension; the guest renders natively and streams measured rects
> back. The compiler only runs when *code* changes.

## What was built

- **The guest** (`scene_host.dart`, an ordinary entry point of the example
  app, launched by the run plugin): decodes the scene JSON, renders built-in
  nodes with the same interpretation the toy uses, renders **external nodes
  through a hand-written registry** — the real `DrinkBadge` with a real
  `Drink` mockup that never serializes, a `CircularProgressIndicator`, a
  `FilledButton` taking the app's own theme — draws the editor's selection
  border itself, and answers `ext.fw.scene.apply` with every node's laid-out
  rect. It announces its VM-service URI in a file so connecting needs no
  hand-off.
- **The editor** (the canvas toy, unchanged in its interactions): an
  `ExternalNode` kind rendered locally as a labeled placeholder, plus a
  `RemoteSceneLink` that pushes `doc.toJson()` on every document change —
  selection included — coalescing while a push is in flight, and shows the
  measured round trip in the toolbar.

## The numbers

| | |
|---|---|
| cold first push (guest's first layout) | 98.0ms rtt · 82.6ms frame |
| **warm, under drag load** (dozens of edits coalesced) | **41.7ms rtt · 33.5ms frame** |
| hot reload of the guest mid-session, scene intact | 513–709ms |
| rects returned per push | 11 (every node) |

Both windows were **occluded** throughout, which taints the numbers in the
slow direction: macOS throttles a hidden window's vsync, so most of the warm
33.5ms "frame" is waiting for a permitted vsync, not work. With visible
windows the expected floor is one frame (~16ms) plus low-single-digit
transport. Even the tainted number is interactive-grade — the toy's own
inspector-to-canvas loop runs at the same frame cadence.

**Liveness, proven rather than argued:** an observe of the guest during idle
counted 97 frames and reported `settled: false` — the spinner really spins on
the canvas. The `FilledButton` renders in the host app's theme without the
editor knowing that theme exists. Editing the badge's `size` arg in the
editor's inspector regrew the real widget live, selection border tracking.

## Traps met, each with the fix in place

- **A hidden guest pumps no frames.** The first push after the windows were
  occluded timed out exactly as the occluded-window memory predicts.
  `scheduleForcedFrame()` — the drive layer's own trick — paints anyway. A
  real implementation should force frames on every apply, since an editor's
  guest may well live behind the studio window.
- **`GlobalObjectKey` compares by `identical`,** so interpolated string keys
  never match and the first sweep returned zero rects. A per-name
  `GlobalKey` cache fixes it; worth remembering for any keyed-by-data render
  tree.
- **The example app could not launch on macOS at all under the pinned SDK.**
  `default-flavor: free` (one word for every platform) now makes the flutter
  tool demand a scheme named `free` on macOS, and the new Swift Package
  Manager integration trips over it first. Three-part workaround shipped
  with this spike: SPM opted off for the fixture
  (`flutter: config: enable-swift-package-manager: false` in its pubspec), a
  `free.xcscheme` copied from Runner's, and — build-dir only, uncommitted — a
  `Debug-free → Debug` products symlink because the scheme copy does not
  create the flavor's build configuration. **This is a fixture regression
  worth a real fix**, independent of the spike: every macOS launch of the
  example was broken, not just this one.

## What this settles

1. **The owner's architecture is right, and it is fast enough.** Data-only
   updates give toy-class editing speed; theme inheritance is by
   construction; external widgets are live, animated, and never rasterized;
   and the editor shows the code path that ships — the two-tabs-one-code-path
   law satisfied at the canvas itself.
2. **The interpret-vs-compile fork dissolves.** Nothing interprets in the
   editor process anymore; the "interpretation" is the scene runtime compiled
   into the guest — one renderer, hosted where the user's widgets are. The
   toy's local mirror stops being a renderer and becomes at most a ghost
   overlay (and could be dropped entirely once the guest composites into the
   editor window).
3. **The registration bridge slot is confirmed**: the spike's hand-written
   registry map is exactly the shape the generated
   preview-entry bridge fills, mockups on the guest side of the wire.
4. **The pipe is the run system's.** Launch by the run plugin, VM-service
   extension, forced frames, rects — every organ was already in the house.

## What remains before this is the editor (not tested here)

Compositing the guest **into** the editor window instead of beside it — the
embedder-guest texture the previews live stage already uses; input routing on
that surface (or an editor overlay positioned from the returned rects — which
now flow); throttling pushes to frame cadence rather than edit cadence;
diff/patch updates if scenes grow large (the whole-model push was ~2KB here);
what a *scenario-driven* clock does to the guest (the motion editor's
scrubber becomes one more field in the applied data — untested); and the
guest's crash/restart story mid-edit.
