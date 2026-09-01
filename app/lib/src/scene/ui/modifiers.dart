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
