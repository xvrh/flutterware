import 'dart:io';

// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';

import 'capture/settle.dart';
import 'utils/resource_cleaner.dart';

class AppContext {
  final Directory appToolDirectory;
  final ResourceCleanerService resourceCleaner;
  final LogClient logger;

  /// Who the window is waiting on, for anything that needs to know when it has
  /// stopped moving. Here because it spans plugins — a panel registers into it
  /// and `fw capture` reads it, and neither knows about the other.
  final SettleRegistry settle;

  AppContext({
    ResourceCleanerService? resourceCleaner,
    required this.logger,
    Directory? appToolDirectory,
    SettleRegistry? settle,
  }) : resourceCleaner = resourceCleaner ?? ResourceCleanerService(),
       settle = settle ?? SettleRegistry(),
       appToolDirectory = appToolDirectory ?? Directory.current;

  AppContext copyWith({
    ResourceCleanerService? resourceCleaner,
    LogClient? logger,
  }) {
    return AppContext(
      resourceCleaner: resourceCleaner ?? this.resourceCleaner,
      logger: logger ?? this.logger,
      appToolDirectory: appToolDirectory,
      settle: settle,
    );
  }
}
