# A picture nobody is watching does not need an engine of its own

**Date:** 2026-08-27
**Status:** Built, 2026-08-27 — §4.2, §5.1, §5.2, §5.3, §5.4, §5.6, §6.3, the
parity check §9 asks for, and §8.6: `screenshot` and `inspect` render on the
harness now, with `engine=guest` as the escape hatch. §3 is measured. **§4.1
was wrong and is retracted** — see the measurement in it. **The parity check
found three real bugs and one open question** — see §9.
**Reads against:** `2026-08-15-previews-audit-on-flutter-tester.md`, whose
closing paragraph this reverses, and `2026-08-11-worktree-comparison-design.md`
§6a, which reversed half of it already.

The 08-15 findings ended with a list of what stays on the embedder guest:

> The embedder guest keeps everything that needs a real frame: `compare`'s
> pixel diffs through `captureAll`, `screenshot`, `inspect`, and the panel.

Five days later `compare` moved anyway and `captureAll` was deleted. Thumbnails
followed. The list is now the panel, `screenshot` and `inspect` — and of those
three only the panel is a *stage*, a live texture a person is driving. The other
two spawn a private embedder, render one frame, and tear it down.

The sentence that justified the list was about frames. It should have been about
who is looking at them.

## 1. Where each surface renders

| surface | lane | since |
|---|---|---|
| the panel | embedder guest | always |
| `audit` | `flutter_tester` | 2026-08-15 |
| `compare` | `flutter_tester` | 2026-08-20 |
| hover thumbnails | `flutter_tester` | 2026-08-25 |
| store frames | `flutter_tester` | 2026-08-26 |
| **`screenshot`** | **embedder guest** | — |
| **`inspect`** (headless half) | **embedder guest** | — |
| `describe --with-knobs` / `--with-axes` | embedder guest | — |
| `filmstrip` / motion | embedder guest | — |
| `check` | neither — the daemon handshake answers it | 2026-08-15 |

Four callers, not two. `describe` spins a whole guest to read what knobs an
entry declared, and it matters here because *knobs on the harness* is the
prerequisite `screenshot` needs anyway (§5.3) — which makes the cheapest of the
four the one to do first.

Every one of them goes through `HeadlessCatalog.observe`
(`app/lib/src/previews/headless_catalog.dart:274`), which is `_withGuest`:
connect to the daemon, compile one entry to a whole kernel, spawn the embedder,
render, tear down.

## 2. `inspect`'s live half is not a render at all

Worth separating before anything moves, because it is the one thing the guest
lane does that no other lane can.

`_withLiveGuest` (`app/lib/src/plugins/native/previews_core.dart:2712`) reads
the session a person has open, when there is one and it is *already showing*
that entry. It never switches the guest — it reads what is on screen or it
declines. That answers questions nothing else can: the dropdown they opened,
the row they scrolled to, the knob they turned by hand.

It is also already fenced off from everything this document proposes.
`_mayAttach` refuses it for knobs, axes, debug flags, a reframe, and —
decisively — for a picture, *"since an attached session offers a VM service and
no frames"*. So the live path never renders, and nothing below touches it.

What is left of `inspect` after that fence is a headless render, identical in
shape to `screenshot`'s.

## 3. What the two lanes cost, and the one place they disagree

Measured 2026-08-27 on this repo's own catalog, this machine, entry
`tool/catalog/demos/counter.dart#counter`.

| | |
|---|---|
| `previews screenshot`, warm daemon, through MCP | **12.81s**, then 12.72s |
| `previews audit` of one file, cold harness, through MCP | 13.54s |
| the same, harness warm on disk | 8.54s |
| `PreviewTestRunner.capture`, fresh build directory, in-process | **3.72s** |
| the same runner, second call, `sync: false` | **63ms** |

