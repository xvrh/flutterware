# 3D in a scene: a view node over imported assets

**Date:** 2026-09-05
**Status:** direction, with two probes measured. Nothing here is scheduled;
each milestone gets its own design before it is built.
**Branch discipline:** this work lives on a branch cut from the scene branch
(`claude/motion-expansion-planning-abdb7f`) and rebases onto it from time to
time. It never writes to the scene branch — another session moves that one.
**Leans on:** `2026-09-05-scene-master-plan.md` (the property table, slots as
a deferred concept, the optional-package rule), `2026-08-31-scene-v1-design.md`
(the guest is the only renderer; the ambient stack is part of the contract),
`2026-08-28-motion-v2-design.md` § open question 7 (the first time 3D was
asked), `app/test/previews/walk_determinism_test.dart` (the law every frame
obeys).

**The brief:** 3D elements in a scene, moved around and animated by the
scene's own motion, for dynamic promotional video and, when trust is earned,
shipped widgets. Generic — a phone turning with the app on its screen was the
example that started it, not the product. The author of the brief models in
Blender and does not want to learn a 3D engine.

---

## 1. What the probes established

Two probes on the tester lane (the export lane), both in
`examples/example/demo/` with a walk test in `app/test/previews/`. Numbers
from 2026-09-05 on macOS, Metal, 900×700, five stops.

**Probe 1 — a box with a live widget on its face** (`phone_rig_probe.dart`).
flutter_scene's `WidgetComponent` hosts a widget subtree, rasterises it to a
GPU texture and binds it to a surface. The widget showed the playhead's time
as a hue and a number; the camera orbited 100° and dollied 2.5 units as a
function of `t`.

| Claim | Measured |
| --- | --- |
| The screen is the stop's own, never the previous one | hue 74/152/223/300° for 75/150/225/300° expected |
| A walk repeats | byte-identical |
| A walk taken backwards renders the same pictures | byte-identical |
| Cost | ~30ms a frame warm; ~2s cold for the harness |

So the walk law — *a frame is `evaluate(t)` and nothing else* — holds for a
GPU renderer with an asynchronous texture in the loop. **The export lane
needs nothing new for 3D.** The capture is `layer.toImage` plus a wrap of the
image's backing texture, and it landed inside each stop's pumps without being
announced; the reason it did is not proven and §6 keeps it as a hazard.

**Probe 2 — an imported asset with named parts and a baked clip**
(`model_probe.dart`, fixture `assets/models/probe_rig.glb` written by
`tool/make_probe_rig_glb.dart` because Blender is not on this machine and a
generated fixture is reproducible). A `Body`, a `Screen` plane with
top-left-origin UVs, a `Lid` with one rotation clip named `Open`.

| Claim | Measured |
| --- | --- |
| The asset loads at run time, no build hook in the consumer | yes, from the ordinary asset bundle |
| A surface is found by name and a widget bound to its material | `getChildByName('Screen')`, `WidgetComponent.bindOnly` onto `baseColorTexture` |
| The clip is scrubbed by the playhead | `createAnimationClip` + `seek(t)`, parked, never played; the lid swings 0→90° across the walk |
| Screen is the stop's own | hue 360/74/153/222/299° for 0/75/150/225/300° |
| Repeat and backwards | byte-identical |
| Text reads the right way round | yes — so probe 1's mirror was the engine's default quad's UVs, not the capture |
| Cost | ~37ms a frame warm (5 frames in 186ms) |

Two more things it found, both about *loading* rather than rendering:

- **A runtime glTF import answers from an isolate** (`compute` packs the
  primitives), and a walk's stop is tens of milliseconds of real time, so
  the reply lands after the test body that started it — in a fake-async
  zone that no longer exists. Four mounts, four imports, none finished.
  The probe imports once per process in the root zone and clones per
  mount; the product does the same behind the readiness door of §5, or
  ships the build-time `.fsceneb` the asset pipeline exists for.
