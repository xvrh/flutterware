# The embedder guest on Linux — what a spike proved, and the port it implies

**Date:** 2026-08-28
**Status:** Spike done, every number below measured this session on this
machine (Ubuntu 24.04, Wayland, Intel Iris Xe / Mesa 25.2.8, Flutter
3.48.0-0.2.pre, engine `c890f62b`). Phase 1 is built on top of it — see **Phase
1, as built** at the end for what landed and what is blocked.

**Context:** the studio GUI and the previews daemon run on Linux (#286), and
`previews screenshot`/`inspect` render under `flutter_tester` (#287), so the
lane an agent uses most no longer needs a guest. What is still macOS-only is
the guest itself — `app/native/` embeds `FlutterEmbedder.framework`, renders
with Metal into `IOSurface`s and hands them to a Swift `FlutterTexture`
plugin. This is what remains between here and a Linux studio that does
everything.

## What is dark on Linux today

Everything downstream of `EmbeddedEngine`:

- **The live previews panel** (`CatalogSession`) — the interactive catalog in
  the GUI. This is the big one.
- **Motion** — `motion_core.dart:340` captures through `HeadlessCatalog`,
  which is guest-only.
- **`previews screenshot --engine=guest`** and **`--logs`**, which only the
  guest can collect.
- **Window capture** of a panel showing a guest (`window_capture.dart`), and
  `main_embedder_dev.dart`.
- **`app/test/previews/lane_parity_test.dart`**, which needs both lanes and so
  cannot run here at all.

The failure is upstream of any of it: `ensureEmbedderFramework`
(`embedder_build.dart`) builds a `darwin-x64/FlutterEmbedder.framework.zip`
URL unconditionally, and `app/native/CMakeLists.txt` links
`-framework FlutterEmbedder -framework Metal -framework IOSurface`.

## Findings

**1. The artifact exists, for every host we might want.** `HTTP 200` on
`linux-x64/linux-x64-embedder.zip`, `linux-arm64/...` and
`windows-x64/...` at the pinned engine revision. The Linux zip is **15MB**
and unpacks to **43MB**: `libflutter_engine.so` and `flutter_embedder.h`,
nothing else — no framework directory, no rpath ceremony beyond
`-Wl,-rpath`. (macOS's is 93MB.) The shipped header is
`FLUTTER_ENGINE_VERSION 1`, same as the vendored
`app/native/flutter_embedder.h`, which is 33 lines behind it and otherwise
compatible.

**2. A surfaceless EGL guest renders the real scene, first try.** A ~200-line
C spike — `eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA)`, a GLES3
context, an FBO-backed `GL_RGBA8` texture, `FlutterRendererConfig.type =
kOpenGL` — ran `tool/embedder/scene.dart`'s kernel and produced the animated
scene with real fonts and real Material colors at 800×600. The engine
announced itself:

```
[IMPORTANT:embedder_surface_gl_impeller.cc(129)] Using the Impeller rendering backend (OpenGLES).
```

`ipc.c` and `input.c` need no change for this: they are plain POSIX and
`FlutterEngineSend*Event`.

**3. It works with no display, and with no GPU.** Same spike with `DISPLAY`,
`WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` unset: 41 frames on the Intel GPU.
With `LIBGL_ALWAYS_SOFTWARE=1` as well: 40 frames on llvmpipe. **CI needs
neither a seat nor a card** — surfaceless EGL falls back to software on its
own and the engine cannot tell.

**4. Readback is affordable, and it is the whole cost of the simple path.**
`glReadPixels` straight off the engine's FBO, on the raster thread, steady
state:

| size | per frame |
| --- | --- |
| 800×600 | **~2.0ms** |
| 1600×1200 | **~4.5ms** |
| 2400×1600 | **~7.0ms** |

At a 60fps budget of 16.7ms that leaves room at every panel size we render,
and it is the only per-frame cost the copy path adds on the guest side. The
GUI side pays a `glTexImage2D` of the same bytes on the studio's own raster
thread.

**5. Zero-copy is reachable — proven across two processes.** A second probe
rendered red into a GL texture, `eglCreateImage(EGL_GL_TEXTURE_2D)` +
`eglExportDMABUFImageMESA` to get an fd, sent it over a `socketpair` with
`SCM_RIGHTS`, and in a **forked process with its own EGLDisplay** imported it
with `EGL_LINUX_DMA_BUF_EXT` + `glEGLImageTargetTexture2DOES` and read the
centre pixel back as `255,0,0,255`:

```
parent: planes=1 fourcc=AB24 stride=1024 offset=0 mod=100000000000001
child:  centre pixel = 255,0,0,255       ZERO-COPY OK
```

Both `EGL_MESA_image_dma_buf_export` and `EGL_EXT_image_dma_buf_import`
(+`_modifiers`, needed — Intel exported `I915_FORMAT_MOD_X_TILED`, not
linear) are on this display.

**6. Flutter's own Linux GL is EGL, which is what makes the last hop
plausible.** `libflutter_linux_gtk.so` imports `epoxy_eglGetPlatformDisplayEXT`,
`epoxy_eglCreateContext`, `epoxy_eglCreateImageKHR` and
`epoxy_glEGLImageTargetTexture2DOES`, and carries an `FlEGLImage` type — the
engine builds its own EGL context rather than borrowing GDK's, so it is EGL
on X11 as well as Wayland, and it already does EGLImage binding internally.
`FlTextureGL::populate` is documented to run with *that* context current, so
a dmabuf import belongs inside it. **Unproven:** the probe used our own
EGLDisplay on both ends, not Flutter's. That is the one hop left.

**7. But dmabuf export is a Mesa extension.** `EGL_MESA_image_dma_buf_export`
is not in NVIDIA's proprietary EGL. A guest on that driver cannot export at
all, so a copy path has to exist regardless of what the fast path does.

**8. The public GTK texture API is exactly two classes.**
`fl_pixel_buffer_texture.h` (`copy_pixels` → an RGBA CPU buffer, called on the
render thread, `width`/`height` inout so resize is expressible) and
`fl_texture_gl.h` (`populate` → target + texture name). Note **RGBA**, where
the macOS ring is BGRA. `app/linux/runner/CMakeLists.txt` is the place to add
a plugin source, and `my_application.cc` already calls `fl_register_plugins`
next to where ours would register — the same shape as
`MainFlutterWindow.swift`.

**9. The two lanes may not agree on a rasterizer here, and the parity test
will not say so.** The guest's `kOpenGL` config forces
`--impeller-backend=opengles`; `rasterizerArguments` (`tester_host.dart:686`)
names a backend only on macOS, so `flutter_tester` on Linux takes the
engine's default — which printed no backend line when run directly, so it is
*not* established what it picks. `lane_parity_test.dart` compares layout and
complaints, explicitly not pixels, so a Vulkan-vs-GLES difference passes it.
Worth settling once the guest exists; the cheap fix if it matters is to name
`opengles` on Linux in `rasterizerArguments` too.

## The port

Two phases, because finding 7 makes the copy path mandatory anyway and
finding 5 makes the fast path a later addition rather than a rewrite.

### Phase 1 — a guest that renders, and a texture that shows it

**Make the artifact platform-neutral.** `embedder_build.dart`:
`embedderFrameworkDir`/`ensureEmbedderFramework` stop naming a framework
(`embedderEngineDir`/`ensureEmbedderEngine`), pick the artifact per host
(`darwin-x64/FlutterEmbedder.framework.zip` vs
`<os>-<arch>/<os>-<arch>-embedder.zip`), and keep the stamp-and-rename dance
as is — it is already the right shape. `removeLegacyEngineDir` stays macOS's
business. `resolveExecutable`'s fallback list gains nothing on Linux
(`/usr/bin/which` already answers) but its error text should stop claiming
`flutter run` on macOS is why. `FlutterCache.icuData` drops `darwin-x64` for
`_hostEngineDir`, which makes it the same expression as `testerIcuData` —
merge them.

**Split the surface unit.** `native/surface.h` is already the seam: a ring,
init/destroy, per-slot handles, lock/unlock for readback, a present fence.
Keep the header, add `surface_linux.c` beside `surface.m` and let
`CMakeLists.txt` pick — the ring becomes three mmap'd files under
`/dev/shm`, the "Metal device/queue" accessors collapse to the EGL display
and contexts, and `surface_present_fence` becomes `glFinish` +
`glReadPixels` into the current slot followed by the callback. The
`--capture-raw` path (`WriteRawCapture`) works unchanged on top of
`surface_lock`.

**Branch `host.c` at the renderer config only.** `kMetal` +
`get_next_drawable`/`present_drawable` on macOS; `kOpenGL` +
`make_current`/`clear_current`/`make_resource_current`/`fbo_callback`/`present`
on Linux, with `--enable-impeller --impeller-backend=opengles
--enable-flutter-gpu`. The socket loop, resize handling, capture arming and
`SendWindowMetrics` are all platform-free and stay put. The
`FW_SOFTWARE_RENDERING` escape hatch keeps working — it just also has
`LIBGL_ALWAYS_SOFTWARE` available underneath it.

**Give a surface a name instead of an id.** `SurfacesAllocatedMessage`
carries `List<int> surfaceIds` — `IOSurfaceID`s. Widen the wire entry to a
length-prefixed UTF-8 string: macOS writes the id as decimal and the Swift
plugin parses it, Linux writes the `/dev/shm` path. Dart passes strings
through the channel and otherwise does not change; `EmbeddedEngine`,
`FrameReadyMessage` and the generation/ring logic are untouched. Both halves
ship together, so there is no compatibility window to keep.

**Write the GTK plugin.** `app/linux/runner/embedder_texture_plugin.cc`, an
`FlPixelBufferTexture` subclass over the mmap'd ring, answering the same four
methods on the same `flutterware/embedder_texture` channel
(`createTexture`/`updateSurfaces`/`markFrameAvailable`/`disposeTexture`).
Register it from `my_application.cc` after `fl_register_plugins`. Watch the
byte order: the ring must be RGBA here where macOS's is BGRA, and the cheapest
place to settle that is `glReadPixels(GL_RGBA)` in the guest.

**Gate on the tests that already exist.** `lane_parity_test.dart` running
green on Linux is the acceptance criterion — it is the one test that needs
both lanes, and it is currently unrunnable here. Then
`integration_test/embedder/live_bridge_test.dart` and the live panel by hand
through `main_embedder_dev.dart`.

### Phase 2 — zero-copy, negotiated

Only worth starting once Phase 1 is green, and only as an upgrade the guest
can decline (finding 7).

The guest probes for `EGL_MESA_image_dma_buf_export` at ring init; if it is
there it exports each slot and announces the ring as dmabuf rather than shm.
The fds cannot go over the control socket — Dart has no `SCM_RIGHTS` — so the
C plugin opens a second `AF_UNIX` socket of its own, and Dart only carries its
path. The plugin's texture becomes an `FlTextureGL` whose `populate` imports
the slot's `EGLImage` into Flutter's context, which is where finding 6 says it
belongs and where the one unproven hop gets proven.

## Out of scope, but named

`flutterware/window` (`window_title.dart`) and `flutterware/clipboard`
(`image_clipboard.dart`) are the other two method channels with no Linux
implementation. Both are gated behind an `isSupported` that returns false
rather than throwing, so neither blocks anything — but a Linux studio that
cannot copy a preview to the clipboard is a gap somebody will notice, and it
is a third small GTK plugin in the same file the embedder texture one lands
in.

---

## Phase 1, as built

Written the same day as the findings above. **The guest half is done and
proven; the GUI half is written, renders, and dies on a panel resize inside the
engine.**

### What works, end to end

`dart run app/tool/embedder/run.dart` on Linux downloads `linux-x64-embedder.zip`,
compiles the scene, builds the C host and writes `scene.png` — the real
pipeline, the real colours, the right way up. The live previews panel comes up
in the studio too: the guest renders the demo, the frames cross into the GUI's
texture, and the panel shows them.

Landed for it:

- **`embedder_build.dart`** picks the artifact per host and stops naming a
  framework (`ensureEmbedderEngine`, `embedderEngineDir`, `embedderEngineMarker`).
  `FlutterCache.icuData` and `testerIcuData` merge into one expression, which
  also fixes a tester spawned on Linux against the macOS `icudtl.dat`.
- **`native/surface_gl.c`** implements `surface.h` on surfaceless EGL: an FBO
  the engine renders into, three `/dev/shm` mappings it is read back into, and
  names retired a generation late so a resize cannot pull a name out from under
  a GUI that has not opened it yet.
- **`native/host.c`** branches at the renderer config and nowhere else. The
  socket loop, resize, capture and window metrics are written once.
- **The wire** carries a ring slot as a length-prefixed string, so an
  `IOSurfaceID` and a shared-memory name are the same message; and the raw
  frame header carries a **pixel order** word, because the Metal ring is BGRA
  and the GL one is RGBA. That word is not cosmetic: without it the first Linux
  frame came out perfect in every respect but colour, blue rendered orange.
- **`app/linux/runner/embedder_texture_plugin.cc`** serves the same four methods
  on the same channel as the Swift plugin.

One bug fell out that was not Linux's: `ensureEmbedderEngine`'s
"another process got there first" branch trusted the revision stamp alone, so
the first Linux run on a machine that had ever run the macOS code downloaded the
Linux engine, found a stamped `FlutterEmbedder.framework` in the way, and kept
it. It now applies the same completeness test it would have returned on.

### The blocker, and what it turned out to be

**It is not the resize, and it is not the texture plugin. It is the
screenshot.** Every `flutterware_act` step photographs the app with
`OffsetLayer.toImage` (`lib/src/drive/guest_drive.dart`), and on this engine
build that call segfaults when the layer tree contains an external texture
whose cached image has to be re-resolved. A resize is simply what invalidates
that cache.

The symptom that hid it: open a live demo, widen the panel, and a second later
the studio dies with `SIGSEGV` — no Dart error, "Lost connection to device".
The fault is entirely inside `libflutter_linux_gtk.so`, and it is byte-identical
across every variation below.

| Suspected | Test | Result |
| --- | --- | --- |
| Our mapping's lifetime | Never unmap anything, ever | Same crash |
| Our buffer at all | Hand the engine plugin-owned memory copied from the ring | Same crash |
| `FlPixelBufferTexture` | Reimplement as `FlTextureGL`, uploading ourselves | Same crash, same address |
| Anything in our plugin | Trace `populate` entry and exit | It **returns** before the fault |
| The stage's own chrome | Refuse `createTexture`, so no texture is ever registered | **No crash** — the panel opens fine |
| A name whose size changed | A fresh `glGenTextures` per size | Same crash |
| Re-pointing a live texture | Dispose and re-create the texture on every resize | Survived one resize, died on the third |
| **The drive screenshot** | **Make `_screenshot` return null, hot reload, resize** | **No crash — resize after resize** |

The last row is the answer, and it was checked both ways in one session:
screenshot off, two real resizes survived; screenshot restored by hot reload,
the very next resize died with the identical backtrace.

### Reading a stripped engine

Flutter publishes no symbols for `linux-x64` — `symbols.zip` and every spelling
of it 404 at the pinned revision, and `libflutter_linux_gtk.so` is stripped down
to 253 exported `fl_*` entries. That is still enough, and the way through is
worth writing down because it took one run:

`app/linux/runner/crash_report.cc` (gated on `FW_CRASH_REPORT=1`) installs a
`SIGSEGV` handler that prints `si_addr`, the whole register file from the
`ucontext`, the load address of every mapped object, and each backtrace frame as
`<module>+<offset>`. `objdump -d --start-address=<offset>` then reads the
faulting instruction and its callers straight out of the shipped `.so`. No local
engine build, no debugger, no ptrace permission.

What it said:

```
signal 11 code 1 addr 0000000000000000 thread "io.flutter.rast"
RDI 0000000000000000   RIP <libflutter_linux_gtk.so+0x1e4aa1a>
```

and at that offset:

```
1e4aa10: push %r14; push %rbx; push %rax
1e4aa14: mov %rsi,%rbx      ; arg2 — a 64-byte struct the caller just zeroed
1e4aa17: mov %rdi,%r14      ; arg1 — `this`
1e4aa1a: mov (%rdi),%rax    ; load the vtable off a NULL `this`
1e4aa1d: call *0x40(%rax)
```

A virtual call on a null object. Its caller picks which of two resolvers to
call, and from which field:

```
1bf3e4e: mov 0x8(%r12),%rcx     ; ctx->gr_context
1bf3e53: mov 0x10(%r12),%rax    ; ctx->aiks_context
1bf3e8e: test %rax,%rax
1bf3e91: je   1bf3e9d           ; no aiks_context → the Skia resolver…
1bf3e9d: call 1bf45d0           ; …with rcx, which is NULL
```

`0x8` and `0x10` are `gr_context` and `aiks_context` of
`flutter::Texture::PaintContext`, and `r15` holds four floats the code subtracts
into a width and a height — the `paint_bounds()` that `TextureLayer::Paint`
passes. So the frame is `EmbedderExternalTextureGL::ResolveTexture`, reached from
`TextureLayer::Paint`, with **both** contexts null.

### Why both contexts are null

`OffsetLayer.toImage` lands in `Picture::RasterizeToImage`, which flattens the
retained layer tree:

```cpp
auto aiks_context = is_impeller_enabled ? snapshot_delegate->GetAiksContext()
                                        : nullptr;
snapshot_display_list = layer_tree->Flatten(
    DlRect::MakeWH(width, height),
    snapshot_delegate->GetTextureRegistry(),
    is_impeller_enabled ? nullptr : snapshot_delegate->GetGrContext(),
    aiks_context.get());
```

Both arms of that ternary hand `Flatten` a null: whichever branch is taken, the
other context is `nullptr` **by construction**. The registers say both were —
`aiks_context` because the code took the `je`, `gr_context` because `rcx` was
`0`. Which of the two produced it is not settled by the disassembly: either
`is_impeller_enabled` reads false here and `GetGrContext()` is null because
there is no Skia context under Impeller, or it reads true and
`GetAiksContext()` returns null on this shell. Naming which needs a symbolized
build; it does not change what to do about it.

Two upstream faults, not one:

1. A snapshot on this shell reaches `Flatten` with no usable context, so it
   cannot resolve an external texture at all.
2. `ResolveTexture` does not guard the fallback. Current master reads
   `else if (context)`, which would return `nullptr` and draw nothing; the
   pinned build has no such test — the disassembly above dereferences `rcx`
   with no `test` before it.

Fault 2 is what turns a blank rectangle into a crash. **macOS never sees
either**: the same `toImage` there already returns a fully transparent rectangle
where a guest panel is, which `app/lib/src/embedder/README.md` has documented
all along as the reason a picture of a panel and its guest is two captures
composited. Linux does not return the hole. It dies.

### What this changes

The Linux panel is **not** a demo you must not resize. It renders, it resizes,
and it survives — measured, repeatedly, with the drive screenshot off. What
cannot happen is `OffsetLayer.toImage` over a tree holding a `Texture`, which in
this repository means:

- the drive guest's per-step screenshot — every `flutterware_act` call;
- `window_capture.dart`, capturing a panel that shows a guest;
- anything else that rasterises the retained tree while a guest is on screen.

So the studio is usable on Linux by a human today and unusable by an agent,
which is the wrong way round for this repository.

### The workaround that landed

The picture that path produces is worthless anyway — a transparent hole on
macOS — so the fix keeps the external texture out of the snapshot rather than
making the snapshot draw it.

- **`lib/src/offscreen_raster.dart`** (`package:flutterware`) is the notice:
  `OffscreenRaster.around(raster)` raises a flag, spends **one frame** on it,
  and only then rasters. The frame is the whole point — `toImage` reads the
  tree the *last* frame left behind, so raising the flag and rastering in the
  same turn photographs the texture regardless. It is forced when the window is
  hidden, which is the state a studio is in for the whole of a drive session,
  and skipped entirely when nothing is watching, so an app with no external
  texture pays nothing.
- **`app/lib/src/embedder/guest_texture.dart`** watches it. `GuestTexture` is
  a `Texture` that stays out of the *layer* tree while a raster is up, and it
  is now the only way this application mounts one — the catalog stage, the
  motion stage and the embedder harness all go through it.

  **It withholds a paint, not a widget, and that distinction was measured.**
  The first cut swapped the `Texture` for a placeholder through a
  `ValueListenableBuilder`, which works and flickers: every human click in a
  live preview ends a burst the recorder photographs, and a rebuilt `Texture`
  is a *newly registered* external texture that the compositor resolves to
  black for one frame. The frame that goes away is not the visible one — the
  stage paints its own ground behind the guest, so withholding reads as an
  ordinary empty panel — the frame that comes *back* is. So the `TextureBox` is
  now built once and never destroyed: a `RenderProxyBox` skips painting it and
  the notice invalidates a repaint, nothing more. A test pins the identity of
  that render object across a raster, because the property is invisible to
  anything that only checks the picture.
- **Both rasters** are wrapped: the drive guest's per-step screenshot
  (`lib/src/drive/guest_drive.dart`) and `WindowCapture`. The latter also had
  to start reading its texture rectangles *before* the raster rather than
  after, because by then there is no `TextureBox` left to ask.

Measured after: the same drag that killed the studio twice — live demo open,
sidebar divider dragged, drive screenshots on — survives, along with demo
switches and further resizes, with the crash handler armed and silent.

The picture an agent gets of a live panel is a flat rectangle where the guest
is. That is not new and not a Linux fact: the drive screenshot has always
returned the hole on macOS too, and the composited picture is `WindowCapture`.

### What is left

1. **File both upstream faults** with the disassembly above: a snapshot that
   reaches `Flatten` with no usable context on this shell, and a
   `ResolveTexture` fallback that dereferences it without a null check.
2. **Delete the workaround when the engine stops needing it.** It is one file
   in each package plus three call sites, and both files say so at the top.
3. **`crash_report.cc` stays** until 1 lands, gated on `FW_CRASH_REPORT=1`. It
   cost one run to write and one run to use, against a session of elimination
   that ruled out six innocent things.

### What a review of it found

Run over the branch after the workaround landed. Three of these are not about
the workaround at all — they are in the guest that had been declared finished,
and two of them were leaks nobody would have seen until a machine ran out of
something.

- **`/dev/shm` was never reclaimed.** `EmbeddedEngine.dispose` sends `Shutdown`
  and then immediately `kill`s the guest, which installs no signal handler — so
  `surface_ring_destroy`, the only place that unlinks, almost never ran. A
  POSIX shared-memory object outlives its process. **Measured on this machine
  after one session of ordinary work: 49 stranded objects, 236MB**, and a
  crashed guest leaked the same way. The plugin now unlinks each name the
  moment it has it mapped, which is the only point both halves are provably
  done with it and which covers a crash as well as a clean stop. Re-measured
  after the fix, with three guests live and rendering: **zero**.
- **Every closed panel stranded a GL texture.** `FlTextureGL` does not own the
  name `populate` hands it, and nothing deleted it — 7.7MB of VRAM at
  1600×1200 per panel, plus one more per resize. Names are now parked on a
  plugin-wide list and deleted by whichever texture paints next, because the
  texture that gives a name up is often the one being disposed and `populate`
  is the only place with the GL context current.
- **`g_mutex_clear` sat in `dispose`**, which GObject may run twice; moved to
  `finalize`.
- **The flip scratch was allocated after the ring was committed**, and
  `surface_gl_readback` answers a missing scratch by returning early — which
  publishes the slot upside down. It is allocated with the ring now and fails
  with it.
- **A refused remap was silent** on both sides; it now says so, because a panel
  frozen at its old size looks like nothing in particular from Dart.
- **`OffscreenRaster.around` was not reentrant.** This process holds two
  rasters and serialises neither, so the inner one's `finally` put the texture
  back under the outer one — the crash again, intermittently and blaming the
  wrong caller. Counted now, with a test.
- **The hidden-window test tested nothing.** `platformDispatcher.onBeginFrame =
  null` leaves `framesEnabled` true, so the forced-frame branch — the one the
  whole workaround depends on during a drive session — was never taken, and
  deleting it left every test green. It drives `AppLifecycleState.hidden` now
  and asserts a frame was actually scheduled; both new assertions were checked
  by breaking the code they guard.