Two things about the middle rows. Every MCP and `fw` call **builds a fresh
session and holds nothing between them** — so the warm `_testRunners` cache in
`PreviewsCore` (`previews_core.dart:356`) serves the GUI and nobody else, and
both lanes pay a bring-up per agent call today. And the 3.72s is a fresh
`build/` directory after the seed-kernel work of 2026-08-26; the 08-27
first-open design records ~13s for a cold catalog before it, so treat 3.72s as
this machine's floor and not as a promise.

The tester lane also runs `--enable-impeller --impeller-backend=metal`
(`app/lib/src/embedder/tester_host.dart:692`), the same engine family as the
guest. "A different rasterizer" is not the objection it looks like.

**Two renders of the same entry came back byte-identical** (`cmp`, PNG for PNG),
which is the property the comparison moved for.

### 3.1 The counter's logo is at 240°

The two lanes were laid side by side. Identical colours, identical type,
identical layout — and the Flutter logo upright in the guest's picture, turned
240° in the tester's.

The demo is `AnimationController(duration: 3s)..repeat()`. The tester lane
photographs at `auditSettle = Settle.elapse(auditBudget)`, five fake seconds:
5/3 turns is 240°, every time, for ever.

Nothing is broken. `auditSettle` is right for what it was written for, and the
08-15 findings say why in one line — *"an audit may hold the clock, a capture
may not"* — and then say what it gives up:

> What this policy gives up is the screen *as it settled*: what a capture
> photographs is the screen at `budget`. The comparison rides that on purpose.

The capture path inherited it because its first caller was the comparison, which
wants reproducible pixels more than it wants a settled frame. A picture somebody
*looks at* wants the opposite. So the settle is a **policy per caller**, not a
constant, and that is gate one.

Note what neither lane can do: for an entry that never stops moving there is no
canonical frame, and the guest's upright logo is luck rather than correctness —
it photographs at whatever real instant the socket round-trip landed on. The
honest difference is that one lane's arbitrary frame is reproducible and the
other's is not.

## 4. Three gates, and one of them was not a gate

Nothing may move until they are shut. Each is small; the third is not — and the
first turned out to be nothing at all.

**~~4.1 Settle policy per call.~~ Retracted 2026-08-27: measured, and false.**
The claim was that `auditSettle`'s `Settle.elapse(5s)` is what puts the
counter's logo at 240° (§3.1), and that a picture should ride `Settle.standard`
instead. Both halves are wrong. Measured directly, on a looping animation and
on an entry waiting on a bare timer:

| | `Settle.standard` | `Settle.elapse(5s)` |
|---|---|---|
| a 3s controller on `repeat()` | 5000ms | 5000ms |
| a 2s timer, then content | 100ms, placeholder — **and a pending-timer failure** | 5000ms, content landed |

A repeating controller schedules a frame every tick, so a frame-driven settle
never goes idle and spends its whole budget anyway: **the two policies produce
the identical picture of a looping entry**, and §4.1 would not have moved that
logo one degree. What it *would* have done is photograph every demo that sleeps
before it loads as its own placeholder — which is the failure the 08-15
findings already recorded, in the sentence this document quoted approvingly and
then proposed to reverse.

So `auditSettle` is already right for a capture, and there is no per-caller
policy to add. The 240° logo stays what §3.1 says it is: a looping entry has no
canonical frame in any lane, and the tools for one are `timeDilation` and the
motion seek, both of which exist.

**4.2 Pixel ratio — built 2026-08-27.** `_capture` asked for
`layer.toImage(Offset.zero & (view.size * dpr), pixelRatio: scale / dpr)`
(`harness.dart:536`) — a physical rect at a logical ratio, so the image that
came out was **logical size**, always. `CaptureViewport.of(device)` is physical
(`app/lib/src/previews/devices.dart:110`): `iphone-16-pro-max` is 1320×2868.
Moving `screenshot` as it stood, that shot silently becomes 440×956, which
destroys the one property the tool is sold on — *a detail worth a pixel comes
back worth several*. Nothing would have failed; the pictures would just have
quietly stopped being worth reading.

