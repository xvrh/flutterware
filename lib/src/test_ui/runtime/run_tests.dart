import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart'
    show AutomatedTestWidgetsFlutterBinding, WidgetController;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import '../protocol/models.dart';
import 'asset_bundle_io.dart';
import 'binding.dart';
import 'fonts.dart';
import 'scenario.dart';
import 'scenario_ref.dart';
import 'setup.dart';

class TestRunner {
  final Map<String, dynamic> scenarios;
  final List<String> languages;
  final List<DeviceInfo> devices;
  final String? projectRoot;

  TestRunner(
    this.scenarios, {
    required this.languages,
    required this.devices,
    this.projectRoot,
  });

  late AutomatedTestWidgetsFlutterBinding _binding;
  late IOAssetBundle _bundle;
  void _setup() {
    WidgetController.hitTestWarningShouldBeFatal = true;
    WidgetsApp.debugAllowBannerOverride = false;
    RenderErrorBox.textStyle = ui.TextStyle(fontFamily: 'Roboto');

    _binding = ScenarioBinding(onReloaded: () {});
    String? projectPackageName;
    var projectRoot = this.projectRoot;
    if (projectRoot != null) {
      projectPackageName = _packageNameAt(projectRoot);
    }
    _bundle = IOAssetBundle(
      'build/unit_test_assets',
      bundleParams: BundleParameters(
        rootProjectPath: projectRoot,
        projectPackageName: projectPackageName,
      ),
    );

    setUpAll(() async {
      await loadAppFonts(_bundle);
      await loadFonts({
        ...await commonFonts,
      });
    });
  }

  void runTests() {
    var runContext = _EmptyRunContext();

    _setup();

    var project =
        ProjectInfo('', rootPath: projectRoot, supportedLanguages: languages);
    for (var language in languages) {
      for (var device in devices) {
        for (var ref in ScenarioRef.flatten(scenarios)) {
          var args = RunArgs(
            ref.name,
            device: device,
            accessibility: AccessibilityConfig(),
            language: language,
            imageRatio: 0,
          );
          test('[${ref.name.join('/')}][$language][${device.name}]', () async {
            var error = await ref.scenario.execute(
              runContext,
              _binding,
              _bundle,
              project,
              args,
            );
            if (error != null) {
              throw Exception(error);
            }
          });
        }
      }
    }
  }
}

class _EmptyRunContext implements RunContext {
  @override
  Future<void> addScreen(RunArgs args, NewScreen newScreen) async {
    // Discard the screen
  }
}

String _packageNameAt(String location) {
  var pubspecContent =
      File(p.join(location, 'pubspec.yaml')).readAsStringSync();
  var pubspec = loadYaml(pubspecContent) as YamlMap;
  return pubspec['name']! as String;
}
