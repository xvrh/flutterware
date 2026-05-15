# Flutter embedder — Step 3a: live software-copy texture bridge

**Date:** 2026-05-15
**Status:** Approved design

## Long-term vision

A fast way to run Dart/Flutter code and display the result live inside the
flutterware desktop app, with hot reload. The host embeds the Flutter engine
directly and controls the renderer.

The staircase toward that goal:

- **Step 1 (done):** compile a hello-world to kernel and run it headless in the
  embedded engine; `print()` reaches stdout. Proved compile → kernel → engine.
- **Step 2 (done):** render a static `runApp` Flutter UI and capture it to a
  PNG, headless. Proved the rendering path — framework build, layout, the
  compositor, frame scheduling.
- **Step 3a (this spec):** display the embedded engine's live, animated,
  interactive output inside a flutterware GUI screen via an external `Texture`,
  using the software renderer plus a CPU copy through a shared `IOSurface`.
- **Step 3b (future):** switch the guest engine to the Metal renderer rendering
  directly into the shared `IOSurface` for a true zero-copy path.
- **Step 4 (future):** hot reload — the engine's VM service plus incremental
  `frontend_server` recompiles.

## Goal of step 3a

Prove the live cross-process display path end to end:

```
scene.dart --(engine + software renderer)--> RGBA frame
  --memcpy--> shared IOSurface --(host texture registrar)--> live Texture in the GUI
```

An animated `runApp` Flutter UI runs in an out-of-process embedded engine. Each
composited frame is copied into a shared `IOSurface`; the flutterware desktop
GUI displays it live in a `Texture` widget on a dev-harness screen. The panel is
resizable and forwards pointer and keyboard input to the guest, so the embedded
view is genuinely interactive. Software renderer only — no Metal, no hot reload.

## Key decisions

- **Out-of-process guest.** The flutterware GUI runs on `FlutterMacOS.framework`
  while the guest runs on `FlutterEmbedder.framework`. Each framework embeds its
  own Dart VM and Skia, and `Dart_Initialize` is effectively process-global, so
  loading both engine binaries into one process risks VM/symbol collisions.
  Running the guest as a separate process side-steps that, isolates crashes (a
  broken user scene cannot take down the GUI), and gives a clean restart path
  for hot reload later. The step-1/2 one-shot C host evolves into a long-lived
  guest process.
- **Software renderer + CPU copy.** Step 3a keeps the working software renderer.
  The guest's `surface_present_callback` `memcpy`s the composited RGBA buffer
  into a shared `IOSurface`. This proves the entire cross-process texture bridge
  — process spawn, surface sharing, the host texture registrar, resize, input —
  with zero new GPU code. Step 3b is then a small delta: the guest stops
  `memcpy`-ing and renders Metal directly into the same `IOSurface`.
- **Shared surface: `IOSurface`.** Pixels cross the process boundary through
  `IOSurface`s rather than POSIX shared memory. `IOSurface` is macOS-idiomatic,
  CPU-mappable, and wraps directly into a `CVPixelBuffer`
  (`CVPixelBufferCreateWithIOSurface`) — so the GUI side is already zero-copy
  and `copyPixelBuffer` simply returns the current wrapper. It is also exactly
  the surface 3b's Metal renderer will render into, keeping the 3a→3b delta
  small.
- **Triple-buffered surfaces.** Three `IOSurface`s in a ring: the guest renders
  into one, the GUI may be reading another, one is spare. This stays tear-free
  without tight cross-process locking. Frame-perfect synchronisation is left to
  step 3b.
- **Control channel: a Unix domain socket.** A dedicated bidirectional socket
  carries a framed protocol (surface handles, frame-ready notifications, resize,
  input, shutdown). Keeping it off stdout means the guest's Dart `print()`
  output stays clean, human-readable, and separately viewable — preserving the
  step-1/2 debugging affordance. The socket also carries the `IOSurface`
  identifiers needed to share surfaces across the process boundary (see Control
  protocol below).
- **GUI owns the guest lifecycle.** A dev-harness screen in the flutterware app
  (reachable when running via `main_dev.dart`) spawns and manages the guest. The
  orchestration logic in `tool/embedder/run.dart` (ensure framework, compile,
  spawn) moves into an app-side runtime class, `EmbeddedEngine`.
- **Native macOS plugin for the texture.** The host engine's
  `FlutterTextureRegistrar` is reachable only from a `FlutterPlugin` registered
  with the macOS `Runner`, not from Dart FFI. A small plugin
  (`EmbedderTexturePlugin`) registers the external texture and wraps the shared
  `IOSurface`s as `CVPixelBuffer`s.