**The fix was the name, not the arithmetic.** `scale` meant a fraction of the
logical screen, which is a basis nobody staging a device thinks in; it is
`pixelRatio` now, physical pixels per logical pixel — the same word the guest's
`FrameCapture` already takes, so both backends are asked for a resolution in
one vocabulary. The arithmetic is unchanged and `1` still means what it meant,
so the comparison and the thumbnails carry on at logical size, which is right
for a diff and for a picture nobody reads text in. What changes is that a
caller staging a 3× phone now passes `3` instead of working out a fraction, and
`TesterRenderer` passes the staged viewport's own ratio without being asked.
Pinned in `capture_test.dart`: at 2 the same entry comes back at twice the side
and four times the bytes.

**4.3 The feature surface.** The extension takes
`entries, device, orientation, output, scale, tree, timings, format`.
`screenshot` and `inspect` between them take knobs, axes, debug switches,
keyboard mode, arbitrary `width`/`height`, `node`, `annotate`, `at`, `logs`.
That is the bulk of the work and §5 is about it.

## 5. The design

### 5.1 One request, two backends — built 2026-08-27

`CatalogObservation` (`headless_catalog.dart:479`) is already the
lane-independent shape, and already serves two producers — a fresh guest and an
attached live session — with a doc comment saying exactly why:

> The same shape whether the reading came from a fresh guest or from the session
> a person has open, so the two paths cannot drift in what they can report.

A third producer is with the grain rather than against it. Give the *request*
the same treatment: `HeadlessCatalog.observe`'s parameter list already **is**
the request object in all but name — it is `_InspectRequest` minus the
projection flags. Lift it.

```
CatalogRender  →  CatalogObservation
  ├── GuestRenderer   (today's HeadlessCatalog.observe, unchanged)
  └── TesterRenderer  (over PreviewTestRunner)
```

`PreviewsCore` picks. Default `tester`; `--engine=guest` as the escape hatch,
and the escape hatch is not decoration — it is what an embedder regression is
caught with once nothing headless exercises the embedder any more (§6.4).

**What landed** (`app/lib/src/previews/catalog_render.dart`): `CatalogRender`,
`CatalogRenderer`, and `CatalogObservation` and `CatalogCapture` moved off the
guest's file, with `HeadlessCatalog extends CatalogRenderer` as the only
backend so far. `observe` became `render`, `screenshot` and `inspect` are typed
against the interface, and no behaviour moved — verified end to end rather than
by unit tests, which never reach a guest: the `node=Tap me` crop comes back
**byte-identical** to the pre-change capture, and the whole-entry shot differs
only in the animation phase, which is §3.1 and was never reproducible on this
lane.

Three things the shape decided that the sketch above did not:

- **`capture` is concrete on the interface, not abstract.** A capture is a
  projection of a render; a second implementation of it is a second chance to
  disagree about what a picture of an entry *is*. Which had already happened
  once here — `observe` was written with a copy of `capture`'s `_Framing`, the
  same lookup and the same two error messages byte for byte.
- **`needsTree` and `framed` live on the request.** A hit, a crop and an
  annotation all need a tree the caller did not ask for, and a backend that
  worked that out for itself would be answering a question nobody could see it
  had been asked. The request decides; the backend obeys.
- **`copyWith` rather than a field-by-field rebuild.** `capture` forces
  `wantKnobs`, and the first cut spelled out all thirteen fields to do it — a
  new field added and forgotten there would have silently stopped travelling.

The argument for why the request is *one* request — five projections of one
observation, and `--annotate`'s ids matching the reported tree because they are
the same tree rather than because the build is deterministic — moved from the
guest's method onto `CatalogRender`, where it is a fact about the request
rather than about an engine.

### 5.2 A new extension, not a wider `audit` — built 2026-08-27

