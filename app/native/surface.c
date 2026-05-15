#include "surface.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurface.h>

static IOSurfaceRef g_ring[SURFACE_RING_COUNT];
static int g_width;
static int g_height;
static int g_next;

static IOSurfaceRef CreateSurface(int width, int height) {
  int bpe = 4;
  int bpr = width * 4;
  int pixel_format = 0x42475241;  // 'BGRA'
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(
      kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef e = CFNumberCreate(NULL, kCFNumberIntType, &bpe);
  CFNumberRef r = CFNumberCreate(NULL, kCFNumberIntType, &bpr);
  CFNumberRef f = CFNumberCreate(NULL, kCFNumberIntType, &pixel_format);
  CFDictionarySetValue(props, kIOSurfaceWidth, w);
  CFDictionarySetValue(props, kIOSurfaceHeight, h);
  CFDictionarySetValue(props, kIOSurfaceBytesPerElement, e);
  CFDictionarySetValue(props, kIOSurfaceBytesPerRow, r);
  CFDictionarySetValue(props, kIOSurfacePixelFormat, f);
  // The GUI process resolves these surfaces with IOSurfaceLookup(id); that
  // only works for surfaces flagged global. Deprecated, but the companion of
  // the by-ID sharing the design chose for step 3a.
  CFDictionarySetValue(props, kIOSurfaceIsGlobal, kCFBooleanTrue);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(w);
  CFRelease(h);
  CFRelease(e);
  CFRelease(r);
  CFRelease(f);
  CFRelease(props);
  return surface;
}

bool surface_ring_init(int width, int height) {
  surface_ring_destroy();
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    g_ring[i] = CreateSurface(width, height);
    if (!g_ring[i]) {
      surface_ring_destroy();
      return false;
    }
  }
  g_width = width;
  g_height = height;
  g_next = 0;
  return true;
}

void surface_ring_destroy(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_ring[i]) {
      CFRelease(g_ring[i]);
      g_ring[i] = NULL;
    }
  }
  g_width = 0;
  g_height = 0;
  g_next = 0;
}

int surface_ring_present(const void* rgba, size_t row_bytes, size_t height) {
  if (!g_ring[0]) return -1;
  int slot = g_next;
  IOSurfaceRef surface = g_ring[slot];
  IOSurfaceLock(surface, 0, NULL);
  uint8_t* dst = (uint8_t*)IOSurfaceGetBaseAddress(surface);
  size_t dst_stride = IOSurfaceGetBytesPerRow(surface);
  const uint8_t* src = (const uint8_t*)rgba;
  size_t rows = height < (size_t)g_height ? height : (size_t)g_height;
  size_t cols = (size_t)g_width;
  for (size_t y = 0; y < rows; y++) {
    const uint8_t* s = src + y * row_bytes;
    uint8_t* d = dst + y * dst_stride;
    for (size_t x = 0; x < cols; x++) {
      d[x * 4 + 0] = s[x * 4 + 2];  // B <- R
      d[x * 4 + 1] = s[x * 4 + 1];  // G
      d[x * 4 + 2] = s[x * 4 + 0];  // R <- B
      d[x * 4 + 3] = s[x * 4 + 3];  // A
    }
  }
  IOSurfaceUnlock(surface, 0, NULL);
  g_next = (g_next + 1) % SURFACE_RING_COUNT;
  return slot;
}

void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    out[i] = g_ring[i] ? IOSurfaceGetID(g_ring[i]) : 0;
  }
}

int surface_ring_width(void) { return g_width; }
int surface_ring_height(void) { return g_height; }

size_t surface_ring_row_bytes(void) {
  return g_ring[0] ? IOSurfaceGetBytesPerRow(g_ring[0]) : 0;
}
