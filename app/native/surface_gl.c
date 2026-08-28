// The ring, where there is no IOSurface and no Metal: a headless EGL context
// the engine renders into, and three shared-memory mappings the GUI reads.
//
// Two decisions worth knowing before reading the code.
//
// **The context is surfaceless, so the guest needs neither a window nor a
// display.** `EGL_PLATFORM_SURFACELESS_MESA` plus `EGL_KHR_surfaceless_context`
// is what lets `eglMakeCurrent` bind a context with no drawable at all, and the
// engine only ever renders into an FBO we name, so a drawable would be dead
// weight. Measured with `DISPLAY`, `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` all
// unset, and again under `LIBGL_ALWAYS_SOFTWARE=1`: both render. That is the
// whole of the CI story — no seat, no card, no Xvfb.
//
// **The ring is shared memory and not a dmabuf, and it costs a copy.** A
// dmabuf would be zero-copy and it does work across processes — the probe in
// `tool/embedder/linux_probes/dmabuf_probe.c` proves it — but exporting one
// is `EGL_MESA_image_dma_buf_export`, which NVIDIA's proprietary driver does
// not have. A path that works on every driver has to exist regardless, so it is
// this one first. See the findings doc for what the copy costs.
#include "surface.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// The EGL side, created once and outliving every ring.
static EGLDisplay g_display = EGL_NO_DISPLAY;
static EGLContext g_context = EGL_NO_CONTEXT;
static EGLContext g_resource_context = EGL_NO_CONTEXT;

// The render target. Recreated whenever the ring changes size, on the raster
// thread, which is the only thread that ever has the context current.
static GLuint g_fbo;
static GLuint g_color;
static int g_fbo_width;
static int g_fbo_height;

// The ring. Names are kept alive one generation longer than the mapping they
// describe — see [retire].
static void* g_map[SURFACE_RING_COUNT];
static char g_name[SURFACE_RING_COUNT][64];
static char g_retired[SURFACE_RING_COUNT][64];
static size_t g_size;
// One row, for the flip in [surface_gl_readback]. Sized with the ring.
static uint8_t* g_row;
static int g_width;
static int g_height;
static int g_next;

// Distinguishes one guest's ring from another's, and one generation from the
// last. Never reset: a name that has been announced must not come back meaning
// something else.
static unsigned g_ring_serial;

static bool init_egl(void) {
  if (g_display != EGL_NO_DISPLAY) return true;

  PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
          "eglGetPlatformDisplayEXT");
  if (get_platform_display) {
    g_display = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                                     EGL_DEFAULT_DISPLAY, NULL);
  }
  // A driver without the surfaceless platform may still have a default display
  // worth trying; if it also lacks EGL_KHR_surfaceless_context the makeCurrent
  // below is where it says so.
  if (g_display == EGL_NO_DISPLAY) {
    g_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  }
  if (g_display == EGL_NO_DISPLAY) return false;

  EGLint major = 0;
  EGLint minor = 0;
  if (!eglInitialize(g_display, &major, &minor)) return false;
  if (!eglBindAPI(EGL_OPENGL_ES_API)) return false;

  // Impeller's GLES backend wants ES 3. The config is only ever used to create
  // contexts — nothing is drawn to a surface — so the colour sizes here are
  // asked for to get a sane config, not because anything reads them.
  EGLint config_attributes[] = {EGL_SURFACE_TYPE,    EGL_PBUFFER_BIT,
                                EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                                EGL_RED_SIZE,        8,
                                EGL_GREEN_SIZE,      8,
                                EGL_BLUE_SIZE,       8,
                                EGL_ALPHA_SIZE,      8,
                                EGL_NONE};
  EGLConfig config;
  EGLint count = 0;
  if (!eglChooseConfig(g_display, config_attributes, &config, 1, &count) ||
      count < 1) {
    return false;
  }

  EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  g_context = eglCreateContext(g_display, config, EGL_NO_CONTEXT,
                               context_attributes);
  if (g_context == EGL_NO_CONTEXT) return false;
  // Shares with the render context, which is what the engine promises its
  // upload thread: textures uploaded there are usable here.
  g_resource_context =
      eglCreateContext(g_display, config, g_context, context_attributes);
  if (g_resource_context == EGL_NO_CONTEXT) return false;
  return true;
}

// Unlinks the previous generation's names and remembers this one's in their
// place.
//
// Not unlinked outright, because the GUI is told about a ring and opens it
// afterwards: unlinking at the moment of replacement is a resize racing a name
// the other process has not got to yet. Unlinking one generation late gives it
// a whole round trip, and the mapping itself survives the unlink for anyone who
// did open it.
static void retire(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_retired[i][0]) shm_unlink(g_retired[i]);
    memcpy(g_retired[i], g_name[i], sizeof(g_name[i]));
    g_name[i][0] = '\0';
  }
}

