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

## Round two — scale, and many guests (same day)

The owner pushed on two things: does it stay fast with many elements, and
what else does the architecture buy. Both answered by extending the spike.

### Multi-guest: one model, every screen

The announce file became a directory (`~/.flutterware/scene_hosts/<name>.txt`)
and the link connects to every URI it finds, pushing to all and reporting
per-guest round trips. Anything may drop an announcement for a guest that
cannot reach the editor's filesystem — which is how the second guest joined:

**The same scene host, launched on the iPhone 16e simulator by the run
plugin, renders the same scene as the desktop guest, live** — scaled to fit
its screen (one `FittedBox`), selection border tracking, spinner animating at
the sim's own 60fps, the mockup `Drink` and the app theme having crossed no
wire. An edit in the editor lands on both guests from one push loop. This is
the language×device export matrix's interactive twin, and it fell out of a
directory listing. (The sim's own iOS project needed the same `free.xcscheme`
copy as macOS — the default-flavor regression is platform-wide.)

### Scale, measured with a 100-nodes-per-click stress button

| nodes | payload | iPhone guest frame | RTT (both windows occluded) |
|---|---|---|---|
| 11 | 1.8KB | 14ms | ~240ms cold |
| 112 | 16.1KB | 36ms | ~540ms first-at-size |
| 314, under drag | 44.7KB | **28ms** | ~300ms |
| 415 | 59.0KB | **28ms** | ~330ms |

The split matters: **the guest's frame cost is flat** — ~28–36ms on a phone
simulator from 11 to 415 nodes, measured inside the host — while the RTT
inflation lives almost entirely on the *editor's* side: the occluded toy's
throttled event loop, plus its own 400-widget mirror rebuild and 400-key
sweep per edit. The mirror is exactly the part the real architecture deletes
(the guest composites into the editor window instead), so the polluted number
indicts the throwaway half, not the pipe. Payload grows ~14KB per 100 nodes;
diff/patch remains the obvious lever if scenes grow past thousands.

### The other advantages, observed rather than listed

- **The guest is a driveable app**, so the whole screen grammar applies to
  the *rendered scene*: one `styles` call against the phone returned the
  banner's full type ramp — including `14/500 white · "Order now"`, a style
  the editor never authored because it belongs to the app's button theme.
  Design audit, agent verification, and screenshots of the truth are free.
- **Hot reload is per-guest and cheap** — 136ms on the simulator — and the
  scene survives it, because the scene is editor-owned data.
- **Isolation**: a crashing user widget takes down a guest, never the editor;
  the announce/reconnect loop already reattaches a relaunched guest.
- Implied and unproven: a *physical* device guest (same pipe, the URI is in
  the run ledger), a guest per theme/locale for side-by-side variants, and
  the tester-lane guest as the headless twin for export.

## Round three — the composited canvas (same day)

The owner's remaining fear, named directly: once the guest composites *into*
the editor window through the embedder texture, does drag stay instant or is
there unfixable lag? Built as the owner chose — inside the studio's machinery
rather than the toy's — and measured.

**What was built:** a dev entry point (`app/lib/main_scene_canvas_dev.dart`,
the *Scene canvas (spike)* run entry) mounting the toy's editor panels around
a canvas whose artboard picture is an embedder guest's texture. The guest is
the example package's new `Scene canvas host` preview entry —
`SceneHostApp(bare: true)`, artboard at the window origin so editor and guest
share one coordinate space — booted by a `CatalogSession` exactly as the
motion and previews panels boot theirs, and pushed to via
`session.callGuestExtension('ext.fw.scene.apply', …)`. The guest's measured
rects become the editor's geometry: hit targets, selection overlay and
handles all read what the guest laid out. Roughly 250 new lines, every organ
pre-existing.

**The numbers, live window:**

| | rtt | guest frame |
|---|---|---|
| cold first apply | 94.4ms | 88.4ms |
| selection change | 40.3ms | 14.0ms |
| **under drag** | **22.2ms** | **20.7ms** |

> **Under drag, the round trip is one guest frame.** Pipe overhead —
> serialize, VM-service hop, rects back — is ~1.5ms. The composited canvas
> costs what any Flutter app's own input-to-present latency costs; there is
> no architectural lag to fix, because there is almost no architecture in the
> path.

The full loop verified through the texture: click-ladder selection from
guest rects, absolute drag (the badge, live in the texture), inspector edits.
The guest runs Impeller/Metal; the daemon snapshot cost 2.3s cold and the
whole boot-to-first-frame sat under 15s on a warm build cache.

Two gaps met and noted: the studio's window-capture pipeline does not
composite *this* guest into screenshots (the live window is fine — agent
screenshots of the spike show a hole where the texture is), and the
`FittedBox`-less bare guest plus `engine.resize` to artboard size is what
makes coordinates line up — zoom still scales the texture in the editor, with
the known blur-at->1× to solve later via resolution-tracking resizes.

## Round four — what the first hour of human use surfaced (same day)

The owner used the composited canvas by hand. Three findings, each fixed the
same hour, and each worth more than its diff:

- **A one-frame blink of the canvas ~1s after every click.** The chain: any
  human tap in a run-guest app opens a ~300ms burst; when it closes, the
  human-beats journal settles and photographs the window; `toImage` cannot
  rasterize an external texture, so the capture raises `OffscreenRaster`,
  during which `GuestTexture` withholds the texture for exactly one frame.
  The withhold exists for a Linux segfault — on macOS the captured picture
  has a hole either way — so macOS now keeps the texture painted through
  rasters and pays nothing. This also cures the same blink in the previews
  live stage, where the stage ground had been masking it.
- **Which raised the better question: why was the app photographing every
  human tap at all?** The capture was armed at guest startup for every
  launched app, while the beats design itself says unpolled beats age out of
  the ring unseen — cost paid in the user's app, value dropped. Split along
  the cost line: the gesture *list* stays always-on (a pointer route, no
  frames, and it must predate the first agent step to fill its `human`
  field), and the *capture* now arms on first consumer contact
  (`ext.flutterware.act` or `ext.flutterware.beats`) and stays armed. Opt-in
  by use, no knob: an app nobody drives and nobody polls never captures.
- **Yellow double underlines on every text node** — bare mode had swapped the
  standalone host's `Scaffold` for a `ColoredBox`, so `Text` inherited the
  no-`Material` debug fallback. Now a `Material`. The lesson outlives the
  typo: this is the two-renderers-diverge failure in miniature — the toy's
  mirror always looked right inside the editor's own ambient stack while the
  real render was wrong, and only showing the real render surfaced it. It
  also names a contract: **a scene guest's ambient stack (`Material`, theme,
  directionality, `MediaQuery`) is part of the scene runtime's job**, and it
  is the same mechanism as the previews `wrapper:` — the registration story's
  wrapper and the canvas's ambient story are one thing.

The meta-finding: all three appeared only because a human used the real
composited pipeline. None was reachable from the toy, from the specs, or from
agent-driven verification alone — the drive layer's own captures were the
*cause* of the first one.

## What remains before this is the editor (not tested here)

Compositing the guest **into** the editor window instead of beside it — the
embedder-guest texture the previews live stage already uses; input routing on
that surface (or an editor overlay positioned from the returned rects — which
now flow); throttling pushes to frame cadence rather than edit cadence;
diff/patch updates if scenes grow large (the whole-model push was ~2KB here);
what a *scenario-driven* clock does to the guest (the motion editor's
scrubber becomes one more field in the applied data — untested); and the
guest's crash/restart story mid-edit.
