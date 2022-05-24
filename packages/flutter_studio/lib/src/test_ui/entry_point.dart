import 'package:path/path.dart' as p;

// 1. List all files in "test_ui"
// 2. Generate code like:
//  import '../../test_ui/onboarding_test.dart' as a1;
//
//  Map<String, Function> allTests() => {
//    'onboarding': a1.main,
//  };
//
//  const _cliServer = Uri.ws('0.0.0.0:1234'); // Inject url server
//
//  void main() {
//    runServer(allTests, _cliServer);
//  }
//

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
}

class TestEntryPoint {
  final List<TestFile> files;
  final Uri serverUri;

  TestEntryPoint(this.files, this.serverUri);

  String toCode() {
    var code = StringBuffer();

    return '$code';
  }
}
