// The two graders on every shipped demo: the file compiles (CI's analyze)
// and it round-trips through the tool byte for byte. A property the table
// spells differently from the file would show here first.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';
import 'package:path/path.dart' as p;

void main() {
  var dir = Directory(p.join('..', 'examples', 'example', 'demo'));
  var files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.scene.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('the demos are where this test expects them', () {
    expect(files, isNotEmpty);
  });
  for (var file in files) {
    test('${p.basename(file.path)} re-emits as it was read', () {
      var source = file.readAsStringSync();
      var parsed = parseSceneFile(source);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var emitted = emitSceneFile(parsed.doc!, className: parsed.className!);
      var again = parseSceneFile(emitted);
      expect(again.refusals, isEmpty, reason: again.refusals.join('\n'));
      expect(
        emitSceneFile(again.doc!, className: again.className!),
        emitted,
        reason: 'emit ∘ parse is not an identity for ${file.path}',
      );
    });
  }
}
