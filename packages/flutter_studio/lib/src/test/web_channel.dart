import 'dart:async';
import 'dart:html';
import 'package:stream_channel/stream_channel.dart';

//ignore_for_file: close_sinks

StreamChannel<String> createWebChannel(WindowBase destinationWindow) {
  var receiveController = StreamController<String>();
  window.onMessage.listen((event) {
    receiveController.add(event.data as String);
  });

  var sendController = StreamController<String>();
  sendController.stream.listen((String message) {
    destinationWindow.postMessage(message, '*');
  });

  return StreamChannel<String>(receiveController.stream, sendController.sink);
}
