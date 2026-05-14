import 'dart:typed_data';
import 'package:flutterware_app/src/passthrough/tee_sink.dart';
import 'package:test/test.dart';

void main() {
  test('TeeSink writes to both stdout sink and capture buffer', () {
    final written = <int>[];
    final sink = TeeSink(
      onBytes: written.addAll,
    );

    sink.add(Uint8List.fromList([1, 2, 3]));
    sink.add(Uint8List.fromList([4, 5]));

    expect(written, equals([1, 2, 3, 4, 5]));
    expect(sink.captured, equals([1, 2, 3, 4, 5]));
    expect(sink.byteCount, equals(5));
  });
}
