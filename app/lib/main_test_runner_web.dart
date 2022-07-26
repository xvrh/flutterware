import 'dart:async';
import 'dart:html';
import 'package:flutterware/internals/web.dart';
import 'package:flutter/material.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';
import 'package:rxdart/rxdart.dart';
import 'src/test_runner/app_connected.dart';
import 'src/test_runner/protocol/api.dart';

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
  runApp(_StandaloneApp(_App(subject.stream)));
}

class _StandaloneApp extends StatelessWidget {
  final Widget app;

  const _StandaloneApp(this.app, {Key? key}) : super(key: key);

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

  const _App(this.clients, {Key? key}) : super(key: key);

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
