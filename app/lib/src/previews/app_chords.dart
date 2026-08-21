import 'package:flutter/services.dart';

/// Whether a key belongs to the app rather than to the guest being previewed.
///
/// The preview forwards everything else and reports it handled, so whatever is
/// reserved here is a key the demo never sees — which makes the reserved set
/// worth keeping to exactly what the host actually binds:
///
/// - the catalog panel's `⌘R` reload and `⌘⇧C` copy-preview, and
/// - the shell's `⌘B` sidebar, `⌘K` search and `⌘⇧[` / `⌘⇧]` worktree cycle.
///
/// Reserving every command chord instead — which is what this used to do —
/// costs the demo far more than it looks. It takes ⌘A, ⌘C, ⌘V and ⌘Z, so a
/// field cannot be selected into or pasted into; and because the modifier keys
/// are themselves chords once held, the guest never learns ⌘ is down, so a
/// demo's own shortcuts cannot fire either.
///
/// Releases are never reserved. `CallbackShortcuts` fires on the press, while a
/// release withheld from the guest leaves it certain the key is still held —
/// which is how a key comes to stop working until it is pressed twice.
bool isReservedAppChord(KeyEvent event, HardwareKeyboard keyboard) {
  if (event is KeyUpEvent) return false;
  if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
  var shift = keyboard.isShiftPressed;
  return switch (event.logicalKey) {
    LogicalKeyboardKey.keyR ||
    LogicalKeyboardKey.keyB ||
    LogicalKeyboardKey.keyK => !shift,
    // Shifted, because plain ⌘C belongs to whatever text has the selection —
    // in the demo as much as in the panel.
    LogicalKeyboardKey.keyC => shift,
    LogicalKeyboardKey.bracketLeft || LogicalKeyboardKey.bracketRight => shift,
    _ => false,
  };
}
