import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:image/image.dart';
import 'package:pool/pool.dart';
import 'package:path/path.dart' as p;

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
    IconPlatform.linux,
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

  bool get isNotEmpty => icons.values.any((v) => v.isNotEmpty);

  AppIcon biggestForPlatforms(List<IconPlatform> platforms) {
    var allIcons = icons.entries
        .where((e) => platforms.contains(e.key))
        .expand((e) => e.value)
        .toList();
    var biggest = allIcons.first;
    for (var icon in allIcons) {
      if (icon.originalWidth > biggest.originalWidth) {
        biggest = icon;
      }
    }
    return biggest;
  }

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
    var results = <IconPlatform, List<AppIcon>>{};

    var pool = Pool(max(2, Platform.numberOfProcessors - 1));

    for (var platform in IconPlatform.values) {
      var files = await platform.allFiles(directory);
      var icons = results[platform] = [];
      for (var file in files) {
        unawaited(pool.withResource(() async {
          AppIcon? icon;
          if (kDebugMode) {
            // "compute" function is not parallelized in debug mode, so it is
            // too slow.
            icon = _loadIcon(_LoadRequest(file, size));
          } else {
            icon = await compute(_loadIcon, _LoadRequest(file, size));
          }
          if (icon != null) {
            icons.add(icon);
          }
        }));
      }
    }
    await pool.close();

    results.removeWhere((key, value) => value.isEmpty);

    return AppIcons(results);
  }

  static AppIcon? _loadIcon(_LoadRequest load) {
    var size = load.size;
    var file = load.file;
    var data = file.readAsBytesSync();
    try {
      var originalImage =
          decodeImage(data) ?? (throw Exception('Fail to load image'));
      var preview = copyResize(originalImage, width: size, height: size, interpolation: Interpolation.linear);

      return AppIcon(
        ByteData.view(preview.getBytes().buffer),
        file.path,
        originalWidth: originalImage.width,
        originalHeight: originalImage.height,
        previewWidth: size,
        previewHeight: size,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> changeIcon(Uint8List bytes,
      {required List<IconPlatform> platforms}) async {
    await compute((_) {
      var encoders = {'.png': encodePng, '.ico': encodeIco};
      var image = decodeImage(bytes)!;
      for (var platform in platforms) {
        var iconsForPlatform = icons[platform];
        if (iconsForPlatform != null) {
          for (var icon in iconsForPlatform) {
            var encoder = encoders[p.extension(icon.path).toLowerCase()];
            if (encoder != null) {
              var newImage = copyResize(
                image,
                width: icon.originalWidth,
                height: icon.originalHeight,
                interpolation: image.width >= icon.originalWidth
                    ? Interpolation.average
                    : Interpolation.linear,
              );

              var newBytes = encoder(newImage);
              File(icon.path).writeAsBytesSync(newBytes);
            }
          }
        }
      }
    }, null);
  }
}

class _LoadRequest {
  final File file;
  final int size;

  _LoadRequest(this.file, this.size);
}

class AppIcon {
  final ByteData preview;
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
