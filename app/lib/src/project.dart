import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';
import 'flutter_sdk.dart';
import 'utils/data_loader.dart';

part 'project.g.dart';

@JsonSerializable()
class Project {
  final String directory;
  final FlutterSdkPath flutterSdkPath;
  final FlutterSdk _flutterSdk;
  late DataLoader<Pubspec> _pubspec;
  late StreamSubscription _pubspecWatcher;

  Project(this.directory, this.flutterSdkPath)
      : _flutterSdk = FlutterSdk(flutterSdkPath) {
    var pubspec = p.join(directory, 'pubspec.yaml');
    _pubspec = DataLoader(
      debugName: 'Pubspec',
      lazy: true,
      loader: () async {
        var content = await File(pubspec).readAsString();
        return Pubspec(loadYaml(content) as YamlMap);
      },
    );
    _pubspecWatcher = FileWatcher(pubspec).events.listen((change) {
      _pubspec.refresh(mode: LoadingMode.none);
    });
  }

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  static Future<bool> isValid(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      var pubspec = File(p.join(path, 'pubspec.yaml'));
      return pubspec.exists();
    }
    return false;
  }

  ValueListenable<Snapshot<Pubspec>> get pubspec => _pubspec;

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  void dispose() {
    _pubspecWatcher.cancel();
    _flutterSdk.dispose();
    _pubspec.dispose();
  }
}

class Pubspec {
  final YamlMap _data;

  Pubspec(this._data);

  String get name => _data['name'] as String;
}
