# 3D in a scene: the master plan

**Date:** 2026-09-07
**Status:** direction, agreed in conversation on 2026-09-06. Every milestone
still gets its own design before it is built. Nothing here is scheduled.
**Leans on:** `2026-09-05-scene-3d-view-design.md` (the probes, the node,
the kind descriptor, the surface — §1, §3, §9, §10 hold the measurements),
`2026-09-05-scene-master-plan.md` (the scene editor's own direction; this
plan rides on its M4 property table and adds one foundation to it).
**Branch:** `claude/scene-3d-rig-probe`, off the scene branch. Nothing here
is landed on master.

**The brief, in plain words:** a scene can hold 3D things that were modelled
elsewhere, and our tool places them, aims a camera at them, animates them on
the same timeline as everything else, and shows pieces of the scene on their
screens. Blender and our tool should be enough; nobody should need a third
editor.

---

## 1. What a user gets

A scene can contain a **3D window**: a rectangle on the artboard like any
other node, with a camera that orbits a point. Inside the window sit
**objects** modelled elsewhere — a phone, a laptop, a product, a mascot.
Each object has a place, a turn and a size. Every one of those numbers, and
the camera's, is a row like opacity: keyed on the timeline, scrubbed in the
inspector, exported in the video.

One kind of object has a **screen**. The modeller names a face; the designer
drops a piece of the scene on it — a frame, a nested scene, a live widget —
and it shows there, with its own motion, captured every frame. A phone, a
laptop, a billboard and a television are the same feature.

An object can carry **clips** from Blender — "Open", "Run" — and a clip is a
block on our timeline: dropped, moved, trimmed, stretched, looped.

Exported as video the way any scene is, or played in the app.

## 2. Who does what

**The modeller works in Blender**, and follows five rules the spec's §2
states: name the object, name the screen face, face it forward, keep the
standard texture layout, name the action. Blender's own glTF export does the
rest; the tool converts the file at build time.

**The designer works in our tool**: imports, places, aims, keys, exports. No
sculpting, no rigging.

**What our tool does not become:** a modeller. It will not sculpt, rig, or
edit a mesh. It *may* grow, later and as rows rather than as a mode: an
environment preset, a light or two on the window, a tint on a placement.
The argument "the engine has its own editor for that" is withdrawn; whether
a second editor exists is not a fact about our product. The boundary is
**Blender makes things, our tool arranges and animates them**, and what
"arranges" includes is allowed to widen.

## 3. What is already true — measured

Everything below ran on the export lane (flutter_tester, Metal) and is in
the tree.

- **Determinism holds.** A 3D frame is a function of the playhead. Forwards,
  backwards and repeated walks are byte-identical, with a live widget on a
  screen and a skinned model mid-clip. 12–15ms a 1080p frame warm.
- **The three kinds exist**, described as data: `View3DNode`, `ModelNode`,
  `SurfaceNode` (`lib/src/scene/core/view3d.dart`). Their rows are numbers
  and strings, so the file, the wire, the inspector and the timeline took
  them with no new code. The renderer lives in the example app
  (`examples/example/lib/scene3d_renderers.dart`), registered on the view.
- **A screen shows a piece of the scene**, live. The demo's phone shows a
  frame with a clock and a bar whose scale is keyed; the lid's clip is keyed
  beside it. A screen with no model is a floating quad.
- **A clip is on the timeline** — as a number track on `animationTime`. Not
  yet as a block.
