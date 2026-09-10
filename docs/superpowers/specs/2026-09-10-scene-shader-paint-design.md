# Scene shader paint — design, from the spike

Status: implemented 2026-09-10 on `claude/scene-shader-spike`, by
`docs/superpowers/plans/2026-09-10-scene-shader-paint.md`. The spike's
measurements below are unchanged; the decisions read as built, with what the
plan corrected and what building it found folded in. It answers the five
questions left open by Phase 3 of
`docs/superpowers/plans/2026-09-10-scene-text-layer-gradients.md`, each by
measurement, then decides the shape. `examples/example` carries the result: a
foil headline, `demo/foil_title.scene.dart`, painted by `shaders/foil.frag`.

## The goal

A text pass can be painted with a project's own fragment shader —
`ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': [0.4], 'uTint': [1, 0.8, 0.2]})`
— as one more `ScenePaint`, so a shader composes with everything a pass
already has: strokes, blur, offset, `box: SceneLayerBox.line`, blend, stacking.
The inspector draws real controls for its uniforms, the editor scrubs it with
the playhead, and a reel renders the same frame twice.

## What the spike measured

Pinned SDK 3.48.0-0.2.pre, macOS. The spike code was never committed: it
lived under `examples/example` (`shaders/spike_foil*.frag`,
`demo/spike_shader_*.dart`, `test/spike_*_test.dart`) and was deleted when the
example scene replaced it.

### 1. A foreground shader renders text on every engine — but no flutterware lane can load one

Glyph-clipped shader text rendered correctly on the previews harness
(`flutter_tester --enable-impeller --impeller-backend=metal`), the previews
guest (embedder, Impeller/Metal), plain `flutter test` (Skia, and Impeller with
`--enable-impeller`) and a macOS app under `flutter run`. Harness and guest
output matched.

**But every flutterware lane failed first with `Asset 'shaders/spike_foil.frag'
not found`.** `AssetBundleBuilder` (`app/lib/src/previews/asset_bundle.dart`)
compiles and links only the framework's two shaders (`frameworkShaderSources`:
ink_sparkle, stretch_effect); `AssetCatalog` has no notion of `flutter:
shaders:` at all. The same builder feeds the harness (`TesterHost`: previews,
scenarios, scene video, store frames, comparison), the compiler daemon
(previews guest, the GUI panel, **the scene editor canvas**) and the render
bundle. With the same bytes precompiled into a plain asset, both lanes rendered
correctly. So today **a user's own `shaders:` entry is broken in every
flutterware lane**, scenes or not — a bug in its own right.

Also measured:
- `FlutterFragCoord()` in a paint shader is local to the canvas transform but
  **includes a paragraph's paint offset**: text drawn at `Offset(160, 0)` sees
  x from 160, text drawn after `canvas.translate(160, 0)` sees x from 0. Units
  are logical pixels at any dpr.
- An undeclared uniform name throws `ArgumentError: No uniform named …` from
  `getUniformX(name)`; a declared-but-unused uniform survives compilation.
- `FragmentProgram.fromAsset` is a microtask around a synchronous native load,
  cached per isolate by asset key: 17–50ms on every lane.
- `ImageFilter.shader` works on Impeller lanes and **throws under default
  `flutter test`** (Skia); its coordinates and the engine-written `uSize` are
  in *physical* pixels.

### 2. A `.frag` edit reaches a live process only through `reinitializeShader`

Fresh processes (every MCP `previews screenshot`, scene video, scenarios) pick
up new bytes on the next run: 5.3s harness, 9.2s guest. A process kept alive
does not: `dart:ui` caches programs by key for the life of the isolate, and new
bytes on disk stayed invisible for over 60s. `ext.ui.window.reinitializeShader
{assetKey}` swapped the program in **26–122ms**, existing `FragmentShader`s
included — exactly what `flutter run`'s `r` does for `shaders:` entries
(244–280ms end to end). flutterware's live guests (GUI previews panel, scene
editor canvas) never call it: on an asset change they only evict
`AssetManifest.bin`. A full app rebuild measured 16.9s.

### 3. Where each capture waits

