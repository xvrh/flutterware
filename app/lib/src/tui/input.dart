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

/// Parse a raw byte stream into a stream of [KeyEvent]s.
///
/// Recognized sequences:
/// - ASCII 0x20–0x7e → printable [CharKey].
/// - ASCII 0x01–0x1a (except 0x09, 0x0a, 0x0d) → ctrl-letter [CharKey].
/// - 0x09 → tab; 0x0a / 0x0d → enter; 0x7f → backspace.
/// - 0x1b alone (stream ends or no more bytes available) → escape.
/// - 0x1b 0x5b … (CSI) → arrows, home/end, page up/down, with optional
///   modifier params (`ESC [1;<mod>A`).
/// - 0x1b 0x4f X (SS3) → arrows (some terminals send these in app mode).
/// - 0xc0–0xfd start of a UTF-8 multi-byte sequence → one [CharKey] with the
///   decoded code point.
///
/// Sequences split across chunk boundaries are reassembled internally.
Stream<KeyEvent> parseKeyEvents(Stream<List<int>> bytes) async* {
  final pending = Queue<int>();
  await for (final chunk in bytes) {
    pending.addAll(chunk);
    while (pending.isNotEmpty) {
      // Attempt to consume one event from the front of [pending]. If the
      // available bytes are an incomplete prefix of a multi-byte sequence,
      // _consume returns null and we break to await more input.
      final result = _consume(pending, streamClosed: false);
      if (result == null) break;
      yield result;
    }
  }
  // Stream closed. Drain any pending bytes; treat lone ESC as escape.
  while (pending.isNotEmpty) {
    final result = _consume(pending, streamClosed: true);
    if (result == null) break;
    yield result;
  }
}

/// Try to consume one [KeyEvent] from the front of [bytes]. Returns null if
/// the bytes form an incomplete sequence and [streamClosed] is false.
/// When [streamClosed] is true, ambiguous prefixes are resolved as best-effort
/// (e.g. lone ESC → escape).
KeyEvent? _consume(Queue<int> bytes, {required bool streamClosed}) {
  final first = bytes.first;

  // --- Special single-byte cases ---
  if (first == 0x1b) {
    // ESC: could be standalone escape, or the start of CSI/SS3.
    if (bytes.length == 1) {
      if (!streamClosed) return null;
      bytes.removeFirst();
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
    }
    final second = bytes.elementAt(1);
    if (second == 0x5b /* [ */) {
      return _consumeCsi(bytes, streamClosed: streamClosed);
    }
    if (second == 0x4f /* O */) {
      return _consumeSs3(bytes, streamClosed: streamClosed);
    }
    // Anything else after ESC: treat ESC as standalone for stage 1.
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }

  if (first == 0x09) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.tab, modifiers: {});
  }
  if (first == 0x0a || first == 0x0d) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.enter, modifiers: {});
  }
  if (first == 0x7f) {
    bytes.removeFirst();
    return const SpecialKey(code: SpecialKeyCode.backspace, modifiers: {});
  }

  // --- ctrl-letter (0x01–0x1a, excluding the specials above) ---
  if (first >= 0x01 && first <= 0x1a) {
    bytes.removeFirst();
    // 0x01 = ctrl-A → rune 'a' (0x61). General: rune = 0x60 + first.
    return CharKey(rune: 0x60 + first, modifiers: const {Modifier.ctrl});
  }

  // --- Plain ASCII printable ---
  if (first >= 0x20 && first <= 0x7e) {
    bytes.removeFirst();
    return CharKey(rune: first, modifiers: const {});
  }

  // --- UTF-8 multi-byte ---
  if (first >= 0xc0 && first < 0xf8) {
    final byteLen = first < 0xe0 ? 2 : (first < 0xf0 ? 3 : 4);
    if (bytes.length < byteLen) {
      if (!streamClosed) return null;
      bytes.clear();
      return const CharKey(rune: 0xFFFD /* replacement */, modifiers: {});
    }
    var rune = first & (0xff >> (byteLen + 1));
    final consumed = <int>[bytes.removeFirst()];
    for (var i = 1; i < byteLen; i++) {
      final next = bytes.removeFirst();
      consumed.add(next);
      rune = (rune << 6) | (next & 0x3f);
    }
    return CharKey(rune: rune, modifiers: const {});
  }

  // --- Anything else (continuation bytes appearing alone, 0xfe/0xff, etc.) ---
  // Drop the byte to avoid an infinite loop.
  bytes.removeFirst();
  return CharKey(rune: 0xFFFD, modifiers: const {});
}

/// Consume an `ESC [ ...` CSI sequence. Called with [bytes] starting at 0x1b 0x5b.
/// Returns null if more bytes are needed and the stream is still open.
KeyEvent? _consumeCsi(Queue<int> bytes, {required bool streamClosed}) {
  // We need at least ESC, [, and one final byte.
  if (bytes.length < 3 && !streamClosed) return null;

  // Snapshot the bytes so we can roll back if incomplete.
  final snapshot = bytes.toList();
  // Consume ESC and [.
  snapshot.removeAt(0);
  snapshot.removeAt(0);

  // Read parameter bytes (0x30–0x3f), intermediate bytes (0x20–0x2f),
  // and finally one final byte (0x40–0x7e).
  final paramBytes = <int>[];
  var idx = 0;
  while (idx < snapshot.length && snapshot[idx] >= 0x30 && snapshot[idx] <= 0x3f) {
    paramBytes.add(snapshot[idx]);
    idx++;
  }
  if (idx >= snapshot.length) {
    return streamClosed ? _csiUnknown(bytes) : null;
  }
  final finalByte = snapshot[idx];
  if (finalByte < 0x40 || finalByte > 0x7e) {
    return streamClosed ? _csiUnknown(bytes) : null;
  }

  // Successful parse — actually consume from [bytes].
  // Total consumed = 2 (ESC, [) + paramBytes.length + 1 (final).
  final totalConsumed = 2 + paramBytes.length + 1;
  for (var i = 0; i < totalConsumed; i++) {
    bytes.removeFirst();
  }

  return _interpretCsi(paramBytes, finalByte);
}

