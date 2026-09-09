# Store assets from scenes — two worked examples, and what a local launch kit would still need

*2026-09-09. Branch `claude/scene-editor-examples-proposal-fc819f`.*

Two examples were built and run end to end: a **store banner** and a **store
video**, both drawn from one authored scene, both filled at render time with a
locale's copy and that locale's real app screenshots, shown on a 3D phone.
Everything below the "Built" heading was measured on this machine rather than
argued from the design.

The second half is the answer to the question behind the examples: *how far is
this from a local tool that does what applaunchflow.com does*. Short version —
**the asset-production half is structurally complete and the gaps are small and
countable; the ASO/monitoring/publishing half is not a local tool at all.**

---

## 1. Built

### 1.1 One scene, three parameters, two outputs

`examples/example/demo/store_hero.scene.dart` is an ordinary scene: a frame at
1024×500 (exactly Google Play's feature graphic), a copy column on the left, a
`View3DNode` on the right holding two `SurfaceNode` phones. Its class header is
where the injection happens:

```dart
class StoreHero({
  final String headline = 'Your coffee,\nready before you are',
  final String subtitle = 'Order ahead. Skip the line. Earn rewards.',
  final String cta = 'Get the app',
  final String shotFront = '',
  final String shotBack = '',
  final SceneTokens tokens = const SceneTokens(),
}) extends SceneDefinition { … }
```

The defaults are the mockup — what the editor's canvas shows while you place
things. A caller answers them, and nothing in the file knows there is more than
one locale.

The screenshot reaches the phone the same way. A scene carries **data**, so
what it can hold is a path; turning a path into pixels is the app's job, which
is what makes it an external widget rather than a node kind:

```dart
// demo/scenes.dart
ExternalWidget('Shot', args: [const Arg<String>('path', '')],
  build: (a) => shots.ShotImage(a.text('path') ?? '')),

// store_hero.scene.dart
late final frontPixels = ExternalNode(ShotArgs(path: shotFront), …);
late final phoneFront = SurfaceNode(
  asset: 'assets/models/phone.glb', mesh: 'Screen', …,
  children: [frontPixels],
);
```

`ShotArgs(path: shotFront)` is a parameter reference — the parser records a
`ParamRef` on the node — so the *same* binding is what the compiled Dart
passes, what the editor shows, and what the export overrides.

### 1.2 The still

`demo/store_hero_preview.dart` is a `@Preview` entry with three knobs. It asks
`lib/store_hero.dart` for the words (the project's `store` translation catalog,
the one the Translations panel shows) and for the pixels (whatever
`store export` last wrote under `unframed/`), and hands the scene five strings.

```bash
fvm dart run flutterware previews screenshot \
  --entry='demo/store_hero_preview.dart#storeHero' \
  --knobs=locale=fr --width=1024 --height=500
```

That is one PNG, 1024×500, French copy, French screenshots — one call on the
warm harness. Swap `locale=en` and it is the English one. No template format, no compositor: it is
the app drawing itself.

### 1.3 The video

The same scene, walked by `StoreHeroReveal` — a motion whose every row is a row
the inspector shows and the timeline keys: the camera's `yaw` and `distance` on
the 3D window, `positionY` and `rotationY` on each phone, `opacity` and
`translateY` on the type.

```bash
cd app && fvm dart run tool/drive_spike/step.dart scene/video '{
  "scene": "StoreHero", "fps": 30,
  "args": {"headline": "Votre café,\nprêt avant vous", "…": "…",
           "shotFront": "…/fr-FR/01-welcome.png"}}'
```

97 frames, 3.23 s of clip, 1024×500, a little under five minutes of wall
clock (the 3D window is re-rendered per frame; §4 of the motion-video note
says the cost is materialising pixels, not encoding them). The camera lands on exactly
the still's framing, so the last frame of the clip *is* the banner — one
authored composition, an animated version and a static version that agree by
construction rather than by somebody keeping them in step.

Nothing in the model file moves. The phone carries no clip on purpose: the
motion lives in one place, and that place is the timeline.

### 1.4 In the editor

Opened in the studio (`fw:///…/flutterware.scene/examples%2Fexample/demo/
store_hero.scene.dart`) the scene is an ordinary document: the tree carries
`glow / stage / phoneBack / backPixels / phoneFront / frontPixels / copy /
title / sub / ctaBox / ctaLabel`, the outline lists **5 parameters** each with
its one reader, one motion at 3.20 s, and the canvas draws the whole thing —
3D phones, real screenshots and all — at guest scale.

The screenshots are there while you place things because the scene's mockup
defaults are a committed *relative* path into the export tree, and `ShotImage`
resolves a relative path against the package. An export hands in an absolute
one. That is the whole of the difference between authoring and rendering: the
same scene, the same binding, a different string.

One thing to know while iterating: the canvas is drawn by a **guest process**,
so a change to a widget the scene places (`ShotImage`, a renderer) needs a
studio restart — a hot reload updates the studio and leaves the guest on the
old code, which looks exactly like the change not working.

### 1.5 The phone

`examples/example/tool/make_phone_blender.py` builds
`assets/models/phone.glb` (47 kB) headless in Blender: a bevelled body, a
camera bump with two lenses, side buttons, and a `Screen` plane at 19.5:9 with
Blender's default UVs — the convention the spec writes down and the walk tests
hold, and the only reason a bound screenshot is not upside down.

**On downloading one instead.** A downloaded glb drops in by changing the
`asset:` row and picking the mesh from the inspector's list — `N3` already
reads mesh and clip names out of the file. It was not done here for two
reasons: the licence of a free phone model is usually the interesting part
(most "free iPhone" models are trademark problems, not licence problems), and a
mesh whose UVs we do not control is the trap that cost an hour on the first 3D
probe. Building it means we own the licence and the UVs. If you want a specific
downloaded model, say which and it is a one-row change.

---

## 2. Four things the examples found


Each was fixed on this branch.

**(a) A `\n` in a scene parameter's default made the tool unusable.**
Three places emit a Dart string literal and only one of them was right.
`scene_file.dart`'s `_str` escapes `\`, `'`, `$`, `\n`, `\r`, `\t`;
`args_codegen.dart:537` and `tokens_library.dart:702` were partial re-writes
escaping the backslash and the quote only. A headline reading `Your coffee,\n
ready before you are` therefore generated `scene_args.dart` with a raw newline
inside a single-quoted literal — unparseable — and the failure surfaced as
`Null check operator used on a null value` with no line number, from `scene
list` and from the studio's Scene panel alike. Fixed by promoting `_str` to
`sceneStringLiteral` and using it in all three. Store headlines are multi-line
about half the time, so this was on the critical path for the whole exercise.
`tokens_library.dart` additionally had `.replaceAll(r'$', r'$')`, a no-op where
`r'\$'` was meant.

**(b) A compiled scene's nodes have no names, and the 3D renderer keyed on
names.** `SceneNode.name` is filled in by the *parser*, from the field name; a
scene the app constructed (`SceneView(StoreHero())`) has `name == ''` on every
node. `scene3d_renderers.dart` kept `_placed` and `_loading` as
`Map<String, …>` keyed by that name, so a compiled scene with two placements
collapsed into one — **a banner with two phones drew one phone**, silently.
Fixed by the same rule the view already uses for its GlobalKeys: the name where
there is one, the node object where there is not. Worth knowing generally: any
kind renderer that remembers per-placement state has this trap, and it only
shows up outside the editor, because the editor always pushes parsed documents.

**(c) `scene video` could not be given arguments**, so a scene with parameters
rendered its mockup defaults and nothing else. Added `args`: a JSON object
validated against the scene's declared parameters (an unknown name is refused
by name, with the ones it does declare) and applied through the read plane's
existing `applyArgs`, which already handles external-argument bindings. Two
settings are two files — the output carries an 8-char digest of the canonical
args, the same rule `previews screenshot` uses for its address — so
`StoreHero-f94b3259.mp4` is the French one and re-running does not overwrite
the English one.

**(d) A single pump is not enough for an image.** This one is *not* fixed, and
it decides which lane can render what. The harness lane (`previews screenshot`,
`scenarios`, `scene video`) waits on `ImageCache.pendingImageCount` before it
photographs anything, so a plain `Image.file` in a scene is waited for with
nobody being told to. The **render** lane (`render render`, the vector/PDF one)
mounts the widget offscreen and pumps once; a widget point's builder is
`Widget Function(…)`, not `FutureOr<Widget> Function(…)`, so there is no
moment at which anything asynchronous can be prepared. Widening that one
signature is source-compatible.

---

## 3. Against applaunchflow

Their surface, feature by feature, with what this repo has today.

| What they sell | Here today | Gap |
|---|---|---|
| **Screenshot editor** — layouts, copy, all store sizes | `StoreShots`: scenario-driven captures, per locale and device class, framed by the project's own `StoreFrame` widget, written into a tree `fastlane supply` reads. Apple's two required sizes come out of the device table exactly. | Templates. There is one frame (the demo panorama) and no library of starting points. Play's phone canvas is declared and not exported (a truthful 20:9 shot is not a legal Play screenshot — the frame is mandatory there, see 2026-08-26). |
| **Promo video** — storyboard, captions, device motion, MP4/WebM, 1–60 s, several ratios | `scene video`: any duration, 30 fps, mp4, deterministic (the harness lane exists because the guest could not repeat itself). Now parameterised. | One canvas per scene, so 9:16 and 16:9 are two scenes. No WebM. No storyboard *as such* — the timeline is the storyboard, which is arguably better, but there is no "captions track". |
| **3D mockup animator** — presets (Swing, Spin, Drop & Zoom, Punch Zoom) | `View3DNode` + `SurfaceNode` + the timeline. Orbit, distance, per-placement position/rotation/size/tint, lights, clips as blocks. Strictly more expressive. | Presets. A preset is a named motion applied to a placement; nothing exists to store or apply one. |
| **Localisation, 25+ languages, one click** | `Translations` plugin, catalogs, budgets, and a scene whose copy is parameters. Every asset above is already per-locale. | Machine translation. Also: nothing renders the *matrix* — you invoke once per locale by hand. |
| **Icon composer** | `LauncherIcon` is a **viewer** by decision (2026-08-12); it reads what is there. | Generation was explicitly rejected. Re-opening that is a decision, not a gap. |
| **Social graphics** — LinkedIn banner, X header, OG image, IG story, Product Hunt | Nothing named, but a scene at 1200×630 *is* an OG image and this exercise proves it. | A size table and a batch export. Small. |
| **ASO copy generator** | — | Not a local tool. Though: this repo already ships an MCP server, and the thing on the other end of it is a model. |
| **Keyword monitor** | — | A network service with a daily job. Out of scope. |
| **Direct publishing to ASC / Play** | The export tree is `fastlane`-shaped. | The upload itself. |
| **A/B testing, review replies, landing pages** | — | Different products. |

### 3.1 The honest summary

For **producing the assets**, the machinery is here and it is better-founded
than a template editor: the composition is a widget, so its ceiling is
Flutter's; the screenshots are the app's own pixels rather than uploads; the
copy is the project's own catalog; and every frame is reproducible because the
playhead is the input. Nothing in the two examples needed a new concept.

What is missing is **plumbing, not capability** — and it is the same shape
every time: *the matrix*. `store export` knows how to walk locales × device
classes × listings; the scene lane knows how to render one thing once. Almost
every gap in the table above is "there is no declaration that says: render this
scene, at these sizes, for these locales, into this tree".

---

## 4. Proposal

In order, each landing something usable.

**S1 — `scene shot`.** The still lane's missing action, symmetrical with
`scene video`: `--scene`, `--args`, `--size WxH`, `--scale`. Today the still
goes through a hand-written `@Preview` entry, which works (it is how §1.2 was
measured) but means every scene needs a preview file and a knob wiring written
by hand. `exportVideo` already does the parse → applyArgs → pair → walk
sequence; a single-frame walk is the same code with one stop. **Half a day.**

**S2 — a listing declaration for composed assets.** `StoreAssets` beside
`StoreShots` in `tool/flutterware.dart`: a scene, a set of sizes, the locales,
and where the tree goes. One invocation writes the whole matrix, named the way
the stores want them. This is the piece that turns two examples into a tool,
and it is mostly the loop `store export` already runs. **Two days.**

**S3 — an `ImageNode` kind.** Today a screenshot enters a scene through an
app-declared external widget — 20 lines, and it works, but it means a designer
cannot place an image without a developer editing `scenes.dart`. An image is
the one content type every store asset has, and it is a `SceneKind` with
`source`, `fit` and `alignment` rows plus a file/asset picker in the inspector.
It also unlocks logos, badges and backgrounds. **Two days**, and it is the
single highest-value item for the "designer works alone" story.

**S4 — the export canvas.** A scene's artboard is its size, so 1024×500 and
1200×630 and 1080×1920 are three scenes today. Two candidate answers: a `size`
argument on export with the root laying out responsively (cheap, limited), or
scene *variants* sharing parameters and tokens (right, larger). Worth
discussing before building. **Discussion first.**

**S5 — motion presets.** A named motion applicable to a placement, so "Spin"
and "Drop & Zoom" are one click. The mechanism is a motion file that binds by
role rather than by node name. **Two days**, and it is what makes the video
half feel like a product rather than a timeline.

**S6 — the vector lane reaches a scene.** Widen `RenderHost.widget`'s builder
to `FutureOr<Widget>` (source-compatible), and note that a scene group has to
live under `lib/` for a render point to import it. Then a press kit, a printed
poster and a real PDF one-pager come out of the same scene. **A day.**

**S7 — the Play feature graphic as a declared asset.** 1024×500 is exactly what
§1.2 renders, and Play requires one. It is S2 with one entry in the size table.

Deliberately **not** proposed: keyword monitoring, ASO copy generation, store
publishing, hosted landing pages, A/B testing. Three of those are network
services with a daily cadence and an account, and the fourth is a different
product. If the ASO copy half is wanted, the interesting route is not a
generator in the GUI — it is that an agent already drives this repo through
MCP, and `store export` already hands it every screenshot and every string.

---

## 5. Where the files are

| | |
|---|---|
| Scene + motion | `examples/example/demo/store_hero.scene.dart` |
| Preview entries (still, mid-reveal) | `examples/example/demo/store_hero_preview.dart` |
| Copy + pixels join | `examples/example/lib/store_hero.dart` |
| The screenshot widget | `examples/example/lib/shot_image.dart` |
| `Shot` declaration | `examples/example/demo/scenes.dart` |
| Phone model + builder | `examples/example/assets/models/phone.glb`, `tool/make_phone_blender.py` |
| Banner copy | `examples/example/assets/store/{en,fr}.json` |
| String-literal fix | `app/lib/src/scene/scene_file.dart` (`sceneStringLiteral`), `args_codegen.dart`, `tokens_library.dart` |
| Placement-key fix | `examples/example/lib/scene3d_renderers.dart` |
| `scene video --args` | `app/lib/src/plugins/native/scene_core.dart` |
