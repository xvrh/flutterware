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
