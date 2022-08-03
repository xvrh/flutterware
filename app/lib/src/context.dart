import 'package:flutterware/src/logs/remote_log_client.dart'; // ignore: implementation_imports
import 'utils/resource_cleaner.dart';

class AppContext {
  final ResourceCleanerService resourceCleaner;
  final LogClient logger;

  AppContext({
    ResourceCleanerService? resourceCleaner,
    required this.logger,
  }) : resourceCleaner = resourceCleaner ?? ResourceCleanerService();

  AppContext copyWith(
      {ResourceCleanerService? resourceCleaner, LogClient? logger}) {
    return AppContext(
      resourceCleaner: resourceCleaner ?? this.resourceCleaner,
      logger: logger ?? this.logger,
    );
  }
}
