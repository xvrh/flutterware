import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'store.dart';

class FileVariableStore implements VariablesStore {
  final File file;
  Map<String, Object?> values;

  FileVariableStore._(this.file, this.values);

  static Future<FileVariableStore> load(File dataFile) async {
    Map<String, Object?>? initialData;

    if (dataFile.existsSync()) {
      try {
        var variableContent = await dataFile.readAsString();
        initialData = jsonDecode(variableContent) as Map<String, Object?>;
      } catch (e) {
        print('Failed to load initial variables $e');
      }
    }
    return FileVariableStore._(dataFile, initialData ?? {});
  }

  void _save() {
    try {
      file.writeAsStringSync(jsonEncode(values));
    } catch (e) {
      print('Failed to save variable $e');
    }
  }

  @override
  Object? operator [](String key) => values[key];

  @override
  void operator []=(String key, Object? value) {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    _save();
  }

  @override
  List<String> get keys => values.keys.toList();
}