- **Load through the bundle the tree provides, never `rootBundle`.** The
  harness counts reads on its own bundle as work in flight and waits for
  them; a `rootBundle` read is invisible and the bytes arrive after every
  stop has been photographed. `loadScene` takes a `bundle` argument;
  `Node.fromGlbAsset` does not, so the runtime path reads the bytes itself
  and hands them to `fromGlbBytes`.

**Three traps, each an hour**, all recorded so nobody pays twice:

1. **`UNIT_TEST_ASSETS` leaks into a spawned tester.** `TesterHost` names an
   explicit environment but `Process.start` merges the parent's, so a host
   spawned from under `flutter test` hands the guest the *outer* package's
   asset mock; flutter_test's binding then answers `flutter/assets` from
   `app/build/unit_test_assets`, and every `rootBundle` read in the guest
   sees the studio's own two assets. `DefaultAssetBundle` readers never
   noticed, because the harness wraps the tree in its own bundle; a dependency
   reading `rootBundle` directly is what exposed it. Fixed in
   `tester_host.dart` (`includeParentEnvironment: false`, a copy of the
   environment minus that key). Any test that spawns a host was affected.
2. **A dependency's memoized future belongs to the first mount's zone.**
   flutter_scene caches `Scene.initializeStaticResources()` process-wide.
   Under a harness that runs each entry in its own fake-async zone, an
   `await` on that future from a later mount never resumes — the
   `ScenarioAssetBundle` trap, arriving through a static cache we do not own.
   Its `.onError` also swallows the failure into a `dart:developer` log the
   tester never forwards, so the visible symptom is a black frame and a
   per-frame "not ready to render" line. Rule: a renderer gates on the
   engine's readiness *flag* and never awaits a cached future.
3. **The captured widget arrived mirrored** on the engine's default quad, from
   either side of it, with the projection's handedness verified against the
   orbit direction. The quad is single-sided. Probe 1 flips the child; probe
   2 owns the surface mesh and its UVs and the text reads correctly, which
   settles it: the default quad's UVs run the other way, the capture is
   fine, and a product surface is always a mesh we or the modeller own.

And one small law re-learned: a hosted widget subtree is its own tree, so the
studio's ambient-stack contract (`Material`, theme, directionality,
`MediaQuery`) applies inside every surface texture. A bare `Text` on the
phone's screen drew the debug underline.

## 2. Who does what

Three people's work meets in a 3D shot, and each has a natural home. This
division is the design; everything in §3 follows from it.

- **Shape, surface and rigging are the modeller's, in Blender.** Geometry,
  UVs, materials, textures, named parts, and — when a part moves on its own —
  a rig and *clips* recorded against it. All of it exports as one glTF, clips
  included. flutter_scene imports glTF directly: meshes, PBR materials,
  skins, morph targets, clips, material variants.
- **Placing, framing, lighting and timing are the designer's, in our
  editor.** Where the object sits in the composition and how big, which way
  it turns, where the camera is and how it moves, which environment lights
  it, which clip plays and how far along it is. These are the kinds of value
  the timeline already keyframes, under a few new names.
- **The runtime plays it back.** It loads the file, keeps the node tree, and
  draws whatever camera and transforms it is handed each frame. It decides
  nothing.

The consequence that matters: **there are two kinds of animation and they
never compete.** A clip is baked inside the asset and the scene only *scrubs*
it — clip time is a number track like any other. Everything else is the
scene's motion, keyed by the same person who keys opacity today.

**The camera, for someone who has not met one.** A point in space looking at
a target, with a lens angle. The parametrisation designers actually use is an
orbit: a target, a distance from it, and two angles around it. Four numbers,
keyframed, give the turn-around, the push-in and the reveal — nearly every
product shot. Blender can export a camera inside the file; "use the asset's
camera" is a later option if the runtime imports it (unchecked).

