import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The comparison model must stay loadable where it is read.
///
/// It has more homes than most models: `fw compare` builds it, the studio's
/// panel renders it, a consumer's `tool/` script reads it under a bare `dart
/// run` — and the exported comparison page parses it **in a browser**, which
/// is the one that bites. A `dart:io` import anywhere in the closure makes
/// that page fail to compile, and it fails at `flutter build web` time in
/// `app/`, a long way from whichever file gained the import.
///
/// So the rule is checked here, beside the model, in milliseconds:
///
/// * the model may not reach `package:flutter`, `dart:ui` or `dart:io`;
/// * `report_io.dart` is the single seam that may, and is exported alongside
///   rather than imported by any of it.
void main() {
  const forbidden = ['package:flutter', 'dart:ui', 'dart:io'];

  var directory = Directory(p.join('lib', 'src', 'comparison'));
  var model = [
    for (var file in directory.listSync().whereType<File>())
      if (file.path.endsWith('.dart') &&
          p.basename(file.path) != 'report_io.dart')
        file.path,
  ];

  /// Every file [start] reaches through relative imports, itself included.
  Set<String> closureOf(String start) {
    var seen = <String>{};
    var queue = [p.canonicalize(start)];
    while (queue.isNotEmpty) {
      var path = queue.removeLast();
      if (!seen.add(path)) continue;
      for (var line in File(path).readAsLinesSync()) {
        var match = RegExp(r"^import '([^']+)'").firstMatch(line);
        var uri = match?.group(1);
        if (uri == null ||
            uri.startsWith('package:') ||
            uri.startsWith('dart:')) {
          continue;
        }
        queue.add(p.canonicalize(p.join(p.dirname(path), uri)));
      }
    }
    return seen;
  }

  test('the model is a real directory, not an empty glob', () {
    // The check above passes vacuously if the directory ever moves, which is
    // the one way a purity test lies.
    expect(model, isNotEmpty);
    expect(model.map(p.basename), contains('report.dart'));
  });

  for (var entry in model) {
    test(
      '${p.basename(entry)} reaches no Flutter, no dart:ui and no dart:io',
      () {
        var offenders = <String>[];
        for (var file in closureOf(entry)) {
          for (var line in File(file).readAsLinesSync()) {
            if (!line.startsWith('import ') && !line.startsWith('export ')) {
              continue;
            }
            for (var banned in forbidden) {
              if (line.contains("'$banned")) {
                offenders.add('${p.relative(file)}: ${line.trim()}');
              }
            }
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'The comparison model is parsed in a browser by the exported '
              'page. Whatever needs this belongs behind the report_io.dart '
              'seam.',
        );
      },
    );
  }

  test('report_io.dart is the seam, and nothing in the model imports it', () {
    expect(
      File(p.join('lib', 'src', 'comparison', 'report_io.dart')).existsSync(),
      isTrue,
    );
    for (var entry in model) {
      for (var file in closureOf(entry)) {
        expect(
          p.basename(file),
          isNot('report_io.dart'),
          reason:
              '${p.relative(entry)} reaches the disk half, which puts dart:io '
              'back in the browser closure.',
        );
      }
    }
  });
}
