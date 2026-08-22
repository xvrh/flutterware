import 'dart:typed_data';

import 'package:flutterware/src/bytes.dart';
import 'package:test/test.dart';

/// The digest a step's picture is fingerprinted with.
///
/// It answers "is this the same frame" for drift and for the `unchanged`
/// flag, so what it owes is: the same bytes give the same answer, and a
/// difference anybody could see gives a different one. It stopped being
/// `sha1` because a raw 1.28MB frame cost 6.19ms to hash and 0.19ms is
/// enough — see [digestBytes] for the measurement.
void main() {
  Uint8List frame({int size = 4096, int? flip}) {
    var bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = (i * 7) & 0xff;
    }
    if (flip != null) bytes[flip] ^= 0x01;
    return bytes;
  }

  test('is sixteen hex characters', () {
    expect(digestBytes(frame()), matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(digestBytes(Uint8List(0)), matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('the same bytes digest the same', () {
    expect(digestBytes(frame()), digestBytes(frame()));
  });

  // The one failure that matters: a step whose screen changed reported as
  // unchanged. Every single-bit flip has to move the digest — the first byte,
  // the last, and a lane boundary in between.
  test('one flipped bit anywhere changes it', () {
    var clean = digestBytes(frame());
    for (var at in [0, 1, 3, 4, 15, 16, 2047, 4094, 4095]) {
      expect(
        digestBytes(frame(flip: at)),
        isNot(clean),
        reason: 'a bit at $at went unnoticed',
      );
    }
  });

  // The tail is folded byte-at-a-time and the length seeds the state, so a
  // buffer that is another one plus zeros is not the same buffer.
  test('trailing zeros are not free', () {
    var short = Uint8List.fromList([1, 2, 3, 4]);
    var padded = Uint8List.fromList([1, 2, 3, 4, 0, 0]);
    expect(digestBytes(short), isNot(digestBytes(padded)));
    expect(digestBytes(Uint8List(4)), isNot(digestBytes(Uint8List(8))));
  });

  test('a length the words do not divide is still read whole', () {
    var odd = Uint8List.fromList([9, 9, 9, 9, 9, 7]);
    var other = Uint8List.fromList([9, 9, 9, 9, 9, 8]);
    expect(digestBytes(odd), isNot(digestBytes(other)));
  });

  // A view onto a larger buffer at a misaligned offset takes the byte loop
  // rather than the word loop, and has to agree with itself.
  test('a misaligned view digests its own bytes', () {
    var backing = frame(size: 4100);
    var view = Uint8List.sublistView(backing, 1, 4097);
    expect(digestBytes(view), digestBytes(Uint8List.fromList(view)));
  });

  // The split multiply is the whole reason this is web-safe, and the only
  // thing that proves it is the plain 64-bit arithmetic it replaces. Same
  // answer here, and every intermediate under 2^48 so dart2js's doubles hold
  // it exactly — which the VM cannot check, so the reference is the check.
  test('agrees with the arithmetic it replaces', () {
    String reference(Uint8List bytes) {
      var length = bytes.length;
      var a = 0x9e3779b1 ^ length;
      var b = 0x85ebca77;
      var c = 0xc2b2ae3d;
      var d = 0x27d4eb2f;
      var words = length >> 2;
      int word(int at) =>
          bytes[at] +
          bytes[at + 1] * 0x100 +
          bytes[at + 2] * 0x10000 +
          bytes[at + 3] * 0x1000000;
      var i = 0;
      for (; i + 4 <= words; i += 4) {
        a = ((a + word(i * 4)) * 0x85ebca77) & 0xffffffff;
        b = ((b + word((i + 1) * 4)) * 0x9e3779b1) & 0xffffffff;
        c = ((c + word((i + 2) * 4)) * 0xc2b2ae35) & 0xffffffff;
        d = ((d + word((i + 3) * 4)) * 0x27d4eb2f) & 0xffffffff;
      }
      for (; i < words; i++) {
        a = ((a ^ word(i * 4)) * 0x01000193) & 0xffffffff;
      }
      for (var j = words * 4; j < length; j++) {
        b = ((b ^ bytes[j]) * 0x01000193) & 0xffffffff;
      }
      int mix(int h) {
        h = (h ^ (h >>> 16)) & 0xffffffff;
        h = (h * 0x85ebca6b) & 0xffffffff;
        h = (h ^ (h >>> 13)) & 0xffffffff;
        h = (h * 0xc2b2ae35) & 0xffffffff;
        return (h ^ (h >>> 16)) & 0xffffffff;
      }

      return mix(a ^ c).toRadixString(16).padLeft(8, '0') +
          mix(b ^ d ^ length).toRadixString(16).padLeft(8, '0');
    }

    for (var size in [0, 1, 3, 4, 7, 16, 17, 4096, 4099]) {
      var bytes = Uint8List(size);
      for (var i = 0; i < size; i++) {
        bytes[i] = (i * 251 + size) & 0xff;
      }
      expect(digestBytes(bytes), reference(bytes), reason: 'at $size bytes');
    }
  });

  test('two different frames do not collide', () {
    var seen = <String>{};
    for (var i = 0; i < 500; i++) {
      var bytes = Uint8List(1024);
      for (var j = 0; j < bytes.length; j++) {
        bytes[j] = (j * 31) & 0xff;
      }
      // A distinct frame per iteration, and distinct in a way that wraps at
      // no modulus: two bytes far apart, one of them past the last full word.
      bytes[i & 511] ^= 0xff;
      bytes[1023 - (i & 255)] ^= (i >> 8) + 1;
      expect(seen.add(digestBytes(bytes)), isTrue, reason: 'collided at $i');
    }
  });
}