**Lighting** is an environment, and the runtime ships a studio one that lights
any import acceptably with no setup. The default is nothing; a preset picker
comes later.

**The surface convention, for the modeller — verified against Blender 5.2's
exporter on 2026-09-05** (`examples/example/tool/make_probe_rig_blender.py`,
walked by `modelProbeBlender`):

1. Name the object that is the surface. The object's name is the node's
   name, and that is what the scene binds to.
2. Face it toward -Y in Blender. The exporter turns Blender's Z-up into
   glTF's Y-up with -Y forward, the runtime flips Z once more on import, and
   the surface ends up facing the engine's default camera.
3. Keep Blender's default plane UVs. The exporter flips V, so the texture's
   origin lands top-left, which is where a widget's origin is. The text on
   the probe's screen reads the right way round with no correction.
4. Keep the model centred at the origin; the orbit camera looks there.
5. Name the action. With the exporter's default animation mode an action
   becomes a clip of that name, which is what the scene scrubs.

Everything else — materials, textures, rigging — is the modeller's own
business and passes through untouched.

## 3. The node: a 3D view

One node kind. A rectangle on the artboard — the uniform bag unchanged: x, y,
size, opacity, corner, fill behind the render — whose typed content is a
camera and a list of things to draw.

**Content.** A list of *placements*. Each names an imported asset and carries
a transform (position, rotation on three axes, uniform scale), and, when the
asset has clips, a chosen clip and a clip time. A placement may later name a
document from flutter_scene's own editor instead of a glTF, for people who
arrange lights and several models there rather than in Blender.

**Camera.** Target, distance, yaw, pitch, lens angle. Orbit is the model;
free-fly is not offered.

**Surfaces.** The phone screen, generalised: **a named mesh in an asset can
host a slot**, and a slot holds a nested scene, an external widget, or a
scenario step. A phone, a laptop, a billboard and a television are the same
feature, differing only in which mesh the modeller named. A slot on a mesh
that does not exist is refused, naming the meshes that do.

**Environment.** A preset, and exposure. Auto-exposure stays off — it is a
clock.

**Animatable rows**, all `TrackKind.number`, all through the existing motion
model: the five camera values; per placement, position ×3, rotation ×3
(angular, dial), scale, clip time; exposure. About fourteen rows, and the
motion model gains nothing.

**Not in the node:** lights as objects, materials, physics, particles, a
scene graph to edit. flutter_scene's editor exists for that; the product
frame already says assets are imported, not drawn. A particle system is also
a random phase, which the walk law forbids.

**One cheap sibling, worth landing first:** `rotateX` and `rotateY` as
imposed properties on *every* node, with a perspective entry in the transform
the view already applies. Two table rows, no dependency, exact, and most of
what "3D motion" means in a marketing clip. Motion v2's open question 7 named
this as the answer that fails only on a true orbit; the view node is the
orbit.

### 3.1 Version zero, shipped as an external — built 2026-09-05

Everything above except the surface slot fits the external-node mechanism
with no change to the scene model, and that is what exists now:

- `examples/example/lib/model_view.dart` — `ModelView`, a widget over one
  asset with an orbit camera (`yaw`, `pitch`, `distance`, `fov`) and one clip
  (`clip`, `clipTime`), loading through `RealWork.run` and the build-time
  `.fsceneb`; every argument a `double` or a `String`.
- `scene_externals.dart` declares it; the generator wrote `ModelViewArgs`
  and `ModelViewTracks`; `demo/showcase.scene.dart` places it beside a
  headline and its motion keys the orbit, the dolly and the clip time
  through `ModelViewTracks`, like any external argument.
- `fw run scene video` renders it: 73 frames at 1024×576, 38KB, encode
  120ms — `app/build/scene/ShowcaseScene.mp4`. The walk test beside it
  (`showcase_export_test.dart`) does the same with the tester's log in view:
  25 frames at 10fps in 2.2s cold.

