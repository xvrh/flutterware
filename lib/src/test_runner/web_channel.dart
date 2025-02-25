import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';
import 'package:stream_channel/stream_channel.dart';

// ignore_for_file: avoid_web_libraries_in_flutter

StreamChannel<String> createWebChannel(Window destinationWindow) {
  var receiveController = StreamController<String>();
  window.onMessage.listen((event) {
    receiveController.add(event.data.dartify()! as String);
  }, onDone: () {
    receiveController.close();
  });

  var sendController = StreamController<String>();
  sendController.stream.listen((String message) {
    destinationWindow.postMessage(message.toJS, '*'.toJS);
  }, onDone: () {
    sendController.close();
  });

  return StreamChannel<String>(receiveController.stream, sendController.sink);
}
