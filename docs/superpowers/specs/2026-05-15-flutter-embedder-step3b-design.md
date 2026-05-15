# Flutter embedder — Step 3b: Metal renderer, zero-copy into shared IOSurfaces

**Date:** 2026-05-15
**Status:** Approved design

## Long-term vision

A fast way to run Dart/Flutter code and display the result live inside the
flutterware desktop app, with hot reload. The host embeds the Flutter engine
directly and controls the renderer.

The staircase toward that goal:

- **Step 1 (done):** compile a hello-world to kernel and run it headless in the
  embedded engine; `print()` reaches stdout.
- **Step 2 (done):** render a static `runApp` Flutter UI and capture it to a
  PNG, headless.
- **Step 3a (done):** display the embedded engine's live, animated, interactive
  output inside a flutterware GUI screen via an external `Texture`, using the
  software renderer plus a CPU copy through a shared `IOSurface`.
- **Step 3b (this spec):** switch the guest engine to the Metal renderer,
  rendering directly into the shared `IOSurface`-backed Metal textures — a true
  zero-copy path. No more per-frame `memcpy` or RGBA→BGRA swap.
- **Step 4 (future):** hot reload — the engine's VM service plus incremental
  `frontend_server` recompiles.

## Goal of step 3b

Replace the software renderer + CPU copy with the Metal renderer rendering
straight into the shared surfaces:

```
scene.dart --(engine + Metal renderer)--> GPU render into IOSurface-backed
  MTLTexture --(host texture registrar)--> live Texture in the GUI
```

The animated, interactive `runApp` scene, the resizable panel, and pointer/key
forwarding all keep working exactly as in 3a — only the guest's renderer and
surface backing change. The per-frame `memcpy` and the RGBA→BGRA channel swap
are deleted.

## Why this is a small delta

The 3a design deliberately chose `IOSurface` as the shared surface precisely so
3b would be a small, guest-side change. The GUI side already wraps each shared
`IOSurface` as a Metal-compatible `CVPixelBuffer`
(`kCVPixelBufferMetalCompatibilityKey`), and the host engine already composites
those buffers through a Metal texture cache. Those surfaces simply become
GPU-written instead of CPU-written; the wrapping is identical. So 3b touches:

- the guest's `FlutterRendererConfig` (`kSoftware` → `kMetal`),
- the guest's surface unit (IOSurfaces now also back `MTLTexture`s), and
- the guest's frame-completion signalling (a GPU fence replaces the implicit
  barrier the CPU `memcpy` used to provide).

The wire protocol, the GUI runtime (`embedded_engine.dart`), the wire codec
(`protocol.dart`), and the native plugin (`EmbedderTexturePlugin.swift`) are
unchanged.

## Key decisions

- **Metal renderer, no compositor.** The guest sets
  `FlutterRendererConfig.type = kMetal` and registers
  `get_next_drawable_callback` / `present_drawable_callback` — the
  non-`FlutterCompositor` path. The guest creates one system-default
  `MTLDevice` and one `MTLCommandQueue` and passes them in the config as
  `device` and `present_command_queue`.
- **IOSurface-backed Metal textures.** Each ring `IOSurface` also backs an
  `id<MTLTexture>` created with
  `[MTLDevice newTextureWithDescriptor:iosurface:plane:]`,
  `MTLPixelFormatBGRA8Unorm`, usage `MTLTextureUsageRenderTarget`. The
  `IOSurface` pixel format stays `'BGRA'`, so Metal renders the surface's
  native format directly — the RGBA→BGRA swap from 3a's software path is
  deleted.
- **GPU completion fence before `FrameReady`.** With the software renderer the
  `memcpy` itself was the synchronisation: when the present callback returned,
  the pixels were fully written. With Metal the engine submits GPU work and may
  invoke `present_drawable_callback` before the GPU has finished writing the
  `IOSurface`; the GUI process then composites that same surface through its
  own Metal device, and without a barrier could sample a half-rendered frame.
  In `present_drawable_callback` the guest commits a trivial empty command
  buffer on `present_command_queue` and sends `FrameReady` from that buffer's
  `addCompletedHandler`. Because the engine submits its render commands on the
  same in-order `present_command_queue`, the empty buffer completes strictly
  after the render — so `FrameReady` is sent only once the frame is fully on
  the surface. (Considered and rejected: sending `FrameReady` synchronously
  with no fence — risks tearing; a cross-process `MTLSharedEvent` — more
  rigorous but significantly more complex than warranted here.)
- **Deferred ring release on resize.** A resize between `get_next_drawable` and
  `present_drawable` must not free a texture the engine is still rendering
  into. `surface_ring_init` allocates a fresh ring but does not free the
  outgoing one; the outgoing ring is *retired* and released only once a frame
  has been presented against the new ring. At most one retired ring is held at
  a time.