So a designer can place a model, key its turn and export a clip today. What
the external cannot do is the surface: content is not an argument. That is
the node kind's reason to exist, and nothing else in §3 is.

### 3.2 The surface, as the third kind — built 2026-09-06

The slot §3 promised exists: `SurfaceNode` (`lib/src/scene/core/view3d.dart`),
a placement with a child. Its rows are the model's placement rows — `asset`,
position ×3, rotation ×3, `size`, `animation`, `animationTime`, shared by
name through one `_placement(of)` list — plus `mesh`, the name of the mesh in
the asset the slot lands on. Its first child is the slot's content: any node
the file can spell, drawn by the view exactly as it would draw it on the
artboard, captured onto that mesh's material. With no `asset` at all the
surface is a plain quad, one unit tall times `size`, as wide as the child's
box: a floating screen with no modelling.

What it took, in order of what it taught:

- **A renderer needs the view's picture of a child.** `SceneKindRenderer`
  gained a third argument, `SceneChildRenderer child`: the view draws one of
  the kind's children the way it draws any node, wrapped in a
  `ListenableBuilder` over the document, so it stays live wherever the
  renderer mounts it — inside flutter_scene's capture host, where the view's
  own rebuild never reaches. The slot's motion (the bar's `scale` in
  `showcase3d`) reaches the texture through that.
- **Two loads of one asset share their materials.** Two rigs bound in turn
  both showed the second slot — `surface_probe.scene.dart` is the picture
  that caught it. The fix is the seam flutter_scene provides for reskinning
  an instance: `host.mesh = mesh.clone()` with a material of the surface's
  own on every primitive. Unlit, because a screen is self-lit; the slot's
  colours arrive as authored rather than shaded by the environment.
- **A kind's children have no artboard box.** The view's measuring pass
  stops at a `KindNode`: a slot drawn into a texture has a box, but not one
  in the artboard's plane. The tree is that node's door, not the canvas.
- **Which way a quad faces is settled by looking.** The renderer's own quad
  (glTF UVs, front toward the engine's default camera) was culled at
  rotation 0 and read mirrored at 180 with the winding written first; the
  other winding is the one that reads. The rig from Blender faces the
  camera at rotation 0 as §2 says — what looked like a 70° turn in the
  showcase was the frustum's edge (half-width ~87 units at that distance
  and lens, the phone at −95).
- **A row name is per kind.** The props test's global uniqueness became
  per-kind, since `scenePropNamed` reads the node's own rows and a surface
  IS a model with a slot. Hand-written rows stay one namespace.

`showcase3d.scene.dart` now places a fox, a phone (the Blender rig, `mesh:
'Screen'`, lid clip keyed) showing a frame with a clock, a caption and a
bar whose scale is keyed, and a plain quad showing a card; the walk test
renders 25 frames in ~2.5s. Not done: a canvas gesture that places a
surface, and the surface's slot as a `SceneRefNode` in the demo (the
mechanism does not care; `_slotSize` already reads the referenced root).

## 4. Where the renderer lives

flutter_scene wants Flutter 3.47, a GPU flag per platform, and its own build
hook. None of that may enter the published package. So:

- **The model and the property rows are in the pure core**, like every other
  node kind — parsed, emitted, round-tripped, animatable, without any 3D
  dependency. `fw scene check` reads a view node with no engine present.
- **The renderer is an optional package**, registered the way an external
  widget is: the app (or the guest, for an artifact) hands the view a builder
  for the node kind; a view with no renderer draws a *named* placeholder,
  never a silent gap. This is the mechanism `ExternalNode` already proved.
- **flutter_scene's names never reach a scene file.** `Scene`, `SceneView`
  and `Node` collide with ours three times over; they stay inside the
  renderer package behind a prefix, and the authoring library exports none
  of them.
