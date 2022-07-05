import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../protocol/models.dart';
import 'runner.dart';
import 'setup_io.dart' if (dart.library.html) 'setup_web.dart';

class BundleParameters {
  final bool Function(String) translationPredicate;
  final String flutterBinPath;
  final String? rootProjectPath;
  final String? projectPackageName;

  BundleParameters({
    required this.rootProjectPath,
    required this.flutterBinPath,
    bool Function(String)? translationPredicate,
    required this.projectPackageName,
  }) : translationPredicate =
            translationPredicate ?? _defaultTranslationPredicate;

  static bool _defaultTranslationPredicate(String key) =>
      key.endsWith('.json') && key.contains('translations');
}

void _setupLogger() {
  Logger.root
    ..level = Level.ALL
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
