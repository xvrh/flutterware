import 'dart:io';

import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as p;

AssetsReport createAssetReport(String directory) {
  var pubspecFile = File(p.join(directory, 'pubspec.yaml'));
  var pubspec = Pubspec.parse(pubspecFile.readAsStringSync());

  var allFiles = <String>{};
  var flutterMap = pubspec.flutter;
  if (flutterMap != null) {
    var assetsList = flutterMap['assets'];
    if (assetsList is List) {
      for (var assetPath in assetsList) {
        if (assetPath is String) {
          _addFile(allFiles, directory, assetPath);
        }
      }
    }
  }
  var totalBytes = 0;
  for (var filePath in allFiles) {
    totalBytes += File(filePath).lengthSync();
  }

  return AssetsReport(fileCount: allFiles.length, totalBytes: totalBytes);
}

const _variants = ['dark', '2.0x', '3.0x', '4.0x', '2x', '3x', '4x'];
void _addFile(Set<String> allFiles, String root, String path) {
  if (path.endsWith('/')) {
    var directory = Directory(p.join(root, path));
    if (directory.existsSync()) {
      var directoryFiles = directory.listSync().whereType<File>();
      for (var file in directoryFiles) {
        _addFile(allFiles, root, file.path);
      }
    }
  } else {
    _addFileIfExist(allFiles, root, path);
    for (var variant in _variants) {
      var fileName = p.basename(path);
      _addFileIfExist(
          allFiles, root, p.join(p.dirname(path), variant, fileName));
    }
  }
}

void _addFileIfExist(Set<String> allFiles, String root, String path) {
  var file = File(p.join(root, path));
  if (file.existsSync()) {
    allFiles.add(file.path);
  }
}

class AssetsReport {
  final int fileCount;
  final int totalBytes;

  AssetsReport({required this.fileCount, required this.totalBytes});
}