bool surface_ring_init(int width, int height) {
  if (width <= 0 || height <= 0) return false;
  if (!init_egl()) return false;

  size_t size = (size_t)width * (size_t)height * 4;
  unsigned serial = g_ring_serial + 1;

  // Built into temporaries and swapped in whole, exactly as the Metal ring is:
  // a failed re-allocation leaves the existing ring intact and presentable.
  void* fresh_map[SURFACE_RING_COUNT] = {NULL, NULL, NULL};
  char fresh_name[SURFACE_RING_COUNT][64];
  bool ok = true;
  for (int i = 0; i < SURFACE_RING_COUNT && ok; i++) {
    snprintf(fresh_name[i], sizeof(fresh_name[i]), "/flutterware-%u-%u-%d",
             (unsigned)getpid(), serial, i);
    // O_EXCL: a leftover of the same name is somebody else's or a crash's, and
    // silently reusing it is how two guests come to share a frame.
    shm_unlink(fresh_name[i]);
    int fd = shm_open(fresh_name[i], O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) {
      ok = false;
      break;
    }
    if (ftruncate(fd, (off_t)size) != 0) {
      close(fd);
      shm_unlink(fresh_name[i]);
      ok = false;
      break;
    }
    fresh_map[i] = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    // The mapping holds the object open; the descriptor has nothing left to do.
    close(fd);
    if (fresh_map[i] == MAP_FAILED) {
      fresh_map[i] = NULL;
      shm_unlink(fresh_name[i]);
      ok = false;
    }
  }
  if (!ok) {
    for (int i = 0; i < SURFACE_RING_COUNT; i++) {
      if (fresh_map[i]) {
        munmap(fresh_map[i], size);
        shm_unlink(fresh_name[i]);
      }
    }
    return false;
  }

  // Unmap this ring's own pages, then take the previous names into the retired
  // slot so they outlive the announcement that named them.
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_map[i]) munmap(g_map[i], g_size);
    g_map[i] = NULL;
  }
  retire();

  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    g_map[i] = fresh_map[i];
    memcpy(g_name[i], fresh_name[i], sizeof(fresh_name[i]));
  }
  free(g_row);
  g_row = (uint8_t*)malloc((size_t)width * 4);
  g_ring_serial = serial;
  g_size = size;
  g_width = width;
  g_height = height;
  g_next = 0;
  return true;
}

void surface_ring_destroy(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_map[i]) munmap(g_map[i], g_size);
    g_map[i] = NULL;
    if (g_name[i][0]) shm_unlink(g_name[i]);
    g_name[i][0] = '\0';
    if (g_retired[i][0]) shm_unlink(g_retired[i]);
    g_retired[i][0] = '\0';
  }
  free(g_row);
  g_row = NULL;
  g_size = 0;
  g_width = 0;
  g_height = 0;
  g_next = 0;
}

int surface_ring_acquire(void) { return g_next; }

void surface_ring_advance(void) {
  g_next = (g_next + 1) % SURFACE_RING_COUNT;
}

const void* surface_lock(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT) return NULL;
  // Nothing to lock: the mapping is plain memory and the reader is another
  // process that is only told about a slot once the frame is in it.
  return g_map[slot];
}

void surface_unlock(int slot) { (void)slot; }

const char* surface_ring_handle(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT) return NULL;
  return g_name[slot][0] ? g_name[slot] : NULL;
}

uint32_t surface_ring_pixel_order(void) { return kSurfaceOrderRgba; }

int surface_ring_width(void) { return g_width; }
int surface_ring_height(void) { return g_height; }

size_t surface_ring_row_bytes(void) { return (size_t)g_width * 4; }

bool surface_gl_make_current(void) {
  return eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE, g_context);
}

bool surface_gl_clear_current(void) {
  return eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT);
}

bool surface_gl_make_resource_current(void) {
  return eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        g_resource_context);
}

uint32_t surface_gl_fbo(void) {
  if (g_width <= 0 || g_height <= 0) return 0;
  if (g_fbo != 0 && g_fbo_width == g_width && g_fbo_height == g_height) {
    return g_fbo;
  }
  if (g_fbo != 0) {
    glDeleteFramebuffers(1, &g_fbo);
    glDeleteTextures(1, &g_color);
    g_fbo = 0;
    g_color = 0;
  }
  glGenTextures(1, &g_color);
  glBindTexture(GL_TEXTURE_2D, g_color);
  // RGBA8 because that is what an FlPixelBufferTexture takes on the other side
  // — the Metal ring is BGRA, and this is the one place the two differ.
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, g_width, g_height, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, NULL);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glGenFramebuffers(1, &g_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         g_color, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    glDeleteFramebuffers(1, &g_fbo);
    glDeleteTextures(1, &g_color);
    g_fbo = 0;
    g_color = 0;
    return 0;
  }
  g_fbo_width = g_width;
  g_fbo_height = g_height;
  return g_fbo;
}

void surface_gl_readback(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT || !g_map[slot]) return;
  if (g_fbo == 0) return;
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  // GL's origin is bottom-left and every reader of this ring expects top-left,
  // so the rows come out upside down and are flipped on the way in. Reading
  // straight into the mapping and flipping afterwards would be one pass fewer,
  // but it would also mean a reader could see a half-flipped frame.
  glReadPixels(0, 0, g_width, g_height, GL_RGBA, GL_UNSIGNED_BYTE,
               g_map[slot]);
  size_t stride = surface_ring_row_bytes();
  if (!g_row) return;
  uint8_t* base = (uint8_t*)g_map[slot];
  for (int y = 0; y < g_height / 2; y++) {
    uint8_t* top = base + (size_t)y * stride;
    uint8_t* bottom = base + (size_t)(g_height - 1 - y) * stride;
    memcpy(g_row, top, stride);
    memcpy(top, bottom, stride);
    memcpy(bottom, g_row, stride);
  }
}
