# S-L3: what a plain `flutter run` app gives you, with no flutterware in it

**Date:** 2026-07-31
**Question:** slice 3 was planned around extracting `installGuestRuntime` and
mounting it through `Devbar`. Is a guest runtime required for tree, screenshot
and logs, or does the VM service already carry them?
**Answer:** not required. All three are reachable with only the `wsUri` we
already store in `RunHandle`. **The guest runtime buys geometry and hit-testing,
and nothing else slice 3 needs.**

Measured against `examples/example` under `flutter run --machine`, on macOS
(Impeller/MetalSDF) and the iPhone 16 Pro simulator (iOS 18.1). Flutter
3.47.0-0.1.pre, the `.fvmrc` pin.

## What is there, with zero app cooperation

The isolate registers 60-odd `ext.flutter.*` extensions before any of our code
would run. The load-bearing ones:

| want | call | macOS | iOS sim |
|---|---|---|---|
| tree (summary) | `ext.flutter.inspector.getRootWidgetTree` `isSummaryTree:true` | 57ms, 25 nodes, 25.5 KB | 25ms, same |
| tree (full) | same, `isSummaryTree:false fullDetails:true` | 101ms, 517 nodes, depth 224, **6.1 MB** | 40ms, 506 nodes, 5.8 MB |
| picture | `ext.flutter.inspector.screenshot` | 174–244ms, 98 KB | **15–42ms**, 39 KB |
| logs | `streamListen` on `Stdout`/`Stderr`/`Logging` | ok | ok |
| errors | `ext.flutter.inspector.structuredErrors: true` → `Flutter.Error` on `Extension` | ok | ok |
| network | `ext.dart.io.getHttpProfile` | ok | ok |
| sockets | `ext.dart.io.getSocketProfile` | ok | ok |

The summary tree is the usable one. The full tree is *six megabytes* for a demo
app with one screen, and 224 levels deep — it is not a thing to put on a wire
every time somebody opens a tab.

### The tree carries source locations, and that is the surprise

Every node in the summary tree — 25 of 25, both platforms — has
`creationLocation` (file, line, column), `locationId`, and
`createdByLocalProject`. Keys show up in the description (`Text-[<'fw-marker'>]`).

```
[root]                binding.dart:1673:24   local=None
  MyApp               main.dart:7:16         local=True
    MaterialApp       main.dart:15:12        local=True
      MyHomePage      main.dart:29:19        local=True
        Scaffold      main.dart:61:12        local=True
          ListView    main.dart:63:13        local=True
            Text-[<'fw-marker'>]  main.dart:66:11   local=True
```

`lib/src/inspect/guest_inspect.dart` documents at length that a *host* cannot
read a widget's creation location, because `_HasCreationLocation` is private and
Dart mangles private names per library — so the guest keeps a shape-derived id
instead. That is true in-process and false over the wire: the inspector's
service extension hands the location out. **Host-side identity can therefore be
`main.dart:66:11` plus a sibling index** — stable across relaunch *and* readable
by a person or an agent, which the shape-derived `0/1/2` never was.

`createdByLocalProject` separates the user's widgets from the framework's for
free, with no pub-root configuration needed.

## The screenshot: one RPC works, the obvious one doesn't

**`_flutter.screenshot` fails on both platforms**, identically:

```
_flutter.screenshot     -> (-32000) Could not capture image screenshot.
_flutter.screenshotSkp  -> (-32000) Cannot capture SKP screenshot with Impeller enabled.
```

The SKP error names the cause, and it applies to the whole target list: macOS,
iOS and Android are all Impeller now. So the rasterizer screenshot is not a path
we can plan on — it is effectively dead everywhere we care about.

**`ext.flutter.inspector.screenshot` works.** Ask it for the root's `valueId`
and it renders the whole render tree into an offscreen layer via `toImage`,
which Impeller supports:

- macOS: 98 KB PNG in 174–244ms
- iOS simulator: 39 KB PNG in **15–42ms**, correct aspect ratio, safe area respected

It is the real screen, DEBUG banner included.

### It is live, not cached

Verified rather than assumed. From outside the app, with the app never having
been touched: `ext.flutter.debugAllowBanner: false` and
`ext.flutter.debugPaint: true`, then screenshot. The banner is gone and the
debug boxes are drawn. The picture is the app's render state at the moment of
the call.

That test also proves something we get as a side effect: **every flag in
`app/lib/src/catalog/debug_flags.dart` works on a real device run** —
`debugPaint`, `repaintRainbow`, `debugAllowBanner`, `brightnessOverride`,
`platformOverride`, `timeDilation`. A panel feature that ports for nothing.

### Two caveats

- **Platform views will not appear.** Native maps, webviews, and video are
  composited by the OS, not by Flutter's layer tree. Expected from how `toImage`
  works; not measured here, because the example has none.
- **Device-level capture is not a fallback everywhere.** The flutter daemon
  reports it per device, and for the wireless iPhone on this desk it says
  `"screenshot": false`. So the inspector RPC is not merely the better path on
  the primary target, it is the only one.

## What the VM service does *not* have: position

`getLayoutExplorerNode` gives geometry per node — but only half of it:

```
size:        Size(760.0, 40.0)
constraints: BoxConstraints(w=760.0, 0.0<=h<=Infinity)
parentData:  <none> (can use size)
```

Size and constraints, at 4ms a node (25 nodes in 99ms). **No offset, no global
rect, anywhere in the inspector surface.** `getDetailsSubtree` at depth 100
answers `(-32000) Server error`, so there is no bulk route either.

That is the whole of the gap, and it is exactly what `frame_capture.dart` needs:
`InspectLayout` (x, y, width, height) is what lets a screenshot be cropped to a
node and annotated with the ids the tree reported. Without it, the tree and the
picture are two observations with nothing joining them — which is the thing
`annotateNodes` was written to fix.

Hit-testing (`ext.flutterware.hitTest`, "what is at x,y") has no VM equivalent
either, and it is the same missing information seen from the other side.

## The shape this implies

**Two layers, and the first one is not optional.**

**Layer 1 — the VM service, on by default, no setup.** Tree with source
locations, screenshot, logs, errors, network, debug flags. Works against *any*
Flutter app in debug mode, including one that has never heard of flutterware.
That reach is worth more than anything below it: the cockpit stops being a
thing you adopt and becomes a thing you point at a project.

**Layer 2 — a Devbar installer, opt-in.** What layer 1 provably cannot do:

- **global rects per node**, which unlock crop and annotate
- **hit-testing**, "what is at this point"
- later: driving verbs, and devbar plugins reporting into the run's tab strip

The install is a package dependency plus one line, and the panel says which
layer a run is on. A run without it is still fully inspectable — it just cannot
draw boxes on the picture.

This inverts the plan slice 3 started with. `installGuestRuntime` was going to
be a prerequisite; it is an enhancement, and it is not on the critical path.

### It would not have worked anyway

Worth recording, because the plan said "extract `installGuestRuntime`" as though
it were a porting job. `FrameCapture` is embedder-only end to end: a unix socket
carrying `CaptureMessage`/`CapturedMessage`, a `.rawframe` written to a
filesystem both processes share, and `native/host.c` arming the capture. None of
that reaches a phone. The screenshot had to be rebuilt for slice 3 whichever way
this probe came out.

## Method

Three throwaway scripts under `app/tool/`, deleted after. Reproduce with
`flutter run --machine`, take `wsUri` from the `app.debugPort` event, and drive
`package:vm_service` — `app/lib/src/embedder/guest_vm_service.dart` already
wraps everything used here.

Physical devices remain untested, as in S-L1 and S-L2. Nothing measured here is
plausibly transport-dependent — these are in-isolate calls — but "plausibly" is
the word doing the work.