`runPreviewHarness` is published (`lib/flutter_test.dart:11`), so
`ext.flutterware.previews.audit` is a **wire contract with whatever
`package:flutterware` the consumer's checkout resolves**. Widening it repeats a
trap the comparison already paid for: a base checkout predating the `output`
argument *rendered the entry and ignored the argument silently*, and every row
had to be rescued by inferring skew from `image == null && failure == null`
(`app/lib/src/previews/test_runner.dart:355`).

So: register `ext.flutterware.previews.render` beside it. One entry, one
observation. A harness that does not have it refuses at the call rather than
answering a question it did not understand, and the host says "this checkout's
`package:flutterware` predates single-entry render" once, in the right words.

`audit` keeps its shape: catalog-wide, verdicts, no framing beyond a device.

**Refusal is the whole contract while the lane is half-built.** `render` names
every argument it cannot yet honour — `screenshot`, `tree`, `at`, `logs` — and
answers an error for each, and `TesterRenderer` refuses a viewport that is not
the panel's own rectangle *before* it asks, since staging is §5.3's adapter and
does not exist yet. A request answered on the wrong surface would look
answered, which is the one outcome this lane may never produce.

Arguments are strings, as service-extension arguments always are, so the request
travels as JSON in one of them — the shape `ext.flutterware.setKnobs` already
uses (`lib/src/ui_catalog/guest.dart:105`).

### 5.3 What the harness applies inside the body

The staging vocabulary is already there and mostly unused by this lane:

- **Viewport, insets, platform, brightness, text scale — built 2026-08-27.**
  `ScenarioRunArgs` (`lib/src/scenarios/run_args.dart:16`) carries all of them,
  and `applyScenarioRunArgs` is what the harness already called for its plain
  rectangle. `_stageViewport` is the adapter; arbitrary `width`/`height` falls
  out for free, which the guest needed a resize message for.

  **A viewport, not a device, and that is what the lane was missing.**
  `applyDevice` needs a `Device`, and half the screens a preview is asked for
  are not one: the panel's rectangle is no device, and `--width` overrides a
  real one into a size no phone has. So the wire carries numbers, exactly as
  the guest's resize message does.

  **One class at both ends rather than two with a contract between them.**
  `StagedViewport` is published (`lib/src/devices.dart`, plain Dart like the
  rest of that file): the host builds one from its `CaptureViewport` and
  encodes it, the harness decodes one and stages it. Two mirror classes would
  be two descriptions of one screen, which this repository has paid for more
  than once; one class cannot drift from itself.
- **Device and orientation** — resolved by the host into the viewport above,
  through the same funnel `screenshot` and `inspect` already frame with. The
  harness's own `applyDevice` stays for `audit`, which frames a whole catalog
  as one named device.
- **The keyboard** — `ViewKeyboardSlab`, already mounted. `KeyboardMode.up` is a
  staged slab with nothing focused; `auto` is what the lane does today. The
  variant limit is already written into the harness's own comment and stays: the
  canvas stages its keyboard before the pump, so an entry that autofocuses a
  `phone` field gets the letters keyboard. Say it in the refusal, do not pretend
  otherwise.
- **Knobs and axes — built 2026-08-27.** `CatalogGuest` is mounted in this lane
  already, which is what makes knobs answer at all. They are applied **in the
  body**, via `CatalogKnobs.instance.applyAll` and `CatalogAxes.instance.apply`
  plus a settle, and *not* over the VM service: the `setKnobs` extension awaits
  `WidgetsBinding.instance.endOfFrame`, and under FakeAsync with nobody pumping
  that never completes — an external call would wait out its two-second timeout
  and report `applied` against a build that never happened. Axes before knobs,
  as the guest applies them, and both *after* the first settle rather than
  before the pump: a knob does not exist until the demo has asked for it.

  **A render says what it rendered on.** `CatalogObservation.stagedOn` is the
  physical size and ratio the backend read back off its *own* binding, not an
  echo of the request — and it is the only check on staging there is. Every
  other answer looks the same on the wrong surface as on the right one: the
  knobs a demo declares, the errors it reported, even a picture, which is only
  wrong in a way somebody already has to suspect. It exists because the test
  for staging could not otherwise be written: the first attempt asserted that a
  form overflows on an iPhone SE, guessed wrong, and would have been
  circumstantial even had it passed.

  **Resolving stayed on the host, and that is the load-bearing half.** Which
  kind a knob is and which label an axis option answers to are facts about the
  build that declared them, so `TesterRenderer` asks once for the declarations,
  resolves against them, and asks again with a typed payload — two pumps of one
  entry against a warm harness. The resolving itself moved out of the guest
  session into `catalog_values.dart`, which both lanes now share, so a name
  nobody declared is refused in the same words either way.