- **`surface.c` → `surface.m`.** Creating `MTLTexture`s and command buffers
  requires Objective-C, so the surface translation unit becomes Objective-C
  (compiled with ARC). It is the natural home for all of: the shared
  `MTLDevice` + `MTLCommandQueue`, the ring of *(IOSurface, MTLTexture)* pairs,
  the present fence, and the retired-ring release. `host.c` stays plain C — the
  Metal handles in `FlutterMetalRendererConfig` are `const void*` aliases, so
  C can register the callbacks and pass the handles through without touching
  Objective-C.
- **No software-renderer fallback.** The software path is replaced outright, not
  kept behind a flag. (The repo's guidance is to avoid feature-flag and
  backwards-compatibility shims.)
- **Headless smoke kept via IOSurface readback.** The software path gave the
  capture code a raw CPU pointer (`allocation`). Metal has no such pointer, so
  under `--capture-raw` the guest `IOSurfaceLock`s the just-presented surface
  inside the fence's completion handler (the GPU is finished by then) and reads
  its pixels back into the step-2 raw-frame file. The readback runs only when
  `--capture-raw` is passed, so it costs nothing in normal operation. The raw
  file's pixel order changes from RGBA to BGRA, since Metal renders BGRA
  directly into the surface.

## Components & boundaries

All paths are under `app/`.

### Guest side — C / Objective-C (`app/native/`)

| Unit | Responsibility | Change in 3b |
|---|---|---|
| `host.c` (C) | Engine lifecycle, main socket loop, ties the pieces together. | Renderer config becomes `kMetal`; registers `get_next_drawable_callback` and `present_drawable_callback`; `PresentSoftware` deleted. Resize handling, socket loop, lifecycle otherwise unchanged. |
| `surface.m` (Obj-C, ARC) — was `surface.c` | The shared `MTLDevice` + `MTLCommandQueue`; the ring of *(IOSurface, MTLTexture)* pairs; the present fence; retired-ring release. | New file (renamed). `surface_ring_present(rgba,…)` removed; new functions added (see below). |
| `ipc.{c,h}` (C) | Unix socket: connect, framed read/write, wire protocol. | Unchanged. |
| `input.c` (C) | Translate protocol pointer/key messages into engine calls. | Unchanged. |
| `CMakeLists.txt` | Build the single `host` executable. | `surface.m` replaces `surface.c`, compiled with `-fobjc-arc`; links `-framework Metal` in addition to the existing frameworks. |

`surface.h` interface after 3b (names indicative; finalised during planning):

- `bool surface_ring_init(int width, int height)` — allocates the shared
  device/queue on first call, then a fresh ring of *(IOSurface, MTLTexture)*
  pairs; retires (does not free) any previous ring. Returns false on failure.
- `void surface_ring_destroy(void)` — releases the current and any retired ring.
- `const void* surface_metal_device(void)` — the `MTLDevice` handle for the
  renderer config.
- `const void* surface_metal_queue(void)` — the `MTLCommandQueue` handle for
  `present_command_queue`.
- `const void* surface_ring_texture(int slot)` — the `MTLTexture` handle for a
  ring slot, handed to the engine from `get_next_drawable_callback`.
- `int surface_ring_acquire(void)` — the slot index the engine should render
  into next (the current `g_next`); does not advance.
- `void surface_ring_present(int slot)` — advances the ring and releases any
  retired ring now that a frame has been presented against the current one.
- `void surface_ring_present_fence(int slot, void (*on_done)(int slot))` —
  commits an empty command buffer on `present_command_queue`; invokes `on_done`
  from its completion handler.
- `surface_ring_ids`, `surface_ring_width`, `surface_ring_height`,
  `surface_ring_row_bytes` — unchanged from 3a.
- A capture-readback helper used under `--capture-raw`: `IOSurfaceLock`s a slot
  and exposes its base address + stride so `host.c` can write the raw file.

(The exact split of `surface_ring_present` vs `surface_ring_present_fence` and
their signatures may be refined during planning, as long as the contract holds:
the ring advances on present, the retired ring is released after a present
against the new ring, and `FrameReady` is emitted from the GPU completion
handler.)

### GUI side — Dart and native

Unchanged. `protocol.dart`, `embedded_engine.dart`, the dev-harness screen, and
`EmbedderTexturePlugin.swift` are not modified. The plugin already wraps each
shared `IOSurface` as a Metal-compatible `CVPixelBuffer`; those surfaces are now
GPU-written rather than CPU-written, but the wrapping path is identical.

## Wire protocol

Unchanged from 3a. `SurfacesAllocated{generation, count, width, height,
rowBytes, surfaceIds[3]}` and `FrameReady{ringIndex, frameId, generation}` keep
their exact layouts; `Resize`, `PointerEvent`, `KeyEvent`, `Shutdown`, `Ready`,
`Error` are unchanged. `rowBytes` remains informational on the GUI side (the
`CVPixelBuffer` reads the real stride from the `IOSurface`).

