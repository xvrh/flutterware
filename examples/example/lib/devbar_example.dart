import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/devbar.dart';
import 'package:logging/logging.dart';
import 'package:flutterware/devbar_plugins/log_analytics.dart';
import 'package:flutterware/devbar_plugins/log_network.dart';
import 'package:flutterware/devbar_plugins/logger.dart';
import 'package:flutterware/devbar_plugins/device_frame.dart';
import 'package:flutterware/devbar_plugins/variables.dart';

import 'src/devbar/info/info_panel.dart';
import 'src/devbar/storage/storage_panel.dart';

final _logger = Logger('devbar_example');

final superCoolFeature = FeatureFlag('superCoolFeature', false);
final otherFeature = FeatureFlag('otherFeature', false);

void main() {
  runApp(_EntryPoint());
}

class _EntryPoint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyDevBar(
      availableUsers: ['John', 'Jane', 'Jack'],
      child: MyApp(),
    );
  }
}

class MyDevBar extends StatelessWidget {
  final Widget child;
  final List<String> availableUsers;

  MyDevBar({
    super.key,
    required this.child,
    required this.availableUsers,
  });

  @override
  Widget build(BuildContext context) {
    return Devbar(
      plugins: [
        LoggerPlugin.new,
        LogNetworkPlugin.new,
        LogAnalyticsPlugin.new,
        VariablesPlugin.new,
        InfoPlugin.new,
        StoragePlugin.new,
        DeviceFramePlugin.new,
      ],
      flags: [
        superCoolFeature.withDefaultValue,
        otherFeature.withValue(true),
      ],
      child: child,
    );
  }

  static MyDevBar? maybeOf(BuildContext context) {
    return context.findAncestorWidgetOfExactType<MyDevBar>();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _userController = TextEditingController();
  StreamSubscription? _variableSubscription;

  @override
  void initState() {
    super.initState();

    _logger.info('Init MyAppState');

    var devbar = Devbar.of(context);
    if (devbar != null) {
      var userVariable = devbar.variables.text('User');
      _userController.text = userVariable.currentValue;
      _variableSubscription = userVariable.value.listen((event) {
        _userController.text = event;
      });
    }
  }

  int _networkId = 0;
  @override
  Widget build(BuildContext context) {
    Widget widget = MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text('My app'),
        ),
        body: Builder(builder: (context) {
          return ListView(
            children: [
              TextFormField(
                controller: _userController,
                decoration: InputDecoration(labelText: 'User'),
              ),
              Divider(),
              ElevatedButton(
                onPressed: () {
                  context.devbar?.analytics.log('Open popup event');

                  showDialog(
                      context: context, builder: (context) => _MyPopup());
                },
                child: Text('Open popup'),
              ),
              Divider(),
              ElevatedButton(
                onPressed: () {
                  context.devbar?.analytics.log('Add network event');

                  var id = _networkId++;
                  context.devbar?.network.request(
                    id,
                    method: 'GET',
                    path: 'https://www.google.com',
                  );
                  context.devbar?.network.response(
                    id,
                    body: {'hello': 'world'},
                  );
                },
                child: Text('Add Network'),
              ),
              Divider(),
              ElevatedButton(
                onPressed: () {
                  _logger.info('One Log');
                },
                child: Text('Add log'),
              ),
              Divider(),
              ElevatedButton(
                onPressed: () {
                  context.devbar?.ui.open();
                },
                child: Text('Open devbar'),
              ),
              Divider(),
              Text(
                'Super cool feature: ${superCoolFeature.dependsOnValue(context)}',
              ),
              Divider(),
              Text(
                'Other feature: ${otherFeature.dependsOnValue(context)}',
              ),
            ],
          );
        }),
      ),
    );

    if (Devbar.of(context) != null) {
      var availableUsers = MyDevBar.maybeOf(context)?.availableUsers;
      if (availableUsers != null) {
        widget = DevbarButton(
          button: DevbarDropdown<String>(
            icon: Icons.account_circle,
            onChanged: (v) {
              setState(() {
                _userController.text = v;
              });
            },
            values: {
              for (var entry in availableUsers)
                entry: Text(
                  entry,
                  textAlign: TextAlign.right,
                ),
            },
          ),
          child: widget,
        );
      }
    }
    return widget;
  }

  @override
  void dispose() {
    _userController.dispose();
    _variableSubscription?.cancel();
    super.dispose();
  }
}

class _MyPopup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('My popup'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DevbarButton(
            button: DevbarIcon(
              onTap: () {
                Devbar.of(context)?.ui.toast(Text('Hello'));
              },
              icon: Icons.ac_unit,
            ),
            child: Text('Child'),
          ),
        ],
      ),
    );
  }
}