- **flutter_tester lanes** (previews harness, scene video, scenarios, reels)
  all settle through `landRealWork`/`RealWorkBudget`
  (`lib/src/scenarios/real_work.dart`), which polls the image cache, asset
  reads in flight, and the public `RealWork.pending`. A program load wrapped in
  `RealWork.track` is waited on there with no new plumbing.
- **The scene editor guest** has no such wait. `SceneCanvasHost._apply`
  (`lib/src/scene/host.dart`) waits one forced frame; the picture path
  (`EmbeddedEngine`/`FrameCapture`) grabs the next composited frame; the scene
  plugin registers no `SettleSource`, so `fw capture`/drive `observe` do not
  wait either.
- **Plain `flutter test`** has no hook: `pumpAndSettle` never reads
  `RealWork.pending`. A consumer must load the program before pumping.

### 4. How scene time reaches a text pass — and why the obvious way fails

Nothing carries scene time to rendering today: `Playable.apply(t)` is
stateless, `MotionPlayer` keeps `_position` to itself, the walk's
`_ScenePlayhead.seek` drops it, and the editor canvas holds no `Playable` at
all — it receives a pre-composed picture over `ext.fw.scene.apply` with no
time field, while `editor.playhead` stays in the studio.

The obvious way to animate a shader — keep one `FragmentShader`, change
`uTime` each frame, repaint the cached paragraph — **does not work, measured on
Skia and Impeller**: a paragraph snapshots its foreground shader's uniforms
when it is built. Changing the shader after layout left the painted glyphs on
the old value; only a fresh paragraph (a relayout) showed the new one. The
**mask path** does work: glyph coverage painted from the cached layout into a
layer, the shader drawn over it in a `drawRect` with `BlendMode.srcIn`, issued
fresh each paint — the change showed on the next paint. And a `drawRect`
snapshots uniforms at the call, so one `FragmentShader` per program can serve
every pass if each pass sets its uniforms just before its draw.

### 5. The studio can list uniforms from the compiler

`impellerc --reflection-json=<file>`, added to the compile flutterware already
runs, lists every uniform with its name, `vec_size` (1–4) and a `location`
that is declaration order; samplers come separately. It costs nothing
measurable (65ms with, 80ms without, on a 5-uniform shader) and it is the same
data `FragmentProgram._uniformInfo` reads natively from the compiled `.iplr`
flatbuffer. Comments are stripped before reflection, so UI meaning that a
shader cannot express — a range, "this vec4 is a colour" — can ride as
comments on the uniform's line without disturbing anything.

## Decisions

1. **Bundle user shaders first.** `AssetBundleBuilder` compiles each package's
   `flutter: shaders:` with `impellerc` over flutterware's stage union (gles,
   gles3, vulkan, metal), links each under its declared key, and caches by
   content (source, resolved includes, engine revision, stages). The same step
   writes `--reflection-json` beside it. This alone fixes user shaders in every
   flutterware lane and is worth landing even with no scene work. A shader
   that does not compile is left out of the bundle, reported once per
   content, and not recompiled until its content changes; a compile whose
   source changed underneath it is not filed under the old content. A live
   guest that already holds the program goes on drawing the last good one
   until the file compiles again — `dart:ui` keeps what it loaded — while the
   inspector shows impellerc's error and every fresh process draws the pass
   blank.

2. **The value.** `ShaderPaint(String asset, {Map<String, List<double>>
   uniforms})` in the pure core, a `ScenePaint` beside `SolidPaint` and
   `SceneGradient`. The file spells every value as a list, a float's too:
   `ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': [0.4], 'uTint': [1, 0.8, 0.2]})`.
   *Corrected while building the example:* this said a float was spelled
   bare, which is not Dart — a scene file compiles, since its group's
   generated arguments file builds the class, and `{'uAngle': 0.4}` is no
   `Map<String, List<double>>`. The grammar refuses a bare number, saying so.
   The wire: `{'k': 'shader', 'asset': …, 'u': {name: [floats]}}`, total like
   every other decoder. A sampler uniform is out of scope for v1.

