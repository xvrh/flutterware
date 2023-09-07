import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'store.dart';

class FileVariableStore implements VariablesStore {
  final File? file;
  Map<String, Object?> values;

  FileVariableStore(this.file, this.values);

  static Future<FileVariableStore> load(File? dataFile) async {
    Map<String, Object?>? initialData;

    if (dataFile != null && dataFile.existsSync()) {
      try {
        var variableContent = await dataFile.readAsString();
        initialData = jsonDecode(variableContent) as Map<String, Object?>;
      } catch (e) {
        print('Failed to load initial variables $e');
      }
    }
    return FileVariableStore(dataFile, initialData ?? const {});
  }

  @override
  void save(Map<String, Object> data) {
    var file = this.file;
    if (file == null) {
      return;
    }
    values = data;
    try {
      file.writeAsString(jsonEncode(data));
      print('Saved variables ${jsonEncode(data)} $file');
    } catch (e) {
      print('Failed to save variable $e');
    }
  }

  @override
  Object? operator [](String key) => values[key];
}
