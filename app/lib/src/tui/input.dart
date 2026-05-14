import 'dart:async';
import 'dart:collection';

enum Modifier { shift, ctrl, alt }

enum SpecialKeyCode {
  up,
  down,
  left,
  right,
  enter,
  tab,
  backspace,
  escape,
  home,
  end,
  pageUp,
  pageDown,
  delete,
  insert,
  f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
}

sealed class KeyEvent {
  final Set<Modifier> modifiers;
  const KeyEvent(this.modifiers);
}

class CharKey extends KeyEvent {
  final int rune;
  const CharKey({required this.rune, required Set<Modifier> modifiers})
      : super(modifiers);

  @override
  bool operator ==(Object other) =>
      other is CharKey &&
      other.rune == rune &&
      _setEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(rune, _setHash(modifiers));

  @override
  String toString() => 'CharKey(0x${rune.toRadixString(16)}, $modifiers)';
}

class SpecialKey extends KeyEvent {
  final SpecialKeyCode code;
  const SpecialKey({required this.code, required Set<Modifier> modifiers})
      : super(modifiers);

  @override
  bool operator ==(Object other) =>
      other is SpecialKey &&
      other.code == code &&
      _setEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(code, _setHash(modifiers));

  @override
  String toString() => 'SpecialKey($code, $modifiers)';
}

bool _setEq(Set a, Set b) {
  if (a.length != b.length) return false;
  for (final x in a) {
    if (!b.contains(x)) return false;
  }
  return true;
}

int _setHash(Set s) {
  var h = 0;
  for (final x in s) {
    h ^= x.hashCode;
  }
  return h;
}

/// Defined in Task 6.
Stream<KeyEvent> parseKeyEvents(Stream<List<int>> bytes) {
  throw UnimplementedError('see Task 6');
}
