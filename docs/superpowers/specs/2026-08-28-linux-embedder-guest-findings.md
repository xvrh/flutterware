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

### The blocker: a resize takes the studio down

Open a live demo, then widen the panel. A second later the studio dies with
`SIGSEGV` — no Dart error, "Lost connection to device". The backtrace (caught
with a temporary handler in the runner) is **entirely inside
`libflutter_linux_gtk.so`**, ~20 frames of what reads as a recursive tree walk
under the raster thread's entry, and it is byte-identical across everything
tried below.

Ruled out, each by measurement:

| Suspected | Test | Result |
| --- | --- | --- |
| Our mapping's lifetime | Never unmap anything, ever | Same crash |
| Our buffer at all | Hand the engine plugin-owned memory copied from the ring | Same crash |
| `FlPixelBufferTexture` | Reimplement as `FlTextureGL`, uploading ourselves | Same crash, same address |
| Anything in our plugin | Trace `populate` entry and exit | It **returns** before the fault |
| The stage's own chrome | Refuse `createTexture`, so no texture is ever registered | **No crash** — the panel opens fine |
| A name whose size changed | A fresh `glGenTextures` per size | Same crash |
| Re-pointing a live texture | Dispose and re-create the texture on every resize | Survived one resize, died on the third |

So it needs the external texture to exist, it does not care which kind, it is
not our memory, and it fires after our code has handed back a valid frame.

A minimal Flutter Linux app — one `FlTextureGL`, marked available on a 16ms
timer, its size alternating 512×512 / 763×527 while the `Texture` widget's own
box alternates too — **does not crash** in 30s of that. So the trigger needs
something more of the studio's tree than "an external texture that resizes",
and what that is remains open.

### Where to pick it up

1. Get symbols. Flutter publishes no `symbols.zip` for `linux-x64`, so this
   means a local engine build or an unstripped `libflutter_linux_gtk.so`. One
   symbolized frame probably ends this.
2. Failing that, grow the minimal app toward the studio's stage — the device
   frame, the clip, the `Fit` scaling, the inspect dock — until it crashes. The
   step that flips it is the answer, and the app is then the bug report.
3. Worth knowing either way: whether the studio survives it with Impeller off.
   `flutter run --no-enable-impeller` answers it, but the run plugin has no way
   to pass that through and the app cannot be driven when launched by hand — so
   this needs either a knob on `run/launch` or an entry point that navigates
   itself.

Until then the Linux panel is a demo you must not resize, which is not a
feature. The guest, the artifact plumbing, the protocol and the wire are all
finished and independently useful — `previews screenshot --engine=guest` and
`--logs` do not go anywhere near a texture.
