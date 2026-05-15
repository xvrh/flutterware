#include "surface.h"

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

// The shared device and command queue, created lazily on the first
// surface_ring_init. The engine submits its render commands on g_queue (passed
// as present_command_queue), so the fence command buffer is correctly ordered.
static id<MTLDevice> g_device;
static id<MTLCommandQueue> g_queue;

// The current ring. Owned entirely by the engine raster thread: surface_ring_init
// is only ever called from get_next_drawable_callback (and once at startup,
// before the engine runs), so no cross-thread locking is needed.
static IOSurfaceRef g_ios[SURFACE_RING_COUNT];
static id<MTLTexture> g_tex[SURFACE_RING_COUNT];
static int g_width;
static int g_height;
static int g_next;

static IOSurfaceRef CreateSurface(int width, int height) {
  int bpe = 4;
  int pixel_format = 0x42475241;  // 'BGRA'
  CFMutableDictionaryRef props = CFDictionaryCreateMutable(
      kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFNumberRef w = CFNumberCreate(NULL, kCFNumberIntType, &width);
  CFNumberRef h = CFNumberCreate(NULL, kCFNumberIntType, &height);
  CFNumberRef e = CFNumberCreate(NULL, kCFNumberIntType, &bpe);
  CFNumberRef f = CFNumberCreate(NULL, kCFNumberIntType, &pixel_format);
  CFDictionarySetValue(props, kIOSurfaceWidth, w);
  CFDictionarySetValue(props, kIOSurfaceHeight, h);
  CFDictionarySetValue(props, kIOSurfaceBytesPerElement, e);
  CFDictionarySetValue(props, kIOSurfacePixelFormat, f);
  // Deliberately do NOT set kIOSurfaceBytesPerRow: width*4 is not necessarily
  // a valid (aligned) row stride, and an unaligned value makes IOSurfaceCreate
  // fail outright for some widths. Letting IOSurface pick the stride keeps
  // creation reliable at every window size.
  // The GUI process resolves these surfaces with IOSurfaceLookup(id); that
  // only works for surfaces flagged global.
  CFDictionarySetValue(props, kIOSurfaceIsGlobal, kCFBooleanTrue);
  IOSurfaceRef surface = IOSurfaceCreate(props);
  CFRelease(w);
  CFRelease(h);
  CFRelease(e);
  CFRelease(f);
  CFRelease(props);
  return surface;
}

static id<MTLTexture> CreateTexture(IOSurfaceRef ios, int width, int height) {
  MTLTextureDescriptor* desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                   width:(NSUInteger)width
                                  height:(NSUInteger)height
                               mipmapped:NO];
  desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  desc.storageMode = MTLStorageModeShared;
  return [g_device newTextureWithDescriptor:desc iosurface:ios plane:0];
}

bool surface_ring_init(int width, int height) {
  if (width <= 0 || height <= 0) return false;
  if (g_device == nil) {
    g_device = MTLCreateSystemDefaultDevice();
    if (g_device == nil) return false;
    g_queue = [g_device newCommandQueue];
    if (g_queue == nil) return false;
  }
  // Build the new ring into temporaries; only swap in (and release the old
  // ring) once every pair is allocated. A failed re-allocation then leaves the
  // existing ring intact and still presentable.
  IOSurfaceRef fresh_ios[SURFACE_RING_COUNT] = {0};
  id<MTLTexture> fresh_tex[SURFACE_RING_COUNT] = {nil, nil, nil};
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    fresh_ios[i] = CreateSurface(width, height);
    fresh_tex[i] =
        fresh_ios[i] ? CreateTexture(fresh_ios[i], width, height) : nil;
    if (!fresh_ios[i] || fresh_tex[i] == nil) {
      for (int j = 0; j <= i; j++) {
        if (fresh_ios[j]) CFRelease(fresh_ios[j]);
        fresh_tex[j] = nil;
      }
      return false;
    }
  }
  surface_ring_destroy();
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    g_ios[i] = fresh_ios[i];
    g_tex[i] = fresh_tex[i];
  }
  g_width = width;
  g_height = height;
  g_next = 0;
  return true;
}

void surface_ring_destroy(void) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    if (g_ios[i]) {
      CFRelease(g_ios[i]);
      g_ios[i] = NULL;
    }
    g_tex[i] = nil;
  }
  g_width = 0;
  g_height = 0;
  g_next = 0;
}

const void* surface_metal_device(void) {
  return (__bridge const void*)g_device;
}

const void* surface_metal_queue(void) {
  return (__bridge const void*)g_queue;
}

const void* surface_ring_texture(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT) return NULL;
  return (__bridge const void*)g_tex[slot];
}

int surface_ring_acquire(void) { return g_next; }

void surface_ring_advance(void) {
  g_next = (g_next + 1) % SURFACE_RING_COUNT;
}

void surface_present_fence(void (*on_complete)(void*), void* user_data) {
  id<MTLCommandBuffer> cb = [g_queue commandBuffer];
  [cb addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    (void)buffer;
    on_complete(user_data);
  }];
  [cb commit];
}

const void* surface_lock(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT || !g_ios[slot]) return NULL;
  IOSurfaceLock(g_ios[slot], kIOSurfaceLockReadOnly, NULL);
  return IOSurfaceGetBaseAddress(g_ios[slot]);
}

void surface_unlock(int slot) {
  if (slot < 0 || slot >= SURFACE_RING_COUNT || !g_ios[slot]) return;
  IOSurfaceUnlock(g_ios[slot], kIOSurfaceLockReadOnly, NULL);
}

void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]) {
  for (int i = 0; i < SURFACE_RING_COUNT; i++) {
    out[i] = g_ios[i] ? IOSurfaceGetID(g_ios[i]) : 0;
  }
}

int surface_ring_width(void) { return g_width; }
int surface_ring_height(void) { return g_height; }

size_t surface_ring_row_bytes(void) {
  return g_ios[0] ? IOSurfaceGetBytesPerRow(g_ios[0]) : 0;
}
