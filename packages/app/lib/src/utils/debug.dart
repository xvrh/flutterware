import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

void runDebugApp(Widget widget) {
  setupDebugLogger();

  // IMPORTANTE NOTE: if we wrap the runApp call in a runZoneGuarded,
  // we should never call WidgetsFlutterBinding.ensureInitialized() outside
  // of this callback
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
