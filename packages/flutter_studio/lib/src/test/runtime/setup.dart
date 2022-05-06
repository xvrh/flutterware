import 'package:flutter/material.dart';
import '../protocol/models.dart';
import 'runner.dart';
import 'setup_io.dart' if (dart.library.html) 'setup_web.dart';

export '../protocol/models.dart' show ConfluenceInfo;

void runScenarios(
  Map<String, dynamic> Function() scenarios, {
  bool Function(String)? translationPredicate,
  required String projectName,
  required List<String> supportedLanguages,
  String? rootProjectPath,
  String? projectPackageName,
  Brightness? defaultStatusBarBrightness,
  int? poEditorProjectId,
  ConfluenceInfo? confluence,
  FirebaseInfo? firebase,
}) async {
  var bundleParams = BundleParameters(
    translationPredicate: translationPredicate,
    rootProjectPath: rootProjectPath,
    projectPackageName: projectPackageName,
  );
  Runner(
    createChannel,
    scenarios: scenarios,
    bundle: () async => createBundle(bundleParams),
    onConnected: onConnected,
    project: ProjectInfo(
      projectName,
      rootPath: rootProjectPath,
      supportedLanguages: supportedLanguages,
      defaultStatusBarBrightness: defaultStatusBarBrightness?.index,
      poEditorProjectId: poEditorProjectId,
      confluence: confluence,
      firebase: firebase,
    ),
  );
}

class BundleParameters {
  final bool Function(String) translationPredicate;
  final String? rootProjectPath;
  final String? projectPackageName;

  BundleParameters({
    required this.rootProjectPath,
    bool Function(String)? translationPredicate,
    required this.projectPackageName,
  }) : translationPredicate =
            translationPredicate ?? _defaultTranslationPredicate;

  static bool _defaultTranslationPredicate(String key) =>
      key.endsWith('.json') && key.contains('translations');
}
