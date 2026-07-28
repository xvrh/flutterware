import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/hot_reload.dart';

void main() {
  test('derives the WebSocket URI, token path and all', () {
    // The real shape, from a `flutter run` on macOS. The token is part of the
    // path, so `ws` appends to it rather than replacing it.
    expect(
      hotReloadWebSocketUri(Uri.parse('http://127.0.0.1:62747/7BJKLz3myDk=/')),
      Uri.parse('ws://127.0.0.1:62747/7BJKLz3myDk=/ws'),
    );
  });

  test('does not double the separator when there is none', () {
    expect(
      hotReloadWebSocketUri(Uri.parse('http://127.0.0.1:1/tok')),
      Uri.parse('ws://127.0.0.1:1/tok/ws'),
    );
  });
}
