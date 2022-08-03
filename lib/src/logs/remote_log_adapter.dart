import 'package:logging/logging.dart';
import 'remote_log_client.dart';

extension LogClientExtension on LogClient {
  void printLogRecord(LogRecord e) {
    var message = '${e.loggerName} - ${e.message}';

    if (e.level < Level.INFO) {
      printTrace(message);
    } else if (e.level < Level.WARNING) {
      printStatus(message);
    } else if (e.level < Level.SEVERE) {
      printWarning(message);
    } else {
      printError(message, stackTrace: e.stackTrace);
    }
  }
}