- **The settle** — §4.1.
- **The reads** — `GuestInspector` is constructed in `_capture` already
  (`harness.dart:558`); `hitTest(x, y)` is a plain method on it
  (`lib/src/inspect/guest_inspect.dart:154`). `at` costs a line. Logs are the
  one real gap: `GuestLogs` is not collected in this lane, because test-zone
  prints ride `live.onMessage` rather than the buffer. Either wire the buffer or
  refuse `--logs` on this engine and say which engine has it.

### 5.4 Crop and annotate need nothing — built 2026-08-27

The nicest finding of the survey. `node` and `annotate` look like guest
features and are not: `_Framing` resolves them **host-side** against the
`InspectTree` (`headless_catalog.dart:376`), and the pixel work is two free
functions over `package:image` — `cropToNode` and `annotateNodes`
(`app/lib/src/embedder/frame_capture.dart:177`, `:195`) — taking an
`img.Image`, an `InspectLayout`/`InspectNode` list and a ratio. Nothing in
either touches a socket.

The tester lane already writes a raw frame and already writes the tree. So the
whole post-frame stage is lane-independent today and only needs lifting out of
`frame_capture.dart`, whose remaining job is the socket exchange and the
embedder's own file layout — *12-byte header, BGRA, a stride*
(`app/lib/src/embedder/raw_frame.dart`) — against the tester's packed RGBA with
its dimensions in the reply. Two decoders, one pipeline.

Keep the guest's fast path while you are there, because it is the commonest call
there is: when nothing has to be read *before* the shutter, ask the harness for
PNG directly and never decode. Only a crop or an annotation needs the tree
first, and only those pay `raw` → decode → draw → crop → encode.

**What landed** is `app/lib/src/previews/catalog_picture.dart`: `PictureFraming`
(the old private `_Framing`), `cropToNode`, `annotateNodes`, a `framePicture`
that applies them and a `writePicture` that encodes and files the result.
`FrameCapture` keeps the capture request, the ack and the `.rawframe` layout —
it hands back a decoded frame and stops. `decodeTesterFrame` is the other end:
packed RGBA with its dimensions in the reply, against the embedder's BGRA
behind a twelve-byte header with a stride. **Two decoders, one pipeline**, which
is exactly what the section predicted.

Three things it settled that reading alone had not:

- **The writing was split and nobody owned it.** The guest encoded and wrote
  inside `_GuestSession.capture`; the harness lane wrote raw bytes and left its
  caller to work out the rest. One picture is written one way now.
- **`EmbeddedEngine.captureImage` was doing two jobs.** It took `crop`,
  `annotate` and `pixelRatio` and passed them into the socket layer, so the
  window capture — which wants an unframed frame to paste into a hole — went
  through a framing path it never used. It takes nothing now; `capturePng`
  frames what it gets.
- **Two tests moved and got better.** `a crop cuts to a node box` and `a crop
  reaching past the frame is clamped` were in `frame_capture_test.dart`,
  reaching the crop through a fake socket because the crop lived behind one.
  They are pixels-in-pixels-out in `catalog_picture_test.dart` now.

Verified end to end rather than by unit tests: the `node=Tap me` crop is
**byte-identical** across the extraction, and `--annotate` still draws its
boxes and ids on the right widgets.

### 5.5 Debug flags travel, with a reset

