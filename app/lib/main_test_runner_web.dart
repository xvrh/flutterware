import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/web.dart';
import 'package:rxdart/rxdart.dart';
import 'src/test_runner/app_connected.dart';
import 'src/test_runner/protocol/api.dart';
import 'src/utils/router_outlet.dart';

void main() async {
  late BehaviorSubject<List<TestRunnerApi>> subject;

  var iframe = web.HTMLIFrameElement()
    ..src = 'client/index.html'
    ..height = '0'
    ..width = '0';

  late StreamSubscription onMessageSubscription;
  onMessageSubscription = web.window.onMessage.listen((e) {
    if (e.data.dartify() == onConnectedMessage) {
      onMessageSubscription.cancel();
      var channel = createWebChannel(iframe.contentWindow!);
      var client = TestRunnerApi(channel, onClose: () {
        subject.close();
      });
      subject.add([client]);
    }
  });

  web.document.body!.children.add(iframe);

  subject = BehaviorSubject.seeded([]);
  runApp(_StandaloneApp(_App(subject.stream)));
}

class _StandaloneApp extends StatelessWidget {
  final Widget app;

  const _StandaloneApp(this.app);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: MaterialApp(
        title: 'Test runner',
        home: Scaffold(body: app),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _App extends StatelessWidget {
  final ValueStream<List<TestRunnerApi>> clients;

  const _App(this.clients);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: clients,
      initialData: clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isEmpty) {
          return Center(
            child: Text('Loading...'),
          );
        } else {
          var client = clients.last;
          return TestRunView(
            key: ValueKey(client),
            client,
          );
        }
      },
    );
  }
}
