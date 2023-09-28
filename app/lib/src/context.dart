import 'dart:io';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'utils/resource_cleaner.dart';

class AppContext {
  final Directory appToolDirectory;
  final ResourceCleanerService resourceCleaner;
  final LogClient logger;

  AppContext({
    ResourceCleanerService? resourceCleaner,
    required this.logger,
    Directory? appToolDirectory,
  })  : resourceCleaner = resourceCleaner ?? ResourceCleanerService(),
        appToolDirectory = appToolDirectory ?? Directory.current;

  AppContext copyWith(
      {ResourceCleanerService? resourceCleaner, LogClient? logger}) {
    return AppContext(
      resourceCleaner: resourceCleaner ?? this.resourceCleaner,
      logger: logger ?? this.logger,
      appToolDirectory: appToolDirectory,
    );
  }
}