- **A consumer adds nothing for an exported video.** The example needed only
  `pub add flutter_scene` — no init, no hook of its own — because built-in
  geometry and a widget texture ship no assets, and a glTF loads at run time
  from the ordinary asset bundle. Shipping a 3D *widget* is where the flag
  and the version floor bite, and that is the consumer's decision, taken
  when trust is earned, as the product frame says.

## 5. Two doors the harness owes, both generic

**Readiness — built 2026-09-05, merged into master's door 2026-09-07.**
The scenarios round that landed as #312 built the same counter under the
name `RealWork` (`lib/src/real_work/tracker.dart`, `package:flutterware/
real_work.dart`), read by the harness's landing loop beside the image
cache's pending count and the bundle's reads in flight. This branch's
`PendingWork` was the same idea built twice; on the rebase it was folded in,
and what it added survives as `RealWork.run(() => …, label: …)`: it runs
the work in the **root zone**, which is the half that matters: a future a dependency
memoizes belongs to the zone that first created it, and awaited from a later
screen's fake-async zone it never resumes. Both probes load through `run`
and the tests lost their warm-up walks. One thing the door does not cure:
flutter_scene's *runtime* glTF import lands in the first body of a harness
process and never in a later one, root zone or not, while a bare `compute`
answers every body (`compute_probe.dart`) and the build-time `.fsceneb`
path walks fine — so it is inside the importer, undiagnosed, and the export
lane's path is the built one anyway. A node kind that loads things needs a way to say *not yet*,
and the walk waits on it. The door serves a Lottie, a Rive file and a video
frame the same day it serves a model. Designed once, in the harness, before
the renderer exists.

**The guest's developer log — built 2026-09-05.** `GuestVmService.developerLog()`
subscribes to the VM service's `Logging` stream; the tester host forwards
each record as a `log:` line beside the guest's stdout, and the embedder
session prints it with the studio's other host lines. Trap 2 in §1 cost an
hour for want of it.

## 6. Hazards

- **The async capture landed in time, and nobody knows exactly why.** The
  most likely reason is that the walk's own `toImage` gives the engine a real
  turn before the shutter, and the widget's capture had been queued first.
  A screen heavier than a colour and a number, or a slower machine, could
  break that ordering. The readiness door of §5 is also the fix here: a
  surface can announce a capture in flight.
- **Conventions eat the days.** Quad facing, capture mirroring and
  handedness took most of probe 1. The product owns its surface convention —
  which way a surface mesh faces, where its UV origin is — and documents it
  as the two-line rule the modeller follows. Probe 2 is the first test of
  that rule on an asset we authored.
- **The canvas on Linux is unverified.** macOS is measured (§7.4). The
  Linux embedder runs OpenGL ES with the same GPU flags and flutter_scene's
  hook produced that target's bundle; it has not been rendered there yet.
- **Cost scales with moving pixels.** A rotating object moves every pixel
  and the video encoder is bound on exactly that. Rendering measured 15 to 24ms a
  frame at 1080p for a three-mesh asset (§7.3); a textured model with the
  post stack on will cost more, and the encoder is a separate number.
- **Sourcing.** A curated set of ready-made devices is a licensing task, not
  a coding one. "Bring your own glTF with a named surface mesh" is the
  escape hatch and the first thing to ship; a bundled set can follow.
- **Determinism beyond the probe.** Auto-exposure, particles, temporal
  anti-aliasing and screen-space effects with history are all clocks. The
  renderer disables them, and the backwards walk is the test that says so.

## 7. Experiments, in order

Each one is a demo entry and a walk test, and each answers one question.

1. **Widget on a surface, camera as `evaluate(t)`** — done, §1.
2. **An imported asset with named parts and a baked clip** — done, §1.
   Every claim held; the two loading findings are what it added.
