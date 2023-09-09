import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'code_style/list_files.dart';

void main() async {
  var process = ProcessRunner(printOutputDefault: true);
  for (var project in allFilesInRepository()
      .whereType<File>()
      .where((f) => p.basename(f.path) == 'pubspec.yaml')) {
    await process.runProcess(['flutter', 'pub', 'get'],
        workingDirectory: project.parent, failOk: true);
  }
}
