import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'src/test/app.dart';
import 'src/test/service.dart';
import 'src/test/standalone.dart';

void main() {
  Logger.root
    ..level = Level.INFO
    ..onRecord.listen(print);
  runApp(StandaloneScenarioApp(ScenarioAppWithServer(
    serviceFactory: (clients) => ScenarioService(clients),
  )));
}
