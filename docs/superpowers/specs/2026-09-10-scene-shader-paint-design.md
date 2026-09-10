# Scene shader paint — design, from the spike

Status: spike done 2026-09-10 on `claude/scene-shader-spike`; this document is
its output and the input to the implementation plan. It answers the five
questions left open by Phase 3 of
`docs/superpowers/plans/2026-09-10-scene-text-layer-gradients.md`, each by
measurement, then decides the shape.

## The goal

A text pass can be painted with a project's own fragment shader —
`ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.4, 'uTint': [1, 0.8, 0.2]})`
— as one more `ScenePaint`, so a shader composes with everything a pass
already has: strokes, blur, offset, `box: SceneLayerBox.line`, blend, stacking.
The inspector draws real controls for its uniforms, the editor scrubs it with
the playhead, and a reel renders the same frame twice.

## What the spike measured

Pinned SDK 3.48.0-0.2.pre, macOS. Spike code is uncommitted under
`examples/example` (`shaders/spike_foil*.frag`, `demo/spike_shader_*.dart`,
`test/spike_*_test.dart`).

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
   flutterware lane and is worth landing even with no scene work.

2. **The value.** `ShaderPaint(String asset, {Map<String, List<double>>
   uniforms})` in the pure core, a `ScenePaint` beside `SolidPaint` and
   `SceneGradient`. The file spells a float bare and a vector as a list:
   `ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.4, 'uTint': [1, 0.8, 0.2]})`.
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

4. **Coordinates by transform, not by uniform.** Before drawing a rect or a
   band the painter translates to that box's top-left and draws at zero, so
   `FlutterFragCoord()` runs over `[0, uSize]` in logical pixels on every
   engine. No `uOrigin` for authors to remember.

5. **Three uniforms the renderer owns**, each set only when the shader
   declares it with the right type: `uSize` (vec2, the box's logical size: the
   whole text, or one line), `uColor` (vec4, the text's own colour, straight
   RGBA 0–1), `uTime` (float, scene seconds). The renderer probes a program's
   names once and caches the answer. A user uniform the shader does not declare
   is skipped and reported, never thrown in `paint`.

6. **Programs load once per process and paint nothing until they have.**
   A program cache in `lib/src/scene/` (it needs `dart:ui`, so not the core)
   loads by asset path, wraps each load in `RealWork.track` so every
   flutter_tester lane waits for it, and exposes a `Listenable` the text
   painter repaints on when a load lands. Before that, a shader pass draws
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

7. **Scene time is an input.** `Playable` records the `position` it was last
   applied at; `SceneView` reads `motion?.position`, or an explicit `time`
   when given, and hands scene seconds to `LayeredText`. Time stays out of the
   layout cache key; `shouldRepaint` compares it only when the stack holds a
   shader pass, so text without one never repaints for time. The editor canvas,
   which has no `Playable`, gets `time` as a new wire field from
   `editor.playhead`. When nothing plays, time is 0 everywhere.

8. **The editor waits for programs and reloads shaders in place.**
   `SceneCanvasHost._apply` awaits pending program loads (bounded) before it
   answers; the scene plugin registers a `SettleSource` that is busy while any
   load is pending, so `fw capture` and drive `observe` wait. When a `.frag`
   changes, the daemon recompiles it, relinks it, and every live guest session
   calls `ext.ui.window.reinitializeShader` for that key beside the manifest
   eviction it already does — a reload in ~0.1s, not a 7–9s restart.

9. **Uniform controls come from reflection plus annotations.** The studio reads
   the reflection JSON the bundle step wrote: names, sizes, declaration order.
   A comment on the uniform's line adds meaning: `// @range 0 6.283`,
   `// @color`, `// @default 0.4`. The inspector hides the three renderer
   uniforms (by name and type), draws a slider for a ranged float, a colour
   field for a `@color` vec4, number fields otherwise, and offers the
   project's declared `shaders:` in the asset picker. A CI test pins that the
   reflection JSON still carries the fields read, on the pinned SDK.

10. **Plain `flutter test` gets an explicit door.** A public
    `precacheSceneShaders(scene)` loads every program a scene uses; a
    consumer's test awaits it before pumping. The docs say so, because that
    lane has no report to catch a blank pass.

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
4. **The program cache** — load, `RealWork.track`, `Listenable`, name probe,
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
  pace (10–300ms a round trip), so a shader may step while other motion looks
  smooth during editor playback. Harness lanes apply time in-process. Measure
  once built; if it reads badly, the guest can run its own clock between pushes.
- **Reflection JSON is tooling output, not API.** Pinned by a CI test; a
  missing field degrades the inspector to raw name-and-number fields, never
  crashes it.
- **The compiler daemon served a stale kernel** for a newly added preview file
  after edits (first sighting taken as the baseline). Unrelated to shaders but
  it will bite a shader-authoring loop that also edits Dart; filed separately.
- Not measured: web, Linux and Windows lanes (the union bundle carries Vulkan
  and GLES stages, so they are expected to load).