All seven are `ext.flutter.*` extensions registered by any debug binding
(`app/lib/src/previews/debug_flags.dart:57`–`:113`), and
`TestWidgetsFlutterBinding` is one. So `applyDebugFlags` works unchanged over
`TesterHost.vm` — no harness argument, no wire change.

They are process globals, and this is the difference that matters: **the guest
was disposable and the harness is not.** A `paint=true` screenshot leaves the
layout guides on, and the next thing to render in that process is somebody's
hover thumbnail. Set and reset around each render, in a `finally`, and treat
`timeDilation` the same way. This is §6.1 and it is the trap most likely to be
found by a user rather than by a test.

### 5.6 `describe` crosses first — built 2026-08-27

`--with-knobs` / `--with-axes` are a `render` with no picture and no settle
budget worth arguing about: the cheapest of the four callers, needing §5.3's
knob plumbing and nothing else. So it moved first, and proved the plumbing
before a picture depends on it.

**Parity was checked against the guest rather than asserted.** Both engines
were asked about the same entry: same three knobs with the same kinds, values
and `min`/`max`, same two axes with the same options, same shell id. The
end-to-end test (`app/test/previews/render_values_test.dart`) then pins the
half a parity check cannot reach — turning a knob and an axis and reading back
what the resulting build declared — on `examples/example`, whose `keyboards`
entry declares a picker while the shell around it declares two axes. A fixture
with knobs only would have left the axis path untested and green.

It also fixed a bug the code carried a comment against. *"One guest for both
when both are asked for"*, said the comment; `axes` and `knobs` were a
`_withGuest` each, so asking for both compiled, launched and tore down **two**
guests to read two projections of the same build.

## 6. What a shared harness costs that a private guest did not

Four things, none of them fatal, all of them new.

**6.1 Sticky globals.** §5.5.

**6.2 The queue.** `TesterHost.exclusive` serialises. Today an agent's
screenshot is a private process that competes with nothing; after this it
queues behind whatever the panel's thumbnail sweep is doing. On a cold catalog
that is the whole compile. The runner already narrates its phase
(`_noteRunnerLine`), so the fix is to say *what* is being waited on rather than
to pretend the wait is not there.

**6.3 One build directory, several processes — built 2026-08-27.** The real
hazard, and it was already on the books: the comparison's head-side runner and
the panel's warm runner share `build/flutterware/previews.dill`, and the
scenario half has had the identical overlap since 2026-08-11. That was two
runners in *one* process. After this move it would be routine across processes
— every `fw`/MCP call builds its own core, so an agent screenshotting a
worktree whose studio is open is two `flutter_tester` hosts on one dill, and a
torn dill is a compile error in a file the user did not touch.

**Neither of the two options this section first offered is right.** "Claim per
process" throws away the on-disk warm dill, which §3 measures at 8.5s against
13.5s — the very thing the move exists to collect. "Key by session" needs a
process to know whether it is the studio, which it cannot and which stops being
true the moment the studio is closed.

What is built instead is a **lane, taken rather than assumed**
(`app/lib/src/embedder/build_directory.dart`). Whoever locks
`<preferred>/<program>.lane` first has that directory; everybody else builds in
a claim of its own under `build/flutterware/sessions`. Self-arbitrating: no
process has to know what it is, the long-lived one ends up holding the shared
lane and keeping its warm dill, and a transient one that finds it free takes it
and leaves the dill behind for the next.

Four things worth knowing about it:

- **A lane belongs to the process, not to a host, and is never released.** The
  kernel drops the lock at exit. A host disposed and rebuilt —
  `restartRunner`, a core reloaded under a mounted panel — comes back to the
  same directory rather than re-racing for it and silently landing somewhere
  colder.
- **It resolves lazily**, behind `BuildLane`. A runner is routinely built and
  never started — a test's fake, a panel that mounts and closes — and taking a
  lane creates a directory and opens a file. Eager resolution wrote into a
  package nothing ever ran, which is how the four `ScenarioRunner` fakes
  standing on `/none` found it.
