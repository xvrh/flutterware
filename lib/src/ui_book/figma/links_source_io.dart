import 'dart:convert';
import 'dart:io';
import 'service.dart';

class FigmaLinksSourceIO implements FigmaLinksSource {
  final File file;

  FigmaLinksSourceIO(this.file);

  void _ensureFile() {
    file.createSync(recursive: true, exclusive: false);
  }

  @override
  bool get canSave => true;

  @override
  void save(FigmaLinks data) {
    _ensureFile();
    var json = JsonEncoder.withIndent('  ').convert(data);
    file.writeAsStringSync(json);
  }

  @override
  Future<FigmaLinks> read() async {
    if (file.existsSync()) {
      var content = await file.readAsString();
      if (content.isNotEmpty) {
        var decoded = jsonDecode(content);
        return FigmaLinks.fromJson(decoded as Map<String, Object?>);
      }
    }
    return FigmaLinks({});
  }
}
