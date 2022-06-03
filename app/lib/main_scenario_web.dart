import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'package:flutter_studio/internal.dart';
import 'package:flutter_studio/internals/web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import 'package:http/http.dart';
import 'package:rxdart/rxdart.dart';
import 'src/test_visualizer/app.dart';
import 'src/test_visualizer/app_connected.dart';
import 'src/test_visualizer/protocol/api.dart';
import 'src/test_visualizer/service.dart';

void main() async {
  late BehaviorSubject<List<TestRunnerApi>> subject;

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
      var client = TestRunnerApi(channel, onClose: () {
        subject.close();
      });
      subject.add([client]);
    }
  });

  document.body!.children.add(iframe);

  subject = BehaviorSubject.seeded([]);

  var service = TestService(subject.stream);
  runApp(_StandaloneApp(_App(service)));
}

class _StandaloneApp extends StatelessWidget {
  final Widget app;

  const _StandaloneApp(this.app, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: MaterialApp(
        title: 'Scenario runner',
        home: Scaffold(body: app),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _App extends StatelessWidget {
  final TestService service;

  const _App(this.service, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: service.clients,
      initialData: service.clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isEmpty) {
          return Center(
            child: Text('Loading...'),
          );
        } else {
          var client = clients.last;
          return ConnectedScreen(
            service,
            client,
            key: ValueKey(client),
          );
        }
      },
    );
  }
}
