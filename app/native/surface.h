#ifndef EMBEDDER_SURFACE_H
#define EMBEDDER_SURFACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// A ring of three IOSurfaces shared with the GUI process. Each IOSurface also
// backs a Metal texture the engine renders into directly (zero-copy). The
// guest renders into one slot at a time; the GUI reads whichever slot
// FrameReady names.
#define SURFACE_RING_COUNT 3

// Creates the shared MTLDevice/MTLCommandQueue on the first call, then a fresh
// ring of (IOSurface, MTLTexture) pairs sized width x height, releasing any
// previous ring. Returns false on device or allocation failure.
bool surface_ring_init(int width, int height);

// Releases the ring.
void surface_ring_destroy(void);

// The MTLDevice handle (id<MTLDevice>) for FlutterMetalRendererConfig.device.
// NULL before the first successful surface_ring_init.
const void* surface_metal_device(void);

// The MTLCommandQueue handle (id<MTLCommandQueue>) for
// FlutterMetalRendererConfig.present_command_queue.
const void* surface_metal_queue(void);

// The MTLTexture handle (id<MTLTexture>) backing ring slot `slot`, handed to
// the engine from get_next_drawable_callback. NULL if slot is out of range.
const void* surface_ring_texture(int slot);

// The slot index the engine should render into next. Does not advance.
int surface_ring_acquire(void);

// Advances to the next ring slot. Called from present_drawable_callback.
void surface_ring_advance(void);

// Commits an empty command buffer on the present command queue and invokes
// `on_complete(user_data)` from its completion handler. Because the engine
// submits its render on the same in-order queue, the handler runs only after
// the GPU has finished writing the frame.
void surface_present_fence(void (*on_complete)(void* user_data),
                           void* user_data);

// IOSurfaceLock / IOSurfaceUnlock a ring slot for CPU readback (used under
// --capture-raw). surface_lock returns the slot's base address, or NULL.
const void* surface_lock(int slot);
void surface_unlock(int slot);

// Fills out[SURFACE_RING_COUNT] with the global IOSurfaceIDs of the ring.
void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]);

int surface_ring_width(void);
int surface_ring_height(void);
size_t surface_ring_row_bytes(void);

#endif  // EMBEDDER_SURFACE_H
