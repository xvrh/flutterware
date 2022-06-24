import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

void runDebugApp(Widget widget) {
  setupDebugLogger();
  runApp(widget);
}

void setupDebugLogger({Level? level}) {
  Logger.root
    ..level = level ?? Level.ALL
    ..onRecord.listen((e) {
      var errorSuffix = '';
      if (e.error != null) {
        errorSuffix = ' (${e.error})';
      }

      debugPrint('[${e.level.name}] ${e.loggerName}: ${e.message}$errorSuffix');

      if (e.stackTrace != null) {
        debugPrint('${e.stackTrace}');
      }
    });
}