## Data flow

1. Startup: the guest creates the `MTLDevice` and `MTLCommandQueue`, allocates
   the ring of *(IOSurface, MTLTexture)* pairs, starts the engine with the
   `kMetal` renderer config, and sends `Ready` then `SurfacesAllocated` — as in
   3a.
2. Per frame, on the engine raster thread:
   1. The engine calls `get_next_drawable_callback` → the guest returns the
      current ring slot's `MTLTexture` in a `FlutterMetalTexture`
      (`texture_id` = slot index, `destruction_callback` = NULL — the guest owns
      the ring).
   2. The engine renders the composited frame into that IOSurface-backed
      `MTLTexture`, submitting its command buffer on `present_command_queue`.
   3. The engine calls `present_drawable_callback` → the guest reads the slot
      from `texture_id`, advances the ring, releases any retired ring, and
      commits an empty command buffer on `present_command_queue`.
   4. The empty buffer's `addCompletedHandler` fires after the GPU finishes the
      render → the guest sends `FrameReady{ringIndex = slot, frameId,
      generation}`. Under `--capture-raw`, the handler also `IOSurfaceLock`s the
      slot once and writes the raw BGRA frame file.
3. The GUI receives `FrameReady` → `markFrameAvailable` → the host engine
   composites the `IOSurface` directly — zero copy, no `memcpy`, no channel
   swap.
4. Resize: `surface_ring_init` allocates fresh surfaces + textures, retires the
   old ring, bumps `generation`, and sends a new `SurfacesAllocated`; the
   retired ring is released after the next present against the new ring.
   Generation gating discards frames composited against superseded surfaces, as
   in 3a.
5. Shutdown: `Shutdown` → the guest releases the ring (current + retired) and
   exits.

## Error handling

Carried over from 3a, plus new Metal-specific failure modes:

- **`MTLCreateSystemDefaultDevice()` returns nil** — the guest sends `Error` and
  exits; the message is surfaced on the harness screen. (No GPU device is rare
  on macOS but possible in restricted environments.)
- **`newTextureWithDescriptor:iosurface:` fails** — treated like an
  `IOSurface` allocation failure: the guest sends `Error` and exits before the
  engine starts, or fails the resize and keeps the existing ring.
- **Resize race against an in-flight texture** — handled structurally by the
  deferred ring release: the engine's in-flight texture (held between
  `get_next` and `present`) belongs to a ring that is retired, not freed, until
  a frame is presented against the new ring.
- All 3a modes (framework download/compile failure, guest crash/EOF, malformed
  frame, generation-gated resize race) are unchanged.

## Testing

- `app/test/embedder/protocol_test.dart` — **unchanged**; the wire format does
  not change.
- `app/integration_test/embedder/live_bridge_test.dart` — **unchanged**, but now
  exercises the Metal path end to end: spawn the guest, assert `Ready` and
  `SurfacesAllocated`, collect several `FrameReady` messages with strictly
  increasing `frameId`, send a `Resize`, assert a fresh `SurfacesAllocated`.
  Metal device creation works headlessly on macOS, so this still runs without a
  display.
- `app/test/embedder/raw_frame_test.dart` and `raw_frame.dart` — **updated** for
  BGRA byte order (the raw capture file changes from RGBA to BGRA).
- **Headless PNG smoke** — `tool/embedder/run.dart` still spawns a guest with
  `--capture-raw`, awaits the first `FrameReady`, reads the raw file, and
  encodes a PNG; it swaps BGRA→RGBA when encoding. This keeps an automated
  visual artifact, important because screenshots cannot be captured in the
  agent environment.
- `app/integration_test/embedder/compiler_test.dart` and `flutter_cache_test.dart`
  — carried over unchanged.
- **Manual** — run via the GUI harness and confirm: the animated scene renders
  live, resizing the panel reflows the guest UI, clicking and typing into the
  texture region reaches the embedded app, and the macOS console shows no
  Metal/`IOSurface` errors or tearing.

The full GUI texture path remains covered by the manual check.

## Key risk

The fence is correct only if the engine submits its render command buffer on
the `present_command_queue` the guest provides — so that the guest's empty
command buffer, committed on the same in-order queue, completes strictly after
the render. The macOS Metal embedder does submit on `present_command_queue`;
implementation must confirm this early, because it is load-bearing for
tear-free frames. If it ever did not hold, `FrameReady` could be sent before
the GPU finished and the GUI could sample a partial frame.

## Out of scope for step 3b (deferred)

- Hot reload — **step 4**.
- Text input / IME (only raw pointer and key events are forwarded).
- Multiple simultaneous embedded engines.
- Frame-perfect cross-process synchronisation beyond the completion-handler
  fence (triple-buffering plus the fence is sufficient for 3b).
- Platforms other than macOS.
