# Scene graduation: three decisions and the foundation plan

2026-09-01. Owner-signed. Follows `2026-09-01-motion-api-sketches.md`, which
closed the motion API; this doc closes the questions that gate moving the
spike's cores to their real homes and re-founding the editor UI.

## Where the branch stands

The maturity ladder, measured against the tree:

- **Settled** — eleven spec docs (2026-08-28 → 09-01), every open question
  owner-signed, every claim probed. Decision capital; survives any rewrite.
- **Taking real shape** — the four cores, spike-located but not spike-quality:
  the scene grammar (`scene_file.dart`, 1041 lines, 39 tests + fuzz), the
  motion grammar (`motion_file.dart`, 1063 lines, 38 tests + fuzz), the live
  models (`model.dart` + `motion_model.dart`), the motion runtime
  (`motion_runtime.dart`, 27 tests). ~1,500 test-backed core lines against
  ~1,600 disposable shell lines. The location is the debt, not the code.
- **Prototype by declaration** — everything the user touches:
  `canvas_toy/main.dart` (stock Material, single selection, no keyboard, no
  undo, mutation straight onto the model), the dev shells, the hand-written
  guest registry. To be re-founded, not patched.
- **To kill** — the old motion plugin, three layers, ~10,700 lines:
  the published API (`lib/motion.dart`, `lib/motion_vocabulary.dart`,
  `lib/src/motion/`, ~2,000), the GUI plugin
  (`app/lib/src/plugins/native/motion_*.dart`, ~5,000), its support tree
  (`app/lib/src/motion/`, ~2,700). Checked 2026-09-01: every import of the
  published motion API is in-repo (the plugin, its tests, catalog demos) —
  no external consumer compiles against it.

## Decision 1 — natural names, own authoring library

Scene and motion files keep `Text`, `Frame`, `Shape`, `Ext`, `Track`, `Key`.
The vocabulary lives in a dedicated authoring library that **only paired
files import unqualified**; the user-facing runtime library (`SceneView`,
`MotionPlayer`, `Effect`) exports none of it.

The two collision surfaces are different problems. Inside a generated file
the tool owns the import section, and a `show` combinator is additive and
future-proof — unlike `hide`, which breaks every emitted file the day
Flutter ships a new name. In the *user's* app files nothing is controllable:
a library that exports both `SceneView` and `Text` makes every file that
mounts a scene beside `material.dart` ambiguous. That rules out the single
shared library on its own; the split is forced, and once split, the natural
names cost nothing.

Rejected: prefixed kind names (`SceneText` on every node line forever) and
an import prefix in files (`s.Text(…)` — the noise lands on most of what a
scene file is).

## Decision 2 — new plugin, motion killed early

`flutterware.scene` is a fresh plugin built clean on the design system. The
keepers are extracted first — the video export pipeline
(`app/lib/src/motion/video.dart`; flutter_tester rendering, cost bound on
moving pixels) and the discovery scan shape (`discovery.dart`) — then the
motion plugin **and** the published motion API are deleted in one PR as soon
as the scene plugin renders at all, before feature parity.

Two facts drove "early" over "at parity": no external consumers (above), and
the new grammar reuses the `.motion.dart` extension, so the old plugin's
discovery trips over new-marker files the moment both exist in one worktree —
coexistence is active noise, not just redundancy. The accepted gap: the old
sequencer/values editing has no replacement for a while.

The sequencer (`motion_sequencer.dart`) is read for its interaction lessons —
lanes, playhead, scrubbing, key dragging — and not ported: the old grammar is
baked into it. The scenarios motion player
(`app/lib/src/scenarios/motion_player.dart`) is a different organ (capture
playback) and stays.

Rejected: convert-in-place (the new editor scaffolded on ~5,000 lines of
old-grammar UI, with Frankenstein intermediate states).

## Decision 3 — own value vocabulary, one pure model

The scene core defines its own `Color`, `FontWeight`, `CrossAxisAlignment`
and `Curves`. Generated files import **only** the authoring library — zero
Flutter imports — and the model plus both grammars are pure Dart.

