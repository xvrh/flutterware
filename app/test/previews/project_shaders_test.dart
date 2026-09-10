import 'dart:io';

import 'package:flutterware_app/src/previews/project_shaders.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The content key of a project shader. Pure, so no SDK: what compiling it
/// produces is in `asset_bundle_test.dart`, against the real `impellerc`.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fw_shader_hash'));
  tearDown(() => root.deleteSync(recursive: true));

  String write(String relative, String content) {
    var file = File(p.join(root.path, relative))..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  test('the hash follows the source', () {
    var source = write('shaders/a.frag', 'void main() {}');
    var before = projectShaderHash(source);
    write('shaders/a.frag', 'void main() { }');
    expect(projectShaderHash(source), isNot(before));
  });

  test('the hash follows a local include, however deep', () {
    var source = write(
      'shaders/a.frag',
      '#include "lib/b.glsl"\nvoid main() {}',
    );
    write('shaders/lib/b.glsl', '#include "c.glsl"\n');
    write('shaders/lib/c.glsl', 'float k = 1.0;');
    var before = projectShaderHash(source);
    write('shaders/lib/c.glsl', 'float k = 2.0;');
    expect(projectShaderHash(source), isNot(before));
  });

  test("the engine's own includes are not files of the project", () {
    var source = write(
      'shaders/a.frag',
      '#include <flutter/runtime_effect.glsl>\nvoid main() {}',
    );
    expect(() => projectShaderHash(source), returnsNormally);
  });

  test('an include cycle is hashed once', () {
    var source = write('shaders/a.frag', '#include "b.glsl"\n');
    write('shaders/b.glsl', '#include "a.frag"\n');
    expect(() => projectShaderHash(source), returnsNormally);
  });
}
