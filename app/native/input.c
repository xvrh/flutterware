#include "input.h"

#include <string.h>

static uint32_t rd_u32(const uint8_t* p, size_t off) {
  uint32_t v;
  memcpy(&v, p + off, 4);
  return v;
}

static uint64_t rd_u64(const uint8_t* p, size_t off) {
  uint64_t v;
  memcpy(&v, p + off, 8);
  return v;
}

static double rd_f64(const uint8_t* p, size_t off) {
  double v;
  memcpy(&v, p + off, 8);
  return v;
}

void input_handle_pointer(FlutterEngine engine, const uint8_t* p, size_t len) {
  if (len < 48) return;
  FlutterPointerEvent ev = {0};
  ev.struct_size = sizeof(FlutterPointerEvent);
  // protocol PointerPhase order matches FlutterPointerPhase.
  ev.phase = (FlutterPointerPhase)rd_u32(p, 0);
  ev.x = rd_f64(p, 4);
  ev.y = rd_f64(p, 12);
  ev.buttons = (int64_t)rd_u32(p, 20);
  double scroll_dx = rd_f64(p, 24);
  double scroll_dy = rd_f64(p, 32);
  ev.timestamp = (size_t)rd_u64(p, 40);
  ev.device_kind = kFlutterPointerDeviceKindMouse;
  if (scroll_dx != 0.0 || scroll_dy != 0.0) {
    ev.signal_kind = kFlutterPointerSignalKindScroll;
    ev.scroll_delta_x = scroll_dx;
    ev.scroll_delta_y = scroll_dy;
  }
  FlutterEngineSendPointerEvent(engine, &ev, 1);
}

void input_handle_key(FlutterEngine engine, const uint8_t* p, size_t len) {
  if (len < 32) return;
  FlutterKeyEvent ev = {0};
  ev.struct_size = sizeof(FlutterKeyEvent);
  uint32_t kind = rd_u32(p, 0);  // 0 down, 1 up, 2 repeat
  ev.type = kind == 1   ? kFlutterKeyEventTypeUp
            : kind == 2 ? kFlutterKeyEventTypeRepeat
                        : kFlutterKeyEventTypeDown;
  ev.physical = rd_u64(p, 4);
  ev.logical = rd_u64(p, 12);
  // modifiers (offset 20, u32) are not part of FlutterKeyEvent; ignored in 3a.
  ev.timestamp = (double)rd_u64(p, 24);
  ev.character = NULL;
  ev.synthesized = false;
  FlutterEngineSendKeyEvent(engine, &ev, NULL, NULL);
}
