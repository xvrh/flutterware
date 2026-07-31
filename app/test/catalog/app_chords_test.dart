import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/catalog/app_chords.dart';

/// Everything reserved here is a key the demo never receives, so the cost of
/// over-reserving is invisible in the panel and obvious in the preview.
void main() {
  late HardwareKeyboard keyboard;

  setUp(() => keyboard = HardwareKeyboard());

  tearDown(() => keyboard.clearState());

  void hold(LogicalKeyboardKey key, PhysicalKeyboardKey physical) {
    keyboard.handleKeyEvent(
      KeyDownEvent(
        physicalKey: physical,
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
  }

  KeyEvent press(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  KeyEvent release(LogicalKeyboardKey key) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  void holdMeta() =>
      hold(LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft);
  void holdShift() =>
      hold(LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft);

  test('an unmodified key is always the demo key', () {
    expect(isReservedAppChord(press(LogicalKeyboardKey.keyR), keyboard), false);
    expect(
      isReservedAppChord(press(LogicalKeyboardKey.backspace), keyboard),
      false,
    );
  });

  test('the host keeps the chords it actually binds', () {
    holdMeta();
    for (var key in [
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyK,
    ]) {
      expect(isReservedAppChord(press(key), keyboard), true, reason: '$key');
    }
  });

  test('every other chord reaches the demo', () {
    holdMeta();
    for (var key in [
      // Select-all, copy, paste, undo: the ones a field cannot do without.
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      expect(isReservedAppChord(press(key), keyboard), false, reason: '$key');
    }
  });

  test('the modifier itself is never reserved', () {
    holdMeta();
    // Withheld, the guest never learns the modifier is down and no demo
    // shortcut can fire.
    expect(
      isReservedAppChord(press(LogicalKeyboardKey.metaLeft), keyboard),
      false,
    );
  });

  test('shift decides the copy and cycle chords', () {
    holdMeta();
    expect(isReservedAppChord(press(LogicalKeyboardKey.keyC), keyboard), false);
    expect(
      isReservedAppChord(press(LogicalKeyboardKey.bracketRight), keyboard),
      false,
    );
    holdShift();
    expect(isReservedAppChord(press(LogicalKeyboardKey.keyC), keyboard), true);
    expect(
      isReservedAppChord(press(LogicalKeyboardKey.bracketRight), keyboard),
      true,
    );
    // And the shifted reload is not a binding, so it is the demo's.
    expect(isReservedAppChord(press(LogicalKeyboardKey.keyR), keyboard), false);
  });

  test('a release is never reserved', () {
    holdMeta();
    // Withholding it would leave the guest holding a key forever — the shape
    // of "that key stopped working until I pressed it twice".
    expect(
      isReservedAppChord(release(LogicalKeyboardKey.keyR), keyboard),
      false,
    );
  });
}
