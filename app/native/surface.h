#ifndef EMBEDDER_SURFACE_H
#define EMBEDDER_SURFACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// A ring of three IOSurfaces shared with the GUI process. The guest renders
// into one slot at a time; the GUI reads whichever slot FrameReady names.
#define SURFACE_RING_COUNT 3

// Allocates a fresh ring of BGRA IOSurfaces sized width x height, releasing
// any previous ring. Returns false on allocation failure.
bool surface_ring_init(int width, int height);

// Releases the ring.
void surface_ring_destroy(void);

// Copies an RGBA frame from the software renderer into the next ring slot,
// swapping channels to BGRA. Returns the slot index written, or -1 if no ring
// exists.
int surface_ring_present(const void* rgba, size_t row_bytes, size_t height);

// Fills out[SURFACE_RING_COUNT] with the global IOSurfaceIDs of the ring.
void surface_ring_ids(uint32_t out[SURFACE_RING_COUNT]);

int surface_ring_width(void);
int surface_ring_height(void);
size_t surface_ring_row_bytes(void);

#endif  // EMBEDDER_SURFACE_H