- **The harness waits for what the engine loads** through a generic door
  (`RealWork.run`, master's own counter with a root-zone door added), and the guest's developer log reaches the tester's log.
- **Blender's export walks identically** to a hand-written file, and the
  Khronos Fox (textured, skinned, animated) walks through the same path.
- **The build-time asset path works** through flutterware's build hooks.

## 4. Blockers, hazards, and what is not a blocker

Nothing here stops the product. In order of weight:

1. **The canvas experience is untested.** Every result is a rendered frame.
   Dragging a 3D window, scrubbing the camera in the inspector, selecting a
   screen's content through the tree: all exist in code, none looked at in
   a running studio. First thing the plan does.
2. **Only macOS has run it.** Linux CI and Windows are untested for the
   engine. Flutter GPU is a preview API and may move. Both argue for what
   is already the shape: the engine sits in a package the core never
   imports, behind the renderer seam, and the core keeps working with a
   named placeholder when it is absent.
3. **Cold start is about two seconds** while the engine brings its shaders
   up, once per process. The harness waits for it; an app playing a scene
   on screen will see a pause once. Not fixable by us; worth stating.
4. **Two engine traps, both handled, both worth reporting upstream** (with
   Xavier's go-ahead): its one-time initialisation is memoised in the zone
   of the first caller, so a later caller must gate on the flag rather than
   await; and two loads of one asset share their materials, so a screen
   binds onto a cloned mesh with a material of its own.
5. **One undiagnosed:** the engine's *runtime* glTF import lands only in
   the first test body of a warm process. The build-time path has no such
   issue and is the product path; the runtime path is a convenience the
   plan does not depend on.
6. **A screen's content has no box on the canvas.** It lives in a texture.
   The tree is its door. A rule to state in the UI, not a problem to solve.

## 5. What the GUI has to gain

Less than it sounds. The inspector already draws every 3D row from the
property table; the tree already shows a window and its children; the
motion panel already keys any animatable row.

Missing, in the order a designer meets them:

- **Add.** Nothing creates a window, a model or a screen except editing the
  file. A tree action ("add a model", "add a screen") under a window, and
  "add a 3D window" on the canvas.
- **Pick.** `asset`, `mesh` and `animation` are typed names today. The
  asset should come from the project's model files; the mesh and the clip
  from what that asset carries. That needs the asset **inspected once** —
  its mesh names, its clips and their lengths — which is one small service
  in the daemon (read the glTF's tables; no engine needed) feeding three
  pickers and the timeline.
- **Orbit.** The camera is numbers. A drag on the 3D window that turns the
  camera, a wheel that dollies, both writing the same rows.
- **A clip is a block.** See §7.
- **State the rule.** A selected screen's content is edited in the tree;
  the canvas says so rather than staying silent.

Nothing else in the studio changes. The scene panel's list, the file
round-trip, the wire, the player and the video export all took the three
kinds as they were.

## 6. The foundation, and what it asks of the scene branch

The three kinds stand on one idea from the spec's §10: **a node kind is
data**. A kind names its rows, whether it holds children, and what the file
calls it; its renderer is registered on the view. Adding the surface — the
third kind — cost one descriptor, one constructor, one `animate()` signature
and ~80 lines of renderer. No parser, emitter, wire, JSON, copy, undo, tree
or inspector code changed.

The scene branch's own master plan built the property table (M4) that made
a *row* cheap. This makes a *kind* cheap, on top of it. The ask is one
decision:

- **If the scene branch takes the descriptor**, the 3D kinds ride along and
  the five hand-written kinds can move onto it one at a time, retiring the
  owner enum and the motion side's second table. The master plan's own
  slots and variants then arrive as kinds rather than as switch cases.
- **If it does not**, the 3D kinds need a hand-written case in each of about
  seven places, which is the price the text and shape kinds pay today. The
  feature still ships; it costs more and every later kind costs the same.

The recommendation is the first. The commits on this branch are the
proposal in code; §9 and §10 of the 3D spec are the reading.

## 7. Clips as blocks

A clip from Blender has a name and a length. Today a placement carries
which clip and the time inside it, and a motion keys the time as a number.
That is correct and stays the runtime truth. The block is the timeline's
view of it:

- **A block** on a model's row has the clip's own length. Drag to move its
  start; trim its ends; stretch to change speed; loop; reverse.
- **It lowers to what exists:** a straight ramp on `animationTime` from
  start to end with the speed as the slope; loop is a repeating ramp,
  reverse a falling one. The wire and the file gain one construct, a clip
  track beside the number track, and the timeline panel draws and drags it.
- **Two clips on one model** sit one after the other, or overlap to
  crossfade. Crossfade needs one more row per placement — the clip's
  weight, which the engine supports — and is the only part that touches
  the engine side.
- **The picker and the block both need the asset inspected** (§5), which is
  why that service comes first.

This is timeline work, not 3D work, and a designer will feel it more than
anything else in the plan.

## 8. Milestones

Each lands something usable. Names are working titles.

| # | Lands | Depends on |
| --- | --- | --- |
| **N0** | The direction decision with the scene branch (§6). Rebase on it either way. | — |
| **N1** | **Seen on the canvas.** A studio from this branch: drag a 3D window, scrub the camera, select a screen's content in the tree, hot-reload the guest. Every finding into the spec. **Done 2026-09-07** — see §10. | a studio instance |
| **N2** | **The referenced scene on a screen.** The demo's phone shows a `SceneRefNode`, the product case. One demo change and one look. **Done 2026-09-07** — see §11. | — |
| **N3** | **Asset inspection.** The daemon reads a model's mesh names, clip names and clip lengths. Surfaced as three pickers; a screen naming a missing mesh is refused with the list. **Done 2026-09-07** — see §12. | — |
| **N4** | **Add and orbit.** Tree actions for a model and a screen; a canvas action for a window; a drag on the window that orbits and a wheel that dollies, writing the rows. **Done 2026-09-07** — see §14. | N1 |
| **N5** | **Clips as blocks** (§7). Clip track in the model, wire and file; the block on the timeline; loop and reverse. **Done 2026-09-07** — see §15. | N3 |
| **N6** | **Crossfade.** Clip weight as a row; two blocks overlapping. **Done 2026-09-07** — see §16. | N5 |
| **N7** | **Looks.** Environment preset and exposure on the window, a light or two, a tint on a placement — as rows. Whatever the pictures ask for first. **Done 2026-09-07** — see §17. | N1 |
| **N8** | **Other platforms.** Linux CI runs the walk test; Windows tried once. **Steps added 2026-09-07, unverified until the branch runs CI** — see §18. | — |
| **N9** | **Upstream.** The two engine findings reported, once Xavier says so. | — |

N1 and N2 are days; N3–N5 are the body of the plan; N6–N9 are as needed.

## 9. Open

1. **Where the renderer package lives** once it leaves the example app: a
   separate pub package (`flutterware_scene3d`) the app depends on, or a
   flag on the main package. The seam is built; the packaging is not.
2. **The screen's content as a parameter.** The scene master plan defers
   slots to *a parameter whose value is content*. A surface's child is a
   first slot; when parameters grow to carry content, the surface should
   take one without changing shape. Not to be designed here.
3. **The window's own size versus the camera's lens.** Today the lens is a
   row and the window's box is the artboard's; a designer who resizes the
   window may expect the framing to hold. Decide at N1, from what it feels
   like.
4. **Tilt on every node** (`rotateX`/`rotateY` as imposed rows). Cheap,
   most of what "3D motion" means in a clip, and independent of the engine.
   Held only because it touches the effects plane the scene branch owns;
   goes in after N0.

## 10. N1, seen on the canvas — 2026-09-07

A studio from this branch, driven through the run plugin at 800×600, on
`showcase3d`. What held: the canvas drew the 3D window on the guest's first
mount, fox and phone at the resting pose; the tree showed the window, its
placements, the phone's screen and the screen's own children with the kind
icons; selecting the window put the table-driven rows in the inspector —
yaw and pitch with dials, distance and lens plain — and a drag on the yaw
field turned the camera in the guest, the phone coming round to face it and
the quad with it; the screen's clock selected from the tree with its own
text inspector and no box on the canvas, as designed; editing its text
pushed to the guest. Autosave wrote each edit to the file.

What did not hold, fixed the same day, both in the view rather than in 3D:

- **Every push remounted the 3D view.** Two causes, one after the other.
  The view keyed each node's box by the node object, and a push decodes a
  fresh document, so every subtree was recreated per edit; the renderer
  keyed its loaded assets the same way. Both now key by name. Then a
  selection change still remounted it: a selected node's Container gains a
  foreground decoration, which changes the Container's internal structure,
  and the same happens when an opacity drops below one or an imposed
  transform appears — so a fade would have reloaded a 3D view mid-motion.
  A second GlobalKey on the node's content lets Flutter move the element
  across the wrappers. Measured by a mount trace: the SceneView's state
  survived every push, the 3D view's did not until this.
- **There is no guest reload door for a renderer change.** The daemon
  recompiles the guest when a scene opens after a studio restart; three
  restarts were the cost of three renderer edits. A canvas-bar reload
  existed in an earlier pass and is not on this master. Worth restoring
  before N4.

Not tried at 800×600: dragging the window on the canvas (the pane was 241px
wide and the artboard at 24%), the orbit-by-mouse that N4 adds, and a
motion playing on the canvas. The window size is the drive layer's known
gap (no resize verb).

## 11. N2, a scene on a screen — 2026-09-07

`demo/phone_home.scene.dart` is a scene designed at phone size, and the
showcase's phone shows it: `screen = SceneRefNode(const PhoneHomeArgs())`
as the surface's child. The mechanism did not care, as §3.2 said; what did
not hold was upstream of it. **The player never instantiated a nested
scene.** A pair carries a reference as its class name and arguments, never
the child's document, and `ScenePlayerHost` drew the "no scene here"
placeholder for every reference — so a video export of any scene nesting
another was already wrong on master, 3D or not. The fix follows the
compiled path that already existed: the generated player entry now hands
the host a map of the group's scene classes to their generated arguments
classes (`nested: const {'PhoneHome': PhoneHomeArgs(), …}`), and the host
sets each reference's `declared` and syncs its instance, exactly as a
compiled parent does — so a motion's `args.*` writes reach the child too.
Only generated code may name a generated class, which is why the map is
generated rather than declared on the group.

## 12. N3, the asset read — 2026-09-07

`app/lib/src/scene/model_assets.dart` reads a `.glb` or `.gltf` on the
studio side with no engine: the JSON chunk's `nodes` that carry a mesh, by
the name the modeller gave the object (which is what the renderer finds
them by — the fox's one mesh node is `fox`, its mesh `fox1`), and the
`animations` with their lengths, the largest input time of their samplers
off the accessor's `max`, or off the buffer when an exporter wrote none.
Cached by path and modification time; the package's model files are
listed under `assets/` on every ask.

The rows say what they pick. `SceneProp.pick` is a new hint on the table —
`modelAsset`, `modelMesh`, `modelClip` — set on the three string rows of
the model and the surface, and the inspector's generic kind section draws
a picker for any row that carries one: the files with their paths, the
meshes, the clips with their lengths as the row's detail, and `none` /
`first mesh` for the empty value. A value the project does not have stays
pickable, since it is what the file says, flagged in red with what the
asset does carry. Seen in the studio: the phone's clip picker offers
`none` and `Open · 2.04 s`, its mesh picker `Screen`.

Two facts the read surfaced: the fox's `Run` clip is 1.16 s where the
showcase keys its time to 2.4 — and the engine's `seek` **clamps** at the
end, so the fox froze on its last pose for half the clip (Xavier noticed;
I had written "wraps" without checking). A `loop` row on the placement,
on by default, wraps the time in the renderer; N5's block makes the length
visible and loop a property of the block. And the hint is the first row property the core carries
for the editor's benefit alone — the file, the wire and the renderer
ignore it, which is the right division.

## 13. The loop, and a walk that was not repeatable — 2026-09-07

Xavier noticed the fox stopped running: the engine's `seek` clamps at the
clip's end, and the showcase keys 2.4 s onto a 1.16 s clip. A `loop` row
on the placement, on by default, wraps the time in the renderer.

Checking the fix across runs found worse: **the walk was not repeatable.**
Three runs of the static surface probe gave two with bare screens and one
textured; the showcase's mid frame lost the lower half of the phone's
screen in two runs of three. Every capture landed in every run, so the
rendered mesh was not the one bound. The cause was order: the surface
swapped the named mesh for a clone with its own material *after* the root
had joined the scene, and the scene sometimes drew the old one. The other
order failed differently — a capture component added to a node the scene
does not hold yet is never registered. So the two halves are split: the
mesh gets its material before the root joins the scene, the capture
component is added after. Three runs of the probe and two of the showcase
are now byte-identical, with both screens whole. The first capture of a
surface is also announced through `RealWork.track`, so a walk waits for it
rather than photographing the frame before it.

`showcase_export_test.dart` should walk twice and compare — the
determinism check the rig probe has and the showcase lacked. Left for the
next pass, with the plan's N8 (other platforms), where the same check is
the first thing to run.

## 14. N4, adding and orbiting — 2026-09-07

Two tools and two menu items, all writing the rows the inspector and the
guest already read:

- **The 3D window tool** (`3`) draws a `View3DNode` the way the frame tool
  draws a frame.
- **The orbit tool** (`O`): a drag on a 3D window turns its camera — half a
  degree per artboard pixel of yaw and pitch, pitch held short of the
  poles — and the wheel over it moves the camera in or out by a tenth per
  hundred pixels. Each drag is one undo entry. A plain drag with the
  select tool still moves the window, which is the canvas's law and the
  reason a modifier was not used: alt reparents, shift and cmd extend the
  selection, and a tool is what every editor of this kind reaches for.
- **Add a model / Add a screen** on the window's row in the tree, since a
  placement has no box on the artboard for the canvas to draw. A new
  screen comes with a plain quad and a yellow card on it, so it shows at
  once; the pickers then take over.
- A kind carries a `help` line, shown under its rows: how the window is
  worked on the canvas, which the rows alone do not say.

Seen live: the drag turned the guest's camera, the wheel moved it in, the
menu added a screen that appeared in the guest as a quad beside the phone.

Two findings on the way. The viewer reads the wheel directly, not through
the pointer signal resolver, so the dolly and the canvas zoom both fired
on one wheel until the canvas turned the viewer's zoom off while the orbit
tool hovers a window. And the toolbar's roomy threshold moved from 360 to
500 for the two extra tools; below it the bar already overflowed at 230
with four tools, which is a toolbar debt rather than a 3D one.

Open, as feel rather than function: the orbit rate is per artboard pixel,
so a window turns faster when the canvas is zoomed out. Screen pixels
would be the natural unit; the node target only knows artboard ones.

## 15. N5, the clip block — 2026-09-07

A placement's time track can carry one block instead of keys:
`MotionClip(at, length, speed, offset, reverse)` on `MotionTrack.clip`.
It evaluates as a ramp held at its ends — the clip's own time at that
moment, in seconds — so the runtime, the walk, the wire and the guest see
a value like any other track's; the placement's `loop` row wraps a time
past the clip's own end, which is where loop lives (§7 said the block; the
row already did it). The JSON carries the block; the file spells it
`animationTime: ClipTrack(at: 0.ms, length: 2400.ms)` with `speed:`,
`offset:` and `reverse:` when they are not the defaults. A track has keys
or a block: a key added to a block track replaces the block, a block put
on a key track replaces the keys, and an undo restores either.

On the timeline the block is a bar with the clip's name from the
placement's `animation` row and its length. A drag on its body moves it,
on either edge trims it; its menu plays it backwards, sets a speed, starts
the clip at the pointer, or deletes it. A block is born from a placement's
time lane menu, as long as the clip the asset says (N3's read), a second
when the asset does not say. The showcase's fox and phone are blocks.

Not done: two blocks on one track, and the crossfade between them — N6,
which needs a weight row on the placement and the engine's clip weights.

## 16. N6, the crossfade — 2026-09-07

A track carries a list of blocks, sorted by start, and each block names
its clip (`clip: 'Walk'`; empty means the placement's own `animation`
row). Where two blocks overlap, the earlier leads and the later comes in:
the runtime's `blendAt(t)` answers both clips, both times and a `blend`
running 0 to 1 from the later's start to the earlier's end. Between blocks
the last to end holds its end; before the first, the first holds its
start.

The placement gained three rows for it — `animation2`, `animationTime2`,
`blend` — and the bound group writes all five (`animation` too, when the
block names one) instead of the one number a key track writes. The
renderer keeps two engine clips, seeks both and weights them `1 − blend`
and `blend`; the engine mixes. The file spells one block `ClipTrack(clip:
'Run', at:, length:)` and several `ClipBlocks([ClipBlock(…), …])`; the
JSON carries the list.

On the timeline every block is its own bar, hit by edge first then body,
the later block on top; the menu of a block reverses it, sets its speed,
starts its clip at the pointer, switches it to another clip of the asset,
adds another block, or deletes it — the last block takes the track. The
showcase's fox walks, then runs, crossfading over 300ms.

Not measured: how the mix looks mid-fade. The walk renders it without
error and the runtime's numbers are tested; the picture of a half-walk
half-run is a thing to look at in the studio rather than assert.

## 17. N7, looks — 2026-09-07

Six rows, all animatable. On the window: `ambient` scales the engine's own
studio environment, which is what lights a model with nothing else said;
`light`, `lightYaw`, `lightPitch` and `lightColor` are a sun — a
directional light on a node the renderer turns, in the scene only while
its intensity is above zero. On a placement: `tint`, a colour multiplied
into every material of the asset. White costs nothing; the first other
colour gives the placement its own materials, copied from the asset's
with the fields a tint has to keep, since the asset's materials are shared
between its loads. The surface's own screen material is tinted in place —
a copy made before its texture was bound showed a flat colour, which is
how that rule was learnt. The showcase has a sun and a pink tint on the
floating card.

Two things found on the way, neither about looks:

- **The phone's screen dimmed face-on and not at ±70°.** Not lighting (the
  drawn material is the surface's own unlit one, checked) and not the
  capture: depth. The engine's camera runs 0.1 to 1000, and a screen 1.8
  units in front of its body, seen from 260 units away, lost the depth
  fight to the body exactly when the view was square-on. The renderer now
  sets the near plane at a hundredth of the camera's distance and the far
  at twenty times it. The dimming had been there since N3 and no test
  looked; §13's determinism check would not have caught it either, since
  it was the same wrong picture every time.
- **A fox standing up mid-run is a gallop phase, not a bug.** Half a day
  of suspicion — clip swapping, clip pools, bind-pose capture — ended with
  a single clip offset to the same moment giving the same pose. Every
  engine clip of an asset is now registered once, at load, at the rest
  pose, and driven by weight; nothing is ever removed. That is the right
  shape for the crossfade anyway.

## 18. N8, other platforms — 2026-09-07

The Linux and Windows jobs already render every preview entry of the
example through `previews audit`, and that includes the 3D probes (a
widget on a box, the rig, the fox) and the scene guest entries — so
flutter_scene's shaders and the example's build hook run there on every
push. What they did not run is a walk: the audit renders stills. Both jobs
now also run `showcase_export_test.dart` (the three scene walks: the
external-widget showcase, the 3D showcase with its crossfade, the surface
probe) and `phone_rig_probe_test.dart` (the repeat-and-backwards
determinism check) from the app package.

Measured here first: the audit passes on macOS with the 3D entries in it,
20 entries, none broken. The new steps are unverified until the branch is
pushed — nothing on this branch has run CI yet, and the last change to
those jobs recorded that Windows previews had been silently broken for
weeks, so the first run is the test. What to expect if it fails: the
tester's Impeller flags on Windows, or the example's `hook/build.dart`
(flutter_scene's build-time conversion) not running under the tester on a
runner.

## 19. The block becomes a thing you select — 2026-09-07

Using N5/N6 as a designer rather than as its author raised five questions
in a row: why speed came in three presets, what "Another block: Walk here"
meant, why a block showed nothing when clicked, what "lid" was, what
"Start the clip here" did. One defect underneath them all: a block was not
selectable, so its five facts lived in a right-click menu, and a menu can
neither show a number nor take one.

Built:

- **A block is selected the way a key is.** `MotionClip` carries a
  runtime `id` (the same reason `MotionKey` does: a drag re-sorts the list
  and an undo restores into copies), `MotionClipRef` names one, the editor
  holds `selectedClip` in the same domain as the key selection — a node
  selection ends it, it ends the node selection, Backspace deletes
  whichever is selected. A new block is born selected.
- **The inspector has a Block section**: clip picker (the asset's clips,
  plus "whatever the animation row names"), Start, Length, Speed as a
  number, "Skip the first … ms" for the offset, a Play backwards check,
  Delete. A caption says how much of the clip the block plays at that
  speed. `setClip` took `at`/`length` and holds every field at its limit
  instead of refusing, because a field being typed into passes through
  zero on its way to a number.
- **The menus shrank.** Block: Play backwards · Add <clip> block here ·
  Delete this block · Delete <group>. Lane: Add <clip> block here — one
  name for the one action, whether or not the click landed on a block.
  The speed presets and the trim item are gone.
- The demo's groups are `foxGait` and `phoneOpen`; `run` and `lid` were
  names only their author could read.

Not built: a drag that slips the clip inside a fixed block (offset by
drag). The field covers it; a modifier-drag would be the next step if it
is missed.

## 20. Landing: replayed onto master — 2026-09-09

Master moved six commits while this branch ran, three of them rewriting
the same scene files (rich text and one key space, variable font axes,
the render package fold). A commit-by-commit rebase would have hit those
regions thirty times over, each intermediate state untestable, so the
branch was squashed and replayed onto master instead: twelve conflicts,
resolved once against the final state, where the suites can judge them.
The pre-replay history is kept as the tag `pre-rebase-3d`.

What the replay had to reconcile:

- **The same bug, found twice.** Both sides discovered that a guest
  spawned from under a `flutter test` inherits `UNIT_TEST_ASSETS` and
  answers every asset read from the outer package's bundle. Master's fix
  was already complete; this branch's was dropped.
- **Text moved into a style.** `fontSize`, `weight` and `color` are no
  longer TextNode arguments, so this branch's four scene files were
  migrated into `style: SceneTextStyle(...)`.
- **One key space.** A group's `args` map is gone; an argument track is
  filed in `tracks` under its own `args.` key, which is one line in the
  clip-block door.
- **The property table met the kind table.** Master's `resolveSceneKey`
  walk already reaches a registered kind's rows through `appliesTo`, so
  the branch's separate lookup in `animatableBase` was dropped for it.

One test had to change, and it is worth stating why rather than burying
it. `compiler_daemon_test` asserted that the published kernel is bigger
than the seed it grew from — "the seed plus this checkout". A seed is
shared across the workspace's members, and this branch gives one member a
3D engine, so the seed a compile of THAT member writes is larger than the
studio catalog's whole program while still being a valid seed for it.
Measured here: program 101,990,888 bytes, seed 102,858,320. The published
kernel was a real program either way; what the test is actually guarding
against is the kernel BEING the seed, byte for byte, so that is what it
now checks, plus a floor.