## Components & boundaries

All paths are under `app/`.

### GUI side — Dart (`app/lib/src/embedder/`)

| Unit | Responsibility | Interface |
|---|---|---|
| `protocol.dart` | Pure codec for the framed control protocol — encode/decode every message type. No I/O. | `encode(Message) -> Uint8List`, `decode(...) -> Message` |
| `embedded_engine.dart` | GUI-side runtime. Owns the guest lifecycle: ensure `FlutterEmbedder.framework`, compile `scene.dart` → kernel, spawn the guest, hold the socket, drive resize/input, expose a `textureId` and a state. Absorbs `run.dart`'s orchestration. | A controller object with a state (`compiling`/`running`/`error`), a `textureId`, `resize()`, `sendPointer()`, `sendKey()`, `dispose()` |
| dev-harness screen | A screen reachable via `main_dev.dart`: a `Texture` wrapped in `Listener` + `Focus`, sized by a `LayoutBuilder` that drives resize. Shows engine state and the guest's log output. | A `Widget` |

`embedded_engine.dart` may be split further during implementation (e.g. a
`guest_process.dart` for spawn/socket plumbing) if it grows large.

### GUI side — native (`app/macos/Runner/`)

| Unit | Responsibility | Interface |
|---|---|---|
| `EmbedderTexturePlugin` (Swift/Obj-C) | A `FlutterPlugin` with access to the host engine's `FlutterTextureRegistrar`. Implements the `FlutterTexture` protocol (`copyPixelBuffer`). Looks up each shared `IOSurface` by ID and wraps it as a `CVPixelBuffer`. | A `MethodChannel`: `createTexture(surfaceIds) -> textureId`, `markFrameAvailable(textureId, ringIndex)`, `disposeTexture(textureId)` |

The plugin is registered alongside the app's generated plugins in the macOS
`Runner`.

### Guest side — C (`app/native/`)

The step-1/2 `host.c` evolves into a long-lived, socket-driven guest. As it
grows past one responsibility it is split into focused translation units:

| Unit | Responsibility |
|---|---|
| `host.c` | Engine lifecycle, the main loop, ties the pieces together. |
| `ipc.c` | Unix socket: connect, framed read/write, the wire protocol. |
| `surface.c` | `IOSurface` allocation, the triple-buffer ring, `memcpy` from the present callback, surface-ID export. |
| `input.c` | Translate protocol pointer/key messages into `FlutterEngineSendPointerEvent` and the engine's key-event calls. |

`CMakeLists.txt` adds the new sources and links `IOSurface` /
`CoreFoundation` frameworks. The build still produces a single `host`
executable.

### Shared contract

Two documented contracts are implemented on both sides of the process boundary:

- **The framed socket protocol** (see Control protocol below).
- **The `IOSurface` pixel format** — RGBA, the current logical dimensions, a
  ring of three surfaces.

Boundary summary: Dart owns the socket and the guest lifecycle; the native
plugin owns only the texture and the `IOSurface`→`CVPixelBuffer` wrapping. Per
frame, `FrameReady` arrives in Dart, which calls `markFrameAvailable` on the
plugin via the `MethodChannel` — one cheap call per frame.

## Control protocol

Framed, length-prefixed messages over the Unix domain socket. Shared
`IOSurface`s are identified by their global `IOSurfaceID` (a `uint32` from
`IOSurfaceGetID`); the GUI recreates a local reference with `IOSurfaceLookup`.
The IDs travel as ordinary fields in the `SurfacesAllocated` message — no
ancillary data or mach-port transfer is needed. (`IOSurfaceLookup` is
deprecated but functional within a login session; the non-deprecated mach-port
path is an option to revisit, not a 3a requirement.)

**Guest → GUI:**

- `Ready` — the engine has started.
- `SurfacesAllocated{generation, count, width, height, rowBytes, surfaceIds[3]}`
  — sent on startup and after every resize. The `generation` counter lets the
  GUI discard frames that reference superseded surfaces.
- `FrameReady{ringIndex, frameId}` — a frame is composited into ring slot
  `ringIndex`. `frameId` increases strictly monotonically.
- `Error{message}` — a fatal guest-side error.

**GUI → guest:**

- `Resize{width, height, pixelRatio}` — the guest re-sends
  `FlutterEngineSendWindowMetricsEvent`, re-allocates the three `IOSurface`s,
  and replies with a fresh `SurfacesAllocated`.
- `PointerEvent{phase, x, y, buttons, scrollDx, scrollDy, timestamp}`.
- `KeyEvent{type, physicalKey, logicalKey, modifiers, timestamp}`.
- `Shutdown` — the guest tears down the engine and exits.

