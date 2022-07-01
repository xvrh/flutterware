import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import '../../utils/cloc/cloc.dart';

CodeMetrics codeMetricsOf(String directory) {
  ClocResult dartCodeForGlobs(List<String> globs) {
    var cloc = countLinesOfCode(_listFiles(directory, globs));
    return cloc.forLanguage(Lang.dart);
  }

  //TODO(xha): read more folders but respect .gitignore file to prevent going into build folders
  return CodeMetrics(
      lib: dartCodeForGlobs(['lib/**']),
      tests: dartCodeForGlobs([
        'test/**',
        'integration_test/**',
        'test_*/**',
      ]),
      other: dartCodeForGlobs([
        'tool/**',
        'bin/**',
      ]));
}

Iterable<File> _listFiles(String root, List<String> globs) sync* {
  for (var glob in globs.map(Glob.new)) {
    yield* glob.listSync(followLinks: false, root: root).whereType<File>();
  }
}

class CodeMetrics {
  final ClocResult lib, tests, other;

  CodeMetrics({required this.lib, required this.tests, required this.other});

  ClocResult get sum => lib + tests;
}
