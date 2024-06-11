import 'dart:convert';
import 'dart:io';
import 'service.dart';

class PersonalSettingsStorageIO extends PersonalSettingsStorage {
  final File file;

  PersonalSettingsStorageIO(this.file);

  @override
  Future<PersonalSettings?> read() async {
    if (file.existsSync()) {
      var content = await file.readAsString();
      if (content.isNotEmpty) {
        var decoded = jsonDecode(content);
        return PersonalSettings.fromJson(decoded as Map<String, Object?>);
      }
    }
    return null;
  }

  @override
  void save(PersonalSettings settings) {
    var content = JsonEncoder.withIndent('  ').convert(settings);
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}
