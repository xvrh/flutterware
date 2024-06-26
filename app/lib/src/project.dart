import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'context.dart';
import 'dependencies/model/service.dart';
import 'drawing/model/service.dart';
import 'icon/model/service.dart';
import 'overview/service.dart';
import 'test_runner/model/service.dart';
import 'ui_catalog/service/service.dart';
import 'utils/async_value.dart';
import 'utils/flutter_sdk.dart';

export 'package:pubspec_parse/pubspec_parse.dart' show Pubspec;

class Project {
  final AppContext context;
  final Directory directory;
  final FlutterSdkPath flutterSdkPath;
  final FlutterSdk _flutterSdk;
  late final tests = TestService(this);
  late final info = ProjectInfoService(this);
  late final icons = IconService(this);
  late final dependencies = DependenciesService(this);
  late final drawing = DrawingService(this);
  late final uiCatalog = UICatalogService(this);
  final Uri? loggerUri;

  Project(this.context, String path, this.flutterSdkPath, {this.loggerUri})
      : directory = Directory(path),
        _flutterSdk = FlutterSdk(flutterSdkPath);

  static Future<bool> isValid(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var pubspec = File(p.join(path, 'pubspec.yaml'));
      return pubspec.exists();
    }
    return false;
  }

  String get absolutePath => directory.absolute.path;

  ValueListenable<Snapshot<Pubspec>> get pubspec => info.pubspec;

  void dispose() {
    _flutterSdk.dispose();
    tests.dispose();
    info.dispose();
    icons.dispose();
    dependencies.dispose();
    drawing.dispose();
  }
}