3. **A shader pass always takes the mask path.** Glyph coverage in opaque
   black, painted from the cached layout inside a `saveLayer` bounded by the
   pass's margin; the shader drawn over it with `srcIn`. Because a paragraph
   freezes its shader, this is the only way a uniform — `uTime` above all —
   changes without a relayout. For `box: text` there is one rect; for `box:
   line` one band per line, exactly as gradients do. The layer's paint carries
   the pass's blend and its opacity. Cost: one offscreen per shader pass, the
   same price a per-line gradient already pays. Vector export needs nothing
   new: a layer holding an `srcIn` draw already exports as one raster patch.
   Nothing about a uniform is cached across a reload: `reinitializeShader`
   zeroes every uniform of a live shader, so the painter sets all of them on
   every paint and `LayeredText` drops its shader slots on reassemble.

4. **Coordinates by transform, not by uniform.** Before drawing a rect or a
   band the painter translates to that box's top-left and draws at zero, so
   `FlutterFragCoord()` runs over `[0, uSize]` in logical pixels on every
   engine. No `uOrigin` for authors to remember.

5. **Three uniforms the renderer owns**, each set only when the shader
   declares it with the right type: `uSize` (vec2, the box's logical size: the
   whole text, or one line), `uColor` (vec4, the text's own colour, straight
   RGBA 0–1), `uTime` (float, scene seconds). The renderer probes each name
   once per draw slot (see decision 6: a slot is a pass × line) and caches
   the answer. A user uniform the shader does not declare is skipped and
   reported, never thrown in `paint`.

6. **Programs load once per process and paint nothing until they have.**
   A program cache in `lib/src/scene/` (it needs `dart:ui`, so not the core)
   loads by asset path and exposes a `Listenable` the text painter repaints
   on when a load lands. Loads run in the root zone through `RealWork.run`, so
   every flutter_tester lane waits for them — not `RealWork.track`, because
   the cache outlives any one scenario, and a load first asked for inside a
   FakeAsync zone that has since finished would otherwise never land. A
   failed load is forgotten on reassemble, so a shader first seen broken is
   asked for again once it is fixed. Before a load lands, a shader pass draws
   nothing: a blank pass is an honest "not yet", where a stand-in colour is a
   wrong frame that looks right.

   **`FragmentShader`s are pooled per draw slot — pass × line — not shared
   per program.** On a real canvas one shader per program would do: a
   `drawRect` snapshots the uniforms at the call (measured). But the vector
   capture (`lib/src/render/capture.dart`) keeps each draw's `Paint` — and the
   live shader object in it — and replays it later to rasterize the layer
   patch. A shared shader would replay every draw with whatever uniforms were
   set last; per-line bands set a different `uSize` within one pass. A slot
   pool, reused across frames, gives each draw its own object. The painter
   step pins this with a capture test.

7. **Scene time is a clock the painter listens to.** `Playable` keeps its
   position in a `SceneValue<Duration> clock` (and `position` reads it);
   `SceneView` and `LayeredText` take a `ValueListenable<Duration>? time`,
   the view defaulting to its motion's clock; and the stack painter lists
   that clock in its repaint listenable **only when the stack holds a shader
   pass**, so text without one never repaints for time. *Corrected by the
   plan:* this first said a value `shouldRepaint` compares, but a seek that
   changes no track writes no fx, the scene never notifies, and a value
   handed down at build would stay where it was — a motion that animates
   nothing but `uTime` would never move. Time stays out of the layout cache
   key. When nothing plays, time is 0: a stop that returns the scene to its
   authored values also returns the clock to zero, and the studio's playhead
   is zero when no motion is open. Scene reels and scene video hand the
   stage's motion clock to the view. The editor canvas, which has no
   `Playable`, gets `time` as a wire field from `editor.playhead`, and a
   document that paints with a shader is pushed when only the playhead
   moved.

8. **The editor waits for programs and reloads shaders in place.**
   `SceneCanvasHost._apply` awaits pending program loads (bounded) before it
   answers; the scene plugin registers a `SettleSource` that is busy while any
   load is pending, so `fw capture` and drive `observe` wait. When a `.frag`
   changes, the daemon recompiles it, relinks it, and every live guest session
   calls `ext.ui.window.reinitializeShader` for that key beside the manifest
   eviction it already does — a reload in ~0.1s, not a 7–9s restart. *As
   built,* the editor settles by the reply rather than by polling the guest:
   `ext.fw.scene.apply` answers with `pendingShaders`, naming only the
   scene's own assets, and the studio is busy while a push is out, until the
   host first answers, or while the last reply named pending programs,
   re-pushing every 250ms while any are. The daemon has no watcher of its
   own — it rebuilds the bundle only when a client asks it something — so
   the scene editor asks once a second while a shader paints the open
   document. Measured driving the studio: a saved `.frag` is on the canvas in
   about 1.5s, with the guest not restarted.

