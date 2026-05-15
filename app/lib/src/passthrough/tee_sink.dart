import 'dart:typed_data';

/// Fans incoming byte chunks out to a live sink (typically stdout) and
/// simultaneously accumulates them in an in-memory buffer.
class TeeSink {
  final void Function(List<int>) onBytes;
  final BytesBuilder _capture = BytesBuilder(copy: false);

  TeeSink({required this.onBytes});

  void add(List<int> chunk) {
    onBytes(chunk);
    _capture.add(chunk);
  }

  Uint8List get captured => _capture.toBytes();
  int get byteCount => _capture.length;
}
