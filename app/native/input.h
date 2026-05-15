#ifndef EMBEDDER_INPUT_H
#define EMBEDDER_INPUT_H

#include <stddef.h>
#include <stdint.h>

#include "flutter_embedder.h"

// Decodes a PointerEvent payload and forwards it to the engine.
void input_handle_pointer(FlutterEngine engine, const uint8_t* payload,
                          size_t len);

// Decodes a KeyEvent payload and forwards it to the engine.
void input_handle_key(FlutterEngine engine, const uint8_t* payload,
                      size_t len);

#endif  // EMBEDDER_INPUT_H