9. **Uniform controls come from reflection plus annotations.** The studio reads
   the reflection JSON the bundle step wrote: names, sizes, declaration order.
   A comment on the uniform's line adds meaning: `// @range 0 6.283`,
   `// @color`, `// @default 0.4`. The inspector hides the three renderer
   uniforms (by name and type), draws a slider for a ranged float, a colour
   field for a `@color` vec4, number fields otherwise, and offers the
   project's declared `shaders:` in the asset picker. A CI test pins that the
   reflection JSON still carries the fields read, on the pinned SDK. The
   inspector shows what renders: a uniform the file does not set reads 0,
   which is what the shader gets, and `@default` is written into the file when
   a shader is picked. Every declared shader is compiled in the background
   when the package's view is made, so the defaults are there by the first
   pick, and a view somebody is looking at re-stats its files once a second,
   so a save, a break and its fix reach the panel on their own. The renderer's
   names — `uSize`, `uColor`, `uTime` — are never editable, at any size.

10. **Plain `flutter test` gets an explicit door.** A public
    `precacheSceneShaders(scene)` loads every program a scene uses; a
    consumer's test loads them before pumping. In a `testWidgets` that is
    `await tester.runAsync(() => precacheSceneShaders(scene));` — awaited
    directly, the load never lands under the fake clock and the test hangs;
    a plain `test()` awaits it directly. The docs say so, because that lane
    has no report to catch a blank pass.

11. **Deferred:** `ImageFilter.shader` (the glyph-reading filter kind) — it
    throws under default `flutter test` and speaks physical pixels; sampler
    uniforms; web.

## Build order

1. **User shaders in the flutterware bundle** — compile `flutter: shaders:`
   with reflection, cache, link. Tests: a package with a `.frag` renders in
   the harness and the guest; the reflection file lands beside it.
2. **Live reload of an edited shader** — daemon recompile on change,
   `reinitializeShader` in every live guest session.
3. **The value** — `ShaderPaint` in the core, wire, file grammar, props-test
   sample.
4. **The program cache** — load, `RealWork.run`, `Listenable`, name probe,
   the per-slot shader pool; `precacheSceneShaders`.
5. **The painter** — mask path for shader passes, coordinates by transform,
   renderer-owned uniforms, nothing painted until loaded. Pixel tests on both
   engines, including a time change with no relayout, and a `captureSvg` of a
   two-line shader pass whose bands differ.
6. **Scene time** — `Playable.position`, `SceneView.time`, `LayeredText.time`,
   the editor's wire field; repaint only where a shader pass exists.
7. **The editor waits** — `_apply` awaits loads, scene plugin `SettleSource`.
8. **The inspector** — Shader kind in the paint picker, asset picker over
   declared shaders, uniform controls from reflection and annotations.
9. **An example shader** in `examples/example` with a scene using it, and the
   spike files removed.

## Risks

- **Editor playback cadence.** The editor canvas gets time at the wire push's
  pace, so a shader may step while other motion looks smooth during editor
  playback. Harness lanes apply time in-process. *Measured* 2026-09-10 on the
  foil example, in a studio window the drive had to force frames for: a
  round trip is 5–75ms idle and 100–250ms during playback, and the canvas
  took a new frame every 100–250ms. Every canvas change rides the same push —
  the opacity track as much as `uTime`, since the guest is the only renderer —
  so the shader steps no more than the other motion does: the editor canvas
  as a whole moves at the push's pace. A visible window at 60Hz was not
  measured. If that reads badly, the guest can still run its own clock
  between pushes.
- **Reflection JSON is tooling output, not API.** Pinned by a CI test; a
  missing field degrades the inspector to raw name-and-number fields, never
  crashes it.
- **The compiler daemon served a stale kernel** for a newly added preview file
  after edits (first sighting taken as the baseline). Unrelated to shaders but
  it will bite a shader-authoring loop that also edits Dart; filed separately.
- Not measured: web, Linux and Windows lanes (the union bundle carries Vulkan
  and GLES stages, so they are expected to load).
