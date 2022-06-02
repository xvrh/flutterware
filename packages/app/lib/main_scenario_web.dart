import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'package:flutter_studio/internal.dart';
import 'package:flutter_studio/internals/web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:rxdart/rxdart.dart';
import 'src/test_visualizer/app.dart';
import 'src/test_visualizer/protocol/api.dart';
import 'src/test_visualizer/service.dart';
import 'src/test_visualizer/standalone.dart';

void main() async {
  late BehaviorSubject<List<ScenarioApi>> subject;

  var iframe = IFrameElement()
    //ignore: unsafe_html
    ..src = 'client/index.html'
    ..height = '0'
    ..width = '0';

  late StreamSubscription onMessageSubscription;
  onMessageSubscription = window.onMessage.listen((e) {
    if (e.data == onConnectedMessage) {
      onMessageSubscription.cancel();
      var channel = createWebChannel(iframe.contentWindow!);
      var client = ScenarioApi(channel, onClose: () {
        subject.close();
      });
      subject.add([client]);
    }
  });

  document.body!.children.add(iframe);

  subject = BehaviorSubject.seeded([]);

  var service = ScenarioService(subject.stream);
  runApp(StandaloneScenarioApp(ScenarioApp(service)));
}