- **The lock is per program, not per directory.** Previews and scenarios have
  always shared `build/flutterware` and always may: their dills, bundles and
  entrypoints are named apart. Only two hosts on one *program* tear anything.
- **The sweep now asks two questions, not one.** The comparison's rule was age
  alone — right for a run that takes minutes, wrong for a session claim held
  by a studio that has been up for two days. A claim is swept when it is a day
  old **and** nobody living holds its stamp. Each half is wrong alone: liveness
  alone evicts a fresh sibling of our own, because advisory locks are per
  process and ours look unheld to us.

`claimComparisonBuildDirectory` was generalized rather than copied —
`claimBuildDirectory(root:)` now serves the comparison and the sessions root
both, and `app/lib/src/comparison/build_directory.dart` is gone. One rule about
what a claim means, in one place.

**6.4 Nothing headless exercises the embedder any more.** Once these four move,
an embedder regression surfaces only when a human opens the panel.
`app/integration_test/embedder/` covers it and `--engine=guest` keeps the path
warm, so this is a reason to keep the flag rather than a reason not to move.

## 7. What does not move

- **The panel.** It is a stage: a live texture, hot entry switching, knobs
  turned by hand. Measured at 57ms an entry switch, which no lane beats.
- **`inspect --live`.** §2. Not a render.
- **`filmstrip` / motion.** Seek is `ext.flutterware.motion.seek`, and the
  guest's own implementation renders a scratch frame first because a
  `MotionScope` registers its extensions when it mounts. In-body under FakeAsync
  is arguably a *better* home for a seek — exact rather than approached — but it
  is its own design and it is not blocking anything. Leave it.
- **`check`.** Already the daemon handshake, no guest.

## 8. Order

1. ~~**§6.3, the build directory.**~~ Built 2026-08-27. First, because
   everything after it makes the collision routine.
2. ~~**§5.1**, `CatalogRender` lifted out of `observe`, guest backend only.~~
   Built 2026-08-27. No behaviour change; the diff is a parameter list becoming
   a class.
3. ~~**§5.3's knobs and axes in the body, plus §5.6 `describe`.**~~ Built
   2026-08-27. The first caller to cross, and the one where a wrong answer is a
   wrong number rather than a wrong picture.
4. ~~**§4.1 settle policy** and **§4.2 pixel ratio**.~~ 2026-08-27: §4.2 built,
   §4.1 retracted as false — the measurement is in §4.
5. ~~**§5.4**, the post-frame stage lifted out of `frame_capture.dart`.~~
   Built 2026-08-27.
6. ~~**`screenshot`.** Then **`inspect`**'s headless half.~~ Built
   2026-08-27, and it was nearly free: both go through `_rendererFor`, which
   picks the harness unless `engine=guest` or `logs` sends the call to the
   embedder. `readFrom` names which one drew it — `live`, `harness` or
   `guest` — because a caller cannot interpret a picture without knowing.

## 9. Not proposed

**Deleting the guest.** The panel keeps `HeadlessCatalog`, `_GuestSession`,
`FrameCapture`, the daemon, the C host. So this is a **second renderer for four
commands**, not a consolidation, and it should not be argued for as one. What it
buys is measured in §3 and is enough on its own: ~3.4× cold, ~200× warm,
reproducible pixels, and one lane shared with the thumbnails, the audit and the
comparison — so a picture in the popover and a picture from the CLI stop being
two different pictures of the same entry.

**And what it costs is the other half of that same sentence.** Today
`screenshot`, `inspect` and the panel are one engine, so what an agent
photographs is what the human is looking at. After this they are two. The
precedent is already set — the hover thumbnail beside the canvas has been
tester-rendered since 2026-08-25, deliberately, because *"there is one embedded
engine and one texture"* — but it is a tie being cut, and the parity check that
found the 800-versus-900 bug in the old audit is what has to stand in for it.

### The check, and what it caught — built 2026-08-27

