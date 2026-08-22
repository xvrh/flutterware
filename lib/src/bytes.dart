import 'dart:typed_data';

/// Whether two buffers hold the same bytes.
///
/// Word-at-a-time where alignment allows: the buffers this compares are
/// screen captures — a raw one is megabytes — and a byte loop was measured
/// as a meaningful slice of a raw step's cost. `Uint32List` rather than 64,
/// because this package also compiles for the web, which has no 64-bit
/// integers. The byte loop stays for the tail and for views an offset
/// misaligns.
bool sameBytes(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  var length = a.length;
  if (length != b.length) return false;
  var words = length >> 2;
  if (words > 0 && (a.offsetInBytes | b.offsetInBytes) & 3 == 0) {
    var wordsA = a.buffer.asUint32List(a.offsetInBytes, words);
    var wordsB = b.buffer.asUint32List(b.offsetInBytes, words);
    for (var i = 0; i < words; i++) {
      if (wordsA[i] != wordsB[i]) return false;
    }
    for (var i = words << 2; i < length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  for (var i = 0; i < length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A 64-bit digest of [bytes], as sixteen hex characters.
///
/// What a step's picture is fingerprinted with, so two runs can be asked
/// "is this the same frame" — drift, and the `unchanged` flag. Never a
/// content address, never a lookup key, never an identity: equality against
/// another digest of the same kind is the only thing anybody does with it.
///
/// Which is why it is **not** cryptographic, where it used to be `sha1`.
/// Measured on 1.28MB frames — a phone screenshot's worth of rgba — on an M4
/// Max:
///
/// | | per frame | throughput |
/// |---|---|---|
/// | `sha1` (`package:crypto`) | 6.19 ms | 206 MB/s |
/// | `md5` | 4.99 ms | 256 MB/s |
/// | CommonCrypto `CC_SHA1` over FFI | 0.45 ms | 2815 MB/s |
/// | this | **0.29 ms** | **4472 MB/s** |
///
/// That mattered because a raw capture is 1.5MB where a PNG is 10KB, so the
/// hash was 150× dearer on exactly the runs that chose raw to skip an
/// encoder — and it cost about what the encoder did, which is why raw looked
/// like it bought nothing. Note the third row: going native is *slower* than
/// staying here, because the bytes have to be copied across the boundary
/// before the fast implementation can start.
///
/// Four lanes and a murmur3 finalizer over 32-bit words. Every modular
/// multiply goes through [_mul32] rather than `*` and a mask, because
/// `0xffffffff * 0x85ebca77` is near 2^64 and dart2js gives `int` a double:
/// past 2^53 the product rounds, and a digest that disagreed between the web
/// and the VM would read as "every step changed". Splitting it into two
/// 16-bit halves keeps every intermediate under 2^48. Measured, that costs a
/// third of the throughput — 0.29ms a frame where the unchecked arithmetic
/// managed 0.19 — which is nothing against the 7.5ms encoder this exists to
/// let a caller skip, and still 21× faster than the `sha1` it replaced.
///
/// The tail is folded in a byte at a time, and the length seeds the state, so
/// buffers that differ only in trailing zeros do not collide.
String digestBytes(Uint8List bytes) {
  var length = bytes.length;
  var a = 0x9e3779b1 ^ length;
  var b = 0x85ebca77;
  var c = 0xc2b2ae3d;
  var d = 0x27d4eb2f;
  var words = length >> 2;
  // A word view where the buffer allows one, and the same words composed by
  // hand where it does not. Both, rather than a separate byte path: a step's
  // picture must digest the same however its buffer was come by, and a view
  // that happens to start at an odd offset is the same picture. The fast path
  // needs a little-endian host to agree with the slow one, which every
  // platform Dart runs on is — the guard is there so a host that was not
  // would be *correct* rather than fast.
  if (words > 0 &&
      bytes.offsetInBytes & 3 == 0 &&
      Endian.host == Endian.little) {
    var view = bytes.buffer.asUint32List(bytes.offsetInBytes, words);
    var i = 0;
    for (; i + 4 <= words; i += 4) {
      a = _mul32(a + view[i], 0x85ebca77);
      b = _mul32(b + view[i + 1], 0x9e3779b1);
      c = _mul32(c + view[i + 2], 0xc2b2ae35);
      d = _mul32(d + view[i + 3], 0x27d4eb2f);
    }
    for (; i < words; i++) {
      a = _mul32(a ^ view[i], 0x01000193);
    }
  } else {
    var i = 0;
    for (; i + 4 <= words; i += 4) {
      a = _mul32(a + _wordAt(bytes, i * 4), 0x85ebca77);
      b = _mul32(b + _wordAt(bytes, (i + 1) * 4), 0x9e3779b1);
      c = _mul32(c + _wordAt(bytes, (i + 2) * 4), 0xc2b2ae35);
      d = _mul32(d + _wordAt(bytes, (i + 3) * 4), 0x27d4eb2f);
    }
    for (; i < words; i++) {
      a = _mul32(a ^ _wordAt(bytes, i * 4), 0x01000193);
    }
  }
  for (var i = words * 4; i < length; i++) {
    b = _mul32(b ^ bytes[i], 0x01000193);
  }
  var lo = _mix(a ^ c);
  var hi = _mix(b ^ d ^ length);
  return lo.toRadixString(16).padLeft(8, '0') +
      hi.toRadixString(16).padLeft(8, '0');
}

/// `(x * k) % 2^32`, computed so that no intermediate passes 2^48.
///
/// The plain `(x * k) & 0xffffffff` is exact on the VM and lossy under
/// dart2js, where an `int` is a double and the product of two 32-bit numbers
/// wants 64 bits. Splitting [x] into halves keeps `lo * k` under 2^48 and
/// throws away the part of `hi * k` that only ever reaches above bit 32.
int _mul32(int x, int k) =>
    (((x & 0xffff) * k) + ((((x >>> 16) * k) & 0xffff) * 0x10000)) & 0xffffffff;

/// One little-endian word, for the buffers the view above cannot be taken on.
///
/// Multiplied rather than shifted: `bytes[at + 3] << 24` overflows a signed
/// 32-bit shift, which is what dart2js compiles `<<` to.
int _wordAt(Uint8List bytes, int at) =>
    bytes[at] +
    bytes[at + 1] * 0x100 +
    bytes[at + 2] * 0x10000 +
    bytes[at + 3] * 0x1000000;

/// murmur3's `fmix32`: without it a lane's high bits never reach its low ones,
/// and two frames differing in one pixel can land on neighbouring digests.
int _mix(int h) {
  h = h ^ (h >>> 16);
  h = _mul32(h, 0x85ebca6b);
  h = h ^ (h >>> 13);
  h = _mul32(h, 0xc2b2ae35);
  return h ^ (h >>> 16);
}
