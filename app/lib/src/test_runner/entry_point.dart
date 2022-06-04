import 'package:path/path.dart' as p;

import 'dart:io';

const _testLocation = 'test_ui';

List<TestFile> collectTestFiles(Directory projectRoot) {
  var testFolder = Directory(p.join(projectRoot.path, _testLocation));
  var files = <TestFile>[];
  if (testFolder.existsSync()) {
    for (var file in testFolder
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))) {
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

String entryPointCode(List<TestFile> files, Uri serverUri) {
  var code = StringBuffer()..writeln('''
// GENERATED-CODE: Flutter Studio - Test runner feature
import 'package:flutter_studio/internals/test_runner.dart';
''');

  var index = 0;
  for (var file in files) {
    code.writeln("import '../../${file.relativePath}' as i$index;");
    ++index;
  }
  code.writeln('Map<String, Function> allTests() => {');
  index = 0;
  for (var file in files) {
    code.writeln("'${file.relativePath}': i$index.main,");
    ++index;
  }
  code.writeln('''
};
const _cliServer = Uri.ws('${serverUri.toString()}'); // Inject url server
void main() {
  runServer(allTests, _cliServer);
}
''');
  return '$code';
}