`app/test/previews/lane_parity_test.dart` renders one entry through both
backends on an iPhone 16 and compares **the layout, not the pixels**: the
surface each judged the entry on, every node's type and box by id, and what
each complained about. Two rasterizers on two clocks will not agree byte for
byte and are not supposed to — the guest photographs whatever real instant its
socket round-trip lands on. What must agree is everything a caller *reasons*
with.

It failed twice before it passed, on two bugs neither lane could have found
alone.

**1. The lanes mounted different trees, so every node id was off by one.** The
generated guest entrypoint wraps each demo in a `KeyedSubtree` keyed per entry
— *"a fresh key per entry so switching remounts rather than reusing the
previous entry's State"* — and the harness never mounted it. A node id is a
position in the summary tree, so one unshared widget shifts every id below it:
`--node=0/1/2` would have named different widgets depending on which engine
answered, and an annotated screenshot's labels would not have matched a tree
read from the other lane. The harness mounts it now; the guest's ids were the
canonical ones, so nothing anybody has stored moves. The 08-15 findings claimed
this invariant already held — *"the same two the guest entrypoint mounts"* — and
it was three, not two.

**2. The headless guest divided every device's safe areas by its pixel ratio.**
`ResizeMessage` is physical throughout (`physical_view_inset_*` is what the
engine reads) and `CaptureViewport` carries a physical size beside *logical*
insets; `_resize` scaled the size and not the insets. An iPhone 16 was staged
with a **19.67pt cutout instead of 59**, an iPhone SE with 10 instead of 20 —
the error scaling exactly with the ratio, which is what identified it. Nothing
failed and every picture looked plausible; an `AppBar` merely sat too high,
under the notch a phone frame exists to catch. **The panel had it right all
along** (`catalog_view.dart`'s `insets: safeAreas * dpr`), so this was only ever
wrong where `previews screenshot` and `inspect` look.

**3. The headless guest never told a preview which device it was.** The
embedder's window-metrics event carries a size, a ratio and four insets and
nothing else, so a device's *identity* travels over the VM service instead —
and only the panel was sending it (`catalog_view.dart`'s `stageAs`). Headless,
`--device=iphone-16` gave the preview a phone's screen and left it running as
whatever platform a bare embedder reports: a Cupertino branch takes the wrong
turn, and a `ThemeData` computing `materialTapTargetSize` from
`defaultTargetPlatform` sizes its buttons for the wrong machine.
`CaptureViewport.platform` has always existed to say this — its own doc says
so, *"a window shaped like a phone running as a Mac renders desktop
transitions"* — and nothing outside the panel said it. `render` says it now.

**And one question it opened, left open.** With **no** device named, the two
lanes still each answer with a platform of their own: the harness keeps the
test binding's, and the guest — since `stageGuestPlatform(null)` resets the
override — takes the machine it runs on. Where a theme reads
`defaultTargetPlatform` that is visible: measured on this repo's own catalog, a
`FilledButton` is 48 logical points tall on the harness and 40 in the guest.
Staging the host platform in the harness was tried and **made it worse** — it
agreed on this repo's catalog and disagreed on `examples/example`'s, which says
the rectangle's platform is not simply "the machine" and the real question is
what a *rectangle* should be. Reverted rather than shipped: a change that
trades one disagreement for another is not a fix. The parity check covers both
surfaces now, so whoever answers the question will be told immediately whether
they did.

**And one divergence it recorded rather than fixed.** `KeyboardMode.auto` —
raise a keyboard exactly when the widget asks, the way a phone does — is a
guest capability this lane structurally lacks: the canvas stages a keyboard
*before* the pump, so there is nothing focused yet to read a variant off, and
the harness's own comment has always said so. The first fixture was
`demo/input.dart#textFields`, which autofocuses, and the two lanes differed by
336 logical points. The fixture is `demo/buttons.dart#buttons` now — a check
carrying a known divergence would report it every run in place of the drift it
exists to catch — and the limit is named here instead.