3. **Cost at export resolution** — done. The model probe at 1920×1080,
   30 stops, walked twice warm: **470ms and 444ms in one run, 670ms and
   732ms in another — 15 to 24ms a frame** depending on what else the
   machine was doing (`phone_rig_probe_test.dart`, "the model probe at
   1080p"). The 30–37ms
   figures above carry a walk's fixed cost over five frames; per frame, a
   1080p rig with a 2× screen texture is faster than real time. Encoding is
   not in this number.
4. **The canvas** — done on macOS. `app/integration_test/scene_3d_probe_test.dart`
   (tagged `gpu`, run by hand) renders the model probe through the
   **embedder** guest, Metal, with `HeadlessCatalog.render`: the imported
   asset, its bound screen and the lid at rest, centre hue 360° (red, the
   playhead's rest), 9.3s including the daemon's boot. So both lanes draw
   the same thing, and the editor's canvas can show a 3D view live. Linux
   (OpenGL ES) is not run; the hook produced that target's bundle.
5. **A Blender export** — done, with Blender 5.2 installed headless. The
   same rig built by a Blender script and exported by Blender's own glTF
   exporter walks identically: names, axes, UVs and the clip all come out as
   §2's convention says, and the convention is now written there. Two things
   it found: Blender 5's layered actions moved the curves off the action
   (set the interpolation preference before keying), and **the asset
   pipeline's hook cache misses a new file in a subfolder of `assets/`** —
   the hook declares the `assets/` directory by its direct children, so a
   second model in `assets/models/` is invisible until something else
   changes or `.dart_tool/hooks_runner/<package>` is removed. A modeller
   will hit that on their second model; it belongs in the refusal, or
   upstream. Still open: a file a stranger modelled by hand.
6. **The build-time path** — done. The example gained the four-line
   `hook/build.dart` the asset pipeline installs, a `hooks` dependency and
   `flutter_scene_generated/` under its assets; flutterware's hook run
   (`BuildHooks`, before the catalog resolves) produced
   `scene.probe_rig.<stamp>.fsceneb` plus its manifest, the symlinking
   bundler shipped the directory, and `loadScene('assets/models/probe_rig.glb',
   bundle: …)` found it. Same walk, same results: hue exact, repeat and
   backwards byte-identical (`modelProbeBuilt`). `loadScene` takes a
   `bundle`, so the read is announced without any workaround; the `.fsceneb`
   loader has no `compute` call in its path (textures still decode on one),
   so the root-zone import cache is belt and braces there, kept for parity
   with the runtime path. Cost to the example: hooks now run on every bundle
   build of the package, ~110ms warm per the hooks memory.

7. **A textured, rigged model from outside** — done. The Khronos "Fox"
   sample (163KB, one texture, a skin, clips `Survey`/`Walk`/`Run`; model
   CC0, rig and animation CC BY 4.0, credited in
   `assets/models/NOTICE.md`) through the version-zero `ModelView`, its yaw
   and clip time driven by a playhead (`fox_probe.dart`). The hook converts
   it with its texture inside the `.fsceneb`; the walk is byte-identical
   repeated and backwards; the fox runs. `ModelView` now orbits the
   model's bounds centre rather than the origin, which an asset with its
   origin at its feet needs. The texture decode landed inside the readiness
   door without anything more said.

## 8. Open

1. Whether a placement's clip time is one track or one per clip — blending
   two clips is a real product need (idle + gesture) and the runtime
   supports weights.
2. Whether the view node's content list is a property or children. Children
   would make placements addressable and selectable on the canvas; a
   property keeps the node one row in the tree. The canvas orbit tool needs
   to answer "which placement did I click" either way.
3. What a slot is, precisely — the master plan defers it to after M9 as *a
   parameter whose value is content*. A surface is the first real one, and
   designing it narrowly here (a nested scene or an external node, bound to
   a mesh name) should not foreclose the component-children case.

## 9. Read against the property table — 2026-09-05, evening

The scene branch landed `lib/src/scene/core/props.dart` (one table the wire,
the JSON, the file's named arguments, the read plane, a copy and an undo
walk) and proved it with four properties. This branch rebased onto it clean.
What that changes for §3, read from the code rather than the plan:

**A row now costs what the commit says.** A `SceneProp` (name, kind, default,
owner, `animatable`, read, write), a field with its constructor parameter, a
renderer case, and a named parameter on the kind's `animate()` extension.
The wire, the JSON, the file, the read plane, the deep copy and the undo
restore take a row with no line. Every value the view node needs is an
existing kind: `number`, `string`, `boolean`, `choice`. No kind is added.

**What a node *kind* still costs, beyond its rows** — the places the table
names as hand-written, counted for one new kind:

| Place | What | Size |
| --- | --- | --- |
| `model.dart` | the class, `typeName`, a `ScenePropOwner` member, a `deepCopyNode` case | a class |
| `scene_file.dart` | one `case` in the parser's dispatch, one in the emitter's head | ~15 lines each |
| `view.dart` | a renderer case | see the seam below |
| `motion_model.dart` | `ScenePropSpec`s in `animatableProps` and an `animate()` extension | a list and a signature |
| `inspector.dart` | a `_…Props` section | hand-laid rows |
| tree, canvas tools | an icon; a placement tool later | small |

Two of those are duplications the table did not remove, and are worth
handing back to M4 rather than working around here:

- **`animatableProps` is a second table.** The motion side keeps its own
  `ScenePropSpec` list per kind (unit, soft range, angular, identity), while
  the table carries `animatable` for the wire. A row that animates is
  declared twice. Folding the spec's fields into `SceneProp` would make the
  timeline's `+` menu and the motion file derive from one place.
- **The inspector is per kind by hand.** Every section is written; the four
  new rows were folded behind a line by hand too. A generic section that
  lays out a node's table rows by kind — number, string, boolean, choice —
  would make the next kind's inspector free, and is what "several hosts"
  promised.

**Placements are children, not a property — open question 2, decided by the
table.** The table carries values; "children and the repeat are structure,
not values". A list of records has no kind, so a placement cannot be a row.
It is a node: a **`ModelNode`** (asset, position ×3, rotation ×3, scale,
clip, clip time — ten rows, all number or string) as a child of the
**`View3DNode`** (camera yaw, pitch, distance, field of view, target ×3,
environment as a choice, exposure — about nine rows). The renderer composes
the children into one 3D scene. This buys what the other answer could not:
a placement is selectable in the tree, addressable by the drive layer, and
undoable like any node.

**A surface is a child too, and the slot is its child — a proposal for open
question 3.** A `SurfaceNode` under a model, with one string row naming the
mesh, whose single child is the content: a `SceneRefNode` for a nested scene
or an `ExternalNode` for a widget. The slot the master plan defers as "a
parameter whose value is content" arrives here as the tree's own nesting,
which the model, the wire and the editor already know how to carry. Whether
that spelling generalises to component children is M4's to judge; it costs
the view node nothing to adopt it first.

**The renderer seam, as a concrete ask.** `view.dart` draws an
`ExternalNode` through a builder the app bound (`bindExternals`), and draws a
named red box when none is. A 3D kind needs the same door one level up: a
renderer registered per *kind* — `SceneView(renderers: {'View3D': …})` or
the equivalent on the host — with the same named placeholder when absent.
One map and one `case`; then the 3D renderer lives in its optional package
and the core never imports it.

**Order, revised.** Tilt first — `rotateX`, `rotateY` and a perspective
entry are imposed properties on the fx plane, not table rows: two
`ScenePropSpec`s, two `Effect` getters, the wire's `fx` tuple growing from
four to six with the four-long form still read, the view's transform, and
two named parameters on each kind's `animate()`. About eight places and no
table row, which is why it goes before the node kind. Then `View3DNode` and
`ModelNode` against the table, with the renderer seam and the inspector
section as the two things to agree with the scene branch first.

## 10. The kind descriptor, spiked — 2026-09-05, night

Built on this branch as feedback in code for the scene branch: the table's
move one level up. Measured against the two 3D kinds as its first consumers,
end to end — file, wire, JSON, undo, inspector, timeline, walk, video.

**What it is.** `lib/src/scene/core/kind.dart`: a `SceneKind` is data — the
name the wire and the JSON carry, the constructor the file spells, its rows
(map-backed `SceneProp.value` rows, with the editing hints on the row),
whether it holds children. `KindNode` (model.dart) is the one node class
every registered kind shares: rows in a value map the table reads and
writes, children when the kind says so. A thin subclass per kind
(`View3DNode`, `ModelNode` in `view3d.dart`) gives the file its constructor
and the motion its typed `animate()` — the two things that are Dart
signatures and cannot be data. The renderer is registered on the view by
name (`SceneView(renderers:)`, `SceneCanvasHost(renderers:)`), and a kind
nobody registered draws a named placeholder, like an external.

**What each host cost — once, for every kind that will ever exist:**

| Host | Change |
| --- | --- |
| parser | one `default:` branch: descriptor by constructor, rows through the table, children by name through the frame's own reader (extracted) |
| emitter | one `case`: constructor from the descriptor, `children:` when it has any |
| wire, JSON | one `case` each way, by kind name |
| deep copy, undo restore | one `case` each; the table moves the rows |
| renderer | one `case`: look the renderer up, or the placeholder |
| inspector | one generic section laid out from the rows — number scrubs with the row's unit, range and dial; string types; boolean checks; choice picks |
| tree | one icon, and `open` reads any node's children rather than a frame's |
| motion | one `case`: the animatable rows become specs, hints included |
| props test | one line: a kind row's fresh node is a `KindNode` |

The compiler found every one of them — each was an exhaustiveness error
on the sealed hierarchy — which is the reason a single `KindNode` subtype is
the right shape: the switches gain one case each, not one per kind.

**What the 3D kinds cost on top:** the two descriptors (about 20 rows), two
constructors, two `animate()` signatures, and the renderer in the example's
`lib/scene3d_renderers.dart`. Nothing in the parser, the emitter, the wire,
the inspector or the timeline. `showcase3d.scene.dart` places a fox under a
view; `Showcase3DSpin` keys `yaw`, `distance` and `animationTime`;
`scene video` renders 73 frames.

**Two facts the spike surfaced:**

- **A node off the wire or out of JSON is the plain `KindNode`, never the
  typed subclass.** The typed class is for the compiled file and the motion
  signature. A renderer therefore reads rows by name — `fxRendered('yaw')`,
  composed with any track — exactly as an external reads its arguments. The
  first renderer filtered on `ModelNode` and drew nothing.
- **Row names are one namespace across kinds.** The frame's boolean `clip`
  collided with the model's clip name; the props test's uniqueness check
  caught it. The model's rows are `animation` and `animationTime`.

**What the spike did not do, deliberately:** rewrite the hand-written kinds
as descriptors (their `ScenePropOwner` enum stays, and `sceneProps` became a
getter that appends the registered kinds' rows), fold the motion side's
`ScenePropSpec` into the row for the old kinds (the hints exist on the row
now and only the registered kinds use them), and make the canvas tools
place a kind. Each is the obvious next step if the direction is taken.

**Recommendation to the scene branch:** take the descriptor. Move the five
kinds onto it one at a time, retire the owner enum and the second table,
and the master plan's slots and variants arrive as kinds rather than as
switch cases.

**Addendum 2026-09-06, from the surface:** the third kind cost one
descriptor, one constructor, one `animate()` and ~80 lines in the renderer.
The hosts did not change — parser, emitter, wire, JSON, copy, restore, tree
and inspector took the surface as they took the model. The one core change
was the renderer signature (§3.2), which any kind that shows a child needs
and no host has to know about.
