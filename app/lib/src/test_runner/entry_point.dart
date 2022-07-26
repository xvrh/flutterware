import 'package:flutterware_app/src/utils/source_code.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'dart:io';

import '../project.dart';

const _testLocation = 'test_app';

List<TestFile> collectTestFiles(Directory projectRoot) {
  var testFolder = Directory(p.join(projectRoot.path, _testLocation));
  var files = <TestFile>[];
  if (testFolder.existsSync()) {
    for (var file in testFolder
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .sortedByCompare((e) => e.path, compareNatural)) {
      // TODO(xha): check for main function?
      files.add(TestFile(projectRoot, file));
    }
  }
  return files;
}

class TestFile {
  final Directory projectRoot;
  final File file;

  TestFile(this.projectRoot, this.file);

  String get relativePath =>
      p.relative(file.absolute.path, from: projectRoot.absolute.path);
}

String entryPointCode(Project project, List<TestFile> files, Uri serverUri) {
  var code = StringBuffer()..writeln('''
// GENERATED-CODE: Flutterware - Test runner feature
import 'package:flutterware/internals/test_runner_daemon.dart';
''');

  var index = 0;
  for (var file in files) {
    code.writeln("import '../../${file.relativePath}' as i$index;");
    ++index;
  }
  code.writeln('Map<String, void Function()> allTests() => {');
  index = 0;
  for (var file in files) {
    code.writeln(
        "'${p.relative(file.relativePath, from: _testLocation)}': i$index.main,");
    ++index;
  }
  code.writeln('''
};
final _cliServer = Uri.parse('${serverUri.toString()}');
void main() {
  runTests(_cliServer, allTests, flutterBinPath: ${escapeDartString(project.flutterSdkPath.flutter)});
}
''');
  return '$code';
}