KeyEvent _csiUnknown(Queue<int> bytes) {
  // Stream closed mid-sequence. Drain ESC and [ at least, and emit escape.
  bytes.removeFirst(); // ESC
  if (bytes.isNotEmpty) bytes.removeFirst(); // [
  return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
}

KeyEvent _interpretCsi(List<int> paramBytes, int finalByte) {
  // Parse parameters: bytes 0x30–0x39 are digits, 0x3b is separator.
  final params = <int>[];
  var cur = 0;
  var any = false;
  for (final b in paramBytes) {
    if (b >= 0x30 && b <= 0x39) {
      cur = cur * 10 + (b - 0x30);
      any = true;
    } else if (b == 0x3b /* ; */) {
      params.add(any ? cur : 0);
      cur = 0;
      any = false;
    }
  }
  if (any) params.add(cur);

  // Modifier param (xterm convention: 1=none, 2=shift, 3=alt, 4=shift+alt,
  // 5=ctrl, 6=ctrl+shift, 7=ctrl+alt, 8=ctrl+shift+alt). Apparent in
  // sequences like `ESC [1;<mod><final>` or `ESC [<n>;<mod>~`.
  Set<Modifier> mods = const {};
  if (params.length >= 2) {
    mods = _xtermModifiers(params[1]);
  }

  switch (finalByte) {
    case 0x41: // A
      return SpecialKey(code: SpecialKeyCode.up, modifiers: mods);
    case 0x42: // B
      return SpecialKey(code: SpecialKeyCode.down, modifiers: mods);
    case 0x43: // C
      return SpecialKey(code: SpecialKeyCode.right, modifiers: mods);
    case 0x44: // D
      return SpecialKey(code: SpecialKeyCode.left, modifiers: mods);
    case 0x48: // H
      return SpecialKey(code: SpecialKeyCode.home, modifiers: mods);
    case 0x46: // F
      return SpecialKey(code: SpecialKeyCode.end, modifiers: mods);
    case 0x7e: // ~
      // First param identifies the key. Common values:
      // 2=insert, 3=delete, 5=pgUp, 6=pgDn, 15=F5, 17=F6, 18=F7, 19=F8,
      // 20=F9, 21=F10, 23=F11, 24=F12.
      final keyId = params.isNotEmpty ? params[0] : 0;
      final code = switch (keyId) {
        2 => SpecialKeyCode.insert,
        3 => SpecialKeyCode.delete,
        5 => SpecialKeyCode.pageUp,
        6 => SpecialKeyCode.pageDown,
        15 => SpecialKeyCode.f5,
        17 => SpecialKeyCode.f6,
        18 => SpecialKeyCode.f7,
        19 => SpecialKeyCode.f8,
        20 => SpecialKeyCode.f9,
        21 => SpecialKeyCode.f10,
        23 => SpecialKeyCode.f11,
        24 => SpecialKeyCode.f12,
        _ => null,
      };
      if (code != null) return SpecialKey(code: code, modifiers: mods);
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
    default:
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }
}

Set<Modifier> _xtermModifiers(int param) {
  // xterm encodes modifiers as (param - 1) treated as a bitfield:
  // bit 0 = shift, bit 1 = alt, bit 2 = ctrl.
  final m = (param - 1).clamp(0, 7);
  final out = <Modifier>{};
  if (m & 1 != 0) out.add(Modifier.shift);
  if (m & 2 != 0) out.add(Modifier.alt);
  if (m & 4 != 0) out.add(Modifier.ctrl);
  return out;
}

KeyEvent? _consumeSs3(Queue<int> bytes, {required bool streamClosed}) {
  // ESC O X — we need 3 bytes.
  if (bytes.length < 3) {
    return streamClosed
        ? (bytes.removeFirst(), const SpecialKey(code: SpecialKeyCode.escape, modifiers: {})).$2
        : null;
  }
  bytes.removeFirst(); // ESC
  bytes.removeFirst(); // O
  final final_ = bytes.removeFirst();
  switch (final_) {
    case 0x41:
      return const SpecialKey(code: SpecialKeyCode.up, modifiers: {});
    case 0x42:
      return const SpecialKey(code: SpecialKeyCode.down, modifiers: {});
    case 0x43:
      return const SpecialKey(code: SpecialKeyCode.right, modifiers: {});
    case 0x44:
      return const SpecialKey(code: SpecialKeyCode.left, modifiers: {});
    case 0x50:
      return const SpecialKey(code: SpecialKeyCode.f1, modifiers: {});
    case 0x51:
      return const SpecialKey(code: SpecialKeyCode.f2, modifiers: {});
    case 0x52:
      return const SpecialKey(code: SpecialKeyCode.f3, modifiers: {});
    case 0x53:
      return const SpecialKey(code: SpecialKeyCode.f4, modifiers: {});
    default:
      return const SpecialKey(code: SpecialKeyCode.escape, modifiers: {});
  }
}
