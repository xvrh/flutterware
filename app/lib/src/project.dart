import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'flutter_sdk.dart';
import 'icon/model/service.dart';
import 'overview/service.dart';
import 'test_runner/service.dart';
import 'utils/async_value.dart';

export 'package:pubspec_parse/pubspec_parse.dart' show Pubspec;

part 'project.g.dart';

@JsonSerializable()
class Project {
  final Directory directory;
  final FlutterSdkPath flutterSdkPath;
  final FlutterSdk _flutterSdk;
  late final tests = TestService(this);
  late final info = ProjectInfoService(this);
  late final icons = IconService(this);
  late final dependencies = DependenciesService(this);

  Project(String path, this.flutterSdkPath)
      : directory = Directory(path),
        _flutterSdk = FlutterSdk(flutterSdkPath);

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  static Future<bool> isValid(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var pubspec = File(p.join(path, 'pubspec.yaml'));
      return pubspec.exists();
    }
    return false;
  }

  String get absolutePath => directory.absolute.path;

  ValueListenable<Snapshot<Pubspec>> get pubspec => info.pubspec;

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  void dispose() {
    _flutterSdk.dispose();
    tests.dispose();
    info.dispose();
    icons.dispose();
    dependencies.dispose();
  }
}