## Data flow

1. The dev-harness screen opens → `EmbeddedEngine` ensures
   `FlutterEmbedder.framework` is present, compiles `scene.dart` → kernel,
   generates a socket path, spawns the guest, and accepts the connection.
2. The guest connects, starts the engine, allocates the three `IOSurface`s, and
   sends `Ready` followed by `SurfacesAllocated` (with the surface IDs).
3. Dart passes the surface IDs to the plugin via `createTexture` → the plugin
   registers the external texture and returns a `textureId` → the screen's
   `Texture` widget binds to it.
4. The animated scene presents continuously: each `surface_present_callback`
   `memcpy`s the composited RGBA into the back `IOSurface`, advances the ring,
   and sends `FrameReady`.
5. Dart receives `FrameReady` → calls `markFrameAvailable` on the plugin → the
   host engine pulls the current `CVPixelBuffer` via `copyPixelBuffer`.
6. A `LayoutBuilder` size change → `Resize` → the guest re-allocates surfaces →
   a new `SurfacesAllocated` → the plugin re-wraps and the GUI rebinds.
7. `Listener` / `Focus` events on the texture region → `PointerEvent` /
   `KeyEvent` → the guest feeds them to the engine.
8. The screen closes → `Shutdown` → the guest exits → Dart unregisters the
   texture and closes the socket.

## Error handling

- **Framework download or compilation failure** — `EmbeddedEngine` surfaces it
  as an `error` state on the harness screen; no guest is spawned.
- **Guest crashes or exits unexpectedly** — the socket closes; Dart detects EOF,
  moves to the `error` state, and unregisters the texture. The GUI process stays
  alive — the point of running the guest out-of-process.
- **Guest fails to start the engine** — the guest sends `Error` and exits; the
  message is surfaced on the harness screen.
- **Malformed or truncated protocol frame** — the codec throws a descriptive
  error; the receiver treats it as a fatal channel error and tears down.
- **Resize race** — frames composited against superseded surfaces are ignored:
  `SurfacesAllocated` carries a generation counter and `FrameReady` is matched
  against the current generation before `markFrameAvailable` is called.
- **`FlutterEmbedder.framework` download failures** — as in steps 1–2.

## Testing

- `app/test/embedder/protocol_test.dart` — **fast unit test**: round-trip every
  message type through `encode`/`decode`, and assert truncated or malformed
  frames are rejected. Runs in the default `flutter test`.
- `app/integration_test/embedder/live_bridge_test.dart` — **heavy integration
  test**: spawn the guest, accept the socket, assert `Ready` and
  `SurfacesAllocated` arrive, collect several `FrameReady` messages with
  strictly increasing `frameId` (proving continuous live frames), send a
  `Resize`, and assert a new `SurfacesAllocated` arrives with the new
  dimensions. No GUI or texture registrar needed — this exercises the guest and
  the wire protocol end to end.
- `app/integration_test/embedder/compiler_test.dart` and `flutter_cache_test.dart`
  — carried over from step 2, updated only if the scene entrypoint path changes.
- **Headless PNG smoke** — `tool/embedder/run.dart` is rebuilt as a thin
  protocol client: connect to a guest, capture one `IOSurface` frame, encode a
  PNG. This keeps a quick visual artifact and reuses the new harness. Step 2's
  raw-frame *file* format, `raw_frame.dart`, and `raw_frame_test.dart` are
  superseded by reading the `IOSurface` directly and are removed. Step 2's
  `render_test.dart` is replaced by `live_bridge_test.dart` above.
- **Manual** — run via `main_dev.dart`, open the harness screen, and confirm:
  the animated scene renders live, resizing the panel reflows the guest UI, and
  clicking and typing into the texture region reaches the embedded app.

The full GUI texture path (the native plugin plus the host registrar) is not
automatically testable and is covered by the manual check.

## Scene

`tool/embedder/scene.dart` becomes an **animated** `runApp` entrypoint (for
example a continuously spinning indicator or a ticking counter) so that frames
flow continuously through the bridge and the "live" path is genuinely
exercised. It also includes a simple interactive element (such as a button or a
hover/tap target) so manual input forwarding can be verified.

## Out of scope for step 3a (deferred)

- Metal / GPU rendering and a true zero-copy path — that is **step 3b**.
- Hot reload — **step 4**.
- Text input / IME (only raw pointer and key events are forwarded in 3a).
- Multiple simultaneous embedded engines.
- Frame-perfect cross-process synchronisation (triple-buffering is sufficient
  for 3a).
- Platforms other than macOS.
