import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:image/image.dart';

class IconPlatform {
  static final android = IconPlatform('Android', [
    'android/app/src/main/res/mipmap-*dpi/ic_launcher.png',
  ]);
  static final ios = IconPlatform('iOS', [
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*x*@?x.png',
  ]);
  static final web = IconPlatform('Web', [
    'web/favicon.png',
    'web/icons/Icon*.png',
  ]);
  static final macOS = IconPlatform('macOS', [
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png',
  ]);
  static final windows = IconPlatform('Windows', [
    'windows/runner/resources/app_icon.ico',
  ]);
  static final linux = IconPlatform('Linux', [
    //TODO
  ]);

  static final values = [
    IconPlatform.android,
    IconPlatform.ios,
    IconPlatform.web,
    IconPlatform.macOS,
    IconPlatform.windows,
  ];

  final String name;
  final List<Glob> locations;

  IconPlatform(this.name, List<String> locations)
      : locations = locations.map(Glob.new).toList();

  @override
  String toString() => name;

  Future<List<File>> allFiles(String root) async {
    var files = <File>[];
    for (var glob in locations) {
      files.addAll((await glob.list(root: root).toList()).whereType<File>());
    }
    return files;
  }
}

class AppIcons {
  final Map<IconPlatform, List<AppIcon>> icons;

  AppIcons(this.icons);

  List<AppIcon> get android => icons[IconPlatform.android] ?? const [];

  static Future<AppIcon?> findSampleIcon(String directory,
      {required int size}) async {
    for (var platform in IconPlatform.values) {
      var files = await platform.allFiles(directory);
      files = files.sortedBy<num>((e) => e.lengthSync()).toList();
      if (files.isNotEmpty) {
        return compute<_LoadRequest, AppIcon?>(
            _loadIcon, _LoadRequest(files.last, size));
      }
    }
    return null;
  }

  static Future<AppIcons> loadIcons(String directory,
      {required int size}) async {
    return compute((_) async {
      var results = <IconPlatform, List<AppIcon>>{};

      for (var platform in IconPlatform.values) {
        var icons = results[platform] = [];
        var files = await platform.allFiles(directory);
        for (var file in files.sortedByCompare((e) => e.path, compareNatural)) {
          var icon = _loadIcon(_LoadRequest(file, size));
          if (icon != null) {
            icons.add(icon);
          }
        }
      }

      return AppIcons(results);
    }, null);
  }

  static AppIcon? _loadIcon(_LoadRequest load) {
    var size = load.size;
    var file = load.file;
    var data = file.readAsBytesSync();
    try {
      var originalImage =
          decodeImage(data) ?? (throw Exception('Fail to load image'));
      var preview = copyResize(originalImage, width: size, height: size);

      return AppIcon(
        preview.getBytes(),
        file.path,
        originalWidth: originalImage.width,
        originalHeight: originalImage.height,
        previewWidth: size,
        previewHeight: size,
      );
    } catch (e) {
      print("Fail to load image $e");
      return null;
    }
  }
}

class _LoadRequest {
  final File file;
  final int size;

  _LoadRequest(this.file, this.size);
}

class AppIcon {
  final Uint8List preview;
  final String path;
  final int originalWidth, originalHeight;
  final int previewWidth, previewHeight;

  AppIcon(
    this.preview,
    this.path, {
    required this.previewWidth,
    required this.previewHeight,
    required this.originalWidth,
    required this.originalHeight,
  });
}
