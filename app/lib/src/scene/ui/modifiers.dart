import 'package:flutter/services.dart';

/// Whether a click should toggle membership rather than replace the selection.
///
/// Read off the hardware keyboard at the moment of the tap rather than
/// carried in the gesture: Flutter's tap details do not say which modifiers
/// were down, and shift/cmd/ctrl all mean "add to" on every desktop editor.
bool get toggleModifier {
  var keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight) ||
      keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
}

/// Whether a drop should move the node into the frame under the pointer.
///
/// Held at the moment of RELEASE, not during the drag: dragging is a
/// position gesture and reparenting is a structural one, and their results
/// do not even look alike — a node dropped into a row loses its position
/// entirely, because there position *is* order. Passing over a frame must
/// therefore mean nothing at all.
///
/// Alt/Option rather than the [toggleModifier] set, which cmd and shift are
/// already spoken for in.
bool get reparentModifier {
  var keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.altLeft) ||
      keys.contains(LogicalKeyboardKey.altRight);
}