The duplication fear was measured before signing: the parser *already owns
these enumerations as tables* — it refuses `Colors.white` and
`Color.fromARGB` today (`expected a color, spelled Color(0xAARRGGBB)`),
carries FontWeight and CrossAxisAlignment tables, and the motion model
already stores curves as *names* with `motionCurveObjects` converting at the
runtime edge. The grammar was never "whatever Flutter accepts"; it is an
allowlist with canonical spellings, because every accepted spelling must
round-trip and be editable. The mirror moves the tables where the compiler
can read them too — `Curves.wiggle` fails to *compile* — it does not copy
them. Surface today: ~90 lines (one `const Color(int argb)`, FontWeight's 9
values, CrossAxisAlignment's 5, the 13 curves), all sets frozen in Flutter
for years. Growth is gated by us admitting a property — which already costs
parser + emitter + editor UI + wire + guest rendering; the mirror value is
the smallest of the six.

What purity buys is the whole headless surface, not one command: `fw scene
check`, the MCP server's scene tools, and future codemods are plain function
calls in a pure-Dart process. A Flutter-typed model cannot even be
*imported* there (`dart:ui` does not exist under plain `dart`) — every
headless touch would pay a flutter_tester spawn (~2.5s, measured) or proxy
through a running GUI.

Mechanical seams the split needs: an own ~15-line listenable replaces
`ChangeNotifier`; the fx flush (`fxTick`'s
addPostFrameCallback + ensureVisualUpdate) becomes an injected hook the
Flutter half binds. Precedent: every portable design/motion format owns its
value vocabulary (Lottie, Rive, SVG/CSS), and SwiftUI ships its own `Color`
beside UIColor with edge conversion.

Known costs, accepted: no IDE color-gutter chip on our `Color` literal;
`Colors.orange` in a hand edit gets a teaching refusal — which it already
gets today.

## The editor foundation

The missing layer under multi-selection, shortcuts and undo is an
**editor-state model between the document and the widgets**. The document
stays pure domain (which is the same refactor decision 3 needs).

- `EditorState`: selection as a *set*, in two domains — node names on the
  scene side, `(group, track, key)` tuples on the timeline side — plus
  hover, active tool, camera/zoom, clipboard.
- Every mutation goes through a command door; the undo stack is the command
  journal ("ops are doors, one undo entry" generalized from the timeline
  decision). Snapshot-based undo is likely affordable (clone/tweak measured
  0.11µs per 11-node construct) and simpler than inverse commands — measure,
  then choose; the door design is identical either way.
- Flutter's Intents/Actions/Shortcuts, with **focus discipline first**:
  canvas, tree, timeline and inspector are focus scopes; shortcuts bind per
  scope (arrow-nudge moves a node on canvas, steps a key on the timeline);
  text fields swallow keys natively. A keystroke dispatches from focus
  upward — the drive layer already proved a focusless window eats every
  shortcut.
- UI pieces iterate in catalog demos against stage-set `EditorState` +
  document — no guest boot, `previews screenshot` for judging. This is the
  mechanism by which UI and model iterate independently.
- Two renderers, roles named: the guest stays the only renderer of *truth*
  (theme, external widgets, measured rects); `NodeView` is demoted
  explicitly to a test/catalog fixture — instant rects for UI iteration,
  never shipping.

## Sequence

1. **Graduate the core** — vocabulary + models + grammars + runtime out of
   `canvas_toy/` into their real homes (pure core published; grammars with
   the editor/CLI), the ~104 tests moving with them. Decisions 1 and 3 land
   here.
2. **Editor foundation** — `EditorState`, command doors + undo, focus
   scopes + first shortcuts, multi-selection on tree and canvas (marquee +
   shift-click over guest rects).
3. **Keyframe editor v1** — timeline panel over the motion model: lanes per
   track, key selection and drag through the sort door, transport, per-scope
   keyboard.
4. **Plugin swap** — extract video export + discovery shape, stand up
   `flutterware.scene` in the shell (CatalogSession guest boot, discovery,
   panels), delete the motion plugin and `lib/motion.dart` in one PR.

Steps 2–3 carry the catalog-driven UI iteration in parallel; step 4's
extraction half can start any time.

---

# Addendum, same day: the pair is one file, and the road to the real editor

Milestones 1 and 2 landed (the core graduated; `SceneEditor` gave the
editor selection sets, command doors, undo and a keyboard). Driving the
result raised the question this addendum answers: the toy is not the
editor, so what replaces it, in what order, and what holds scene and
motion together.

## Decision 4 — one file per pair (grammar 0.5)

A scene file now holds **one scene class and any number of motion classes
that animate it**. `banner_intro.motion.dart` is gone; `banner.scene.dart`
carries `BannerScene` and `BannerIntro`. There is one marker, one parse
door (`parseSceneFile`), one emitter (`emitSceneFile(doc, motions: …)`),
one round-trip invariant.

What decided it:

- **The pair was already indivisible.** A motion resolves its targets
  against a scene by field name, so `parseMotionFile` had to be handed the
  scene document and its class name — "half a pair, never read alone" was
  a comment in the code. One file deletes that ceremony.
- **Compilable files are the next milestone.** Two files would have to
  import each other the moment the vocabulary becomes a real library; one
  file needs no import between the halves at all.
- **A rename is atomic.** Renaming a node updates the motions that target
  it in the same buffer — no window where one file of a pair is stale.
- **One document in the UI wants one document on disk.** The workspace
  shows a scene and its motion together; the file now matches.

Two costs, accepted rather than dodged:

- **One version marker for both halves.** `scene=0.5` covers the motion
  grammar too; a motion-grammar change bumps the scene file version. They
  ship together anyway.
- **All-or-nothing across the pair.** A hand edit that breaks the motion
  half now refuses the whole file, layout included. That is the standing
  policy (a partially loaded document is the lie the editor must never
  tell), and the refusal still carries a line number and a fix.

A second class with no `extends SceneMotion<…>` is refused as `extends`,
teaching the clause that makes a class a motion.

## Decision 5 — plugin home first

The order is: **workspace model → `flutterware.scene` plugin (mounting
today's widgets) → panel-by-panel rebuild → nesting.** Panels are built
once, in their final home; the alternative pays the migration cost on
finished work. The motion plugin and `lib/motion.dart` die at the plugin
step, before parity, as decision 2 already settled.

## Decision 6 — the toy stays until the last panel moves

`canvas_toy/` remains the fast standalone loop (no studio boot) while
panels migrate, because it mounts the same widgets the plugin does. It is
deleted in one PR when the rebuild finishes — nothing stranded, no second
shell kept alive forever.

## Decided, same day: one surface, timeline docked under the canvas

The three arrangements were built as catalog demos over the same panels and
the same stage-set editor, photographed at the wide window, and chosen from
the pictures: **tree · canvas over timeline · inspector**, transport in the
timeline's gutter (`SceneWorkspaceView`). Design/Animate modes lost because
Animate dropped the tree exactly when the lanes reference its nodes; the
drawer lost because it is the docked shape with a toggle, and the toggle can
be added later without changing anything else. Whether the pair is one surface
with a docked timeline, two modes over one document, or a timeline panel you
open, was to be answered by building the arrangements and looking at them,
not by argument — and it was. The experiment is cheap once the panels are widgets over
`SceneEditor`: a catalog demo per arrangement, stage-set state, one
`previews screenshot` each.

What is *not* open, because earlier decisions imply it:

- **Timeline rows are scene nodes.** An `AnimateGroup` targets a node by
  field name; the gutter is the node tree filtered to animated ones.
- ~~**Unplaced groups are library assets**, so they need a home beside the
  timeline, not on the playhead.~~ Reversed 2026-09-02, looking at it: the
  "library" strip explained nothing to its first reader. In the editor every
  group is on the timeline — a declared-but-unplaced group (legal in a
  hand-edited file) shows at zero and is placed by dragging its bar. A per-node
  animation that is not part of this clip is a second *motion*, which the
  scene-first workspace gives a home.
- **Nesting is a drill-in.** An instance's internals are not addressable
  (the nesting research law), so entering a nested scene switches the
  whole workspace, with a breadcrumb back — and a parent may animate only
  the nested scene's declared parameters plus the imposed props.

## Built 2026-09-02: nesting

A nested scene is a node kind — `Scene(PromoBadge, x: …, args: {'label': …})`
in the grammar, `SceneRefNode` in the core — holding the child's class name
and overrides for its declared parameters. Only number and colour parameters
animate (`args.<param>` tracks, like an `Ext`'s args); a string has no
in-between values. The instance is runtime state like `measured`: the
workspace resolves the class name to a file of the same package
(`resolveNested`), instantiates a copy with the args applied, and re-resolves
on the way back out of a drill-in so the parent draws the child as it is
now. The wire flattens the instance under the ref's box with internal names
prefixed, so the host needs no resolver and no internal ever collides with a
parent name. Enter is a double-click on the node in the tree or on the
canvas; the workspace view remounts per file so the canvas refits, the guest
follows the active file, and Save writes every dirty file the workspace
holds.
